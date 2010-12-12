use Krang::ClassFactory qw(pkg);
use strict;
use warnings;
use Krang::ClassLoader 'Script';

use Krang::ClassLoader 'Test::Content';
use Krang::ClassLoader 'Story';
use Krang::ClassLoader 'Media';

use Krang::ClassLoader 'Site';
use Krang::ClassLoader 'Template';

use Krang::ClassLoader Conf => qw(InstanceElementSet);

use Test::More qw(no_plan);

# use the TestSet1 instance, if there is one
foreach my $instance (pkg('Conf')->instances) {
    pkg('Conf')->instance($instance);
    if (InstanceElementSet eq 'TestSet1') {
        last;
    }
}

BEGIN {
    use_ok(pkg('Category'));
}

# Create site
my $site = pkg('Site')->new(
    preview_url  => 'category_copy_test.preview.com',
    url          => 'category_copy_test.com',
    preview_path => '/tmp/category_copy_preview',
    publish_path => '/tmp/category_copy_publish'
);
$site->save;
END { $site->delete }
isa_ok($site, 'Krang::Site');

# setup group with asset permissions
my $group = pkg('Group')->new(
    name           => 'ForOtherUser',
    asset_story    => 'edit',
    asset_media    => 'edit',
    asset_template => 'edit',
);
$group->save();
END { $group->delete }

# put a user into this group
my $user = pkg('User')->new(
    login     => 'bob',
    password  => 'bobspass',
    group_ids => [$group->group_id],
);
$user->save();
END { $user->delete }

# some variables
my ($creator, $this, $that, $source, $destination, $water, $conflict, $copied);
my (@categories, @stories, @media, @templates, @tmp);

note('');
note('1. Test without conflict possibility');
note('');
setup_tree();

# can we copy?
eval {
    $this->can_copy_test(
        dst_category => $that,
        story        => 1,
        media        => 1,
        template     => 1,
        overwrite    => 0
    );
};
is(not($@), 1, "May copy test without conflicts");

# do copy
eval {
    $copied = $this->copy(
        dst_category => $that,
        story        => 1,
        media        => 1,
        template     => 1,
        overwrite    => 0
    );
};
is(not($@), 1, "Actual copy succeeded");
push @categories, @{$copied->{category}} if $copied->{category};
push @stories,    @{$copied->{story}}    if $copied->{story};
push @media,      @{$copied->{media}}    if $copied->{media};
push @templates,  @{$copied->{template}} if $copied->{template};

note('');
note('2. Story conflict without overwrite');
note('');
setup_tree();
$conflict = pkg('Story')->new(
    categories => [$that],
    slug       => 'from_story_1',
    class      => 'article',
    title      => 'Conflicting with \$from_story_1'
);
$conflict->save;
$conflict->checkin;
push @stories, $conflict;
eval {
    $this->can_copy_test(
        dst_category => $that,
        story        => 1,
        media        => 1,
        template     => 1,
        overwrite    => 0
    );
};
note('Testing Story conflict without overwrite - should throw exception');
isa_ok($@, 'Krang::Category::CopyAssetConflict');

# do copy
eval {
    $copied = $this->copy(
        dst_category => $that,
        story        => 1,
        media        => 1,
        template     => 1,
        overwrite    => 0
    );
};
is(not($@), 1, "Trying to copy did not throw error");
@tmp = pkg('Story')->find(url => $conflict->url);
is(scalar(@tmp), 1, "No story copied");

($conflict) = pkg('Story')->find(story_id => $conflict->story_id);
is($conflict->trashed, 0, "Conflicting story has not been trashed");

push @categories, @{$copied->{category}} if $copied->{category};
push @stories,    @{$copied->{story}}    if $copied->{story};
push @media,      @{$copied->{media}}    if $copied->{media};
push @templates,  @{$copied->{template}} if $copied->{template};

note('');
note('3. Story conflict with overwrite');
note('');
setup_tree();
$conflict = pkg('Story')->new(
    categories => [$that],
    slug       => 'from_story_1',
    class      => 'article',
    title      => 'Conflicting with \$from_story_1'
);
$conflict->save;
$conflict->checkin;
push @stories, $conflict;
eval {
    $this->can_copy_test(
        dst_category => $that,
        story        => 1,
        media        => 1,
        template     => 1,
        overwrite    => 1
    );
};
is(not($@), 1, 'Can copy test succeeded');

