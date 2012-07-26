package Krang::Message;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader Conf    => qw(KrangRoot AvailableLanguages DefaultLanguage);
use Krang::ClassLoader Session => qw(%session);
use File::Spec::Functions qw(catfile catdir);
use Carp qw(croak);
use Krang::ClassLoader Log => qw(debug);
use Krang::ClassLoader 'File';
use Krang::ClassLoader 'Charset';
use Encode qw(decode_utf8 encode_utf8);
use I18N::LangTags qw(is_language_tag);
use Class::ISA;

use base 'Exporter';
our @EXPORT_OK =
  qw(add_message get_messages get_message_text clear_messages add_alert get_alerts clear_alerts);
our %EXPORT_TAGS = (
    add   => [qw(add_message add_alert)],
    get   => [qw(get_messages get_message_text get_alerts)],
    clear => [qw(clear_messages clear_alerts)],
    all   => \@EXPORT_OK,
);

our %CONF;

=head1 NAME

Krang::Message - module to handle UI messages in Krang

=head1 SYNOPSIS

  use Krang::ClassLoader Message => qw(add_messsage get_messages clear_messages);

  # show the 'invalid_type' message, which requires no parameters
  add_message('invalid_type');

  # show the 'duplicate_url' message, supplying the story_id and url
  add_message('duplicate_url', story_id => $story_id, url => $url);

  # show the 'invalid_title' message defined for Krang::CGI::Story
  # regardless of the current module
  add_message('invalid_title', from_module => 'Krang::CGI::Story');

  # get computed message output
  @messages = get_messages();

  # get messages in a hash by key
  %messages = get_messages(keys => 1);

  # get the text of a message as defined in the the F<lang/messages.LANGUAGE> file.
  $text = get_message_text('invalid_title', 'Krang::CGI::Story');

  # clear messages
  clear_messages();

=head1 DESCRIPTION

Krang::Message offers the C<add_message()> and C<add_alert()> functions.
These allows you to register a message or alert which will be shown to
the user at the next convenient point.  In the web UI that will be on
the next screen shown. 

Messages are specified symbolically, allowing Krang to maintain
centralized language-specific databases of message text in
F<lang/messages.LANGUAGE>, with LANGUAGE being a RFC3066-style
language tag.  This allows non-programmers to edit this text.
Variable replacement in error text is specified using a Perlish
syntax.  For example, if the C<duplicate_url> message were specified
like this:

  duplicate_url "Duplicate!  The story with ID $id already has the URL $url."

Then the call to C<add_message()> should look like:

  add_message('duplicate_url', id => $id, url => $url);

Messages in F<lang/messages.LANGUAGE> may be specified in per-module
blocks.  For example, Krang::CGI::Story's messages could be specified
like:

  <Module "Krang::CGI::Story">
     invalid_type  "Invalid type!"
     invalid_title "Invalid title!"
  </Module>

This allows different modules to define the same name differently.

Addons can include their own F<lang/messages.LANGUAGE> file which will
be read in after the standard Krang file, overriding any duplicated
entries.

Any messages found in F<lang/messages.LANGUAGE> can be used by either
C<add_message()> or C<add_alert()>. The method chosen will effect how
the message is displayed to the user.

=head1 INTERFACE

=over 4

=item add_message('name');

=item add_message('name', param => 'value', ...);

=item add_message('name', from_module => 'Krang::Module');

Adds a message to the current list of messages.  The first parameter
is always the message identifier, which must appear in
F<lang/messages.LANGUAGE>.  It must either be in the block for the current
module or outside of any block.  Any parameters after the message name
are parameters to the alert, except for the following:

=over 

=item * C<from_module> 

This sets an alternate module name to use to lookup the message definition.

=item * C<ignore_bad_vars>

This will skip checking of the other parameters passed to make sure they
were in the message. Use this only if need to pass extra variables to the
message without knowing just what the message takes.

=back

If the module inherits from one or more modules those blocks will be
searched if the module's block does not define the requested alert
name.

=cut

sub add_message {
    my ($key, %args) = @_;
    my @caller = caller;
    my $from_module = delete $args{from_module} || $caller[0];
    debug("add_message($key) called from $from_module, line $caller[2].");

    # get the text of this message with any variable substitution
    my $message = get_message_text($key, $from_module, %args);
    croak(
        "Unable to find message '$key' in lang/messages.$session{language} " . "for '$from_module'")
      unless $message;

    # push message
    push(@{$session{messages} ||= []}, [$key, $message]);
}

=over 4

=item add_alert('name');

=item add_alert('name', param => 'value', ...);

=item add_alert('name', from_module => 'Krang::Module');

Adds an alert to the current list of messages.  The first parameter
is always the message identifier, which must appear in
F<lang/messages.LANGUAGE>. It must either be in the block for the current
module or outside of any block.  Any parameters after the alert name
are parameters to the alert, except for the following:

=over 

=item * C<from_module> 

This sets an alternate module name to use to lookup the message definition.

