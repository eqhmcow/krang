package Krang::Message;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader Conf => qw(KrangRoot);
use Krang::ClassLoader Session => qw(%session);
use File::Spec::Functions qw(catfile);
use Carp qw(croak);
use Krang::ClassLoader Log => qw(debug);
use Krang::ClassLoader 'File';
use Class::ISA;

use base 'Exporter';
our @EXPORT_OK = qw(add_message get_messages clear_messages);

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

  # get messages in a hash by message key
  %messages = get_messages(keys => 1);

  # clear message list
  clear_messages();

=head1 DESCRIPTION

Krang::Message offers the C<add_message()> function.  This allows you
to register a message which will be shown to the user at the next
convenient point.  In the web UI that will be on the next screen
shown, usually in red text at the top of the screen.  In the SOAP
interface it might be included as part of the next SOAP message
returned to the client.

Messages are specified symbolically, allowing Krang to maintain a
centralized database of message text in F<conf/messages.conf>.  This
allows non-programmers to edit this text.  Variable replacement in
error text is specified using a Perlish syntax.  For example, if the
C<duplicate_url> message were specified like this:

  duplicate_url "Duplicate!  The story with ID $id already has the URL $url."

Then the call to C<add_message()> should look like:

  add_message('duplicate_url', id => $id, url => $url);

Messages in F<conf/messages.conf> may be specified in per-module
blocks.  For example, Krang::CGI::Story's messages could be specified
like:

  <Module "Krang::CGI::Story">
     invalid_type  "Invalid type!"
     invalid_title "Invalid title!"
  </Module>

This allows different modules to define the same name differently.

Addons can include their own F<conf/messages.conf> file which will be
read in after the standard Krang file, overriding any duplicated
entries.

=head1 INTERFACE

=over 4

=item add_message('name');

=item add_message('name', param => 'value', ...);

=item add_message('name', from_module => 'Krang::Module');

Adds a message to the current list of messages.  The first parameter
is always the message identifier, which must appear in
F<conf/messages.conf>.  It must either be in the block for the current
module or outside of any block.  Any parameters after the message name
are parameters to the message, except for C<_from_module> which sets
an alternate module name to use to lookup the message definition.

If the module inherits from one or more modules those blocks will be
searched if the module's block does not define the requested message
name.

=cut

sub add_message {
    our ($CONF);
    my ($key, %args) = @_;
    my @caller = caller;
    my $from_module = delete $args{from_module} || $caller[0];
    debug("add_message($key) called from $from_module, line $caller[2].");

    # look through this class and any super-classes for this message
    my $message;
    foreach my $module (Class::ISA::self_and_super_path($from_module)) {
        # get handle for the module block, if there is one
        my $conf;
        eval { $conf = $CONF->block(Module => $module) };
        $conf ||= $CONF;
        
        # get message definition
        $message = $conf->get($key);
        last if $message;
    }
    croak("Unable to find message '$key' in conf/messages.conf ".
          "for '$from_module'")
      unless $message;

    # perform substitutions
    while (my ($name, $value) = each %args) {
        unless ($message =~ s/\$\Q$name\E/$value/g) {
            croak("Unable to find substitution variable '$name' for message ".
                  "'$key' in conf/messages.conf");
        }
    }

    # push message
    push(@{$session{messages} ||= []}, [ $key, $message ]);
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

=item clear_messages();

Clears the current list of messages.  This should be called after
outputing the messages to the user.

=cut

sub clear_messages {
    $session{messages} = [];
}

# load the configuration file
sub _load_config {
    # find all messages.conf files in reverse order to give the
    # intended overriding effect
    my @files = reverse Krang::File->find_all("conf/messages.conf");
    
    our $CONF = Config::ApacheFormat->new();
    $CONF->read($_) for @files;
}
BEGIN { _load_config() };

1;

=back
