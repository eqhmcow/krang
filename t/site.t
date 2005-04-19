use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader 'Script';
use Krang::ClassLoader 'Category';
use Test::More qw(no_plan);

BEGIN {
    use_ok(pkg('Site'));
}

# constructor tests
####################
# invalid param failure
eval {
    my $site = pkg('Site')->new(preview => 'This is a bad param',
                                preview_path => 'sites/preview/test1/',
                                preview_url => 'preview.testsite.t',
                                publish_path => 'sites/test1/',
                                url => 'testsite.t');
};
like($@, qr/invalid: 'preview'/, 'init() test');

# missing 'publish_path' failure
eval {my $siteX = pkg('Site')->new(preview_path => 'preview/path3/',
                                   preview_url => 'preview.testsite3.t',
                                   url => 'testfailure.t')};
like($@, qr/Required argument 'publish_path'/,
     "init() failure - publish_path");

# missing 'publish_path' failure
eval {my $siteX = pkg('Site')->new(preview_path => 'preview/path3/',
                                   preview_url => 'preview.testsite3.t',
                                   publish_path => 'path/')};
like($@, qr/Required argument 'url'/, "init() failure - url");

# create new object
my $site2 = pkg('Site')->new(publish_path => 'sites/test1/',
                             preview_path => 'sites/preview/test1/',
                             preview_url => 'preview.testsite.t',
                             url => 'testsite.t');
isa_ok($site2, 'Krang::Site', 'new() test');


# save tests
#############
$site2->save();
isa_ok($site2, 'Krang::Site', 'save() test');

# duplicate test
my $site3 = pkg('Site')->new(publish_path => 'sites/test2/',
                             preview_path => 'sites/preview/test2/',
                             preview_url => 'preview.testsite2.t',
                             url => 'testsite.t');
eval {$site3->save();};
isa_ok($@, 'Krang::Site::Duplicate');
like($@, qr/already exists/);

# accessor/mutator tests
#########################
$site2->preview_path('preview_path');
is($site2->preview_path(), 'preview_path', 'preview_path()');

$site2->preview_url('url');
is($site2->preview_url(), 'url', 'preview_url()');

$site2->publish_path('sites/test2/');
is($site2->publish_path(), 'sites/test2/', 'publish_path()');

$site2->url('testsite1.t');
is($site2->url(), 'testsite1.t', 'url()');

$site2->save();

# find tests
#############
# setup a bunch of sites
$site3 = pkg('Site')->new(publish_path => 'pblish/path3/',
                          preview_path => 'preview/path3/',
                          preview_url => 'preview.testsite3.t',
                          url => 'testsite3.t');
$site3->save();
my $site4 = pkg('Site')->new(publish_path => 'pblish/path4/',
                             preview_path => 'preview/path4/',
                             preview_url => 'preview.testsite4.t',
                             url => 'testsite4.t');
$site4->save();
my $site5 = pkg('Site')->new(publish_path => 'pblish/path5/',
                             preview_path => 'preview/path5/',
                             preview_url => 'preview.testsite5.t',
                             url => 'testsite5.t');
$site5->save();

# we should get an array of 5 objects back
my @sites = pkg('Site')->find(url_like          => '%.t%',
                              publish_path_like => '%/%',
                              order_by          => 'url',
                              order_desc        => 1);
is(scalar @sites, 4, 'find() - quantity');
isa_ok($_, 'Krang::Site') for @sites;
is($sites[0]->url(), 'testsite5.t', 'find() - ordering');

# count test
my $count = pkg('Site')->find(count => 1,
                              preview_path_like => '%review\_pat%');
is($count, 1, 'find() - count');

# ids only
my @site_ids = pkg('Site')->find(ids_only => 1,
                                 publish_path_like => '%pblish/%');
like($_, qr/^\d+$/, 'find() - valid ids') for @site_ids;

# site_id
@sites = pkg('Site')->find(site_id => [$site3->site_id, $site4->site_id]);
isa_ok($_, 'Krang::Site') for @sites;
like($sites[0]->url(), qr/3/, 'find() - ordering 2');

# limit/offset
@sites = pkg('Site')->find(site_id => [@site_ids],
                           limit => 2,
                           offset => 1,
                           order_desc => 1);
is(scalar @sites, 2, 'find() - limit/offset 1');
isa_ok($_, 'Krang::Site') for @sites;
like($sites[0]->url(), qr/4/, 'find - limit/offset 2');

# update category test
my $category = pkg('Category')->new(dir => '/blah',
                                    site_id => $site2->site_id());
$category->save();

$site2->url('testsite2.t');
$site2->save();
my @cats = pkg('Category')->find(site_id => $site2->site_id());
like($cats[0]->url(), qr/testsite2\.t/, 'update_child_categories() test');


# deletion tests
#################
# deletion test - failure
eval {$site2->delete()};
isa_ok($@, 'Krang::Site::Dependency');
like($@, qr/Site cannot be deleted/, 'delete() failure test');
my $dependents = $@->category_id;
is($_ =~ /^\d+$/, 1, 'Krang::Site::Dependency test') for @$dependents;

# delete '/blah'
my $result = $cats[1]->delete();
is($result, 1, 'delete() category test');

# deletion
$result = $site2->delete();
is($result, 1, 'delete() test 2');

$result = $site3->delete();
is($result, 1, 'delete() test 3');

$result = $site4->delete();
is($result, 1, 'delete() test 4');

$result = $site5->delete();
is($result, 1, 'delete() test 5');
