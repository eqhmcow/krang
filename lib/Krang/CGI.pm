package Krang::CGI;
use strict;
use warnings;

use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'AddOn';

# pull in Krang::lib when not running in mod_perl
BEGIN { $ENV{MOD_PERL} or eval "use pkg('lib')" }
# trigger InitHandler when not in mod_perl
BEGIN { $ENV{MOD_PERL} or pkg('AddOn')->call_handler('InitHandler') }

use Krang::ClassLoader 'Charset';
use Krang::ClassLoader Message      => ':all';
use Krang::ClassLoader Widget       => qw(category_chooser_object);
use Krang::ClassLoader Localization => qw(localize);
use MIME::Base64 qw(decode_base64);
use Encode qw(decode_utf8);
use Unicode::Normalize;
use URI::Escape qw(uri_escape);
use Carp qw(croak);

=head1 NAME

Krang::CGI - Krang base class for CGI modules

=head1 SYNOPSIS

  package Krang::CGI::SomeSuch;
  use Krang::ClassLoader base => 'CGI';

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

Some additional methods are provided:

=over

=item script_name

The name of the script making the request. This is useful if you need
to set the target actions for requests that might come from various places.

=back

=head1 AUTHORIZATION

User authentication is handled by L<Krang::Handler>. But for authoriztion,
L<Krang::Handler> assumes that any valid user is also authorized to
perform every action and leaves module and run-mode authorization up
to the individual modules. A simple mechanism is provided by this base
class to add this protection.

=head2 Protecting a Module

To restrict an entire module to only users with given permissions, simply
use the C<PACKAGE_PERMISSIONS> C<< param() >> in either the init stage,
or through C< new() >. For instance, F<user.pl> contains:

    my $app = pkg('CGI::User')->new(
        PARAMS => {
            PACKAGE_PERMISSIONS => [qw(admin_users admin_users_limited)],
        }
    )->run();

This means that only users with either the C<admin_users> or
C<admin_users_limited> permissions will be access to the entire script.

You can also protect on asset permissions:

    my $app = pkg('CGI::Story')->new(
        PARAMS => {
            PACKAGE_ASSETS => { story => [qw(read-only edit)] },
        }
    )->run();

=head2 Protecting a Run Mode

Protecting a run mode is similar to protecting an entire module. Simple
use the C<RUNMODE_PERMISSIONS> param. The main difference is that
C<PACKAGE_PERMISSIONS> takes an arrayref, and C<RUNMODE_PERMISSIONS>
takes a hashref. The keys of this hash are the names of the run modes. The
values are arrayrefs containing the permissions needed.

So to add run mode level protection to F<publisher> to protect the
C<publish_*> run modes, we need something like this:

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

and you can also protect based on asset permissions:

    my $app = pkg('CGI::Story')->new(
        PARAMS => {
            PACKAGE_ASSETS => { story => [qw(read-only edit)] },
            RUNMODE_ASSETS => {
                new_story                     => { story => ['edit'] },
                create                        => { story => ['edit'] },
                edit                          => { story => ['edit'] },
                checkout_and_edit             => { story => ['edit'] },
                check_in                      => { story => ['edit'] },
                revert                        => { story => ['edit'] },
                delete                        => { story => ['edit'] },
                delete_selected               => { story => ['edit'] },
                checkout_selected             => { story => ['edit'] },
                checkin_selected              => { story => ['edit'] },
                delete_categories             => { story => ['edit'] },
                add_category                  => { story => ['edit'] },
                set_primary_category          => { story => ['edit'] },
                copy                          => { story => ['edit'] },
                db_save                       => { story => ['edit'] },
                db_save_and_stay              => { story => ['edit'] },
                save_and_jump                 => { story => ['edit'] },
                save_and_add                  => { story => ['edit'] },
                save_and_publish              => { story => ['edit'] },
                save_and_view                 => { story => ['edit'] },
                save_and_view_log             => { story => ['edit'] },
                save_and_edit_contribs        => { story => ['edit'] },
                save_and_edit_schedule        => { story => ['edit'] },
                save_and_go_up                => { story => ['edit'] },
                save_and_bulk_edit            => { story => ['edit'] },
                save_and_leave_bulk_edit      => { story => ['edit'] },
                save_and_change_bulk_edit_sep => { story => ['edit'] },
                save_and_find_story_link      => { story => ['edit'] },
                save_and_find_media_link      => { story => ['edit'] },
              },
        }
    )->run();

