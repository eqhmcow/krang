use Krang::ClassFactory qw(pkg);

use Test::More qw(no_plan);

use strict;
use warnings;

use Krang::ClassLoader 'Script';
use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader Conf    => qw(KrangRoot InstanceElementSet);
use Krang::ClassLoader DB      => qw(dbh);

use File::Spec::Functions;
use Time::Piece;

use Krang::ClassLoader 'Test::Content';

BEGIN {
    use_ok(pkg('Story'));
    use_ok(pkg('Media'));
}

# make sure we don't fail because TrashMaxItems is too low
BEGIN {
    my $trash = qq{TrashMaxItems "1000"\n};
    my $fh    = IO::Scalar->new(\$trash);
    $Krang::Conf::CONF->read($fh);
}

# use the TestSet1 instance, if there is one
foreach my $instance (pkg('Conf')->instances) {
    pkg('Conf')->instance($instance);
    if (InstanceElementSet eq 'TestSet1') {
        last;
    }
}

# use Krang::Test::Content to create sites.
my $creator = pkg('Test::Content')->new;

END {
    $creator->cleanup();
}

my $site = $creator->create_site(
    preview_url  => 'trash_and_retire_test.preview.com',
    publish_url  => 'trash_and_retire_test.com',
    preview_path => '/tmp/trash_and_retire_test_preview',
    publish_path => '/tmp/trash_and_retire_test_publish'
);

isa_ok($site, 'Krang::Site');

# create categories.
my $category = $creator->create_category();
isa_ok($category, 'Krang::Category');

my @cats = ();
push @cats, $creator->create_category() for 1 .. 5;

# test objects Story, Media and Template
test_this($_)
  for (
    [qw(story    stories   slug    ), [{}, {}, {}, {}, {}]],
    [
        qw(media    media     filename),
        [
            {format => 'png'},
            {format => 'png'},
            {format => 'png'},
            {format => 'png'},
            {format => 'png'}
        ]
    ],
    [
        qw(template templates filename),
        [
            {element_name => 'element', content => 'x', category => $cats[0]},
            {element_name => 'element', content => 'x', category => $cats[1]},
            {element_name => 'element', content => 'x', category => $cats[2]},
            {element_name => 'element', content => 'x', category => $cats[3]},
            {element_name => 'element', content => 'x', category => $cats[4]},
        ]
    ],
  );