# do copy
eval {
    $copied = $this->copy(
        dst_category => $that,
        story        => 1,
        media        => 1,
        template     => 1,
        overwrite    => 1
    );
};
my @copied_stories = $copied->{story} ? @{$copied->{story}} : ();
($conflict) = pkg('Story')->find(story_id => $conflict->story_id);
is(not($@),                 1,              "Actual copy did not throw error");
is($conflict->trashed,      1,              "Conflicting story has been trashed");
is($copied_stories[0]->url, $conflict->url, "Copied Story has same URL as conflicting story");

push @categories, @{$copied->{category}} if $copied->{category};
push @stories,    @copied_stories;
push @media,      @{$copied->{media}}    if $copied->{media};
push @templates,  @{$copied->{template}} if $copied->{template};

note('');
note('4. Media conflict without overwrite');
note('');
setup_tree();

# Add a TO category also existing in FROM
$source = pkg('Category')->new(
    parent_id => $that->category_id,
    dir       => 'source'
);
$source->save;
push @categories, $source;

# Add a conflicting media in /to/that/source/
$conflict = $creator->create_media(
    category => $source,
    title    => "Conflict with From Media 2",
    filename => 'from_media_2',
    format   => 'jpg'
);
eval {
    $this->can_copy_test(
        dst_category => $that,
        story        => 1,
        media        => 1,
        template     => 1,
        overwrite    => 0
    );
};
note('Testing Media conflict without overwrite - should throw exception');
isa_ok($@, 'Krang::Category::CopyAssetConflict');

# do copy
eval {
    $copied = $this->copy(
        dst_category => $that,
        story        => 1,
        media        => 1,
        template     => 1,
        overwrite    => 0
    );
};
is(not($@), 1, "Trying to copy did not throw error");
@tmp = pkg('Media')->find(url => $conflict->url);
is(scalar(@tmp), 1, "No media copied");

($conflict) = pkg('Media')->find(media_id => $conflict->media_id);
is($conflict->trashed, 0, "Conflicting media has not been trashed");

push @categories, @{$copied->{category}} if $copied->{category};
push @stories,    @{$copied->{story}}    if $copied->{story};
push @media,      @{$copied->{media}}    if $copied->{media};
push @templates,  @{$copied->{template}} if $copied->{template};

note('');
note('5. Media conflict with overwrite');
note('');
setup_tree();

# Add a TO category also existing in FROM
$source = pkg('Category')->new(
    parent_id => $that->category_id,
    dir       => 'source'
);
$source->save;
push @categories, $source;

# Add a conflicting media in /to/that/source/
$conflict = $creator->create_media(
    category => $source,
    title    => "Conflict with From Media 2",
    filename => 'from_media_2',
    format   => 'jpg'
);
eval {
    $this->can_copy_test(
        dst_category => $that,
        story        => 1,
        media        => 1,
        template     => 1,
        overwrite    => 1
    );
};
is(not($@), 1, 'Media conflict with overwrite');

# do copy
eval {
    $copied = $this->copy(
        dst_category => $that,
        story        => 1,
        media        => 1,
        template     => 1,
        overwrite    => 1
    );
};
my @copied_media = $copied->{media} ? @{$copied->{media}} : ();
($conflict) = pkg('Media')->find(media_id => $conflict->media_id);
is(not($@),               1,              "Actual copy did not throw error");
is($conflict->trashed,    1,              "Conflicting media has been trashed");
is($copied_media[1]->url, $conflict->url, "Copied Media has same URL as conflicting media");

push @categories, @{$copied->{category}} if $copied->{category};
push @stories,    @{$copied->{story}}    if $copied->{story};
push @media,      @copied_media;
push @templates,  @{$copied->{template}} if $copied->{template};

note('');
note('6. Template conflict without overwrite');
note('');
setup_tree();

# Add a TO category also existing in FROM
$source = pkg('Category')->new(
    parent_id => $that->category_id,
    dir       => 'source'
);
$source->save;
push @categories, $source;
$water = pkg('Category')->new(
    parent_id => $source->category_id,
    dir       => 'water'
);
$water->save;
push @categories, $water;

