package Krang::Log;

=pod

=head1 NAME

Log - Krang logging module

=head1 SYNOPSIS

  use Krang::Log qw(debug info critical);

  debug("I'm inside of block X and \$a == $a.");

  critical("This is a critical application failure!!!!");

  info("Supply informative message here.");

=head1 DESCRIPTION

This module logs messages to file based on the configuration directives set in
'krang.conf'.  The relevant configuration directives are:

=over 4

=item * LogFile

Sets the path of the log.

=item * LogLevel

Determines the minimum log level to be recorded.  The acceptable values for
this setting are the integers 1-3 which correspond to functions: critical,
info, debug.

=item * LogTimeStamp

Turns on the printing of timestamps before each log message.  1 or 0 are the
valid settings.

=item * TimeStampFormat

Sets the format of the timestamps prepended to messages.  See Posix::strftime
in the L<POSIX> manpage for a list of the valid formatting tokens.  Formats
are stringified using Time::Piece->strftime().  See L<Time::Piece>.

=item * LogWrap

If set to true, turns on wrapping for log messages over 80 columns
long using Text::Wrap.  This is somewhat time-consuming and should not
be used in production.

=back

On compilation, the log object is created and all the functions provided in the
import list are exported into the caller's namespace.  No functions are
exported by default.

The following log levels are supported and available as exported functions:

=over 4

=item * debug (3)

Verbose debugging messages should use this level.  Messages at this
level need only be useful to a developer working on the code.

=item * info (2)

Generally useful informational messages belong at this level.  These
messages should highlight the actions the application is taking at a
moderate level of detail.

=item * critical (1)

Error messages resulting from uncaught exceptions will be written at
this level.  Other messages that should *always* make their way to the
log file should use this level too.  Explicit use of this log-level
should be very rare.

=back

Output from this module resembles the following:

   [timestamp] [level] message

Please note, a newline character will be appended to the message if
one is not included.

=cut

# Pragmas
use strict;
use warnings;

# Krang Modules
use Krang;
use Krang::Conf qw(logfile loglevel logtimestamp timestampformat logwrap);

# Module Dependencies
use Fcntl qw(:flock);
use IO::File;
use File::Spec;
use Time::Piece;
use Carp qw(croak);

# load Text::Wrap if wrapping long lines
BEGIN { 
    if (logwrap) {
        require Text::Wrap;
        import Text::Wrap 'wrap';
        $Text::Wrap::columns = 80;
    }
}

# log levels and acceptable function calls
our (%valid_functions, %valid_levels);

# minimum log level
our $LOG_LEVEL;

# Package ref to log object
our $LOG;


# instantiate a new log object so we are ready to go after compliation
BEGIN {
    our %valid_functions = (debug   	=> 3,
                            info    	=> 2,
                            critical	=> 1);

    our %valid_levels = reverse %valid_functions;

    $LOG = bless({}, "Krang::Log");

    # setup filehandle for log; add $KRANG_ROOT to LogFile directive
    my $log = File::Spec->catfile($ENV{KRANG_ROOT},
                                  Krang::Conf->logfile());
    $LOG->{fh} = IO::File->new(">>$log") or
      croak("Unable to open logfile, $log: $!\n");
    $LOG->{path} = $log;

    # set logging level using LogLevel directive; convert arg to int
    # if we have a string
    my $level = Krang::Conf->loglevel();
    croak("Value required for LogLevel directive in 'krang.conf'.")
        unless defined $level;
    my $lvl_pv;
    if ($level =~ /^[a-zA-z]+$/) {
        croak("Invalid LogLevel: $level.")
          unless exists $valid_functions{$level};
        $lvl_pv = $level;
        $level = $valid_functions{$level};
    }
    croak("Invalid LogLevel setting: " .
                (defined $lvl_pv ? $lvl_pv : $level))
        unless exists $valid_levels{$level};
    $LOG_LEVEL = $level;

    # turn on/off timestamp - on by default
    $LOG->{timestamp} = Krang::Conf->logtimestamp() || 1;

    # set timestamp format if any
    my $fmt = Krang::Conf->timestampformat();
    if (defined $fmt) {
        eval {
            my $t = localtime();
            $t->strftime($fmt);
        };
        croak("Invalid timestamp format '$fmt': $@") if $@;
    }
    $LOG->{timestamp_format} = $fmt || '%D %r';
}

