# test the category chooser widget

use Krang::ClassFactory qw(pkg);
use Test::More qw(no_plan);
use strict;
use warnings;
use Krang::ClassLoader 'Script';
use Krang::ClassLoader Widget => qw(category_chooser_object);
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

my $site = $creator->create_site(
    preview_url  => "prev.choosertest.com",
    publish_url  => "choosertest.com",
    preview_path => "/tmp/prev.chooser",
    publish_path => "/tmp/chooser",
);
my @cats = pkg('Category')->find(site_id => $site->site_id());
push @cats,
  $creator->create_category(
    dir    => 'cat_1',
    parent => $cats[0]->category_id
  );
push @cats,
  $creator->create_category(
    dir    => 'cat_2',
    parent => $cats[0]->category_id
  );
push @cats,
  $creator->create_category(
    dir    => 'cat_3',
    parent => $cats[0]->category_id
  );
push @cats,
  $creator->create_category(
    dir    => 'cat_1.1',
    parent => $cats[1]->category_id
  );
push @cats,
  $creator->create_category(
    dir    => 'cat_1.2',
    parent => $cats[1]->category_id
  );
push @cats,
  $creator->create_category(
    dir    => 'cat_1.3',
    parent => $cats[1]->category_id
  );
push @cats,
  $creator->create_category(
    dir    => 'cat_1.3.1',
    parent => $cats[-1]->category_id
  );

# create a group to test permissions with
my $group = pkg('Group')->new(
    name                => 'Chooser Test',
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
    asset_template      => 'edit'
);
$group->save();

# get a test user and assume their identity
my ($user) = $creator->create_user(group_ids => [$group->group_id]);
$ENV{REMOTE_USER} = $user->user_id();

END {
    $user->delete    if $user;
    $group->delete() if $group;
}
END { $ENV{REMOTE_USER} = 1 }

# create a choose with every category, using all varieties of
# permissions checking
ok(_chooser_has_cat($_)) for @cats;
ok(_chooser_has_cat($_, {may_see  => 0})) for @cats;
ok(_chooser_has_cat($_, {may_edit => 1})) for @cats;

# now mark a category readonly.  Make sure it doesn't appear in
# may_edit chooser
$group->categories($cats[3]->category_id => 'read-only');
$group->save();

ok(_chooser_has_cat($_)) for @cats;
ok(_chooser_has_cat($_, {may_see => 0})) for @cats;
ok(_chooser_has_cat($_, {may_edit => 1})) for grep { $_ != $cats[3] } @cats;
ok(not _chooser_has_cat($cats[3], {may_edit => 1}));

# now mark a category hidden.  Make sure it doesn't appear in
# may_edit or may_see choosers
$group->categories($cats[3]->category_id => 'hide');
$group->save();

ok(_chooser_has_cat($_)) for grep { $_ != $cats[3] } @cats;
ok(not _chooser_has_cat($cats[3]));
ok(_chooser_has_cat($_, {may_see => 0})) for @cats;
ok(_chooser_has_cat($_, {may_edit => 1})) for grep { $_ != $cats[3] } @cats;
ok(not _chooser_has_cat($cats[3], {may_edit => 1}));

# returns 1 if a chooser has the category in it, 0 otherwise
# we look at the HTML returned for the categories parent
# to see if the category's url is in there
sub _chooser_has_cat {
    my ($cat, $extra_args) = @_;
    $extra_args ||= {};

    my $query     = CGI->new();
    my $chooser   = category_chooser_object(name => 'name', query => $query, %$extra_args);
    my $parent_id = _get_parent_tree_id($cat, $chooser);
    return 0 unless defined $parent_id and $parent_id ne '';

    $query->param(id => $parent_id);
    my $html = $chooser->handle_get_node(query => $query);
    my $regex = quotemeta($cat->dir);
    return $html =~ /$regex/;
}

# the $chooser->handler_get_node() method uses sort of an xpath like
# id for the nodes position. We need to determine what the id is
# recursively
sub _get_parent_tree_id {
    my ($cat, $chooser) = @_;

    # sorta icky since we rely on $chooser's internal {data} element
    my $id;
    my $val = $cat->category_id . "," . $cat->url;
    $id = _get_tree_id($id, $val, $chooser->{data});
    if ($id =~ m/(.*)\/[^\/]*$/) {
        return $1;
    } else {
        return $id;
    }
}

sub _get_tree_id {
    my ($id, $val, $data) = @_;
    my $new_id;
    for (0 .. $#$data) {
        $new_id = defined $id ? ($id . '/' . $_) : $_;
        if ($data->[$_]->{value} eq $val) {
            return $new_id;
        } else {
            my $children = $data->[$_]->{children};

            # look at our children if we have any
            if ($children && scalar @$children) {
                $new_id = _get_tree_id($new_id, $val, $children);
                return $new_id if $new_id;
            }
        }
    }
}