# Add a conflicting template in /to/that/source/water/
$conflict = $creator->create_template(
    category     => $water,
    element_name => 'from_template_2',
    content      => 'x'
);
eval {
    $this->can_copy_test(
        dst_category => $that,
        story        => 1,
        media        => 1,
        template     => 1,
        overwrite    => 0
    );
};
note('Testing Template conflict without overwrite - should throw exception');
isa_ok($@, 'Krang::Category::CopyAssetConflict');

# do copy
eval {
    $copied = $this->copy(
        dst_category => $that,
        story        => 1,
        media        => 1,
        template     => 1,
        overwrite    => 0
    );
};
is(not($@), 1, "Trying to copy did not throw error");
@tmp = pkg('Template')->find(url => $conflict->url);
is(scalar(@tmp), 1, "No template copied");

($conflict) = pkg('Template')->find(template_id => $conflict->template_id);
is($conflict->trashed, 0, "Conflicting template has not been trashed");

push @categories, @{$copied->{category}} if $copied->{category};
push @stories,    @{$copied->{story}}    if $copied->{story};
push @media,      @{$copied->{media}}    if $copied->{media};
push @templates,  @{$copied->{template}} if $copied->{template};

note('');
note('7. Template conflict with overwrite');
note('');
setup_tree();

# Add a TO category also existing in FROM
$source = pkg('Category')->new(
    parent_id => $that->category_id,
    dir       => 'source'
);
$source->save;
push @categories, $source;
$water = pkg('Category')->new(
    parent_id => $source->category_id,
    dir       => 'water'
);
$water->save;
push @categories, $water;

# Add a conflicting template in /to/that/source/water/
$conflict = $creator->create_template(
    category     => $water,
    element_name => 'from_template_2',
    content      => 'x'
);
eval {
    $this->can_copy_test(
        dst_category => $that,
        story        => 1,
        media        => 1,
        template     => 1,
        overwrite    => 1
    );
};
is(not($@), 1, 'Template conflict with overwrite');

# do copy
eval {
    $copied = $this->copy(
        dst_category => $that,
        story        => 1,
        media        => 1,
        template     => 1,
        overwrite    => 1
    );
};
my @copied_templates = $copied->{template} ? @{$copied->{template}} : ();
($conflict) = pkg('Template')->find(template_id => $conflict->template_id);
is(not($@), 1, "Actual copy did not throw error");
is($conflict->trashed, 1, "Conflicting template has been trashed");
is($copied_templates[1]->url,
    $conflict->url, "Copied Template has same URL as conflicting template");

push @categories, @{$copied->{category}} if $copied->{category};
push @stories,    @{$copied->{story}}    if $copied->{story};
push @media,      @{$copied->{media}}    if $copied->{media};
push @templates,  @copied_templates;

note('');
note('8. Resolvable URL Conflict between would-be-created category and story existing in TO');
note('');
setup_tree();
$conflict = pkg('Story')->new(
    categories => [$that],
    slug       => 'source',
    class      => 'article',
    title      => 'Conflicting with would-be-created source/ category'
);
$conflict->save;
$conflict->checkin;
push @stories, $conflict;
eval {
    $this->can_copy_test(
        dst_category => $that,
        story        => 1,
        media        => 1,
        template     => 1,
        overwrite    => 0
    );
};
is(not($@), 1,
    "Resolvable conflict between would-be-created category and slug-provided story in copy destination"
);

# do copy
eval {
    $copied = $this->copy(
        dst_category => $that,
        story        => 1,
        media        => 1,
        template     => 1,
        overwrite    => 0
    );
};
is(not($@), 1, "Actual copy did not throw error");

# could the category be created?
my ($cat) = pkg('Category')->find(parent_id => $that->category_id, dir => 'source');
isa_ok($cat, 'Krang::Category');

# has the conflicting story be turned into an index page of this category?
my ($cat_idx) = pkg('Story')->find(category_id => $cat->category_id, slug => '');
isa_ok($cat_idx, 'Krang::Story');