Please see HREF[Krang Permissions System|permissions.html] for more
information on the different permissions available.

=cut

use base 'CGI::Application';

use Krang::ClassLoader Conf => qw(KrangRoot InstanceDisplayName Charset);
use Krang::ClassLoader 'ErrorHandler';
use Krang::ClassLoader 'HTMLTemplate';
use Krang::ClassLoader Log     => qw(critical info debug);
use Krang::ClassLoader Session => qw/%session/;
use Krang::ClassLoader 'User';
use CGI::Application::Plugin::JSON qw(:all);
use Data::Dumper ();
use File::Spec::Functions qw(catdir rel2abs);

# set this to one to see HTML errors in a popup in the UI
use constant HTMLLint => 0;
my $LOGIN_URL;

BEGIN {

    # setup instance and preview scheme if not running in mod_perl
    # needs to be set before import of Krang::ElementLibrary in
    # Krang::CGI::ElementEditor
    unless ($ENV{MOD_PERL}) {
        my $instance =
          exists $ENV{KRANG_INSTANCE} ? $ENV{KRANG_INSTANCE} : (pkg('Conf')->instances())[0];
        debug("Krang::CGI:  Setting instance to '$instance'");
        pkg('Conf')->instance($instance);
    }

    # register the auth_forbidden runmode
    # and prevent aggressive caching from some browsers (looking at you IE)
    # it also does Base64 decoding if the parameters were encoded as Base64
    __PACKAGE__->add_callback(
        init => sub {
            my $self = shift;

            # add access_forbidden, redirect_to_login, redirect_to_workspace rms
            $self->run_modes(
                access_forbidden      => 'access_forbidden',
                redirect_to_login     => 'redirect_to_login',
                redirect_to_workspace => 'redirect_to_workspace'
            );

            # send the no-cache headers
            if ($ENV{MOD_PERL}) {
                require Apache;
                my $r = Apache->request();
                $r->no_cache(1);
            } else {
                $self->header_add(
                    -cache_Control => 'no-cache',
                    -pragma        => 'no-cache',
                );
            }

            my $q = $self->query;

            return if $q->param('is_non_utf8_redirect');

            # Decode the data
            # If the 'base64' flag is set data could be Base64 encoded (we
            # Base64 encode in the client-side JavaScript since JavaScript
            # would natively encode to UTF-8 (done # by encodeURIComponent()).
            # So by encoding in Base64 first we preserve the orginal
            # characters.
            if ($q->param('base64')) {
                my @names = $q->param();
                foreach my $name (@names) {

                    # 'ajax' and 'base64' are not encoded
                    next if $name eq 'ajax' or $name eq 'base64';
                    my @values = $q->param($name);
                    foreach my $i (0 .. $#values) {
                        $values[$i] = decode_base64($values[$i]);
                    }

                    $q->param($name => @values);
                }
            } elsif ($q->param('ajax') or pkg('Charset')->is_utf8) {

                # else we mark the strings as UTF8 so other stuff doesn't
                # have to worry about it
                my @names = $q->param();
                foreach my $name (@names) {
                    my @values = $q->param($name);
                    foreach my $i (0 .. $#values) {

                        # CGI.pm overloads file upload params so that they are both
                        # strings and filehandles. If we decode it it will just be
                        # a string. There might be a better way to handle this if
                        # we might have UTF-8 named files.
                        next if lc(ref $values[$i]) eq 'fh';
                        $values[$i] = Unicode::Normalize::NFC(decode_utf8($values[$i]));
                    }

                    $q->param($name => @values);
                }
            }
        }
    );

    # setup our Authorization
    __PACKAGE__->add_callback(
        prerun => sub {
            my ($self, $rm) = @_;

            # if someone is actually logged in
            if ($ENV{REMOTE_USER}) {

                # make sure they can authorize this package first
                my $perms      = $self->param('PACKAGE_PERMISSIONS');
                my $assets     = $self->param('PACKAGE_ASSETS');
                my $authorized = $self->_check_permissions($perms) && $self->_check_assets($assets);

                # now see if there are any run mode level restrictions
                if ($authorized) {
                    $perms      = $self->param('RUNMODE_PERMISSIONS');
                    $assets     = $self->param('RUNMODE_ASSETS');
                    $authorized = $self->_check_permissions($perms->{$rm})
                      && $self->_check_assets($assets->{$rm});
                }

                # don't let them go any further if they aren't authorized
                $self->prerun_mode('access_forbidden') unless ($authorized);
            }
        }
    );

    __PACKAGE__->add_callback(
        postrun => sub {

            # check for HTML errors if HTMLLint is on
            my ($self, $o) = @_;
            return unless HTMLLint;

            # parse the output with HTML::Lint
            require HTML::Lint;
            my $lint = HTML::Lint->new();
            $lint->parse($$o);
            $lint->eof();

            # if there were errors put them into a javascript popup
            if ($lint->errors) {
                my $err_text = "<ul>" . join(
                    "",
                    map { "<li>$_</li>" }
                      map {
                        s/&/&amp;/g;
                        s/</&lt;/g;
                        s/>/&gt;/g;
                        s/\\/\\\\/g;
                        s/"/\\"/g;
                        $_;
                      }
                      map {
                        $_->as_string
                      } $lint->errors
                ) . "</ul>";
                my $js = qq|
            <script type="text/javascript">
            var html_lint_window = window.open( '', 'html_lint_window', 'height=300,width=600' );
            html_lint_window.document.write( '<html><head><title>HTML Errors Detected</title></head><body><h1>HTML Errors Detected</h1>$err_text</body></html>' );
            html_lint_window.document.close();
            html_lint_window.focus();
            </script>
        |;
                if ($$o =~ m!</body>!) {
                    $$o =~ s!</body>!$js\n</body>!;
                } else {
                    $$o .= $js;
                }
            }
        }
    );

    # make sure our redirect headers are AJAXy
    # if the original request was for AJAX
    # also make sure that the Charset is set if we have it
    __PACKAGE__->add_callback(
        postrun => sub {

            # take care of AJAXy redirects
            my $self  = shift;
            my %props = $self->header_props();
            my $uri   = delete $props{'uri'}
              || delete $props{'-uri'}
              || delete $props{'url'}
              || delete $props{'-url'};

            if ($uri) {

                # add ajax flag
                my $ajax = $self->param('ajax');
                $self->add_to_query(\$uri, "ajax=$ajax")
                  if $ajax;

                unless (pkg('Charset')->is_utf8()) {
                    $self->add_to_query(\$uri, 'is_non_utf8_redirect=1');
                }

                # and allow non-AJAXy redirects
                $props{'-uri'} = $uri if $uri;
                $self->header_props(%props);
            }
        }
    );

    # make sure our session gets unloaded as soon as we're done processing
    # rather than waiting until the client actually gets all the information
    # (eg, waiting until the object goes out of scope)
    # NOTE: after this is run, if the session is needed in another postrun or
    # teardown callback then it will be reloaded and thus re-locked
    __PACKAGE__->add_callback(
        postrun => sub {
            my $self = shift;
            pkg('Session')->unload();
        }
    );

    __PACKAGE__->add_callback(
        prerun => sub {
            my $self = shift;

            # This run mode is added as a run mode to every controller class since it's used
            # in almost all of them. It is designed to be called as an AJAX request by
            # the C<category_chooser> widget to return a portion of the category tree.
            $self->run_modes(
                category_chooser_node => sub {
                    my $self    = shift;
                    my $query   = $self->query();
                    my $chooser = category_chooser_object(
                        query    => $query,
                        may_edit => 1,
                    );
                    return $chooser->handle_get_node(query => $query);
                },
            );

            # store the ajax flag in $self->param early on
            # since some modules will call $query->delete_all();
            $self->param(ajax => (scalar $self->query->param('ajax')));
        }
    );
}

