package Krang::FTP::DirHandle;
use strict;
use warnings;
use Krang::DB qw(dbh);
use Krang::Conf;
use Krang::Session qw(%session);
use Krang::Category;
use Krang::Template;
use Krang::Media;
use Krang::Log qw(debug info critical);
use Net::FTPServer::DirHandle;
use Krang::FTP::FileHandle;

# Inheritance
our @ISA = qw(Net::FTPServer::DirHandle);

=head1 NAME

    Krang::FTP::DirHandle - Virtual FTP Server DirHandle

=head1 SYNOPSIS

=head1 DESCRIPTION

This module provides a directory handle object for use by
Krang::FTP::Server.

=head1 INTERFACE

This module inherits from Net::FTPServer::DirHandle and overrides the
required methods.  This class is used internally by Krang::FTP::Server.

=head2 METHODS

=over

=item Krang::FTP::DirHandle->new($ftps, [$pathname, $instance, $type, $category_id])

Creates a new Krang::FTP::DirHandle object.  Requires a Krang::FTP::Server
object as its first parameter.  Optionally takes a pathname, instance, type,  
and category_id. Type must correspond with media or template. If not supplied the pathname defaults to "/".

=cut

sub new {
    my $class       = shift;
    my $ftps        = shift;       # FTP server object.
    my $pathname    = shift || "/";
    my $instance    = shift;
    my $type        = shift;
    my $category_id = shift;

    # create object
    my $self = Net::FTPServer::DirHandle->new($ftps, $pathname);
    bless $self, $class;
  
    # set category id, default to dummy value.  
    $self->{category_id} = $category_id;
  
    # set instance
    $self->{instance} = $instance;

    # set type
    $self->{type} = $type;

    return $self;
}

=item $dirhandle->get($filename)

The get() method is used to do a lookup on a specific filename.  If a
template or media object called $filename exists in this category then 
get() will call Krang::FTP::FileHandle->new() and return the object. 
If a category exists underneath this category called $filename then new()
will be called and the directory handle will be returned.  Failing
that, undef is returned.

=cut

sub get {
    my $self        = shift;
    my $filename    = shift;
    my $category_id = $self->{category_id};
    my $type = $self->{type} || '';
    my $instance = $self->{instance};
 
    if (not $instance) {
        foreach my $inst (@{$self->{ftps}{auth_instances}}) {
            if ($filename eq $inst) {
                Krang::Conf->instance($inst);
                my $session_id = Krang::Session->create();
                my $user_id = ${$self->{ftps}{user_objects}}{$inst}->user_id;
                $self->{ftps}{user_obj} = ${$self->{ftps}{user_objects}}{$inst};
                $ENV{REMOTE_USER} = $user_id;
    
                # arrange for it to be deleted at process end
                eval "END { Krang::Session->delete() }";
               
                return Krang::FTP::DirHandle->new(  $self->{ftps},
                                                    $self->pathname . $filename . "/", 
                                                    $filename 
                                                ); 
            }
        }
            # return undef if filname doesn't match a authorized instance
            return undef;

    } elsif ($type) {
        if ($type eq 'media') {
            # look for media with name = $filename in spec'd cat
            my @media = Krang::Media->find( filename => $filename,
                                            category_id => $category_id );
        
            if (@media) {
                return new Krang::FTP::FileHandle(  $self->{ftps},
                                                    $media[0],
                                                    $type,
                                                    $category_id
                                                    ); 
            }         
        } elsif ($type eq 'template') {
            # look for template with name = $filename in spec'd cat
            my @template = Krang::Template->find(   filename => $filename,
                                                    category_id => $category_id );

            if (@template) {
                return new Krang::FTP::FileHandle(  $self->{ftps},
                                                    $template[0],
                                                    $type,
                                                    $category_id
                                                    );
            }
        } 
    } elsif ( (not $type) && (($filename eq 'template') || ($filename eq 'media')) ) {
    # $type is not defined, and they are asking for template or media
    # they want to see sites (top level cats) under template or media
        $type = $filename;
        return Krang::FTP::DirHandle->new( $self->{ftps},
                                            $self->pathname . $filename . "/",
                                            $instance,
                                            $type,
                                            $category_id
                                           );
    }
   
    if (not $category_id) { 
        my @categories = Krang::Category->find( url => $filename.'/' );

        return Krang::FTP::DirHandle->new( $self->{ftps},
                                           $self->pathname . $filename . "/",
                                           $instance,
                                           $type,
                                           $categories[0]->category_id,
                                          ) if $categories[0];
    } else {
        my @categories = Krang::Category->find( dir => $filename,
                                                parent_id => $category_id );
        return Krang::FTP::DirHandle->new( $self->{ftps},
                                           $self->pathname . $filename . "/",
                                           $instance,
                                           $type,
                                           $categories[0]->category_id,
                                          ) if $categories[0];
    }

    # if no matching media/template or dir
    return undef;
}   

