package Krang::CGI::Media::BulkUpload;
use base qw(Krang::CGI);
use strict;
use warnings;
                                                                                
use Carp qw(croak);

use Krang::Media;
use Krang::Message qw(add_message);
use Krang::Widget qw(category_chooser);
use Krang::Conf qw(FTPAddress FTPPort);
use Krang::Session qw(%session);

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

=back

=cut

1;

