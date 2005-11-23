use Krang::ClassFactory qw(pkg);
use Test::More qw(no_plan);
use File::Find qw(find);
use Krang::ClassLoader 'Script';

# a list of non-CGI Krang modules with a suitable find method
our %TEST_PACKAGES = map { ($_,1) } (pkg('Alert'), pkg('Category'), pkg('Contrib'), pkg('Desk'), pkg('Group'), pkg('List'), pkg('ListGroup'), pkg('ListItem'), pkg('Media'), pkg('Site'), pkg('Story'), pkg('Template'), pkg('User'));

# Hash of known field names for "order_by" test
our %ORDER_BY_FIELD = (
                       pkg('Alert')    => 'alert_id', 
                       pkg('Category') => 'category_id',
                       pkg('Contrib')  => 'contrib_id',
                       pkg('Group')    => 'group_id',
                       pkg('List')     => 'list_id',
                       pkg('ListGroup') => 'list_group_id',
                       pkg('Media')    => 'media_id',
                       pkg('Site')     => 'site_id',
                       pkg('Story')    => 'story_id',
                       pkg('Template') => 'template_id',
                       pkg('User')     => 'user_id',
                      );

# Check all Krang object modules
find({
      wanted => sub { 
           return unless /^lib\/(Krang\/.*)\.pm$/;
           return if /#/; # skip emacs droppings
           return if /^lib\/Krang\/CGI/;  # Skip CGIs
           return if /^lib\/Krang\/Profiler/;  # Skip Profiler

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
#    9. "order_by" $ORDER_BY_FIELD{$perl_package}
#
sub check_find {
    my $perl_package = shift;

    # skip modules without a suitable find()
    return unless ($TEST_PACKAGES{$perl_package});

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
    my %order_params = (ids_only => 1, order_desc => 0);

    # Krang::List and Krang::ListItem require further grouping, or ordering will fail tests.
    if ($perl_package eq 'Krang::List') { $order_params{list_group_id} = 1; }
    if ($perl_package eq 'Krang::ListItem') { $order_params{list_id} = 1; }

    eval { @stuff = $perl_package->find(%order_params) };
    ok(not($@), "$perl_package->find(ids_only=>1, order_desc => 0)");
    die ($@) if ($@);

    $order_params{order_desc} = 1;
    eval { @stuff2 = $perl_package->find(%order_params) };
    ok(not($@), "$perl_package->find(ids_only=>1, order_desc => 1)");
    die ($@) if ($@);

    ok( eq_array([@stuff], [reverse @stuff2]), "$perl_package->find(ids_only=>1, order_desc => 1) : order_desc=>1 reverses order_desc=>0") 
      if @stuff;

    # 6. limit=>1 returns only one record
    unless ($perl_package eq 'Krang::Desk') { # Krang::Desk doesnt use limit
        eval { @stuff = $perl_package->find(limit=>1) };
        ok(not($@), "$perl_package->find(limit=>1)");
        die ($@) if ($@);

        # actually check for one or less records, since may be no records in db
        ok(scalar @stuff <= 1, "$perl_package->find(limit=>1) : limit=>1 returns only one record");
    }

    # 7. offset=>1, limit=>1 returns the next record
    unless ($perl_package eq 'Krang::Desk') { # Krang::Desk doesnt use offset
        eval { @stuff = $perl_package->find(limit=>2) };
        ok(not($@), "$perl_package->find(limit=>2)");
        die ($@) if ($@);

        eval { @stuff2 = $perl_package->find(offset=>1, limit=>1) };
        ok(not($@), "$perl_package->find(offset=>1, limit=>1) : offset=>1, limit=>1 returns the next record");
        die ($@) if ($@);

        my $order_by = $ORDER_BY_FIELD{$perl_package};
        if ($order_by) {
            is($stuff[1]->$order_by, $stuff2[0]->$order_by, "$perl_package->find(offset=>1, limit=>1) : offset=>1, limit=>1 returns the next record") if $stuff[1];
        }
    }

    # 8. unknown param is fatal error
    my $unknown_param = time() . '_no_such_param';
    eval { @stuff = $perl_package->find($unknown_param => 1) };
    ok($@, "$perl_package->find($unknown_param => 1) : unknown param is fatal error");
    
    # 9. order_by $ORDER_BY_FIELD{$perl_package}
    my $order_by = $ORDER_BY_FIELD{$perl_package};
    if ($order_by) {
        eval { @stuff = $perl_package->find( order_by => $order_by ) };
        ok(not($@), "$perl_package->find( order_by => $order_by )".' : order_by $ORDER_BY_FIELD{$perl_package}' );
    }    
}