=item open($filename, $mode)

This method is called to open a file in the current directory.  
The possible modes are 'r', 'w' and 'a'. Same as get since we are 
not supporting new files here.
The method returns a Krang::FTP::FileHandle or undef on failure.

=cut

sub open {
    my $self        = shift;
    my $filename    = shift;
    my $mode        = shift;
    my $category_id = $self->{category_id};
    my $type        = $self->{type};
    my $instance    = $self->{instance};
    
    # get file extension
    my ($name, $file_type) = split(/\./, $filename);

    debug(__PACKAGE__."::open($filename, $mode)\n"); 

    if ((not $instance) || (not $category_id)) {
        return undef;
    }
    
    if ($type eq 'media') {
        # look for media with name = $filename in spec'd cat
        my @media = Krang::Media->find( filename => $filename,
                                        category_id => $category_id );

        if ($media[0]) {
            return new Krang::FTP::FileHandle(  $self->{ftps},
                                                $media[0],
                                                $type,
                                                $category_id
                                                )->open($mode);
        } else {
            my $new_m = Krang::Media->new ( filename => $filename,
                                            title => $filename,
                                            category_id => $category_id );

            return new Krang::FTP::FileHandle(  $self->{ftps},
                                                    $new_m,
                                                    $type,
                                                    $category_id
                                                    )->open($mode);  
        }
    } elsif ($type eq 'template') {
        if ($file_type eq 'tmpl') {
            # look for template with name = $filename in spec'd cat
            my @template = Krang::Template->find(   filename => $filename,
                                                    category_id => $category_id );

            if ($template[0]) {
                return new Krang::FTP::FileHandle(  $self->{ftps},
                                                    $template[0],
                                                    $type,
                                                    $category_id
                                                    )->open($mode);
            } else { # else this must be a new template, create it
                my $new_t = Krang::Template->new(   category_id => $category_id,
                                                    filename => $filename,
                                                    content => '' );

                return new Krang::FTP::FileHandle(  $self->{ftps},
                                                    $new_t,
                                                    $type,
                                                    $category_id
                                                    )->open($mode);
            }
        }
    }

    return undef; 
}

=item list($wildcard)

The list() method is called to do a wildcard search inside a
directory.  The method performs a search for categories and media/templates
matching the specified wildcard.  The return value is a reference to
an array of two-element arrays - the first element is the name and the
second is the corresponding FileHandle or DirHandle object.  The
results are sorted by names before being returned.  If nothing matches
the wildcard then a reference to an empty array is returned.

=cut

sub list {
    my $self        = shift;
    my $wildcard    = shift;
    my $category_id = $self->{category_id};
    my $instance    = $self->{instance};
    my $type        = $self->{type};
    my $ftps        = $self->{ftps};

    my @results;
    
    # translate wildcard to like
    my $like;
    if ($wildcard and $wildcard ne '*') {
        $like = $ftps->wildcard_to_sql_like($wildcard);
    }
    $like = '%' if not $like;

    if (not $instance) {
   
        foreach my $inst (@{$self->{ftps}{auth_instances}}) {
            push @results, [$inst, Krang::FTP::DirHandle->new( $self->{ftps}, "/$inst", $inst ) ];
        }
        return \@results;
    
    } elsif (not $type) { # if no $type, return 'media' and 'template'
    
        @results = ( ['media', Krang::FTP::DirHandle->new( $self->{ftps}, "/$instance/media", 'media') ], ['template', Krang::FTP::DirHandle->new( $self->{ftps}, "/$instance/template", 'template') ] );
        return \@results;
    
    } elsif ( not $category_id ) { # if category not defined, return top level cats
        my @categories = Krang::Category->find( url_like => $like, order_by => 'url', parent_id => undef );
        
        foreach my $cat ( @categories ) {
            my $dirh = Krang::FTP::DirHandle->new( $self->{ftps},
                                                   "/$instance/$type/" . $cat->url() ,
                                                    $instance,
                                                    $type,
                                                    $cat->category_id() );
            my $url = $cat->url;
            chop $url;
            push @results, [ $url, $dirh ];
        }
        return \@results;
    } 
    
    # get subdirectories.
    my @categories = Krang::Category->find( parent_id => $category_id );   
    
    # create dirhandles
    foreach my $cat (@categories) {
        my $dirh = new Krang::FTP::DirHandle (  $self->{ftps},
                                                $self->pathname."/".$cat->dir,
                                                $instance,
                                                $type,
                                                $cat->category_id );
        push @results, [ $cat->dir, $dirh ];
    }
  
    if ( $category_id ) { 
        # get templates or media 
        if ($type eq 'media') {
            my @media = Krang::Media->find( filename_like => $like,
                                            category_id => $category_id );
            foreach my $media (@media) {
                my $fileh = new Krang::FTP::FileHandle (    $self->{ftps},
                                                            $media,
                                                            $type,
                                                            $category_id );
                push @results, [ $media->filename, $fileh ];
            }
        } else {
            my @template = Krang::Template->find(   filename_like => $like,
                                                    category_id => $category_id );
            foreach my $template (@template) {
                my $fileh = new Krang::FTP::FileHandle (    $self->{ftps},
                                                            $template,
                                                            $type,
                                                            $category_id );
                push @results, [ $template->filename, $fileh ];
            }
        }
    }

    return \@results; 
}

