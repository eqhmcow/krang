package Krang::CGI::Debug;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader base => 'CGI';
use Krang::ClassLoader Conf => qw(KrangRoot);
use File::Spec::Functions qw(catfile);
use Krang::ClassLoader 'Group';
use Data::Dumper;

=head1 NAME

Krang::CGI::Debug - a debugger for Krang

=head1 SYNOPSIS

  use Krang::ClassLoader 'CGI::Debug';
  pkg('CGI::Debug')->new()->run();

=head1 DESCRIPTION

This application allows admins to access a screen where they can read
the logs, read the configuration file and evaluate Perl code in the
context of the running Krang instance.  The inherent security risk of
this feature is mitigated by the fact that only full admins can access
this feature, and only by knowing the hotkey (Ctrl-Alt-D).

=head1 INTERFACE

=head2 RUN MODES

=over

=cut

sub setup {
    my $self = shift;
    $self->mode_param('rm');
    $self->start_mode('show');    
    $self->run_modes(show => 'show');
    $self->tmpl_path('Debug/');
}

=item show

The only available run-mode, displays the interface and accepts
commands.

=cut

sub show {
    my $self = shift;

    # make sure they're really a global admin
    my %admin_perms = pkg('Group')->user_admin_permissions();
    my @admin_apps = (qw(admin_users admin_groups admin_contribs
                         admin_sites admin_categories admin_jobs
                         admin_desks admin_lists));
    croak("Attempt by non-global admin to access debug.pl!")
      if grep { not $admin_perms{$_} } @admin_apps;

    my $query = $self->query();
    my $template = $self->load_tmpl('debug.tmpl');

    my $log = catfile(KrangRoot, 'logs', 'krang.log');
    $template->param(log  => scalar `tail -n300 $log`);

    my $conf = catfile(KrangRoot, 'conf', 'krang.conf');
    $template->param(conf => scalar `cat $conf`);

    my $perl = $query->param('perl');
    my $output = "";
    if (defined $perl and length $perl) {
        no strict;
        no warnings;

        my $num = int(rand() * time());
        my @ret = eval "sub debug_$num { $perl } debug_$num();";
        my $err = $@;
        if ($err) {
            $output = "DIED: $err";
        } elsif (@ret == 1) {
            $output = Dumper($ret[0]);
        } else {
            $output = Dumper(\@ret);
        }
    }
    $template->param(output => $output);

    return $template->output();
}

=back

=cut

1;
