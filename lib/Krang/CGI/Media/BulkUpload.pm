package Krang::CGI::Media::BulkUpload;
use base qw(Krang::CGI);
use strict;
use warnings;
                                                                                
use Carp qw(croak);

use Krang::Media;
use Krang::Category;
use Krang::Message qw(add_message);
use Krang::Widget qw(category_chooser);
use Krang::Conf qw(KrangRoot FTPAddress FTPPort);
use Krang::Session qw(%session);
use Krang::Log qw(debug);
use File::Temp qw/ tempdir /;
use File::Spec::Functions qw(catdir catfile abs2rel);
use File::Find;
use IO::File;

# these have to be global because of File::Find processing
my $media_list;
my %category_list;
my $is_category;
my $media_in_root;

=head1 NAME
                                                                                
Krang::CGI::Media::BulkUpload - web interface used to upload archives 
of media files.

=head1 SYNOPSIS
                                                                                
  use Krang::CGI::Media::BulkUpload;
  my $app = Krang::CGI::Media::BulkUpload->new();
  $app->run();
                                                                                
=head1 DESCRIPTION
                                                                                
Krang::CGI::Media::BulkUpload provides a web based UI that takes a 
valid archive file (.tar, .zip, .sit), opens it, evaluates the contents,
and creates new media files corresponding with files in the archive.
Directories in the archive match categories.

=head1 INTERFACE
                                                                                
Following are descriptions of all the run-modes provided by
Krang::CGI::Media::BulkUpload.

=cut

# setup runmodes
sub setup {
    my $self = shift;
    
    $self->start_mode('choose');
    
    $self->run_modes([qw(
                            choose
                            upload
                    )]);
    
    $self->tmpl_path('Media/BulkUpload/');
}
                                                                                
=over

=item choose()

Displays filechooser widget and category/site chooser in preparation
for upload.

=cut

sub choose {
    my $self = shift;
    my $query = $self->query;
    my $template = $self->load_tmpl('choose.tmpl', associate => $query );

    $template->param( category_chooser => category_chooser(name=>'category_id', query=>$query) );

    $template->param( upload_chooser => scalar $query->filefield(-name => 'media_file',
                                                     -size => 32) );
    # FTP Settings
    $template->param( ftp_server => FTPAddress, ftp_port => FTPPort, username => $session{username}, instance => $ENV{KRANG_INSTANCE} );
    return $template->output; 
}

=item upload() 

Uploads archive of media files, and places them in appropriate categories.
Returns error messages if categories do not exist.

=cut