=pod

=head1 INTERFACE

=over 4

=item * log

Most of the work for this module is done here.  All calls to convenience
methods are routed through AUTOLOAD() to here; function calls exported via
import() are redirected to AUTOLOAD() which in turn end up here.

Time::Piece->strftime() is used to stringify the timestamp formats.  An error
is thrown unless a valid format is provided.  See also L<Time::Piece> for
information on the strftime() method.

This method takes two arguments:

=over 4

=item * level

This arg must be one of the valid levels in %valid_functions or an error is
thrown.  The valid levels in increasing severity are: debug, info, notice,
warning, error, critical, emergency.  The integers 1-3 are also valid
arguments; on output they are converted to their corresponding strings

=item * message

The string to be logged to the logfile.

=back

=cut

sub log {
    my $self = shift;
    my %args = @_;

    my ($level_IV, $level_PV, $message, $timestamp);

    # check for the required arguments
    for (qw/level message/) {
        croak("The required argument '$_' was not passed.")
          unless exists $args{$_};
    }

    # check for valid log level
    if ($args{level} =~ /^\d+$/) {
        $level_IV = $args{level};

        croak("Invalid log level '$level_IV'.")
          unless exists $valid_levels{$level_IV};

        # retrieve string equivalent
        $level_PV = $valid_levels{$level_IV};
    } else {
        $level_PV = $args{level};

        croak("Invalid method call '$level_PV'.")
          unless exists $valid_functions{$level_PV};

        $level_IV = $valid_functions{$level_PV};
    }

    # don't bother to do anything if the log level is below muster
    return unless $level_IV <= $LOG_LEVEL;

    # calculate timestamp
    $timestamp = '';
    if (exists $LOG->{timestamp} && $LOG->{timestamp}) {
        $timestamp = $LOG->{timestamp_format} || '%D %r';

        # get time object see L<Time::Piece>
        my $t = localtime();

        # make sure the timestamp_format is valid
        eval {$timestamp = "[" . $t->strftime($timestamp) . "] "};

        croak($@) if $@;
    }

    # print message to file
    $message = $timestamp . "[" . lc($level_PV) . "] $args{message}";

    # make sure message ends in a newline
    $message .= "\n" unless $message =~ /\n\z/;

    # wrap long messages if logwrap is on
    if (logwrap and length $message > 79) {
        $message = wrap('', "  ", $message) . "\n";
    }

    # try to obtain an exclusive lock
    croak("Failed to obtain file lock : $!")
        unless (flock($LOG->{fh}, LOCK_EX));

    $LOG->{fh}->print($message)
      or croak("Unable to print to logfile: $!");

    # release lock - does it have a return value?
    flock($LOG->{fh}, LOCK_UN) 
      or croak("Unable to unlock logfile: $!");

    # return value for Tests...
    return $message;
}

=pod

=item * import

This method exports convenience methods into the callers namespace.  Again,
only the functions debug, info, notice, warning, error, critical,
emergency are valid; anything else will result in an error.

=back

=cut

sub import {
    my $pkg = shift;
    my $callpkg = caller(0);

    foreach my $name (@_) {
        # make sure it a supported method
        croak("Unsuppored method: $name")
            unless exists $valid_functions{$name};

        no strict 'refs';
        *{"$callpkg\::$name"} = sub ($){my $msg = shift; $pkg->$name($msg);};
    }
}

sub AUTOLOAD {
    our $AUTOLOAD;
    my ($self, $arg) = @_;
    my ($level) = $AUTOLOAD =~ /::([^:]+)$/;

    return if $level =~ /DESTROY$/;

    # getter/setter for log_level, timestamp and timestamp_format
    if ($level =~ /log_level|^timestamp/) {
        if (defined $arg) {
            $LOG_LEVEL = $arg if $level eq 'log_level';
            $LOG->{$level} = $arg;
        } else {
            return $LOG->{$level};
        }
    } else {
        # forward call to log()
        $self->log(level => $level, message => $arg);
    }
}

{
    no warnings;
    q|The best laid schemes o' Mice an' Men
      Gang aft agley|
}

=pod

=head1 TO DO

=over 4

=item * Figure out how to incorporate Carp::Assert for debugging

=item * Log tracing for errors.

=back

=head1 SEE ALSO

L<Krang>, L<Krang::Conf>, L<Time::Piece>

=cut