=item list_status($wildcard)

This method performs the same as list() but also adds a third element
to each returned array - the results of calling the status() method on
the object.  See the status() method below for details.

=cut

sub list_status {
  my $self = shift;
  my $wildcard = shift;

  my $list = $self->list($wildcard);
  foreach my $row (@$list) {
    $row->[3] = [ $row->[1]->status ];
  }

  return $list;
}

=item parent()

Returns the Krang::FTP::DirHandle object for the parent of this directory.
For the root dir it returns itself.

=cut

sub parent {
    my $self = shift;
    my $category_id = $self->{category_id};
    my $type = $self->{type};
    my $instance = $self->{instance};
    my $dirh;

    return $self if $self->is_root;

    $dirh = $self->SUPER::parent;    

    if ($category_id) {

       $dirh->{type} = $type;
       $dirh->{instance} = $instance;

        # get parent category_id for category
        my @cats;
        @cats = Krang::Category->find( category_id => $category_id );
 
        if ($cats[0]) {
            if (my $parent_cat = $cats[0]->parent) {
                # get a new directory handle and change category_id to parent's
                $dirh->{category_id} = $parent_cat->category_id();
            } else {
                $dirh->{category_id} = undef;
            }
        } 
    } elsif ($type) {
        $dirh->{type} = '';
        $dirh->{instance} = $instance;
    } 
 
 
    return bless $dirh, ref $self; 
}

=item status()

This method returns information about the object.  The return value is
a list with seven elements - ($mode, $perms, $nlink, $user, $group,
$size, $time).  To quote the good book (Net::FTPServer::Handle):

          $mode     Mode        'd' = directory,
                                'f' = file,
                                and others as with
                                the find(1) -type option.
          $perms    Permissions Permissions in normal octal numeric format.
          $nlink    Link count
          $user     Username    In printable format.
          $group    Group name  In printable format.
          $size     Size        File size in bytes.
          $time     Time        Time (usually mtime) in Unix time_t format.

In this case all of these values are fixed for all categories: ( 'd',
0777, 1, "nobody", "", 0, 0 ).

=cut

sub status {
    my $self        = shift;
    my $category_id = $self->{category_id} || '';
    my $type = $self->{type} || '';
    my $instance = $self->{instance} || '';

    debug(__PACKAGE__."::status() : instance = $instance  : type = $type : category = $category_id \n");

    return ( 'd', 0777, 2, "nobody", "nobody", 0, 0 );
}

=item move()

Unsupported method that always returns -1.  Category management using
the FTP interface will probably never be supported.

=cut

sub move   {
  $_[0]->{error} = "Categories cannot be modified through the FTP interface.";
  -1;
}

=item delete()

Unsupported method that always returns -1.  Category management using
the FTP interface will probably never be supported.

=cut

sub delete {
  $_[0]->{error} = "Categories cannot be modified through the FTP interface.";
  -1;
}

=item mkdir()

Unsupported method that always returns -1.  Category management using
the FTP interface will probably never be supported.

=cut

sub mkdir  {
  $_[0]->{error} = "Categories cannot be modified through the FTP interface.";
  -1;
}

=item can_*()

Returns permissions information for various activites.  can_write(),
can_enter() and can_list() all return true since these operations are
supported on all categories.  can_delete(), can_rename() and
can_mkdir() all return false since these operations are never
supported.

=cut

sub can_write  { 1; }
sub can_delete { 0; }
sub can_enter  { 1; }
sub can_list   { 1; }
sub can_rename { 0; }
sub can_mkdir  { 0; }

=back

=head1 SEE ALSO

Net:FTPServer::DirHandle

L<Krang::FTP::Server>

L<Krang::FTP::FileHandle>

=cut 

1;
