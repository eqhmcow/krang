use strict;

use Data::Dumper;
use Test::More qw(no_plan);
use Time::Piece;

use Krang::Script;

# set debug flag
$ENV{SCH_DEBUG} = 1;

BEGIN {use_ok('Krang::Schedule');}

my $date = localtime;
my $day_factor = $date->day_of_week == 0 ? 6 : $date->day_of_week - 1;
my $hour_factor = $date->hour == 0 ? 19 : $date->hour - 4;
my $min_factor = $date->minute == 0 ? 56 : $date->minute - 4;

# I.A
our $s1 = Krang::Schedule->new(action => 'publish',
                              object_id => 1,
                              object_type => 'story',
                              repeat => 'weekly',
                              day_of_week => $day_factor,
                              hour => $date->hour,
                              minute => 15);

# I.B
our $s2 = Krang::Schedule->new(action => 'publish',
                              object_id => 1,
                              object_type => 'story',
                              repeat => 'weekly',
                              day_of_week => $date->day_of_week + 1,
                              hour => $date->hour,
                              minute => 15);

# I.C && I.E
our $s3 = Krang::Schedule->new(action => 'publish',
                              object_id => 1,
                              object_type => 'story',
                              repeat => 'weekly',
                              day_of_week => $date->day_of_week,
                              hour => $date->hour + 4,
                              minute => 15);

# I.D.i
our $s4 = Krang::Schedule->new(action => 'publish',
                              object_id => 1,
                              object_type => 'story',
                              repeat => 'weekly',
                              day_of_week => $date->day_of_week,
                              hour => $hour_factor,
                              minute => 15);

# I.D.ii
our $s5 = Krang::Schedule->new(action => 'publish',
                              object_id => 1,
                              object_type => 'story',
                              repeat => 'weekly',
                              day_of_week => $date->day_of_week + 1,
                              hour => $hour_factor,
                              minute => 15);

# I.F
our $s6 = Krang::Schedule->new(action => 'publish',
                              object_id => 1,
                              object_type => 'story',
                              repeat => 'weekly',
                              day_of_week => $date->day_of_week,
                              hour => $date->hour,
                              minute => $date->minute + 4);

# I.G.i
our $s7 = Krang::Schedule->new(action => 'publish',
                              object_id => 1,
                              object_type => 'story',
                              repeat => 'weekly',
                              day_of_week => $date->day_of_week,
                              hour => $date->hour,
                              minute => $min_factor);

# I.G.ii
our $s8 = Krang::Schedule->new(action => 'publish',
                              object_id => 1,
                              object_type => 'story',
                              repeat => 'weekly',
                              day_of_week => $date->day_of_week,
                              hour => $date->hour + 1,
                              minute => $min_factor);

# I.H
our $s9 = Krang::Schedule->new(action => 'publish',
                              object_id => 1,
                              object_type => 'story',
                              repeat => 'weekly',
                              day_of_week => $date->day_of_week,
                              hour => $date->hour,
                              minute => $date->minute + 4);

# II.A && II.D.ii
our $s10 = Krang::Schedule->new(action => 'publish',
                               object_id => 1,
                               object_type => 'story',
                               repeat => 'daily',
                               hour => $hour_factor,
                               minute => $min_factor);

# II.B
our $s11 = Krang::Schedule->new(action => 'publish',
                               object_id => 1,
                               object_type => 'story',
                               repeat => 'daily',
                               hour => $date->hour + 4,
                               minute => $date->minute);

# II.C && II.D.i
our $s12 = Krang::Schedule->new(action => 'publish',
                               object_id => 1,
                               object_type => 'story',
                               repeat => 'daily',
                               hour => $date->hour,
                               minute => $min_factor);

# II.E
our $s13 = Krang::Schedule->new(action => 'publish',
                               object_id => 1,
                               object_type => 'story',
                               repeat => 'daily',
                               hour => $date->hour,
                               minute => $date->minute + 4);

# III.A
our $s14 = Krang::Schedule->new(action => 'publish',
                               object_id => 1,
                               object_type => 'story',
                               repeat => 'hourly',
                               minute => $min_factor);

# III.B
our $s15 = Krang::Schedule->new(action => 'publish',
                               object_id => 1,
                               object_type => 'story',
                               repeat => 'hourly',
                               minute => $date->minute);

{
    no strict;
    for (1..15) {
        isa_ok(${"s$_"}, 'Krang::Schedule');
        my $obj = ${"s$_"}->save();
        isa_ok($obj, 'Krang::Schedule');
    }
}

eval {Krang::Schedule->run()};
is($@ eq '', 1, 'run() test did not fail');

# delete
is($_->delete, 1, 'deletion test') for Krang::Schedule->find;
