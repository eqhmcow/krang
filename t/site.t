use strict;
use warnings;

use Krang;
use Krang::Category;

use Test::More qw(no_plan);

BEGIN {
    use_ok('Krang::Site');
}

# constructor tests
####################
# invalid param failure
eval {
    my $site = Krang::Site->new(preview => 'This is a bad param',
                                publish_path => 'sites/test1/',
                                url => 'testsite.com');
};
is($@ =~ /invalid: 'preview'/, 1, 'init() test');

# missing 'publish_path' failure
eval {my $siteX = Krang::Site->new(url => 'testfailure.com')};
is($@ =~ /Required argument 'publish_path'/, 1,
   "init() failure - publish_path");

# missing 'publish_path' failure
eval {my $siteX = Krang::Site->new(publish_path => 'path/')};
is($@ =~ /Required argument 'url'/, 1, "init() failure - url");

# create new object
my $site2 = Krang::Site->new(publish_path => 'sites/test1/',
                             url => 'testsite.com');
isa_ok($site2, 'Krang::Site', 'new() test');


# save tests
#############
$site2->save();
isa_ok($site2, 'Krang::Site', 'save() test');

# duplicate test
my $site3 = Krang::Site->new(publish_path => 'sites/test2/',
                             url => 'testsite.com');
eval {$site3->save();};
is($@ =~ /'url' is a duplicate/, 1, 'save() duplicate test');


# accessor/mutator tests
#########################
$site2->preview_path('preview_path');
is($site2->preview_path(), 'preview_path', 'preview_path()');

$site2->preview_url('url');
is($site2->preview_url(), 'url', 'preview_url()');

$site2->publish_path('sites/test2/');
is($site2->publish_path(), 'sites/test2/', 'publish_path()');

$site2->publish_url('url');
is($site2->publish_url(), 'url', 'publish_url()');

$site2->url('testsite2.com');
is($site2->url(), 'testsite2.com', 'url()');

$site2->save();

# find tests
#############
# setup a bunch of sites
$site3 = Krang::Site->new(publish_path => 'publish/path3/',
                             url => 'testsite3.com');
$site3->save();
my $site4 = Krang::Site->new(publish_path => 'publish/path4/',
                             url => 'testsite4.com');
$site4->save();
my $site5 = Krang::Site->new(publish_path => 'publish/path5/',
                             url => 'testsite5.com');
$site5->save();

# we should get an array of 5 objects back
my @sites = Krang::Site->find(url_like => '%.com%',
                              publish_path_like => '%/%',
                              order_by => 'url',
                              order_desc => 'asc');
is(scalar @sites, 4, 'find() - quantity');
isa_ok($_, 'Krang::Site') for @sites;
is($sites[0]->url(), 'testsite2.com', 'find() - ordering');

# count test
my $count = Krang::Site->find(count => 1,
                              preview_path_like => '%path%');
is($count, 1, 'find() - count');

# ids only
my @site_ids = Krang::Site->find(ids_only => 1,
                                 publish_path_like => '%publish%');
is(scalar @site_ids, 3, 'find() - ids_only');
is($_ =~ /^\d+$/, 1, 'find() - valid ids') for @site_ids;

# site_id
@sites = Krang::Site->find(site_id => [@site_ids]);
is(scalar @sites, 3, 'find() - site_id');
isa_ok($_, 'Krang::Site') for @sites;
is($sites[0]->url() =~ /3/, 1, 'find() - ordering 2');

# limit/offset
@sites = Krang::Site->find(site_id => [@site_ids],
                           limit => 2,
                           offset => 1,
                           order_desc => 'desc');
is(scalar @sites, 2, 'find() - limit/offset 1');
isa_ok($_, 'Krang::Site') for @sites;
is($sites[0]->url() =~ /4/, 1, 'find - limit/offset 2');


# update category test
my $category = Krang::Category->new(name => '/',
                                    site_id => $site2->site_id());
$category->save();
$site2->url('testsite2.com');
$site2->save();
my ($new_cat) = Krang::Category->find(site_id => $site2->site_id());
is($new_cat->url() =~ /testsite2\.com/, 1, 'update_child_categories() test');


# deletion tests
#################
# deletion test - failure
eval {$site2->delete()};
is($@ =~ /refers to this site/, 1, 'delete() failure test');

# delete category
$new_cat->delete();

# deletion
my $result = $site2->delete();
is($result, 1, 'delete() test 2');

$result = $site3->delete();
is($result, 1, 'delete() test 3');

$result = $site4->delete();
is($result, 1, 'delete() test 4');

$result = $site5->delete();
is($result, 1, 'delete() test 5');