sub test_this {
    my $spec = shift;

    my $object  = $spec->[0];
    my $objects = $spec->[1];
    my $fn      = $spec->[2];
    my $args    = $spec->[3];
    my $Object  = ucfirst($object);

    my $create_meth = 'create_' . $object;
    my $obj_id      = $object . '_id';

    # create some objects
    my @args = @$args;
    my $obj0 = $creator->$create_meth(%{$args->[0]});
    my $obj1 = $creator->$create_meth(%{$args->[1]});
    my $obj2 = $creator->$create_meth(%{$args->[2]});
    my $obj3 = $creator->$create_meth(%{$args->[3]});
    my $obj4 = $creator->$create_meth(%{$args->[4]});

    my @objects = ($obj0, $obj1, $obj2, $obj3, $obj4);
    my ($oid0, $oid1, $oid2, $oid3, $oid4) = map { $_->$obj_id } @objects;
    my ($fn0,  $fn1,  $fn2,  $fn3,  $fn4)  = map { $_->$fn } @objects;

    # initially neither retired nor trashed
    is($_->retired, 0, "$Object is not retired") for @objects;
    is($_->trashed, 0, "$Object is not trashed") for @objects;

    my @live = pkg($Object)->find();
    is(scalar(@live), 5, "Five $objects alive");

    # test archiving
    $obj0->retire();
    is($obj0->retired, 1, "$Object $oid0 is retired");
    is($obj0->trashed, 0, "$Object $oid0 is not trashed");

    @live = pkg($Object)->find();
    is(scalar(@live), 4, "Four $objects alive");

    my @retired = pkg($Object)->find(include_live => 0, include_retired => 1);
    is(scalar(@retired), 1, "One $object retired");
    is($retired[0]->$obj_id, $oid0, "Found correct retired $object");

    my @trashed = pkg($Object)->find(include_live => 0, include_trashed => 1);
    is(scalar(@trashed), 0, "No $objects trashed");

    # find retired $object by ID does not need the include_retired search option
    my @found_by_id = pkg($Object)->find($obj_id => $oid0);
    is(scalar(@found_by_id), 1,
        "Archived $Object found by ID without include_retired search option");

    $obj0->unretire();
    is($obj0->retired, 0, "$Object $oid0 is not retired");
    is($obj0->trashed, 0, "$Object $oid0 is not trashed");

    @live = pkg($Object)->find();
    is(scalar(@live), 5, "Five $objects alive");

    my $count = pkg($Object)->find(count => 1);
    is($count, 5, "Five $objects alive (with count option)");

    @retired = pkg($Object)->find(include_live => 0, include_retired => 1);
    is(scalar(@retired), 0, "No $objects retired");

    $count = pkg($Object)->find(include_live => 0, include_retired => 1, count => 1);
    is($count, 0, "No $objects retired (with count option)");

    @trashed = pkg($Object)->find(include_live => 0, include_trashed => 1);
    is(scalar(@trashed), 0, "No $objects trashed");

    $count = pkg($Object)->find(include_live => 0, include_trashed => 1, count => 1);
    is($count, 0, "No $objects trashed (with count option)");

    # test trashing
    $obj0->trash();
    is($obj0->trashed, 1, "$Object $oid0 is trashed");
    is($obj0->retired, 0, "$Object $oid0 is not retired");

    @live = pkg($Object)->find();
    is(scalar(@live), 4, "Four $objects alive");

    @trashed = pkg($Object)->find(include_live => 0, include_trashed => 1);
    is(scalar(@trashed), 1, "One $object trashed");
    is($trashed[0]->$obj_id, $oid0, "Found correct trashed $object");

    $count = pkg($Object)->find(include_live => 0, include_trashed => 1, count => 1);
    is($count, 1, "One $object trashed (found with count option)");

    @retired = pkg($Object)->find(include_live => 0, include_retired => 1);
    is(scalar(@retired), 0, "No $objects retired");

    $count = pkg($Object)->find(include_live => 0, include_retired => 1, count => 1);
    is($count, 0, "No $objects retired (with count option)");

    # find trashed $object by ID does not need the include_trashed search option
    @found_by_id = pkg($Object)->find($obj_id => $oid0);
    is(scalar(@found_by_id), 1,
        "Trashed $Object found by ID without include_trashed search option");

    $obj0->untrash();
    is($obj0->retired, 0, "$Object $oid0 is not retired");
    is($obj0->trashed, 0, "$Object $oid0 is not trashed");

    @live = pkg($Object)->find();
    is(scalar(@live), 5, "Five $objects alive");

    @trashed = pkg($Object)->find(include_live => 0, include_trashed => 1);
    is(scalar(@trashed), 0, "No $objects trashed");

    @retired = pkg($Object)->find(include_live => 0, include_retired => 1);
    is(scalar(@retired), 0, "No $objects retired");

    @trashed = pkg($Object)->find(include_live => 0, include_trashed => 1, ids_only => 1);
    is(scalar(@trashed), 0, "No $objects trashed (with ids_only option)");

    @retired = pkg($Object)->find(include_live => 0, include_retired => 1, ids_only => 1);
    is(scalar(@retired), 0, "No $objects retired (with ids_only option)");

    # test trashing of previously retired $object
    $obj0->retire();
    $obj1->retire();
    $obj2->trash();

    is($obj0->retired, 1, "$Object $oid0 is retired");
    is($obj1->retired, 1, "$Object $oid1 is retired");

    @live = pkg($Object)->find();
    is(scalar(@live), 2, "Two $objects alive");

    @retired = pkg($Object)->find(include_live => 0, include_retired => 1);
    is(scalar(@retired), 2, "Two $objects retired");

    @trashed = pkg($Object)->find(include_live => 0, include_trashed => 1);
    is(scalar(@trashed), 1, "One $object trashed");
    is($trashed[0]->$obj_id, $oid2, "Found correct trashed $object");

    $obj1->trash();

    is($obj1->trashed, 1, "$Object $oid1 is trashed");
    is($obj1->retired, 1, "$Object $oid1 still has retired flag (to restore it later to retire)");

    @live = pkg($Object)->find();
    is(scalar(@live), 2, "Two $objects alive");

    @retired = pkg($Object)->find(include_live => 0, include_retired => 1);
    is(scalar(@retired), 1, "One $object retired");
    is($retired[0]->$obj_id, $oid0, "Found correct retired $object");

    @trashed = pkg($Object)->find(include_live => 0, include_trashed => 1);
    is(scalar(@trashed), 2, "Two $objects trashed");

    $obj1->untrash();

    is($obj1->trashed, 0, "$Object $oid1 no longer trashed");
    is($obj1->retired, 1, "$Object $oid1 again retired");

    @live = pkg($Object)->find();
    is(scalar(@live), 2, "Two $objects alive");

    @retired = pkg($Object)->find(include_live => 0, include_retired => 1);
    is(scalar(@retired), 2, "Two $objects retired");

    @trashed = pkg($Object)->find(include_live => 0, include_trashed => 1);
    is(scalar(@trashed), 1, "One $object trashed");
    is($trashed[0]->$obj_id, $oid2, "Found correct trashed $object");

    $obj1->unretire();

    is($obj1->trashed, 0, "$Object $oid1 not trashed");
    is($obj1->retired, 0, "$Object $oid1 not retired");

    @live = pkg($Object)->find();
    is(scalar(@live), 3, "Three $objects alive");

    @retired = pkg($Object)->find(include_live => 0, include_retired => 1);
    is(scalar(@retired), 1, "One $object retired");
    is($retired[0]->$obj_id, $oid0, "Found correct retired $object");

    @trashed = pkg($Object)->find(include_live => 0, include_trashed => 1);
    is(scalar(@trashed), 1, "One $object trashed");

    # test creation of $object with same URL as retired $object
    $obj0->retire();
    is($obj0->retired, 1, "$Object $oid0 is retired");

    my $dup00 = '';
    $fn0 =~ s/\.png$//;    # special for Media: strip the file extension
    eval { $dup00 = $creator->$create_meth($fn => $fn0, %{$args->[0]}) };
    ok(not($@), "Dup 1 of $Object $oid0 created");

    # retire dup00 and try to create dup01
    $dup00->retire();
    is($dup00->retired, 1, "Dup 1 of $Object $oid0 retired");

    my $dup01 = '';
    eval { $dup01 = $creator->$create_meth($fn => $fn0, %{$args->[0]}) };
    ok(not($@), "Dup 2 of $Object $oid0 created");

    # try to unretire $obj0 and $dup00 - should throw an error
    eval { $obj0->unretire() };
    isa_ok($@, "Krang::${Object}::DuplicateURL");

    eval { $dup00->unretire() };
    isa_ok($@, "Krang::${Object}::DuplicateURL");

    # test DuplicateURL throwing when untrashing
    $dup01->trash;
    my $dup01_id = $dup01->$obj_id;
    is($dup01->trashed, 1, "Dup 2 of $Object $oid0 is trashed");
    is($dup01->retired, 0, "Dup 2 of $Object $oid0 is not retired");

    # create another dupe
    my $dup03 = '';
    eval { $dup03 = $creator->$create_meth($fn => $fn0, %{$args->[0]}) };
    ok(not($@), "Dup 3 of $Object $oid0 created");

    # try to untrash $dup01 - should throw exception
    eval { $dup01->untrash };
    isa_ok($@, "Krang::${Object}::DuplicateURL");

    # now trash retired objects
    $obj0->trash;
    is($obj0->trashed, 1, "$Object $oid0 is trashed");
    is($obj0->retired, 1, "$Object $oid0 still has retired flag set");

    $dup00->trash;
    is($dup00->trashed, 1, "Dup 1 of $Object $oid0 is trashed");
    is($dup00->retired, 1, "Dup 1 of $Object $oid0 still has retired flag set");

    # ... and untrash them - should both land in Archive without DuplicateURL error
    $obj0->untrash;
    is($obj0->trashed, 0, "$Object $oid0 is untrashed");
    is($obj0->retired, 1, "$Object $oid0 lives in retire again");

    $dup00->untrash;
    is($dup00->trashed, 0, "Dup 1 of $Object $oid0 is untrashed");
    is($dup00->retired, 1, "Dup 1 of $Object $oid0 lives in retire again");

    END { my $dbh = dbh; $dbh->do("DELETE FROM trash") }
}
use Data::Dumper;
