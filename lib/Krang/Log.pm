package Krang::Log;

=pod

=head1 NAME

Krang::Log - Krang logging module

=head1 SYNOPSIS

  use Krang::Log qw(debug info critical ASSERT assert affirm should shouldnt);

  # logging messages
  debug("I'm inside of block X and \$a == $a.");

  critical("This is a critical application failure!!!!");

  info("Supply informative message here.");

  # assertion functions from Carp::Assert
  assert($positive >= 0) if ASSERT
  affirm { $positive >= 0 } if ASSERT;
  should($nine, 9) if ASSERT;
  shouldnt($nine, 10) if ASSERT;

=head1 DESCRIPTION

This module logs messages to file based on the configuration
directives set in 'krang.conf'.  The relevant configuration directives
are:

=over 4

=item * LogLevel

Determines the minimum log level to be recorded.  This value may be
set to a single integer.  The acceptable values for this setting are
the integers 1-3 which correspond to functions: critical, info, debug.
For example, to see all messages:

  LogLevel 3

Optionally, log levels may be set for specific modules.  For example,
if you were working on Krang::CGI::Story and didn't want to see debug
messages from other modules:

  LogLevel 2,Krang::CGI::Story=3

You can also specify a regex to match against module names.  For
example, to suppress debug messages from all CGI modules:

  LogLevel 3,/^Krang::CGI/=2

=item * Assertions

If set to true assertions will be active.  This is the default for
'make test' but setting it in krang.conf will activate assertions all
the time.

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
use Krang::Conf qw(assertions loglevel
		   KrangUser KrangGroup KrangRoot);

# Module Dependencies
use Carp qw(verbose croak);
use Data::Dumper;
use Fcntl qw(:flock);
use IO::File;
use File::Spec::Functions qw(catfile catdir);
use Time::Piece;

# constants
use constant LogFile => "logs/krang.log";

# declare exportable functions
use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(debug info critical assert affirm should shouldnt ASSERT);

# log levels and acceptable function calls
our ($reopen_log, %valid_functions, %valid_levels);

# log level settings
our $LOG_LEVEL_DEFAULT;
our %LOG_LEVEL_PER_MODULE;
our @LOG_LEVEL_REGEX;

# Package ref to log object
our $LOG;


# instantiate a new log object so we are ready to go after compliation
BEGIN {
    # reopen the log on each write if the Schedule Daemon is running...
    our $reopen_log = $ENV{SCH_DAEMON} || 0;

    our %valid_functions = (debug   	=> 3,
                            info    	=> 2,
                            critical	=> 1);

    our %valid_levels = reverse %valid_functions;

    $LOG = bless({}, "Krang::Log");

    # setup filehandle for log; add $KRANG_ROOT to LogFile directive
    my $log = File::Spec->catfile(KrangRoot, LogFile);

    my $log_exists = (-e $log) ? 1 : 0;
    open(LOG, ">>", $log) or
      croak("Unable to open logfile, $log: $!\n");
    $LOG->{path} = $log;

    # if the log file is freshly created
    if (not $log_exists) {
        my ($uid) = (getpwnam(KrangUser))[2];
        my ($gid) = (getgrnam(KrangGroup))[2];
        chown($uid, $gid, $log)
          or croak("Unable to chown '$log' to $uid, $gid : $!");
    }

    # set logging level using LogLevel directive; convert arg to int
    # if we have a string
    my $level = Krang::Conf->loglevel();
    croak("Value required for LogLevel directive in 'krang.conf'.")
        unless defined $level and length $level;

    # handle default log level
    my @parts = split(',', $level);
    $LOG_LEVEL_DEFAULT = shift(@parts);
    croak("Invalid LogLevel '$level': must begin with a number.")
      unless $LOG_LEVEL_DEFAULT =~ /^\d+$/;
    croak("Invalid LogLevel: '$level' : numbers must be valid log levels.")
        unless exists $valid_levels{$LOG_LEVEL_DEFAULT};

    # parse out extended log levels
    for (@parts) {
        if (m!^\s*/([^=\s]+)/\s*=\s*(\d+)\s*$!) {
            my ($regex, $val) = ($1, $2);
            croak("Invalid LogLevel: '$level' : " .
                  "numbers must be valid log levels.")
              unless exists $valid_levels{$val};
            push(@LOG_LEVEL_REGEX, [ qr/$regex/ => $val ]);
        } elsif (m!([\w:]+)\s*=\s*(\d+)\s*$!) {
            my ($module, $val) = ($1, $2);
            croak("Invalid LogLevel: '$level' : " .
                  "numbers must be valid log levels.")
              unless exists $valid_levels{$val};
            $LOG_LEVEL_PER_MODULE{$module} =  $val;
        } else {
            croak("Unable to parse LogLevel '$level': bad token '$_'");
        }
    }

    if (not @parts) {
        if ($LOG_LEVEL_DEFAULT != 3) {
            eval 'sub debug ($) { }';
        } else {
            eval 'sub debug    ($) { __PACKAGE__->log(level => "debug",    message => shift); }';
        }

        if ($LOG_LEVEL_DEFAULT == 1) {
            eval 'sub info ($) { }';
        } else {
            eval 'sub info     ($) { __PACKAGE__->log(level => "info",     message => shift); }';
        }

    } else {
         eval 'sub debug    ($) { __PACKAGE__->log(level => "debug",    message => shift); }';
        eval 'sub info     ($) { __PACKAGE__->log(level => "info",     message => shift); }';
    }

    # turn assertions on or off based on KRANG_ASSERT or Assertions
    # conf setting
    my $assert_on = exists $ENV{KRANG_ASSERT} ? $ENV{KRANG_ASSERT} :
      Krang::Conf->assertions();

    # set PERL_NDEBUG to control Carp::Assert
    $ENV{PERL_NDEBUG} = not $assert_on;
}

