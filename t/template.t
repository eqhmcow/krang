use strict;
use warnings;

use Krang::Script;
use Krang::Category;
use Krang::Site;

use Data::Dumper;
use Test::More qw(no_plan);


BEGIN {use_ok('Krang::Template');}

# set up site and category
my $site = Krang::Site->new(preview_path => './sites/test1/preview/',
                            preview_url => 'preview.testsite1.com',
                            publish_path => './sites/test1/',
                            url => 'testsite1.com');
$site->save();
isa_ok($site, 'Krang::Site');

my ($category) = Krang::Category->find(site_id => $site->site_id());

# constructor failure
my $tmpl;
eval {$tmpl = Krang::Template->new(category => 'blah',
                                   content => 'blah',
                                   filename => 'A.tmpl')};
like($@, qr/'category' argument must be a 'Krang::Category'/s,
     'constructor failure');

# constructor success 1 - tests category arg
eval {$tmpl = Krang::Template->new(category => $category,
                                   content => '<blink><tmpl_var bob></blink>',
                                   filename => 'bob.tmpl')};
is($@, '', 'contructor good :)');

# constructor success 2
$tmpl = Krang::Template->new(category_id => $category->category_id(),
                             content => '<blink><tmpl_var bob></blink>',
                             filename => 'bob.tmpl');
isa_ok($tmpl, 'Krang::Template');

# test category meth
my $cat = $tmpl->category;
is($cat->dir, $category->dir, 'category() method test');

# increment version
$tmpl->save();
is($tmpl->version(), 1, 'Version Check');

# duplicate check
eval {
    my $tmplX = Krang::Template->new(category_id => $category->category_id(),
                                     filename => 'bob.tmpl');
    $tmplX->save();
};
is($@ =~ /Duplicate URL/, 1, 'duplicate_check()');

# save description for revert test
my $content = $tmpl->content();

# check Krang::MethodMaker meth...
$tmpl->content('<tmpl_var content>');
my $content2 = $tmpl->content();
is($content2, '<tmpl_var content>', 'Getter/Setter Test');

# increment version
$tmpl->save();
is($tmpl->version(), 2, 'Version Check 2');

# revert check
$tmpl->revert(1);
is($tmpl->content(), $content, 'Revert Test');

# increment version
$tmpl->save();
is($tmpl->version(), 3, 'Version Check 3');

# verify checkin works
$tmpl->checkin();
is($tmpl->checked_out, 0, 'Checkin Test');

# verify save fails on a checked-in object
eval{$tmpl->save()};
like($@, qr/Template isn't checked out/i, 'verify_checkout() Test');

# verify checkout works
is($tmpl->checkout()->isa('Krang::Template'), 1, 'Checkout Test');

my $tmpl2 = Krang::Template->new(category_id => $category->category_id(),
                                 content => '<html></html>',
                                 filename => 't_w_c.tmpl');

$tmpl2->save();


# test mark_as_deployed
eval { $tmpl2->mark_as_deployed(); };
if ($@) {
    diag($@);
    fail('Krang::Template->mark_as_deployed()');
} else {
    pass('Krang::Template->mark_as_deployed()');
    ok($tmpl2->deployed(), 'Krang::Template->mark_as_deployed()');
    ok($tmpl2->deployed_version() eq $tmpl2->version(), 'Krang::Template->mark_as_deployed()');
    ok($tmpl2->testing() eq 0, 'Krang::Template->mark_as_deployed()');
}

# test mark_as_undeployed
eval { $tmpl2->mark_as_undeployed(); };
if ($@) {
    diag($@);
    fail('Krang::Template->mark_as_undeployed()');
} else {
    pass('Krang::Template->mark_as_undeployed()');
    ok($tmpl2->deployed() == 0, 'Krang::Template->mark_as_undeployed()');
    ok(!defined($tmpl2->deployed_version()), 'Krang::Template->mark_as_undeployed()');
    ok(!defined($tmpl2->deploy_date()), 'Krang::Template->mark_as_undeployed()');
}



# find() tests
###############
# make sure find() croaks
eval {Krang::Template->find(count => 1, ids_only => 1)};
is($@ =~ /Only one/, 1, 'Find Failure 1');

eval {Krang::Template->find(XXX => 69)};
is($@ =~ /invalid/, 1, 'Find Failure 2');

my ($tmpl3) = Krang::Template->find(filename_like => '%bob%');
is(ref $tmpl3, 'Krang::Template', "Find - _like 1");

my @ids = ($tmpl->template_id(), $tmpl2->template_id());

my $i = 1;
my @tmpls = Krang::Template->find(template_id => \@ids);
is (ref $_, 'Krang::Template', "Find - template_id " . $i++) for @tmpls;

my $count = Krang::Template->find(count => 1, template_id => \@ids);
is($count, scalar @ids, "Find - count");

$i = 2;
my @tmpls2 = Krang::Template->find(creation_date_like => '%2003%');
is(ref $_, 'Krang::Template', "Find - _like " . $i++) for @tmpls2;

my ($tmpl4) = Krang::Template->find(limit => 1,
                                    offset => 1,
                                    order_by => 'filename',
                                    category_id => $category->category_id);
is($tmpl4->filename(), 't_w_c.tmpl', "Find - limit, offset, order_by");

my @tmpls5 = Krang::Template->find(order_desc => 1,
                                   creation_date_like => '%2003%',
                                   category_id => $category->category_id);
isa_ok($_, 'Krang::Template') for @tmpls5;
is($tmpls5[0]->filename(), 't_w_c.tmpl', "Find - ascend/descend");

# version find
my ($tmplXYZ) = Krang::Template->find(template_id => $tmpl->template_id,
                                      version => 2);
isa_ok($tmplXYZ, 'Krang::Template');
is($tmplXYZ->version(), 2, 'Template version test');

# clean up the mess
END {
    unlink 't_w_c.tmpl';
    is($tmpl->delete(), 1, 'Deletion Test 1');
    is($tmpl2->delete(), 1, 'Deletion Test 2');

    # delete category and site
    $site->delete();
}