push @categories, @{$copied->{category}} if $copied->{category};
push @stories,    @{$copied->{story}}    if $copied->{story};
push @media,      @{$copied->{media}}    if $copied->{media};
push @templates,  @{$copied->{template}} if $copied->{template};

note('');
note('9. Unresolvable URL Conflict between would-be-created category and story existing in TO');
note('');
setup_tree();
$conflict = pkg('Story')->new(
    categories => [$that],
    slug       => 'source',
    class      => 'article',
    title      => 'Conflicting with would-be-created source/ category'
);
$conflict->save;
$conflict->checkin;
push @stories, $conflict;
$conflict->checkin();

# checkout as other user
note(
    "We are now another user - testing unresolvable conflict between would-be-created category and slug-provided story in copy destination"
);
{
    local $ENV{REMOTE_USER} = $user->user_id;

    $conflict->checkout;
    is($conflict->checked_out_by, $user->user_id, "Conflicting story checked out by other user");
}
note(
    "We are the normal test user again: Can-copy-test should throw a Krang::Story::CantCheckOut exception"
);
eval {
    $this->can_copy_test(
        dst_category => $that,
        story        => 1,
        media        => 1,
        template     => 1,
        overwrite    => 0
    );
};
isa_ok($@, 'Krang::Story::CantCheckOut');

note(
    "Trying to copy although we can't check out some story should throw a Krang::Category::DuplicateURL"
);
eval {
    $copied = $this->copy(
        dst_category => $that,
        story        => 1,
        media        => 1,
        template     => 1,
        overwrite    => 1
    );
};
isa_ok($@, 'Krang::Category::DuplicateURL');
{
    note("We are now another user");
    local $ENV{REMOTE_USER} = $user->user_id;

    $conflict->checkin;
    is($conflict->checked_out, 0, "Conflicting story is checked in back again.");
}
note("We are the normal test user again.");

note('');
note('10. Conflict with existing destination category to which we have no EditAcces');
note('');
setup_tree();

# Add a TO category also existing in FROM
$conflict = pkg('Category')->new(
    parent_id => $that->category_id,
    dir       => 'source'
);
$conflict->save;
push @categories, $conflict;
{

    # setup group with asset permissions
    my $group = pkg('Group')->new(
        name           => 'LimitedCategoryAccess',
        asset_story    => 'edit',
        asset_media    => 'edit',
        asset_template => 'edit',
        categories     => {$conflict->category_id => 'read-only'},
    );
    $group->save();
    END { $group->delete }

    # put a user into this group
    my $user = pkg('User')->new(
        login     => 'limited',
        password  => 'limited',
        group_ids => [$group->group_id],
    );
    $user->save();
    END { $user->delete }

    note("We are a user without edit permission to Category " . $conflict->category_id);
    local $ENV{REMOTE_USER} = $user->user_id;

    eval {
        $this->can_copy_test(
            dst_category => $that,
            story        => 1,
            media        => 1,
            template     => 1,
            overwrite    => 1
        );
    };
    isa_ok($@, 'Krang::Category::NoEditAccess');
}

note('');
note('11. Conflict between would-be-created story and existing category');
note('');
setup_tree();

$conflict = pkg('Story')->new(
    categories => [$this],
    slug       => 'destination',
    class      => 'article',
    title      => 'Conflicting with existing destination category'
);
$conflict->save;
$conflict->checkin;
push @stories, $conflict;
$conflict->checkin();

note('Testing without overwrite - should not throw exception');

eval {
    $this->can_copy_test(
        dst_category => $that,
        story        => 1,
        media        => 0,
        template     => 0,
        overwrite    => 0
    );
};
note($@);
is(!$@, 1, 'No Krang::Category::CopyAssetConflict thrown');

# do copy
eval {
    $copied = $this->copy(
        dst_category => $that,
        story        => 1,
        media        => 1,
        template     => 1,
        overwrite    => 0
    );
};

is(not($@), 1, "Trying to copy did not throw error");
@tmp = pkg('Story')->find(url => $that->url . 'destination/');
is(scalar(@tmp), 1, "Story has been transformed into category index of existing category");

push @categories, @{$copied->{category}} if $copied->{category};
push @stories,    @{$copied->{story}}    if $copied->{story};
push @media,      @{$copied->{media}}    if $copied->{media};
push @templates,  @{$copied->{template}} if $copied->{template};

