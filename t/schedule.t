use strict;

use Carp qw/verbose croak/;
use Data::Dumper;
use File::Spec;
use IO::File;
use Test::More qw(no_plan);
use Time::Piece;
use Time::Piece::MySQL;
use Time::Seconds;

use Krang::Script;

BEGIN {
    # set debug flag
    $ENV{SCH_DEBUG} = 1;
    use_ok('Krang::Schedule');
}

my ($date, $next_run);
my $now = localtime;
my $now_mysql = $now->mysql_datetime;
$now_mysql =~ s/:\d+$//;


# I.A
# putative run time for the current week has passed; set next_run to the next
# future runtime in the subsequent week.
$date = Time::Piece->from_mysql_datetime("2003-04-04 12:00:00");
our $s1 = Krang::Schedule->new(action => 'publish',
                               object_id => 1,
                               object_type => 'story',
                               repeat => 'weekly',
                               day_of_week => $date->day_of_week,
                               hour => $date->hour,
                               minute => $date->minute);
eval {isa_ok($s1->save(), 'Krang::Schedule')};
is($@, '', 'save() works :)');
like($s1->{next_run}, qr/^2003-04-11 12:00/, 'next_run check 1');


# I.B
# next_run will be set to some time later this week
# run date is two days in the future...
$date = $now + (2 * ONE_DAY);
our $s2 = Krang::Schedule->new(action => 'publish',
                               object_id => 1,
                               object_type => 'story',
                               repeat => 'weekly',
                               day_of_week => $date->day_of_week,
                               hour => $date->hour,
                               minute => $date->min);

eval {isa_ok($s2->save(), 'Krang::Schedule')};
is($@, '', 'save() works :)');

$next_run = Time::Piece->from_mysql_datetime($s2->{next_run}) + 2;
is($next_run->day_of_week, $date->day_of_week, 'next_run check 2');


# I.C && I.E
# next_run should be set to sometime today, in the future...

# 2 hrs in the future
$date = $now + (2 * ONE_HOUR);
our $s3 = Krang::Schedule->new(action => 'publish',
                               object_id => 1,
                               object_type => 'story',
                               repeat => 'weekly',
                               day_of_week => $date->day_of_week,
                               hour => $date->hour,
                               minute => $date->minute);

eval {isa_ok($s3->save(), 'Krang::Schedule')};
is($@, '', 'save() works :)');

$next_run = Time::Piece->from_mysql_datetime($s3->{next_run}) - (2 * ONE_HOUR);
($next_run = $next_run->mysql_datetime) =~ s/:\d+$//;
is($next_run, $now_mysql, 'next_run check 3');


# I.C && I.D.i
# advance next_run to next week because the hour on which it was expected to
# run today has already passed
$date = $now - ONE_HOUR;
our $s4 = Krang::Schedule->new(action => 'publish',
                               object_id => 1,
                               object_type => 'story',
                               repeat => 'weekly',
                               day_of_week => $date->day_of_week,
                               hour => $date->hour,
                               minute => $date->minute);

eval {isa_ok($s4->save(), 'Krang::Schedule')};
is($@, '', 'save() works :)');

$next_run = Time::Piece->from_mysql_datetime($s4->{next_run}) - ONE_WEEK +
  ONE_HOUR + ONE_HOUR;
($next_run = $next_run->mysql_datetime) =~ s/:\d+$//;
is($next_run, $now_mysql, 'next_run check 4');


# I.A && I.D.ii
# next run must be sometime next week less an our hour or more
$date = $now - ONE_DAY - ONE_HOUR;
our $s5 = Krang::Schedule->new(action => 'publish',
                               object_id => 1,
                               object_type => 'story',
                               repeat => 'weekly',
                               day_of_week => $date->day_of_week,
                               hour => $date->hour,
                               minute => $date->min);

eval {isa_ok($s5->save(), 'Krang::Schedule')};
is($@, '', 'save() works :)');

$next_run = Time::Piece->from_mysql_datetime($s5->{next_run}) - ONE_WEEK
  + ONE_DAY + ONE_HOUR + ONE_HOUR;
($next_run = $next_run->mysql_datetime) =~ s/:\d+$//;
is($next_run, $now_mysql, 'next_run check 5');


# I.C && I.F && I.H
# next_run will be set to this week, the present hour ,a few minutes in the
# future
$date = $now + (ONE_MINUTE * 4);
our $s6 = Krang::Schedule->new(action => 'publish',
                              object_id => 1,
                              object_type => 'story',
                              repeat => 'weekly',
                              day_of_week => $date->day_of_week,
                              hour => $date->hour,
                              minute => $date->minute);

eval {isa_ok($s6->save(), 'Krang::Schedule')};
is($@, '', 'save() works :)');

$next_run = Time::Piece->from_mysql_datetime($s6->{next_run}) -
  (ONE_MINUTE * 4);
($next_run = $next_run->mysql_datetime) =~ s/:\d+$//;
is($next_run, $now_mysql, 'next_run check 6');


# I.C && I.F && I.G.i
# next run advances a week because the minute of its putative run has passed
$date = $now - ONE_MINUTE;
our $s7 = Krang::Schedule->new(action => 'publish',
                              object_id => 1,
                              object_type => 'story',
                              repeat => 'weekly',
                              day_of_week => $date->day_of_week,
                              hour => $date->hour,
                              minute => $date->min);

eval {isa_ok($s7->save(), 'Krang::Schedule')};
is($@, '', 'save() works :)');

# - ONE_HOUR, inexplicable side effect of subtraction involving ONE_WEEK
$next_run = Time::Piece->from_mysql_datetime($s7->{next_run}) - ONE_WEEK
  - ONE_HOUR + ONE_HOUR + ONE_MINUTE;