sub _check_permissions {
    my ($self, $perms) = @_;
    if ($perms && ref $perms eq 'ARRAY') {
        my %actual_perms = pkg('Group')->user_admin_permissions();
        foreach my $perm (@$perms) {
            debug("Checking for permission '$perm'");
            if ($actual_perms{$perm}) {
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

sub _check_assets {
    my ($self, $assets) = @_;
    if ($assets && ref $assets eq 'HASH') {
        my %actual_assets = pkg('Group')->user_asset_permissions();
        foreach my $asset (keys %$assets) {
            debug("Checking for asset '$asset'");

            # assets have values, not just true/false so check for a correct value
            for my $val (@{$assets->{$asset}}) {
                if ($val eq $actual_assets{$asset}) {
                    debug("Found correct value '$val' for asset '$asset'");
                    return 1;
                }
            }
            debug("No correct asset value found for '$asset'");
        }
        return 0;
    } else {
        debug("No asset to check");
        return 1;
    }
}

=head1 METHODS

=head2 Run Modes

This base class provides four runmodes:

=head3 access_forbidden

This runmode logs an unauthorized access attempt and passes $msg to
C<$pkg->redirect_to_login($msg)>.

If not provided, the message defaults to C<You do not have permissions
to access that portion of the site.>

=cut

sub access_forbidden {
    my ($self, $msg) = @_;

    info(
        "Unauthorized Access attempted by user #$ENV{REMOTE_USER}." . " Redirecting to 'login.pl'");

    $msg ||= localize("You do not have permissions to access that portion of the site.");

    return $self->redirect_to_workspace($msg);
}

=head3 redirect_to_login

This runmode deletes the user's session and redirects to the login
screen, where $msg will be shown.

=cut

sub redirect_to_login {
    my ($self, $msg) = @_;

    # delete user's session
    pkg('Session')->delete($ENV{KRANG_SESSION_ID});
    return $self->_redirect_to_url_with_msg('login.pl', $msg);
}

sub _redirect_to_url_with_msg {
    my ($self, $url, $msg) = @_;

    if( $msg ) {
        if( $url =~ /\?/ ) {
            $url .= '&';
        } else {
            $url .= '?';
        }
        $url .= "message=" . uri_escape($msg);
    }

    if ($self->param('ajax')) {
        return qq{<script type="text/javascript">location.replace("$url")</script>};
    } else {
        $self->header_add(-location => $url);
        $self->header_type('redirect');
        return "Redirecting to <a href='$url'>$url</a>";
    }
}

=head3 redirect_to_workspace

This runmode redirects the user to his or her workspace. Optionally passing a
message to be displayed when they get there.

=cut

sub redirect_to_workspace {
    my ($self, $msg) = @_;
    return $self->_redirect_to_url_with_msg('workspace.pl', $msg);
}

=head3 cancel_edit

Returns object to the state it was in previous to Edit (though a new 
version may have been written to disk via Save & Stay)

=cut

sub get_edit_object {
    my $pkg = shift;
    croak("You must implement get_edit_object in class $pkg!");
}

sub cancel_edit {
    my $self   = shift;
    my $q      = $self->query;
    my $user   = $ENV{REMOTE_USER};
    my $object = $self->get_edit_object()
      || die("No object returned from get_edit_object()");

    # if it's a new object that hasn't yet been saved, delete it
    if ($self->_cancel_edit_deletes($object)) {
        $object->checkin;
        $object->delete;
    }

    # regardless, grab previous URL and check-out status
    my $type           = ref $self;
    my $pre_edit_url   = delete $session{KRANG_PERSIST}{CANCEL_EDIT}{SENDS_BROWSER_TO_URL}{$type} || '';
    my $pre_edit_owner = delete $session{KRANG_PERSIST}{CANCEL_EDIT}{RETURNS_OBJECT_TO_USER_ID}{$type};

    # if it's an object we opened from workspace, we'll leave it there, otherwise...
    unless ($pre_edit_url eq 'workspace.pl') {
        if (!$pre_edit_owner) {

            # if object wasn't checked out to anyone prior to our edit, check it in...
            $object->checkin;
            if ($object->isa('Krang::Story') && $object->last_desk_id) {

                # and, if it was a story on a desk, return it to that desk
                $object->move_to_desk($object->last_desk_id);
            }
        } elsif ($pre_edit_owner != $user) {

            # if object was checked out to a different user, we must have stolen it..
            $object->checkin;
            $ENV{REMOTE_USER} = $pre_edit_owner;    # this hack returns the object to
            $object->checkout;                      # the user from whom we stole it
            $ENV{REMOTE_USER} = $user;
        }
    }

    # clear it from our session
    $self->clear_edit_object();

    # finally, return to pre-edit URL
    $self->header_props(uri => $pre_edit_url || 'workspace.pl');
    $self->header_type('redirect');
    return "";
}

sub _cancel_edit_goes_to {
    my ($self, $pre_edit_url, $pre_edit_owner) = @_;
    my $type = ref $self;

    if (!$pre_edit_url) {
        # get
        return (
            $session{KRANG_PERSIST}{CANCEL_EDIT}{SENDS_BROWSER_TO_URL}{$type},
            $session{KRANG_PERSIST}{CANCEL_EDIT}{RETURNS_OBJECT_TO_USER_ID}{$type}
        );
    } else {
        my $object = $self->get_edit_object()
          || die("No object returned from get_edit_object()");

        # set
        $session{KRANG_PERSIST}{CANCEL_EDIT}{SENDS_BROWSER_TO_URL}{$type}      = $pre_edit_url;
        $session{KRANG_PERSIST}{CANCEL_EDIT}{RETURNS_OBJECT_TO_USER_ID}{$type} = $pre_edit_owner;
    }
}

sub _cancel_edit_deletes {
    my ($self, $object) = @_;

    # currently only story.pl creates an object even before the user hits Save...
    my $cancel_goes_to = ($self->_cancel_edit_goes_to)[0];
    return ($object->version == 1 && $cancel_goes_to && $cancel_goes_to =~ /new_story$/);
}

sub _cancel_edit_changes_owner {
    my $self           = shift;
    my $pre_edit_owner = ($self->_cancel_edit_goes_to)[1];
    return (!$pre_edit_owner || $pre_edit_owner != $ENV{REMOTE_USER});
}

sub _cancel_edit_goes_to_workspace {
    my $self = shift;
    my $goto = ($self->_cancel_edit_goes_to)[0] || '';
    return $goto eq 'workspace.pl';
}

=head2 Helper Methods

The following methods are also provided to help with common tasks:

=head3 script_name

The name of the script being run.

=cut

sub script_name {
    return shift->query->url(-relative => 1);
}

=head3 update_nav

Tell the Front-End UI that whatever action we just took could alter the
Navigation of the current user, so it should update the Navigation after
this request.

=cut

sub update_nav {
    my $self = shift;
    my $q    = $self->query;

    $self->add_json_header('krang_update_nav' => 1);
}

=head3 add_to_query

Add a parameter to the given URL (reference)

    $self->add_to_query(\$uri, "ajax=$ajax")

=cut

sub add_to_query {
    my ($self, $uri, $param) = @_;
    if ($$uri =~ /\?/) {
        $$uri .= '&';
    } else {
        $$uri .= '?';
    }
    $$uri .= $param;
}

=head3 json_messages

Return any messages or alerts that were added via L<Krang::Message>
as JSON request body. Any extra parameters passed in will be part of the
JSON data structure returned.

    return $self->json_messages();
    return $self->json_messages(success => 1);

=cut

sub json_messages {
    my ($self, %extras) = @_;
    my @msgs   = get_messages();
    my @alerts = get_alerts();
    clear_messages();
    clear_alerts();
    return $self->json_body(
        {
            messages => \@msgs,
            alerts   => \@alerts,
            %extras,
        }
    );
}

sub load_tmpl {
    my $self = shift;
    my ($tmpl_file, @extra_params) = @_;

    # add tmpl_path to path array if one is set, otherwise add a path arg
    if (my $tmpl_path = $self->tmpl_path) {
        my @tmpl_paths = (ref $tmpl_path eq 'ARRAY') ? @$tmpl_path : $tmpl_path;
        my $found = 0;
        for (my $x = 0 ; $x < @extra_params ; $x += 2) {
            if ($extra_params[$x] eq 'path'
                and ref $extra_params[$x + 1] eq 'ARRAY')
            {
                unshift @{$extra_params[$x + 1]}, @tmpl_paths;
                $found = 1;
                last;
            }
        }
        push(@extra_params, path => [@tmpl_paths]) unless $found;
    }

    my $t = pkg('HTMLTemplate')->new_file($tmpl_file, @extra_params);

    # add the AJAX flag if we need to
    $t->param(ajax => 1) if ($self->param('ajax') && $t->query(name => 'ajax'));
    return $t;
}

sub run {
    my $self = shift;
    my @args = (@_);

    # Load and unload session ONLY if we have a session ID set
    my $we_loaded_session = 0;
    if (my $session_id = $ENV{KRANG_SESSION_ID}) {

        # Load session if we have a KRANG_SESSION_ID
        debug("Krang::CGI:  Loading Session '$session_id'");
        pkg('Session')->load($session_id);
        $we_loaded_session++;
        binmode(STDOUT, ':utf8') if pkg('Charset')->is_utf8;
    }

    # setup character set if one is defined
    $self->query->charset(Charset) if Charset;

    #
    # Run CGI
    #
    my $output;
    eval { $output = $self->SUPER::run(@args); };
    if (my $err = $@) {
        debug("Krang::CGI:  UN-Loading Session after error");
        pkg('Session')->unload();
        die $err;
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
    my $self   = shift;
    my $output = '';

    # Call standard dump
    $output .= $self->SUPER::dump_html();

    # Dump Session state
    $output .= "\n<p>Session State:</p>\n<pre><b>\n";
    $output .= Data::Dumper::Dumper(\%session);
    $output .= "\n</b></pre>\n";

    return qq|<div style="text-align:left;margin-left:170px">\n$output\n</div>|;
}

sub get_session_media_obj {
    my ($self, $edit_uuid) = @_;
    $edit_uuid ||= $self->query->param('edit_uuid');
    return $session{SessionEditor}{pkg('Media')}{$edit_uuid};
}

sub get_session_story_obj {
    my ($self, $edit_uuid) = @_;
    $edit_uuid ||= $self->query->param('edit_uuid');
    return $session{SessionEditor}{pkg('Story')}{$edit_uuid};
}

sub get_session_template_obj {
    my ($self, $edit_uuid) = @_;
    $edit_uuid ||= $self->query->param('edit_uuid');
    return $session{SessionEditor}{pkg('Story')}{$edit_uuid};
}


1;