sub upload {
    my $self = shift;
    my $q = $self->query;
   
    # if file was uploaded 
    if (my $fh = $q->upload('media_file')) {
        my $filename = $q->param('media_file');
        my $archive_type = file_type($filename);
    
        if (not $archive_type) {
            add_message('invalid_file_type');
            return $self->choose();
        }
         
        # store file in tempdir
        my $path = tempdir( DIR => catdir(KrangRoot, 'tmp'));
        my $filepath = catfile($path, $filename );
        open (FILE, ">$filepath") || croak("Unable to open $filepath for writing
media!");
                                                                         
        my $buffer;
        while (read($fh, $buffer, 10240)) { print FILE $buffer }
        close $fh;
        close FILE;

        # open media source 
        my $opened_root = open_media_source($filepath, $archive_type);
        return $self->choose() if not $opened_root;
  
        # get chosen category_id, if one
        my $root_category = $q->param('category_id');
        $is_category = 1 if $root_category;
 
        # find all files and dirs in archive 
        File::Find::find(\&build_image_list, $opened_root);    

        add_message('media_in_root'), return $self->choose() if $media_in_root;

        # check to see all dirs in archive match Krang site/cats,
        # return if not
        return $self->choose if check_categories($root_category);

        # check media to see if already exist or checked out
        return $self->choose if check_media();

        # if we have gotten this far, upload the files as Krang::Media
        my ($create_count, $update_count) = create_media();
        add_message('media_uploaded', new_count => $create_count, update_count => $update_count);
                
    } else {
        add_message('no_file');
    } 
 
    return $self->choose();
}

=item create_media

Create and save Krang::Media objects for files in archive.
Returns number of uploaded media.

=cut

sub create_media {
    my $new_count = 0;
    my $update_count = 0;

    foreach my $file (@$media_list) {
        if ($file->{media_id}) { # if media_id exists, update object
            my $media = (Krang::Media->find( media_id => $file->{media_id} ))[0];
            my $fh = new IO::File $file->{full_path}; 
            $media->upload_file( filename => $file->{name}, filehandle => $fh );
            $media->save();
            $update_count++;
        } else { #else create new media object
            my $category_id = $category_list{$file->{category}};
            my $fh = new IO::File $file->{full_path};
            my $media = Krang::Media->new(  title => $file->{name},
                                            category_id => $category_id,
                                            filename => $file->{name},
                                            filehandle => $fh );
            $media->save();
            $new_count++;
        }
    }
    
    return $new_count, $update_count;
}

=item check_media

Check media files to see if they already exist and if so,
if they are checked out.  If any are checked out to someone 
other than you, return 1. If exist and not checked out, check out.

=cut

sub check_media {
    my $checked_out;
    foreach my $file (@$media_list) {
        my $category_id = $category_list{$file->{category}};
        my $media = (Krang::Media->find( title => $file->{name},
                                        category_id => $category_id,
                                        filename => $file->{name} ))[0] || '';
        if ($media) {
            if ($media->checked_out) {
                if ($media->checked_out_by == $session{user_id}) {
                    $file->{media_id} = $media->media_id;
                } else {
                    $checked_out = 1;
                    add_message('checked_out', file => $file->{name}, id => $media->media_id );
                }
            } else {
                $file->{media_id} = $media->media_id;
                $media->checkout;
            }
        } 
    }
    return $checked_out;
}

=item check_categories($root_category_id)

Check to see if all categories in the archive correspond with Krang
Categories. Takes a starting category as arg.
Returns 1 if bad categories found, else undef. 

=cut

sub check_categories {
    my $root_category_id = shift;
    my $root_category = $root_category_id ? (Krang::Category->find( category_id => $root_category_id ))[0] : '';
    my $root_cat_path =  $root_category ? $root_category->url : '';

    my $not_found;
    
    foreach my $cat (keys %category_list) {
        my $found_cat = (Krang::Category->find( url => "$root_cat_path$cat/" ))[0];
        $category_list{$cat} = $found_cat->category_id if $found_cat;

        if (not $found_cat) {
            add_message("bad_category", url => "$root_cat_path$cat/");
            $not_found = 1;
        }
    }
    return $not_found;
}

=item open_media_source($filepath, $archive_type)

Unzips, untars, or unstuffs media archive. Returns startpath for opened 
archive,

=cut

sub open_media_source {
    my $filepath = shift;
    my $type = shift;
    my $tempdir = tempdir( DIR => catdir(KrangRoot, 'tmp'));
    
    # create statement to unzip, untar, or unstuff media source file
    my $source_open_statement; 

    if ($type eq 'tar') {
        my $tar_bin = `which tar`;
        chomp $tar_bin;
        add_message('no_opener_binary', which => 'tar', type => 'tar'), return 0 if not ( -B $tar_bin);
        $source_open_statement = "$tar_bin -xf $filepath -C $tempdir";
    } elsif ($type eq 'zip') {
        my $unzip_bin = `which unzip`;
        chomp $unzip_bin;
        add_message('no_opener_binary', which => 'unzip', type => 'zip'), return 0 if not ( -B $unzip_bin);
        $source_open_statement = "$unzip_bin -oq $filepath -d $tempdir";
    } elsif ($type eq 'sit') {
        my $unstuff_bin = `which unstuff`;
        chomp $unstuff_bin;
        add_message('no_opener_binary', which => 'unstuff', type => 'stuffit'), return 0 if not ( -B $unstuff_bin);        
        # unstuff wants relative paths
        my $rel_filepath = abs2rel( $filepath );
        my $rel_tempdir = abs2rel( $tempdir );
        $source_open_statement = "$unstuff_bin -q -d=$rel_tempdir $rel_filepath";
    }    

    debug(__PACKAGE__."->open_media_source - atempting to run '$source_open_statement'");

    unless (system($source_open_statement) == 0) { 
        add_message("problems_opening");
        return 0;
    }
                                                                     
    return $tempdir;
}

=item file_type($filename)

returns file extenstion if one of (tar,zip,sit), else returns 0.

=cut 

sub file_type {
    my $filename = shift;
    if ($filename =~ /.*\.tar$/) {
        return 'tar';
    } elsif ($filename =~ /.*\.zip$/) {
        return 'zip';
    } elsif ($filename =~ /.*\.sit$/) {
        return 'sit';
    }

    return 0;
}

=sub build_image_list()

Used by File::Find::find to process files.

=cut 

sub build_image_list {
    my $path = $File::Find::dir;
    my $file = $_;
    return unless -f $File::Find::name;
   
    my $opened_root = $File::Find::topdir; 
    $path =~ s/$opened_root//; 
    $path =~ s/^\/// if $path;
                                         
    my $temp;
    my $full_path = $File::Find::name;
    debug(__PACKAGE__."->build_image_list - found: $full_path");

    $media_in_root = 1 if ((not $is_category) and (not $path));
  
    $temp->{name} = $file;
    $temp->{category} = $path if $path;
    $temp->{full_path} = $full_path;
                                                                         
    push @$media_list, $temp;
    $category_list{$path} = 1 if ((not $category_list{$path}) and ($path));
}

=back

=cut

1;

