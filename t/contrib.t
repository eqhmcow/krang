use Test::More qw(no_plan);
use strict;
use warnings;
use Krang::Script;

BEGIN { use_ok('Krang::Contrib') }

# create new contributor object
my $contrib = Krang::Contrib->new(prefix => 'Mr', first => 'Matthew', middle => 'Charles', last => 'Vella', email => 'mvella@thepirtgroup.com');
isa_ok($contrib, 'Krang::Contrib');

$contrib->contrib_type_ids(1,3);
$contrib->selected_contrib_type(1);

my @contrib_type_ids = $contrib->contrib_type_ids();
is("@contrib_type_ids", "1 3");
is($contrib->selected_contrib_type, 1);

eval { $contrib->selected_contrib_type(2) };
like($@, qr/bad/);

$contrib->save();

my $contrib_id = $contrib->contrib_id();

my @contrib_object = Krang::Contrib->find( contrib_id => $contrib_id );

my $contrib2 = $contrib_object[0];

is($contrib2->first, 'Matthew');
is($contrib2->contrib_type_ids()->[0], 1);
is($contrib2->contrib_type_ids()->[1], 3);

$contrib2->contrib_type_ids(2,4);

$contrib2->save();

my @contrib_object2 = Krang::Contrib->find( full_name => 'matt vella' );

my $contrib3 = $contrib_object2[0];

is($contrib3->contrib_id, $contrib_id);

# test count
my $count = Krang::Contrib->find( full_name => 'matt vella',
                                  count     => 1 );
is($count, 1);


# Test ability to make a change to an existing record and save()
$contrib2->first('George1234');
$contrib2->save();

# Has contrib2 been updated in database?
my ($contrib2loaded) = Krang::Contrib->find( contrib_id => $contrib2->contrib_id() );
is($contrib2loaded->first(), 'George1234');


## Test simple_search()
#
# Should find one
my @ss_contribs = Krang::Contrib->find(simple_search=>'George1234 Vella');
is(scalar(@ss_contribs), 1);

# Should find one
@ss_contribs = Krang::Contrib->find(simple_search=>'George1234');
is(scalar(@ss_contribs), 1);

# Should find one
@ss_contribs = Krang::Contrib->find(simple_search=>'Vella');
is(scalar(@ss_contribs), 1);

# Should find NONE
@ss_contribs = Krang::Contrib->find(simple_search=>'George1234 Carlin');
is(scalar(@ss_contribs), 0);

# Clean up added contrib
$contrib2->delete();

# create a few contribs to test ordering
my @contribs;
push(@contribs,
     Krang::Contrib->new(first => 'Bohemia', last => 'Bolger'),
     Krang::Contrib->new(first => 'Alvin', last => 'Arthur'),
     Krang::Contrib->new(first => 'Conifer', last => 'Caligula'));
$_->contrib_type_ids(1) for @contribs;
$_->save for @contribs;
END { $_->delete for @contribs };
my %ids = map { $_->contrib_id, 1 } @contribs;

my @results = grep { $ids{$_->contrib_id} } 
  Krang::Contrib->find(order_by => 'first');
is(@results, 3);
is($results[0]->contrib_id, $contribs[1]->contrib_id);
is($results[1]->contrib_id, $contribs[0]->contrib_id);
is($results[2]->contrib_id, $contribs[2]->contrib_id);

@results = grep { $ids{$_->contrib_id} } 
  Krang::Contrib->find(order_by => 'first', order_desc => 1);
is(@results, 3);
is($results[2]->contrib_id, $contribs[1]->contrib_id);
is($results[1]->contrib_id, $contribs[0]->contrib_id);
is($results[0]->contrib_id, $contribs[2]->contrib_id);

@results = grep { $ids{$_->contrib_id} } 
  Krang::Contrib->find(order_by => 'last,first', order_desc => 1);
is(@results, 3);
is($results[2]->contrib_id, $contribs[1]->contrib_id);
is($results[1]->contrib_id, $contribs[0]->contrib_id);
is($results[0]->contrib_id, $contribs[2]->contrib_id);


# Test exclude_contrib_ids: Filter set of contribs based on ID
{
    # Create set of contribs
    my @first_names = qw(Jesse Matt Sam Rudy Adam Peter);
    my @last_names = qw(One Two Three Four Five Six);
    my @types = qw(1 2 3);
    my @new_contribs = ();
    for (0..5) {
        my $c = Krang::Contrib->new(
                            first => $first_names[$_],
                            last => "TestGuy_" . $last_names[$_],
                            contrib_type_ids => [ $types[rand(3)] ],
                           );
        $c->save();
        push(@new_contribs, $c);
    }

    my @exclude_contrib_ids = map { $_->contrib_id() } @new_contribs[0..2];

    # Select back contribs, with and without exclusions.  We should get exactly three more without
    my $count = Krang::Contrib->find(count=>1);
    my $count_excluded = Krang::Contrib->find(count=>1, exclude_contrib_ids=>\@exclude_contrib_ids);

    # Is that what we got?
    is(($count - $count_excluded), 3, "exclude_contrib_ids");

    # Delete test contribs
    $_->delete() for (@new_contribs);
}


# make sure contribs without middle names are caught as dups
my $con1 = Krang::Contrib->new(first => 'Bobby', last => 'Bob');
$con1->save();
END { $con1->delete() };
my $con2 = Krang::Contrib->new(first => 'Bobby', last => 'Bob');
eval { $con2->save() };
isa_ok($@, 'Krang::Contrib::DuplicateName');


# test Krang::Contrib->full_name()
my $contrib4 = Krang::Contrib->new(prefix => 'Mr', first => 'Homer', middle => '', last => 'Simpson', email => 'homer@thepirtgroup.com');
my $name1 = 'Mr Homer Simpson';
my $name2 = 'Mr Homer Jay Simpson';
my $name3 = 'Mr Homer Jay Simpson, MD';

ok($contrib4->full_name() eq $name1, 'Krang::Contrib->full_name()');

$contrib4->middle('Jay');

ok($contrib4->full_name() eq $name2, 'Krang::Contrib->full_name()');

$contrib4->suffix('MD');

ok($contrib4->full_name() eq $name3, 'Krang::Contrib->full_name()');

$contrib4->suffix(undef);
$contrib4->middle(undef);

ok($contrib4->full_name() eq $name1, 'Krang::Contrib->full_name()');