=item * C<ignore_bad_vars>

This will skip checking of the other parameters passed to make sure they
were in the message. Use this only if need to pass extra variables to the
message without knowing just what the message takes.

=back

If the module inherits from one or more modules those blocks will be
searched if the module's block does not define the requested alert
name.

=cut

sub add_alert {
    my ($key, %args) = @_;
    my @caller = caller;
    my $from_module = delete $args{from_module} || $caller[0];
    debug("add_alert($key) called from $from_module, line $caller[2].");

    # get the text of this alert including variable substitution
    my $alert = get_message_text($key, $from_module, %args);
    unless ($alert) {
        my $msg_file =
          $session{language} eq 'en' ? 'conf/messages.conf' : "lang/messages.$session{language}";
        croak("Unable to find alert '$key' in $msg_file for '$from_module'");
    }

    # push alert
    push(@{$session{alerts} ||= []}, [$key, $alert]);
}

=item @messages = get_messages();

=item @messages = get_messages(dups => 1);

=item %messages = get_messages(keys => 1);

Returns the computed messages set by calls to add_message().  By
default this list contains only unique messages, but call with C<dups>
set to 1 to suppress this behavior.  When called with C<keys> set to 1
returns a hash of messages keyed by message identifier.

=cut

sub get_messages {
    my %args = (dups => 0, keys => 0, @_);
    my $messages = $session{messages} || [];

    # return key=>message mapping
    return map { @$_ } @$messages
      if $args{keys};

    # return all messages, including duplicates
    return map { $_->[1] } @$messages
      if $args{dups};

    # return unique messages
    my %seen;
    return grep { not $seen{$_}++ } map { $_->[1] } @$messages;
}

=item @alerts = get_alerts();

=item @alerts = get_alerts(dups => 1);

=item %alerts = get_alerts(keys => 1);

Returns the computed alerts set by calls to add_alert().  By
default this list contains only unique alerts, but call with C<dups>
set to 1 to suppress this behavior.  When called with C<keys> set to 1
returns a hash of alerts keyed by alert identifier.

=cut

sub get_alerts {
    my %args = (dups => 0, keys => 0, @_);
    my $alerts = $session{alerts} || [];

    # return key=>alert mapping
    return map { @$_ } @$alerts
      if $args{keys};

    # return all alerts, including duplicates
    return map { $_->[1] } @$alerts
      if $args{dups};

    # return unique messages
    my %seen;
    return grep { not $seen{$_}++ } map { $_->[1] } @$alerts;
}

=item get_message_text($key, $class [, %args ]);

Returns the message text for the specified C<$key> in the
appropriate C<$class>. If ther text has variables for substitution,
they can be provided by using passing in extra C<%args>.

=cut

sub get_message_text {
    my ($key, $class, %args) = @_;
    my $language        = $session{language} || DefaultLanguage || 'en';
    my $ignore_bad_vars = delete $args{ignore_bad_vars};
    my $CONF            = $CONF{$language};
    my $msg;

    foreach my $module (Class::ISA::self_and_super_path($class)) {

        # get handle for the module block, if there is one
        my $conf;
        eval { $conf = $CONF->block(Module => $module) };
        $conf ||= $CONF;

        # get message definition
        $msg = $conf->get($key);

        # turn UTF-8 on the string if we need to
        $msg = decode_utf8($msg) if pkg('Charset')->is_utf8;

        last if $msg;
    }

    # perform substitutions
    if( $msg ) {
        foreach my $name (sort { length($b) <=> length($a) } keys %args) {
            my $value = $args{$name};
            unless($msg =~ s/\$\Q$name\E/$value/g) {
                croak(  "Unable to find substitution variable '$name' for message "
                      . "'$key' in lang/$language/messages.conf") unless $ignore_bad_vars;
            }
        }
    }

    return $msg;
}

=item clear_messages();

Clears the current list of messages.  This should be called after
outputing the messages to the user.

=cut

sub clear_messages {
    $session{messages} = [];
}

=item clear_alerts();

Clears the current list of alerts.  This should be called after
outputing the alerts to the user.

=cut

sub clear_alerts {
    $session{alerts} = [];
}

# load the configuration files
sub _load_config {
    our %CONF;

    # the English default
    my @languages = (['en' => 'conf']);

    # other languages
    push @languages, map { [$_ => catdir('lang', $_)] }
      grep { $_ ne 'en' } AvailableLanguages;

    # load them for all AvailableLanguages or just English
    for my $spec (@languages) {
        my ($lang, $dir) = @$spec;

        croak "$lang is not a valid language tag"
          unless is_language_tag($lang);

        # find all messages.conf files in reverse order to
        # give the intended overriding effect
        my @files = reverse Krang::File->find_all(catfile($dir, 'messages.conf'));

        my $conf = Config::ApacheFormat->new();
        $conf->read($_) for @files;

        $CONF{$lang} = $conf;
    }
}
BEGIN { _load_config() }

1;

=back
