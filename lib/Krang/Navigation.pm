package Krang::Navigation;
use strict;
use warnings;

use Krang::Desk;
use Krang::Conf qw(FTPHostName FTPPort EnableBugzilla);
use Krang::Session qw(%session);

=head1 NAME

Krang::Navigation - Krang module to manage UI navbar

=head1 SYNOPSIS

  use Krang::Navigation;

  Krang::Navigation->fill_template(template => $template);

=head1 DESCRIPTION

This module manages the navigation for the Krang UI.

=head1 INTERFACE

=over

=item C<< Krang::Navigation->fill_template(template => $template) >>

This call fills in the navigation variables and loops in the supplied
template.  All navigation vars and loops start with "nav_".  If the
template does not include the standard header.tmpl then this call with
do nothing.

=back

=cut

sub fill_template {
    my ($pkg, %arg) = @_;
    my $template = $arg{template};

    # if they're not using the nav, return early
    return unless $template->query(name => 'nav_desk_loop');

    # get user permission hashes
    my %desk_perms  = Krang::Group->user_desk_permissions();
    my %asset_perms = Krang::Group->user_asset_permissions();
    my %admin_perms = Krang::Group->user_admin_permissions();

    # setup desk loop
    $template->param( nav_desk_loop => 
                      [ map {{desk_id => $_->desk_id, desk_name => $_->name}}
                        grep { ($desk_perms{$_->desk_id} || "") ne 'hide' }
                        Krang::Desk->find() ]);

    # setup permissions vars
    for (qw(story media template)) {
        $template->param("nav_hide_$_", 1)
          if $asset_perms{$_} eq 'hide';
    }
    
    # fill in admin vars
    my @admin_apps = (qw(admin_users admin_groups admin_contribs
                         admin_sites admin_categories admin_jobs
                         admin_desks admin_lists));
    $template->param(map { ("nav_$_", $admin_perms{$_}) } @admin_apps);

    # hide bugzilla link if it's not enabled
    $template->param(nav_hide_bugzilla => 1) unless EnableBugzilla;

    # can they see any admin tools?
    $template->param(nav_hide_admin => 1) 
      unless grep { $admin_perms{$_} } @admin_apps;

    # can they see all admin tools?
    $template->param(nav_global_admin => 1) 
      unless grep { not $admin_perms{$_} } @admin_apps;

    # setup template FTP link
    my ($user) = Krang::User->find(user_id => $ENV{REMOTE_USER});
    $template->param(nav_ftp_server => FTPHostName, 
                     nav_ftp_port => FTPPort, 
                     nav_ftp_username => $user->login,
                     nav_ftp_instance => $ENV{KRANG_INSTANCE} );
                     
}

1;

