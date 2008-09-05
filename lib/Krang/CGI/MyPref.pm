package Krang::CGI::MyPref;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => qw(CGI);
use strict;
use warnings;

use Carp qw(croak);
use Krang::ClassLoader 'MyPref';
use Krang::ClassLoader 'User';
use Krang::ClassLoader 'PasswordHandler';
use Krang::ClassLoader Message => qw(add_message add_alert);
use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader Conf => qw(PasswordChangeTime DefaultLanguage);
use Krang::ClassLoader Localization => qw(%LANG localize);
use JSON::Any;

=head1 NAME

Krang::CGI::MyPref - interface to edit Krang user preferences
 and password.

=head1 SYNOPSIS
  
  use Krang::ClassLoader 'CGI::MyPref';
  my $app = pkg('CGI::MyPref')->new();
  $app->run();

=head1 DESCRIPTION

Krang::CGI::MyPref provides a form in which a krang user
can view and change thier preferences.  See Krang::MyPref
for which prefs are available.

=head1 INTERFACE

Following are descriptions of all the run-modes provided by
Krang::CGI::MyPref.

=cut

# setup runmodes
sub setup {
    my $self = shift;

    $self->start_mode('edit');
    
    $self->run_modes([qw(
                            edit
                            update_prefs
                            force_pw_change
                    )]);

    $self->tmpl_path('MyPref/');    
}

=over 

=item edit

Displays current preferences edit form.

=cut

sub edit {
    my $self = shift;
    my $error = shift || '';
    my $q = $self->query;
    my $user_id = $ENV{REMOTE_USER};
    my $template = $self->load_tmpl('edit.tmpl', associate => $q);
    $template->param( $error => 1 ) if $error;

    # do we want just show the pw portion
    my $pw_only = $self->param('password_only') || $q->param('password_only');
    $template->param( password_only => $pw_only);

    $template->param(
        search_results_selector => scalar $q->popup_menu(
            -name    => 'search_page_size',
            -values  => [ 5, 10, 20, 30, 40, 50, 100 ],
            -default => pkg('MyPref')->get('search_page_size'),
        )
    );

    $template->param(
        use_autocomplete_selector => scalar $q->radio_group(
            -name    => 'use_autocomplete',
            -values  => [ 1, 0 ],
            -labels  => { 1 => localize('Yes'), 0 => localize('No') },
            -default => pkg('MyPref')->get('use_autocomplete'),
            -class   => 'radio',
        )
    );

    $template->param(
        message_timeout_selector => scalar $q->popup_menu(
            -name   => 'message_timeout',
            -values => [ (1..10), 0 ],
            -labels => { 0 => localize('Never') },
            -default => pkg('MyPref')->get('message_timeout'),
        )
    );

    # Show language selector only if we have more than one AvailableLanguage
    if (scalar keys %LANG > 1) {
	my $lang = pkg('MyPref')->get('language') || DefaultLanguage;

	$template->param(
            language_selector => scalar $q->popup_menu(
                -name     => 'language',
                -values   => [ sort keys %LANG ],
                -labels   => \%LANG,
                -default  => $lang,
                -onchange => q|$('edit_pref_form').addClassName('non_ajax')|,
            )
        );
	$template->param(multi_lang => 1);
    }

    $template->param(
        syntax_highlighting_radio => scalar $q->radio_group(
            -name   => 'syntax_highlighting',
            -values => [ 0, 1],
            -labels => { 0 => 'No', 1 => 'Yes', },
            -default => pkg('MyPref')->get('syntax_highlighting'),
        )
    );

    $template->param(password_spec => pkg('PasswordHandler')->_password_spec);

    return $template->output; 
}

=item update_prefs()

Updates preferences and user password

=cut

sub update_prefs {
    my $self = shift;
    my $q = $self->query();
    my $prefs_changed = 0;

    # look at each pref
    my @prefs = qw(search_page_size use_autocomplete message_timeout syntax_highlighting);
    for my $name (@prefs) {
        my $old = pkg('MyPref')->get($name);
        my $new = $q->param($name);
        # if it's changed then update it
        if (defined $new && $old ne $new) {
            pkg('MyPref')->set($name => $new);
            add_message("changed_$name");
            $prefs_changed = 1;
        } 
    }

    # process language pref only if we have more than one AvailableLanguage
    if (scalar keys %LANG > 1) {
	my $curr_lang = pkg('MyPref')->get('language') || DefaultLanguage || 'en';
	my $new_lang = $q->param('language');

	if ($new_lang ne $curr_lang) {
	    # update language
	    pkg('MyPref')->set(language => $new_lang);
	    $session{language} = $new_lang;
	    add_message("changed_language", lang => $LANG{$new_lang});
	    push @prefs, 'language';
	    $prefs_changed = 1;
	}
    }

    # if we changed anything, then update our prefs cookie
    # with the new values via JSON so that the JS
    # on the client side can access it
    if( $prefs_changed ) {
        my %prefs;
        for my $name (@prefs) {
            $prefs{$name} = pkg('MyPref')->get($name);
        }
        my $pref_cookie = $q->cookie(
            -name  => 'KRANG_PREFS',
            -value => JSON::Any->new->encode(\%prefs),
	    -path  => '/'
        );
        $self->header_add(-cookie => [$pref_cookie->as_string]);
    }

    if (my $pass = $q->param('new_password')) {
        my $user_id = $ENV{REMOTE_USER};
        my $user = (pkg('User')->find( user_id => $user_id ))[0];

        # make sure the passwords match
        my $new_pw = $q->param('new_password');
        my $pw_re  = $q->param('new_password_repeat');
        if( $new_pw ne $pw_re ) {
            add_alert('password_mismatch');
            return $self->edit();
        }

        # check the password constraints
        my $valid = pkg('PasswordHandler')->check_pw(
            $new_pw,
            $user->login,
            $user->email,
            $user->first_name,
            $user->last_name,            
        );

        if( $valid ) {
            $user->password($new_pw);
            $user->save;
            add_message("changed_password");
        }
    }
    unless ($prefs_changed || $q->param('new_password')) {
        add_message("nothing_to_update");
    }

    return $self->edit();
}

=item force_pw_change()

Shows the user the preference edit screen with message letting
them know they are required to change their password.

=cut

sub force_pw_change {
    my $self = shift;
    add_alert('force_password_change', days => PasswordChangeTime);
    $self->param(password_only => 1);
    return $self->edit();
}

=back

=cut

1;
