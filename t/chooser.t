# test the category chooser widget

use Krang::ClassFactory qw(pkg);
use Test::More qw(no_plan);
use strict;
use warnings;
use Krang::ClassLoader 'Script';
use Krang::ClassLoader Widget => qw(category_chooser);
use Krang::ClassLoader 'Test::Content';
use CGI;

my $creator = pkg('Test::Content')->new;
END { $creator->cleanup(); }

# set up category tree:
#
# choosertest.com
#   cat_1
#     cat_1.1
#     cat_1.2
#     cat_1.3
#       cat_1.3.1
#   cat_2
#   cat_3

my $site = $creator->create_site(preview_url  => "prev.choosertest.com",
                                 publish_url  => "choosertest.com",
                                 preview_path => "/tmp/prev.chooser",
                                 publish_path => "/tmp/chooser",
                                );
my @cats = pkg('Category')->find(site_id => $site->site_id());
push @cats, $creator->create_category(dir     => 'cat_1',
                                      parent  => $cats[0]->category_id);
push @cats, $creator->create_category(dir     => 'cat_2',
                                      parent  => $cats[0]->category_id);
push @cats, $creator->create_category(dir     => 'cat_3',
                                      parent  => $cats[0]->category_id);
push @cats, $creator->create_category(dir     => 'cat_1.1',
                                      parent  => $cats[1]->category_id);
push @cats, $creator->create_category(dir     => 'cat_1.2',
                                      parent  => $cats[1]->category_id);
push @cats, $creator->create_category(dir     => 'cat_1.3',
                                      parent  => $cats[1]->category_id);
push @cats, $creator->create_category(dir     => 'cat_1.3.1',
                                      parent  => $cats[-1]->category_id);


# create a group to test permissions with
my $group = pkg('Group')->new( name => 'Chooser Test',
                               may_publish         => 1,
                               may_checkin_all     => 1,
                               admin_users         => 1,
                               admin_users_limited => 1,
                               admin_groups        => 1,
                               admin_contribs      => 1,
                               admin_sites         => 1,
                               admin_categories    => 1,
                               admin_jobs          => 1,
                               admin_desks         => 1,
                               admin_lists         => 1,
                               asset_story         => 'edit',
                               asset_media         => 'edit',
                               asset_template      => 'edit' );
$group->save();

# get a test user and assume their identity
my ($user) = $creator->create_user(group_ids => [$group->group_id]);
$ENV{REMOTE_USER} = $user->user_id();

END { $user->delete if $user;
      $group->delete() if $group };
END { $ENV{REMOTE_USER} = 1 };

# create a choose with every category, using all varieties of
# permissions checking
my $query = CGI->new();
my $chooser = category_chooser(name => 'name', query => $query);
ok(_chooser_has($chooser, $_)) for @cats;
$chooser = category_chooser(name => 'name', query => $query,
                            may_see => 0,
                           );
ok(_chooser_has($chooser, $_)) for @cats;
$chooser = category_chooser(name  => 'name', query => $query,
                            may_edit => 1,
                           );
ok(_chooser_has($chooser, $_)) for @cats;

# now mark a category readonly.  Make sure it doesn't appear in
# may_edit chooser
$group->categories($cats[3]->category_id => 'read-only');
$group->save();

$chooser = category_chooser(name => 'name', query => $query);
ok(_chooser_has($chooser, $_)) for @cats;
$chooser = category_chooser(name => 'name', query => $query,
                            may_see => 0,
                           );
ok(_chooser_has($chooser, $_)) for @cats;
$chooser = category_chooser(name => 'name', query => $query,
                            may_edit => 1,
                           );
ok(_chooser_has($chooser, $_)) for grep { $_ != $cats[3] } @cats;
ok(not _chooser_has($chooser, $cats[3]));


# now mark a category hidden.  Make sure it doesn't appear in
# may_edit or may_see choosers
$group->categories($cats[3]->category_id => 'hide');
$group->save();

$chooser = category_chooser(name => 'name', query => $query);
ok(_chooser_has($chooser, $_)) for grep { $_ != $cats[3] } @cats;
ok(not _chooser_has($chooser, $cats[3]));
$chooser = category_chooser(name => 'name', query => $query,
                            may_see => 0,
                           );
ok(_chooser_has($chooser, $_)) for @cats;
$chooser = category_chooser(name => 'name', query => $query,
                            may_edit => 1,
                           );
ok(_chooser_has($chooser, $_)) for grep { $_ != $cats[3] } @cats;
ok(not _chooser_has($chooser, $cats[3]));

# returns 1 if a chooser has the category in it, 0 otherwise
sub _chooser_has {
    my ($chooser, $cat) = @_;
    return 1 if $chooser =~ $cat->dir;
    return 0;
}

