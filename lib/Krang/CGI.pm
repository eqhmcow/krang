package Krang::CGI;
use strict;
use warnings;

use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'AddOn';
use Krang::ClassLoader Message => qw(add_message);

# pull in Krang::lib when not running in mod_perl
BEGIN { $ENV{MOD_PERL} or eval "use pkg('lib')" }

# trigger InitHandler when not in mod_perl
BEGIN { $ENV{MOD_PERL} or pkg('AddOn')->call_handler('InitHandler') }


=head1 NAME

Krang::CGI - Krang base class for CGI modules

=head1 SYNOPSIS

  package Krang::CGI::SomeSuch;
  use base 'Krang::CGI';

  sub setup {
    my $self = shift;
    $self->start_mode('status');
    $self->run_modes(status => \&status);
  }

  sub status {
    my $self = shift;
    my $query = $self->query;
    # ...
  }

=head1 DESCRIPTION

Krang::CGI is a subclass of L<CGI::Application>.  All the usual
CGI::Application features are available.

=head1 INTERFACE

See L<CGI::Application>.

=head1 AUTHORIZATION

User authentication is handled by L<Krang::Handler>. But for authoriztion,
L<Krang::Handler> assumes that any valid user is also authorized to perform
every action and leaves module and run-mode authorization up to the individual
modules. A simple mechanism is provided by this base class to add this protection.

=head2 Protecting a Module

To restrict an entire module to only users with given permissions, simply use 
the C<PACKAGE_PERMISSIONS> C<< param() >> in either the init stage, or through
C< new() >. For instance, F<user.pl> contains:

    my $app = pkg('CGI::User')->new(
        PARAMS => {
            PACKAGE_PERMISSIONS => [qw(admin_users admin_users_limited)],
        }
    )->run();

This means that only users with either the C<admin_users> or C<admin_users_limited>
permissions will be access to the entire script.

=head2 Protecting a Run Mode

Protecting a run mode is similar to protecting an entire module. Simple use the
C<RUNMODE_PERMISSIONS> param. The main difference is that C<PACKAGE_PERMISSIONS>
takes an arrayref, and C<RUNMODE_PERMISSIONS> takes a hashref. The keys of this
hash are the names of the run modes. The values are arrayrefs containing the
permissions needed.

So to add run mode level protection to F<publisher> to protect the C<publish_*>
run modes, we need something like this: 

    my $app = pkg('CGI::Publisher')->new(
        PARAMS => {
            RUNMODE_PERMISSIONS => {
                publish_story       => [qw(may_publish)],
                publish_story_list  => [qw(may_publish)],
                publish_assets      => [qw(may_publish)],
                publish_media       => [qw(may_publish)],
            },
        },
    )->run();

Please see HREF[Krang Permissions System|permissions.html] for more information
on the different permissions available.

=cut

use base 'CGI::Application';

use Krang::ClassLoader 'ErrorHandler';
use Data::Dumper ();

use Krang::ClassLoader Conf => qw(KrangRoot InstanceDisplayName Charset);
use File::Spec::Functions qw(catdir rel2abs);
use Krang::ClassLoader Log => qw(critical info debug);
use Krang::ClassLoader 'User';
use Krang::ClassLoader 'HTMLTemplate';

# Krang sessions
use Krang::ClassLoader Session => qw/%session/;

# set this to one to see HTML errors in a popup in the UI
use constant HTMLLint => 0;
my $LOGIN_URL;

BEGIN {
    # setup instance and preview scheme if not running in mod_perl
    # needs to be set before import of Krang::ElementLibrary in
    # Krang::CGI::ElementEditor
    unless($ENV{MOD_PERL}) {
        my $instance = exists $ENV{KRANG_INSTANCE} ?
          $ENV{KRANG_INSTANCE} : (pkg('Conf')->instances())[0];
        debug("Krang::CGI:  Setting instance to '$instance'");
        pkg('Conf')->instance($instance);
        $ENV{KRANG_PREVIEW_SCHEME} = $ENV{HTTPS} ? 'https' : 'http';
    }

    # register the auth_forbidden runmode
    __PACKAGE__->add_callback(
        init => sub {
            my $self = shift;
            $self->run_modes( access_forbidden => \&_forbidden );
        }
    );
    # setup our Authorization
    __PACKAGE__->add_callback(
        prerun => sub {
            my ($self, $rm) = @_;

            # if someone is actually logged in
            if( $ENV{REMOTE_USER} ) {

                # make sure they can authorize this package first
                my $perms = $self->param('PACKAGE_PERMISSIONS');
                my $authorized = $self->_check_permissions($perms);

                # now see if there are any run mode level restrictions
                if( $authorized ) {
                    $perms = $self->param('RUNMODE_PERMISSIONS');
                    if( $perms && ref $perms eq 'HASH' ) {
                        $authorized = $self->_check_permissions($perms->{$rm});
                    }
                }

                # don't let them go any further if they aren't authorized
                $self->prerun_mode('access_forbidden') unless($authorized);
            }
        }
    );
}

