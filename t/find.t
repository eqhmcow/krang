use Test::More qw(no_plan);
use File::Find qw(find);
use Krang::Script;

# a list of non-CGI Krang modules without a suitable find method
our %BAD_DEFAULT = map { ($_,1) } (qw( Krang::DB Krang::History ));

# Hash of known field names for "order_by" test
our %ORDER_BY_FIELD = (
                       Krang::Category => 'category_id',
                       Krang::Contrib => 'contrib_id',
                       Krang::Media => 'media_id',
                       Krang::Site => 'site_id',
                       Krang::Story => 'story_id',
                       Krang::Template => 'template_id',
                       Krang::User => 'user_id',
                      );

# Check all Krang object modules
find({
      wanted => sub { 
           return unless /^lib\/(Krang\/.*)\.pm$/;
           return if /#/; # skip emacs droppings
           return if /^lib\/Krang\/CGI/;  # Skip CGIs

           my $perl_package = join('::', (split(/\//, $1)));
           check_find($perl_package);
       },
       no_chdir => 1
     },
     'lib/Krang/');


# A Krang object module find() method is OK if:
#    1. count=>1 returns count which matches subsequent searches.
#    2. returns list of objects by default
#    3. ids_only=>1 returns list of non-objects by default
#    4. count=>1 and ids_only=>1 is fatal error
#    5. order_desc=>1 reverses order_desc=>0
#    6. limit=>1 returns only one record
#    7. offset=>1, limit=>1 returns the next record
#    8. unknown param is fatal error
#    9. Can't test "order_by" without known column names
#
sub check_find {
    my $perl_package = shift;

    # skip modules without a suitable find()
    next if $BAD_DEFAULT{$perl_package};

    # Can we load the module?
    require_ok($perl_package);

    # It's all good if $perl_package can't find()
    next unless ($perl_package->can('find'));

    # print STDERR "Can find():  $perl_package\n";

    # 1. count=>1 returns count which matches subsequent searches.
    my $count;
    eval { $count = $perl_package->find(count=>1) };
    ok(not($@), "$perl_package->find(count=>1)");
    die ($@) if ($@);

    # 2. returns list of objects by default, or empty array
    my @stuff;
    eval { @stuff = $perl_package->find() };
    ok(not($@), "$perl_package->find()");
    die ($@) if ($@);
    is(scalar(@stuff), $count, "$perl_package->find():  Found $count objects");

    # 3. ids_only=>1 returns list of non-objects by default
    eval { @stuff = $perl_package->find(ids_only=>1) };
    ok(not($@), "$perl_package->find(ids_only=>1)");
    die ($@) if ($@);
    ok(not(grep { ref($_) } @stuff), "$perl_package->find(ids_only=>1):  Results are not objects");

    # 4. count=>1 and ids_only=>1 is fatal error
    $@ = undef;  # Clear error
    eval { $perl_package->find(ids_only=>1, count=>1) };
    ok($@, "$perl_package->find(ids_only=>1, count=>1):  Is fatal error");

    # 5. order_desc=>1 reverses order_desc=>0

    # 6. limit=>1 returns only one record

    # 7. offset=>1, limit=>1 returns the next record

    # 8. unknown param is fatal error
    my $unknown_param = time() . '_no_such_param';

    # 9. Can't test "order_by" without known column names

}