note('');
note(
    '12. Conflict between would-be-created story and existing category having index story - without overwrite'
);
note('');
setup_tree();

$conflict = pkg('Story')->new(
    categories => [$this],
    slug       => 'destination',
    class      => 'article',
    title      => 'Conflicting with existing destination category\'s index story'
);
$conflict->save;
$conflict->checkin;
push @stories, $conflict;

my $index = pkg('Story')->new(
    categories => [$destination],
    slug       => '',
    class      => 'article',
    title      => 'Exsting category\'s index story',
);
$index->save;
$index->checkin;
push @stories, $index;

eval {
    $this->can_copy_test(
        dst_category => $that,
        story        => 1,
        media        => 0,
        template     => 0,
        overwrite    => 0,
    );
};

note('Testing without overwrite - should throw exception');
isa_ok($@, 'Krang::Category::CopyAssetConflict');

# do copy
eval {
    $copied = $this->copy(
        dst_category => $that,
        story        => 1,
        media        => 1,
        template     => 1,
        overwrite    => 0,
    );
};

my ($findex) = pkg('Story')->find(url => $index->url);
is($findex->story_id, $index->story_id,
    'The existing index category has been preserved. No copy occured.');

push @categories, @{$copied->{category}} if $copied->{category};
push @media,      @{$copied->{media}}    if $copied->{media};
push @templates,  @{$copied->{template}} if $copied->{template};
push @stories,    @{$copied->{story}}    if $copied->{story};

note('');
note(
    '13. Conflict between would-be-created story and existing category having index story - with overwrite'
);
note('');
setup_tree();

$conflict = pkg('Story')->new(
    categories => [$this],
    slug       => 'destination',
    class      => 'article',
    title      => 'Conflicting with existing destination category\'s index story'
);
$conflict->save;
$conflict->checkin;
push @stories, $conflict;

$index = pkg('Story')->new(
    categories => [$destination],
    slug       => '',
    class      => 'article',
    title      => 'Exsting category\'s index story',
);
$index->save;
$index->checkin;
push @stories, $index;

eval {
    $this->can_copy_test(
        dst_category => $that,
        story        => 1,
        media        => 0,
        template     => 0,
        overwrite    => 1,
    );
};

note('Testing with overwrite - should not throw exception');
is(!$@, 1, 'No Krang::Category::CopyAssetConflict thrown');

# do copy
eval {
    $copied = $this->copy(
        dst_category => $that,
        story        => 1,
        media        => 1,
        template     => 1,
        overwrite    => 1,
    );
};

my @indices = pkg('Story')->find(url => $index->url, include_trashed => 1);
is(scalar(@indices), 2, "Two stories with the same URL exist now");

($index) = grep { $_->story_id == $index->story_id } @indices;
is($index->trashed, 1, "Original category index story has been trashed.");

my ($new_index) = grep { $_->story_id != $index->story_id } @indices;
isa_ok($new_index, 'Krang::Story');

push @stories,    @{$copied->{story}}    if $copied->{story};
push @categories, @{$copied->{category}} if $copied->{category};
push @media,      @{$copied->{media}}    if $copied->{media};
push @templates,  @{$copied->{template}} if $copied->{template};

#   --- End tests ---