($next_run = $next_run->mysql_datetime) =~ s/:\d+$//;
is($next_run, $now_mysql, 'next_run check 7');


# I.C && I.F && I.G.ii
# next_run is a minute or more in the future
$date = $now + ONE_MINUTE;
our $s8 = Krang::Schedule->new(action => 'publish',
                              object_id => 1,
                              object_type => 'story',
                              repeat => 'weekly',
                              day_of_week => $date->day_of_week,
                              hour => $date->hour,
                              minute => $date->min);

eval {isa_ok($s8->save(), 'Krang::Schedule')};
is($@, '', 'save() works :)');

$next_run = Time::Piece->from_mysql_datetime($s8->{next_run}) - ONE_MINUTE;
($next_run = $next_run->mysql_datetime) =~ s/:\d+$//;
is($next_run, $now_mysql, 'next_run check 8');


# II.A && II.D.ii
# next_run is set to tomorrow less a minute or so
$date = $now - ONE_HOUR - ONE_MINUTE;
our $s9 = Krang::Schedule->new(action => 'publish',
                               object_id => 1,
                               object_type => 'story',
                               repeat => 'daily',
                               hour => $date->hour,
                               minute => $date->min);

eval {isa_ok($s9->save(), 'Krang::Schedule')};
is($@, '', 'save() works :)');

# day and week subtraction is off by an hour
$next_run = Time::Piece->from_mysql_datetime($s9->{next_run}) - ONE_DAY
  + ONE_HOUR + ONE_MINUTE;
($next_run = $next_run->mysql_datetime) =~ s/:\d+$//;
is($next_run, $now_mysql, 'next_run check 9');


# II.B
# next_run is an hour or more in the future
$date = $now + ONE_HOUR;
our $s10 = Krang::Schedule->new(action => 'publish',
                                object_id => 1,
                                object_type => 'story',
                                repeat => 'daily',
                                hour => $date->hour,
                                minute => $date->min);

eval {isa_ok($s10->save(), 'Krang::Schedule')};
is($@, '', 'save() works :)');

$next_run = Time::Piece->from_mysql_datetime($s10->{next_run}) - ONE_HOUR;
($next_run = $next_run->mysql_datetime) =~ s/:\d+$//;
is($next_run, $now_mysql, 'next_run check 10');


# II.C && II.D.i
# next_run advances a day as its schedule hour has passed
$date = $now - ONE_HOUR;
our $s11 = Krang::Schedule->new(action => 'publish',
                                object_id => 1,
                                object_type => 'story',
                                repeat => 'daily',
                                hour => $date->hour,
                                minute => $date->min);

eval {isa_ok($s11->save(), 'Krang::Schedule')};
is($@, '', 'save() works :)');

# day and week subtraction is off by an hour
$next_run = Time::Piece->from_mysql_datetime($s11->{next_run}) - ONE_DAY
  + ONE_HOUR;
($next_run = $next_run->mysql_datetime) =~ s/:\d+$//;
is($next_run, $now_mysql, 'next_run check 11');


# II.E
# next run is set 1 or more minutes in the future
$date = $now + ONE_MINUTE;
our $s12 = Krang::Schedule->new(action => 'publish',
                                object_id => 1,
                                object_type => 'story',
                                repeat => 'daily',
                                hour => $date->hour,
                                minute => $date->min);

eval {isa_ok($s12->save(), 'Krang::Schedule')};
is($@, '', 'save() works :)');

$next_run = Time::Piece->from_mysql_datetime($s12->{next_run}) - ONE_MINUTE;
($next_run = $next_run->mysql_datetime) =~ s/:\d+$//;
is($next_run, $now_mysql, 'next_run check 12');


# III.A
# next_run advances an hour because its scheduled minute has passed;
$date = $now - ONE_MINUTE;
our $s13 = Krang::Schedule->new(action => 'publish',
                                object_id => 1,
                                object_type => 'story',
                                repeat => 'hourly',
                                minute => $date->min);

eval {isa_ok($s13->save(), 'Krang::Schedule')};
is($@, '', 'save() works :)');

$next_run = Time::Piece->from_mysql_datetime($s13->{next_run}) - ONE_HOUR +
  ONE_MINUTE;
($next_run = $next_run->mysql_datetime) =~ s/:\d+$//;
is($next_run, $now_mysql, 'next_run check 13');


# III.B
# next_run in now...should be run in Krang::Schedule->run
our $s14 = Krang::Schedule->new(action => 'publish',
                                object_id => 1,
                                object_type => 'story',
                                repeat => 'hourly',
                                minute => $now->minute,
                                context => [a => 1]);

eval {isa_ok($s14->save(), 'Krang::Schedule')};
is($@, '', 'save() works :)');

$next_run = Time::Piece->from_mysql_datetime($s14->{next_run});
($next_run = $next_run->mysql_datetime) =~ s/:\d+$//;
is($next_run, $now_mysql, 'next_run check 14');


# run test - 1 tests should run
my $path = File::Spec->catfile($ENV{KRANG_ROOT}, 'logs', "schedule_test.log");
my $log = IO::File->new(">>$path") ||
  croak("Unable to open logfile: $!");
my $count = Krang::Schedule->run($log);
is($count, 1, 'run() succeeded :).');

# force a save failure
$s1->repeat('fred');
eval {$s1->save()};
like($@, qr/'repeat' field set to invalid setting -/, 'save() failure test');

# delete everything
for (1..14) {
    no strict;
    is(${"s$_"}->delete, 1, "deletion test $_");
}

END {
    $log->close();
#    unlink $path;
}
