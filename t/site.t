use strict;
use warnings;

use Krang;
use Krang::Category;

use Test::More qw(no_plan);

BEGIN {
    use_ok('Krang::Site');
}

# force constructor failure
eval {
    my $site = Krang::Site->new(preview => 'This is a bad param',
                                publish_path => 'sites/test1/',
                                url => 'testsite.com');
};
is($@ =~ /invalid: 'preview'/, 1, 'init() test');

# create new object
my $site2 = Krang::Site->new(publish_path => 'sites/test1/',
                             url => 'testsite.com');
isa_ok($site2, 'Krang::Site', 'new() test');

# accessor check
is($site2->url(), 'testsite.com', 'accessor test');

# save
$site2->save();
isa_ok($site2, 'Krang::Site', 'save() test');

# duplicate test
my $site3 = Krang::Site->new(publish_path => 'sites/test2/',
                             url => 'testsite.com');
eval {$site3->save();};
is($@ =~ /'url' is a duplicate/, 1, 'save() duplicate test');

# find test
my ($site4) = Krang::Site->find(url_like => '%.com%',
                                publish_path_like => '%sites/%',
                                order_desc => 'asc',
                                limit => 1,
                                order_by => 'url');
isa_ok($site4, 'Krang::Site', 'find() test');

# update category test
my $category = Krang::Category->new(name => '/',
                                    site_id => $site2->site_id());
$category->save();
$site2->url('testsite2.com');
$site2->save();
my ($new_cat) = Krang::Category->find(site_id => $site2->site_id());
is($new_cat->url() =~ /testsite2\.com/, 1, 'update_child_categories() test');

# deletion test - failure
eval {$site2->delete()};
is($@ =~ /refers to this site/, 1, 'delete() failure test');

# delete category
$new_cat->delete();

# deletion
my $result = $site2->delete();
is($result, 1, 'delete() test');