sub setup_tree {

    $_->delete for @stories, @media, @templates;
    eval { $creator->cleanup() };
    $_->delete for reverse @categories;

    @categories = ();
    @stories    = ();
    @media      = ();
    @templates  = ();

    $creator = pkg('Test::Content')->new;

############### Source Category Subtree ######################
    my ($root) = pkg('Category')->find(dir => '/');

    my $from = pkg('Category')->new(
        parent_id => $root->category_id,
        dir       => 'from'
    );
    $from->save;
    push @categories, $from;

    $this = pkg('Category')->new(
        parent_id => $from->category_id,
        dir       => 'this'
    );
    $this->save;
    push @categories, $this;

    my $source = pkg('Category')->new(
        parent_id => $this->category_id,
        dir       => 'source'
    );
    $source->save;
    push @categories, $source;

    my $water = pkg('Category')->new(
        parent_id => $source->category_id,
        dir       => 'water'
    );
    $water->save;
    push @categories, $water;

    my $fresh = pkg('Category')->new(
        parent_id => $water->category_id,
        dir       => 'fresh'
    );
    $fresh->save;
    push @categories, $fresh;

    # Some stories
    my $from_story_1 = pkg('Story')->new(
        categories => [$this],
        slug       => 'from_story_1',
        class      => 'article',
        title      => 'From Story 1'
    );
    $from_story_1->save;
    push @stories, $from_story_1;

    my $from_story_2 = pkg('Story')->new(
        categories => [$source],
        slug       => 'from_story_2',
        class      => 'article',
        title      => 'From Story 2'
    );
    $from_story_2->save;
    push @stories, $from_story_2;

    my $from_story_3 = pkg('Story')->new(
        categories => [$water],
        slug       => '',
        class      => 'article',
        title      => 'From Story 3 (slugless)'
    );
    $from_story_3->save;
    push @stories, $from_story_3;

    # Some media
    my $from_media_1 = $creator->create_media(
        category => $this,
        title    => 'From Media 1',
        filename => 'from_media_1',
        format   => 'jpg',
    );

    my $from_media_2 = $creator->create_media(
        category => $source,
        title    => 'From Media 2',
        filename => 'from_media_2',
        format   => 'jpg',
    );

    # Some templates
    my $from_template_1 = $creator->create_template(
        category     => $this,
        element_name => 'from_template_1',
        content      => 'x'
    );

    my $from_template_2 = $creator->create_template(
        category     => $water,
        element_name => 'from_template_2',
        content      => 'x'
    );

############### Destination Category Subtree ######################
    my $to = pkg('Category')->new(
        parent_id => $root->category_id,
        dir       => 'to'
    );
    $to->save;
    push @categories, $to;

    $that = pkg('Category')->new(
        parent_id => $to->category_id,
        dir       => 'that'
    );
    $that->save;
    push @categories, $that;

    $destination = pkg('Category')->new(
        parent_id => $that->category_id,
        dir       => 'destination'
    );
    $destination->save;
    push @categories, $destination;

    my $sea = pkg('Category')->new(
        parent_id => $destination->category_id,
        dir       => 'sea'
    );
    $sea->save;
    push @categories, $sea;

    my $planet = pkg('Category')->new(
        parent_id => $sea->category_id,
        dir       => 'planet'
    );
    $planet->save;
    push @categories, $planet;

    # Some stories
    my $to_story_1 = pkg('Story')->new(
        categories => [$that],
        slug       => 'to_story_1',
        class      => 'article',
        title      => 'To Story 1'
    );
    $to_story_1->save;
    push @stories, $to_story_1;

    my $to_story_2 = pkg('Story')->new(
        categories => [$sea],
        slug       => '',
        class      => 'article',
        title      => 'To Story 2 (slugless)'
    );
    $to_story_2->save;
    push @stories, $to_story_2;

    my $to_story_3 = pkg('Story')->new(
        categories => [$sea],
        slug       => 'to_story_3',
        class      => 'article',
        title      => 'To Story 3'
    );
    $to_story_3->save;
    push @stories, $to_story_3;

    my $to_story_4 = pkg('Story')->new(
        categories => [$planet],
        slug       => 'to_story_4',
        class      => 'article',
        title      => 'To Story 4'
    );
    $to_story_4->save;
    push @stories, $to_story_4;

    # Some media
    my $to_media_1 = $creator->create_media(
        category => $that,
        title    => 'To Media 1',
        filename => 'to_media_1',
        format   => 'jpg',
    );

    my $to_media_2 = $creator->create_media(
        category => $planet,
        title    => 'To Media 2',
        filename => 'to_media_2',
        format   => 'jpg',
    );

    # Some templates
    my $to_template_1 = $creator->create_template(
        category     => $sea,
        element_name => 'to_template_1',
        content      => 'x'
    );

    my $to_template_2 = $creator->create_template(
        category     => $planet,
        element_name => 'to_template_2',
        content      => 'x'
    );

    $_->checkin for @stories;
}

END {
    $_->delete for @stories, @media, @templates;
    $creator->cleanup();
    $_->delete for reverse @categories;
}
