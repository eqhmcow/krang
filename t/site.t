use strict;
use warnings;

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
is($@ =~ /'url' is the same/, 1, 'save() duplicate test');

# find test
my ($site4) = Krang::Site->find(url_like => '%.com%',
                               publish_path_like => '%sites/%',
                               ascend => 1,
                               limit => 1,
                               order_by => 'url');
isa_ok($site4, 'Krang::Site', 'find() test');

# deletion
my $result = $site2->delete();
is($result, 1, 'delete() test');