# load Capr::Assert and rename DEBUG to ASSERT
use Carp::Assert qw(assert affirm should shouldnt DEBUG);
use constant ASSERT => DEBUG;
use constant REOPEN => $reopen_log;

=pod

=head1 INTERFACE

=over 4

=item * log

Most of the work for this module is done here.  All calls to convenience
methods are routed through AUTOLOAD() to here; function calls exported via
import() are redirected to AUTOLOAD() which in turn end up here.

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

    # check for the required arguments
    my $level = $args{level};
    my $message = $args{message};    
    croak("Required argument level parameter was not passed.")
      unless $level;
    croak("Required argument level parameter was not passed.")
      unless $message;

    # check for valid log level
    my ($level_IV, $level_PV);
    if ($level =~ /^\d+$/) {
        $level_IV = $level;

        croak("Invalid log level '$level_IV'.")
          unless exists $valid_levels{$level_IV};

        # retrieve string equivalent
        $level_PV = $valid_levels{$level_IV};
    } else {
        $level_PV = $level;

        croak("Invalid method call '$level_PV'.")
          unless exists $valid_functions{$level_PV};

        $level_IV = $valid_functions{$level_PV};
    }

    # check caller against defined log level setters
    my $log_level = $LOG_LEVEL_DEFAULT;
    my $i = 0;
    my $pkg;
    do {
        $pkg = (caller($i++))[0];
    } while ($pkg eq 'Krang::Log' and $i < 100);

    if (exists $LOG_LEVEL_PER_MODULE{$pkg}) {
        $log_level = $LOG_LEVEL_PER_MODULE{$pkg};
    } elsif (@LOG_LEVEL_REGEX) {
        for my $test (@LOG_LEVEL_REGEX) {
            my ($regex, $val) = @$test;
            if ($pkg =~ /$regex/) {
                $log_level = $val;
                last;
            }
        }
    }

    # don't bother to do anything if the log level is below muster
    return unless $level_IV <= $log_level;

    # calculate timestamp
    my $timestamp = "[" . localtime()->strftime('%D %T') . "] ";

    # print message to file
    $message = $timestamp . "[" . Krang::Conf->instance . "] [" . lc($level_PV) . "] $message";

    # make sure message ends in a newline
    $message .= "\n" unless $message =~ /\n\z/;

    # reopen filehandle if we're running under the Daemon
    $self->_reopen_log() if REOPEN;

    # try to obtain an exclusive lock
    # croak("Failed to obtain file lock : $!")
    #   unless (flock($LOG->{fh}, LOCK_EX) || REOPEN);

    print LOG $message;

    # release lock - does it have a return value?
    # croak("Unable to unlock logfile: $!")
    #  unless (flock($LOG->{fh}, LOCK_UN) || REOPEN);

    # return value for Tests...
    return $message;
}

=item * debug($msg)

Log a message at the debug level.  Available for export.

=item * info($msg)

Log a message at the info level.  Available for export.

=item * critical($msg)

Log a message at the critical level.  Available for export.

=cut

sub critical ($) { __PACKAGE__->log(level => 'critical', message => shift); }

=item * assert

=item * affirm

=item * should

=item * shouldnt

These functions are exported directly from Carp::Assert, with one
change.  Instead of using the DEBUG constant, use the ASSERT constant
exported by Krang::Log.  For all other information, see
L<Carp::Assert>.

=cut

# for some reason in the course of forking via Proc::Daemon some bad file
# descriptors come out of the woodwork, this is the jury-rigging to attempt to
# handle it
sub _reopen_log {
    my $self = shift;

    open(LOG, ">>", $LOG->{path}) or
      croak("Unable to open logfile, $LOG->{path}: $!\n");
}


=back

=head1 TO DO

=over 4

=item * Fix flock() bugs and re-enable flock() around print() to log.

=item * Log tracing for errors.

=back

=head1 SEE ALSO

L<Krang>, L<Krang::Conf>, L<Time::Piece>

=cut


my $quote = <<END;
But, Mousie, thou art no thy lane
In proving foresight may be vain:
The best-laid schemes o' mice an' men
                Gang aft agley,
An' lea'e us nought but grief an' pain,
                For promised joy.

--Robert Burns, from 'To a Mouse'
END