sub _check_permissions {
    my ($self, $perms) = @_;
    if( $perms && ref $perms eq 'ARRAY' ) {
        my %actual_perms = pkg('Group')->user_admin_permissions();
        foreach my $perm (@$perms) {
            debug("Checking for permission '$perm'");
            if( $actual_perms{$perm} ) {
                debug("Found permission '$perm'");
                return 1;
            } else {
                debug("Did not find permission '$perm'");
            }
        }
        return 0;
    } else {
        debug("No permissions to check");
        return 1;
    }
}

sub _forbidden {
    my $self = shift;

    info(
        "Unauthorized Access attempted by user #$ENV{REMOTE_USER}."
        . " Redirecting to 'login.pl'"
    );
    my $msg = "You do not have permissions to access that portion of the site.";
    $self->header_add( -location => "login.pl?alert=$msg" );
    $self->header_type('redirect');
}

# load template using Krang::HTMLTemplate.  CGI::App doesn't provide a
# way to specify a different class to use, so this code is copied in.
sub load_tmpl {
    my $self = shift;
    my ($tmpl_file, @extra_params) = @_;
    
    # add tmpl_path to path array if one is set, otherwise add a path arg
    if (my $tmpl_path = $self->tmpl_path) {
        my @tmpl_paths = (ref $tmpl_path eq 'ARRAY') ? @$tmpl_path : $tmpl_path;
        my $found = 0;
        for( my $x = 0; $x < @extra_params; $x += 2 ) {
            if ($extra_params[$x] eq 'path' and
            ref $extra_params[$x+1] eq 'ARRAY') {
                unshift @{$extra_params[$x+1]}, @tmpl_paths;
                $found = 1;
                last;
            }
        }
        push(@extra_params, path => [ @tmpl_paths ]) unless $found;
    } 

    my $t = pkg('HTMLTemplate')->new_file($tmpl_file, @extra_params);
    return $t;
}

sub run {
    my $self = shift;
    my @args = ( @_ );

    # setup character set if one is defined
    $self->query->charset(Charset) if Charset;

    # Load and unload session ONLY if we have a session ID set
    my $we_loaded_session = 0;
    if (my $session_id = $ENV{KRANG_SESSION_ID}) {
        # Load session if we're in CGI_MODE and we have a KRANG_SESSION_ID
        debug("Krang::CGI:  Loading Session '$session_id'");
        pkg('Session')->load($session_id);
        $we_loaded_session++;
    }


    #
    # Run CGI
    #
    my $output;
    eval { $output = $self->SUPER::run(@args); };
    if (my $err = $@) {
        debug("Krang::CGI:  UN-Loading Session after error");
        pkg('Session')->unload();
        die $@;
    }


    # In debug mode append dump_html()
    if ($ENV{KRANG_DEBUG} and $self->header_type() ne 'redirect') {
        my $dump_html = $self->dump_html();
        $output .= $dump_html;
        print $dump_html;
    }


    # Unload session if we loaded it
    if ($we_loaded_session) {
        debug("Krang::CGI:  UN-Loading Session");
        pkg('Session')->unload();
    }

    return $output;
}


# Krang-specific dump_html
sub dump_html {
    my $self = shift;
    my $output = '';

    # Call standard dump
    $output .= $self->SUPER::dump_html();

    # Dump Session state
    $output .= "<P>\nSession State:<BR>\n<b><PRE>";
    $output .= Data::Dumper::Dumper(\%session);
    $output .= "</PRE></b>\n";

    return "<div style='text-align: left; margin-left: 170px'>$output</div>";
}

# check for HTML errors if HTMLLint is on
sub cgiapp_postrun {
    my ($self, $o) = @_;   
    return unless HTMLLint;

    # parse the output with HTML::Lint
    require HTML::Lint;
    my $lint = HTML::Lint->new();
    $lint->parse($$o);
    $lint->eof();

    # if there were errors put them into a javascript popup
    if ($lint->errors) {
        my $err_text = "<ul>" . join("", map { "<li>$_</li>" }
                                     map { s/&/&amp;/g;
                                           s/</&lt;/g;
                                           s/>/&gt;/g;
                                           s/\\/\\\\/g;
                                           s/"/\\"/g;
                                           $_; }
                                     map { $_->as_string } $lint->errors) .
                                       "</ul>";
    my $js = <<END;
<script language="javascript">
  var html_lint_window = window.open("", "html_lint_window", "height=300,width=600");
  html_lint_window.document.write("<html><head><title>HTML Errors Detected</title></head><body><h1>HTML Errors Detected</h1>$err_text</body></html>");
  html_lint_window.document.close();
  html_lint_window.focus(); 
</script>
END
        if ($$o =~ m!</body>!) {
            $$o =~ s!</body>!$js\n</body>!;
        } else {
            $$o .= $js;
        }
    }
}

1;
