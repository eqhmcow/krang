use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use File::Spec::Functions;
use File::Path;
use Krang::ClassLoader 'Contrib';
use Krang::ClassLoader 'Pref';
use Krang::ClassLoader Conf => qw(KrangRoot instance InstanceElementSet EnableSSL PreviewSSL);
use Krang::ClassLoader 'Site';
use Krang::ClassLoader 'Category';
use Krang::ClassLoader 'Story';
use Krang::ClassLoader 'Element';
use Krang::ClassLoader 'Template';
use Krang::ClassLoader 'Script';
use Krang::ClassLoader 'URL';
use Krang::ClassLoader 'IO';

use Krang::ClassLoader 'Test::Content';

use Data::Dumper;

# skip all tests unless a TestSet1-using instance is available
BEGIN {
    my $found;
    foreach my $instance (pkg('Conf')->instances) {
        pkg('Conf')->instance($instance);
        if (InstanceElementSet eq 'TestSet1') {
            $found = 1;
            last;
        }
    }

    unless ($found) {
        eval "use Test::More skip_all => 'test requires a TestSet1 instance';";
    } else {
        eval "use Test::More qw(no_plan);";
    }
    die $@ if $@;
}

# Set preview scheme
my $scheme = PreviewSSL ? 'https' : 'http';

# instantiate publisher
use_ok(pkg('Publisher'));

############################################################
# PRESETS

my $template_dir = catdir(KrangRoot, 't', 'publish');

# Site params
my $preview_url  = 'publishtest.preview.com';
my $publish_url  = 'publishtest.com';
my $preview_path = '/tmp/krangpubtest_preview';
my $publish_path = '/tmp/krangpubtest_publish';

# Content params
my $para1       = "para1 " x 40;
my $para2       = "para2 " x 40;
my $para3       = "para3 " x 40;
my $head1       = "header " x 10;
my $head_output = "<h1>$head1</h1>\n";
my $deck1       = 'DECK DECK DECK';
my $page_output = "<h1>$head1</h1>THIS IS A VERY WIDE PAGE<p>$para1</p><p>$para2</p><p>$para3</p>";
my $category1   = 'CATEGORY1 ' x 5;
my $category2   = 'CATEGORY2 ' x 5;
my $category3   = 'CATEGORY3 ' x 5;
my $story_title = 'Test Title';

my $pagination1 = '<P>Page number 1 of 1.</p>';

my $page_break = pkg('Publisher')->page_break();

my $category1_head   = 'THIS IS HEADS' . $category1 . '---';
my $category1_tail   = '---' . $category1 . 'THIS IS TAILS';
my $category1_output = $category1_head . pkg('Publisher')->content() . $category1_tail;

my $category2_head   = 'THIS IS HEADS' . $category2 . '---';
my $category2_tail   = '---' . $category2 . 'THIS IS TAILS';
my $category2_output = $category2_head . pkg('Publisher')->content() . $category2_tail;

my $category3_head   = 'THIS IS HEADS' . $category3 . '---';
my $category3_tail   = '---' . $category3 . 'THIS IS TAILS';
my $category3_output = $category3_head . pkg('Publisher')->content() . $category3_tail;

my %article_output = (
    3 => $category3_head
      . "<title>$story_title</title>"
      . $page_output
      . $pagination1 . '1'
      . $category3_tail,
    2 => $category2_head
      . "<title>$story_title</title>"
      . $page_output
      . $pagination1 . '1'
      . $category2_tail,
    1 => $category1_head
      . "<title>$story_title</title>"
      . $page_output
      . $pagination1 . '1'
      . $category1_tail
);

# list of templates to delete at the end of this all.
my @test_templates_delete = ();
my %test_template_lookup  = ();

# file path of element template
my %template_paths    = ();
my %template_deployed = ();

my %slug_id_list;

my @non_test_deployed_templates = ();

my $publisher = pkg('Publisher')->new();

isa_ok($publisher, 'Krang::Publisher');

can_ok(
    $publisher,
    (
        'publish_story',     'preview_story',   'unpublish_story',       'publish_media',
        'preview_media',     'unpublish_media', 'asset_list',            'deploy_template',
        'undeploy_template', 'PAGE_BREAK',      'story',                 'category',
        'story_filename',    'publish_context', 'clear_publish_context', 'url_for',
    )
);

############################################################
# remove all currently deployed templates from the system
#
@non_test_deployed_templates = pkg('Template')->find(deployed => 1);

foreach (@non_test_deployed_templates) {
    &test_undeploy_template($_);
}

END {

    # restore system templates.
    foreach (@non_test_deployed_templates) {
        $publisher->deploy_template(template => $_);
    }
}

############################################################

my $creator = pkg('Test::Content')->new;

# create a site and category for dummy story
my $site = $creator->create_site(
    preview_url  => $preview_url,
    publish_url  => $publish_url,
    preview_path => $preview_path,
    publish_path => $publish_path
);

END {
    $creator->cleanup();
    rmtree $preview_path;
    rmtree $publish_path;
}

my ($category) = pkg('Category')->find(site_id => $site->site_id());
$category->element()->data($category1);
$category->save();

# create child & subchild categories
my $child_cat = $creator->create_category(
    dir    => 'testdir_a',
    parent => $category->category_id,
    data   => $category2
);

my $child_subcat = $creator->create_category(
    dir    => 'testdir_b',
    parent => $child_cat->category_id,
    data   => $category3
);

############################################################
# testing template seach path.

# Directory structures for template paths.
my @rootdirs = (KrangRoot, 'data', 'templates', pkg('Conf')->instance());

my @dirs_a = (
    File::Spec->catfile(@rootdirs, $site->url(), 'testdir_a', 'testdir_b'),
    File::Spec->catfile(@rootdirs, $site->url(), 'testdir_a'),
    File::Spec->catfile(@rootdirs, $site->url()),
    File::Spec->catfile(@rootdirs)
);

$publisher->{category} = $child_subcat;    # internal hack - set currently running category.
my @paths = $publisher->template_search_path();

ok(@paths == @dirs_a, 'Krang::Publisher->template_search_path()');

for (my $i = 0 ; $i <= $#paths ; $i++) {
    ok($paths[$i] eq $dirs_a[$i], 'Krang::Publisher->template_search_path()');
}

############################################################
# testing Krang::ElementClass->find_template().

# create new stories -- get root element.
my @media;
my @stories;
for (1 .. 10) {
    push @media, $creator->create_media(category => $category);
}

for (1 .. 10) {
    push @stories, $creator->create_story(category => [$category]);
}

my $story = $creator->create_story(
    category  => [$category, $child_cat, $child_subcat],
    paragraph => [$para1,    $para2,     $para3],
    header    => $head1,
    deck      => $deck1,
    title     => $story_title
);
my $story2 = $creator->create_story(
    category       => [$category],
    linked_stories => [$story],
    linked_media   => [$media[0]],
    header         => $head1,
    deck           => $deck1,
    paragraph      => [$para1, $para2, $para3],
    title          => $story_title
);

my $element = $story->element();

# put test templates out into the production path.
deploy_test_templates($category);

# cleanup - removing all outstanding assets.
END {
    foreach (@test_templates_delete) {

        # delete created templates
        $publisher->undeploy_template(template => $_);
        $_->delete();
    }
}

############################################################
# Testing the publish process.

test_find_templates();

test_contributors();

test_publish_status();

test_linked_assets();

test_story_build($story, $category);

test_publish_story($story);

test_preview_story($story);

test_maintain_versions($story2);

test_cgistory_publish();

test_publish_flattened();

test_fill_flattened_page_loop($story);

test_fill_flattened_missing_template($story);

test_media_deploy();

test_storylink();

test_medialink();

test_categorylink();

test_template_testing($story, $category);

test_full_preview();

test_full_publish();

test_story_unpublish();

test_story_disappearing();

test_media_unpublish();

test_additional_content_block();

test_multi_page_story();

test_publish_category_per_page();

test_publish_context();

test_is_modified();

test_publish_if_modified_in_category();

############################################################
#
# SUBROUTINES.
#

# test Krang::Contrib section of story
# add contributor to story.
# test Krang::ElementClass->_build_contrib() to see if the
# returning hash is consistent with what's expected.

sub test_contributors {

    my $cat        = $creator->create_category();
    my @categories = ($cat);

    my %contributor   = build_contrib_hash();
    my %contrib_types = pkg('Pref')->get('contrib_type');

    $publisher->_set_publish_mode();

    my $story   = $creator->create_story(category => \@categories);
    my $contrib = $creator->create_contrib(%contributor);
    my $media   = $creator->create_media(category => $categories[0]);

    $contrib->image($media);
    $contrib->save();

    $story->contribs({contrib_id => $contrib->contrib_id, contrib_type_id => 1});

    my $story_element = $story->element();

    $publisher->{story} = $story;

    my $contributors = $story_element->class->_build_contrib_loop(
        publisher => $publisher,
        element   => $story_element
    );

    foreach my $schmoe (@$contributors) {
        foreach (keys %contributor) {
            next if ($_ eq 'image_url');
            ok($schmoe->{$_} eq $contributor{$_},
                "Krang::ElementClass->_build_contrib_loop() -- $_");
        }
        ok(
            $schmoe->{contrib_id} eq $contrib->contrib_id(),
            'Krang::ElementClass->_build_contrib_loop()'
        );

        # make sure contrib types are ok as well.
        foreach my $gig (@{$schmoe->{contrib_type_loop}}) {
            ok(
                (
                    exists($contrib_types{$gig->{contrib_type_id}})
                      && $contrib_types{$gig->{contrib_type_id}} eq $gig->{contrib_type_name}
                ),
                'Krang::ElementClass->_build_contrib_loop()'
            );
        }

        # test image
        ok($media->url eq $schmoe->{image_url},
            'Krang::ElementClass->_build_contrib_loop() -- image_url');

    }

    $creator->delete_item(item => $contrib);
    $creator->delete_item(item => $media);
    $creator->delete_item(item => $story);
    $creator->delete_item(item => $cat);

}

#
# test_template_testing()
#
# When a user previews content, any templates they have in the system that have been flagged as
# 'testing' should be used.
# The priority of 'testing' templates works as follows:
# in any dir/cat structure site/a/b/c:
#   testing template:  test/site/a/b/c/template.tmpl
#   has priority over: prod/site/a/b/c/template.tmpl
# but:
#   prod template:     prod/site/a/b/c/template.tmpl
#   has priority over: test/site/a/b/template.tmpl
#
# Got it?  good.
#
sub test_template_testing {

    my ($story, $category) = @_;

    # take header template, update content, flag for testing.
    my $header = $test_template_lookup{header};

    my $header_content = $header->content();

    $header->content('TESTING' . $header_content);
    $header->save();

    $header->mark_for_testing();

    # test that directory paths returned include testing dirs in the right order
    $publisher->_set_preview_mode();

    $publisher->_deploy_testing_templates();
    my @paths = $publisher->template_search_path(category => $category);
    my $base = catdir(KrangRoot, 'tmp');

    ok($paths[0] =~ /^$base\/\w+/, 'Krang::Publisher->_deploy_testing_templates');

    # test that testing templates are deployed properly.
    ok(-e catfile($paths[0], 'header.tmpl'), 'Krang::Publisher->_deploy_testing_templates');

    # test that in preview mode, testing templates are used.
    $publisher->{story}    = $story;
    $publisher->{category} = $category;

    my $page = $element->child('page');
    my $head = $page->child('header');

    my $head_pub = $head->publish(element => $head, publisher => $publisher);
    ok($head_pub eq ('TESTING' . $head_output), 'Krang::Publisher testing templates');

    # test that in publish mode, testing templates not are used.
    $publisher->_set_publish_mode();

    $head_pub = $head->publish(element => $head, publisher => $publisher);
    ok($head_pub eq $head_output, 'Krang::Publisher testing templates');

    # remove testing templates & test.
    $publisher->_undeploy_testing_templates();
    isnt(-e catfile($paths[0], 'header.tmpl'), 'Krang::Publisher->_undeploy_testing_templates()');

    # cleanup.
    $header->content($header_content);
    $header->save();    # clears testing flag

}

sub test_full_preview {

    $publisher->preview_story(story => $story);

    foreach ($story, $story2, @stories) {
        my @paths = build_preview_paths($_);
        foreach my $path (@paths) {
            note("Missing $path")
              unless (ok(-e $path, 'Krang::Publisher->preview_story() -- complete story writeout'));
        }
    }

    foreach (@media) {
        my $path = $_->preview_path;
        ok(-e $path, 'Krang::Publisher->preview_story() -- complete media writeout');
    }

}

sub test_full_publish {

    $publisher->publish_story(story => $story);

    foreach ($story, $story2, @stories) {
        my @paths = build_publish_paths($_);
        foreach my $p (@paths) {
            ok(-e $p, 'Krang::Publisher->publish_story() -- complete story writeout');
        }
    }

    foreach (@media) {
        my $path = $_->publish_path();
        ok(-e $path, 'Krang::Publisher->publish_story() -- complete media writeout');
    }

}

# create a new story, create multiple pages for it.
# publish it, find all the pages, compare them to what's expected.
sub test_multi_page_story {

    my $category = $creator->create_category();
    my $story = $creator->create_story(category => [$category]);

    $story->checkout();

    my $page2 = $story->element->add_child(class => 'page');
    _add_page_data($page2);
    my $page3 = $story->element->add_child(class => 'page');
    _add_page_data($page3);
    my $page4 = $story->element->add_child(class => 'page');
    _add_page_data($page4);

    $story->save();
    $story->checkin();

    $publisher->_set_publish_mode();

    my @pages = $publisher->_build_story_single_category(story => $story, category => $category);

    is(@pages, 4, 'Krang::Publisher - multi-page story');

    $creator->delete_item(item => $story);
    $creator->delete_item(item => $category);

}

#
# test the publisher functionality of calling category->publish() for
# each page of a story.
#
sub test_publish_category_per_page {

    my $category = $creator->create_category();
    my $story    = $creator->create_story(
        category => [$category],
        class    => 'publishtest'
    );

    $story->checkout();

    my $page2 = $story->element->add_child(class => 'page');
    _add_page_data($page2);
    my $page3 = $story->element->add_child(class => 'page');
    _add_page_data($page3);
    my $page4 = $story->element->add_child(class => 'page');
    _add_page_data($page4);

    $story->save();
    $story->checkin();

    $publisher->_set_publish_mode();

    my @pages = $publisher->_build_story_single_category(story => $story, category => $category);

    is(@pages, 4, 'Krang::Publisher - multi-page story');

    # load each page, and make sure it has the page numbering at the end.
    my $i = 1;
    foreach (@pages) {
        my $page   = load_story_page($_);
        my $string = "page number=$i total=4";

        # find that page number!
        if ($page =~ /$string/) {
            pass('Krang::Publisher - publish_category_per_page');
        } else {
            note("Cannot find '$string':\n\n$page");
            fail('Krang::Publisher - publish_category_per_page');
            die;
        }
        $i++;
    }

}

############################################################
# Testing related stories/media list.

sub test_publish_status {

    my $story = $creator->create_story(category => [$category]);
    my $pub = pkg('Publisher')->new();

    # need to create filesystem paths to handle FS checks.
    my @pub_paths = build_publish_paths($story);
    foreach (@pub_paths) {
        $_ =~ /^(.*\/)[^\/]+/;
        my $dir = $1;
        mkpath($dir, 0, 0755);
        `touch $_`;
    }
    my @pre_paths = build_preview_paths($story);
    foreach (@pre_paths) {
        $_ =~ /^(.*\/)[^\/]+/;
        my $dir = $1;
        mkpath($dir, 0, 0755);
        `touch $_`;
    }

    eval {

        # this should croak - no publish status set.
        $pub->test_publish_status(object => $story);
    };

    $@
      ? pass('Krang::Publisher->test_publish_status()')
      : fail('Krang::Publisher->test_publish_status()');

    my $bool;
    eval {

        # this should return true - the story should be published.
        $bool = $pub->test_publish_status(object => $story, mode => 'publish');
    };

    if ($@) {
        note("Unexpected croak: $@");
        fail('Krang::Publisher->test_publish_status()');
    } else {
        is($bool, 1, 'Krang::Publisher->test_publish_status()');
    }

    # 'preview' the story - the next test should return 0, as the
    # current version of the story has now been previewed.
    $story->mark_as_previewed();

    $bool = $pub->test_publish_status(object => $story, mode => 'preview');
    is($bool, 0, 'Krang::Publisher->test_publish_status()');

    # but a publish test should return 1.
    $bool = $pub->test_publish_status(object => $story, mode => 'publish');
    is($bool, 1, 'Krang::Publisher->test_publish_status()');

    # mark as published, test again - should now be 0.
    $story->mark_as_published();
    $bool = $pub->test_publish_status(object => $story, mode => 'publish');
    is($bool, 0, 'Krang::Publisher->test_publish_status()');

    # 'preview' the story as unsaved - the next test should return 1.
    $story->mark_as_previewed(unsaved => 1);
    $bool = $pub->test_publish_status(object => $story, mode => 'preview');
    is($bool, 1, 'Krang::Publisher->test_publish_status()');

    $pub->_init_asset_lists();
    my ($publish_ok, $check_links) = $pub->_check_asset_status(
        object         => $story,
        mode           => 'publish',
        version_check  => 0,
        initial_assets => 0
    );

    # should pass.
    is($publish_ok, 1, 'Krang::Publisher: version_check off');

    $pub->_init_asset_lists();
    ($publish_ok, $check_links) = $pub->_check_asset_status(
        object         => $story,
        mode           => 'publish',
        version_check  => 1,
        initial_assets => 0
    );
    is($publish_ok, 0, 'Krang::Publisher: version_check on');

    # add the file to the filesystem - should return false.
    $story->mark_as_published();

    $bool = $pub->test_publish_status(object => $story, mode => 'publish');
    is($bool, 0, 'test_publish_status() - filesystem check');

    # remove one file from the filesystem - should return true.
    unlink $pub_paths[0];
    $bool = $pub->test_publish_status(object => $story, mode => 'publish');
    is($bool, 1, 'test_publish_status() - filesystem check');

    # test with preview too.
    unlink $pre_paths[0];
    $bool = $pub->test_publish_status(object => $story, mode => 'preview');
    is($bool, 1, 'test_publish_status() - filesystem check');

    # cleanup
    foreach (@pub_paths, @pre_paths) {
        $_ =~ /^(.*\/)[^\/]+/;
        my $dir = $1;
        unlink $_ if -e $_;
        rmtree($dir);
    }

}

sub test_linked_assets {

    my $publisher = pkg('Publisher')->new();

    # touch filesystem locations to simulate publishing story.
    my @paths;
    foreach ($story, $story2, @stories) {
        push @paths, build_publish_paths($_);
        push @paths, build_preview_paths($_);
    }
    foreach (@media) {
        push @paths, $_->preview_path(), $_->publish_path();
    }
    foreach (@paths) {
        $_ =~ /^(.*\/)[^\/]+/;
        my $dir = $1;
        mkpath($dir, 0, 0755);
        `touch $_`;
    }

    # test that asset_list(story) returns story.
    my $publish_list =
      $publisher->asset_list(story => $story, mode => 'preview', version_check => 1);
    my %expected = (media => {}, story => {$story->story_id => $story});
    test_publish_list($publish_list, \%expected);

    # clear asset lists to not interfere with tests.
    $publisher->_clear_asset_lists();

    # link story to story.
    # nothing changes in terms of what's expected.
    link_story($story, $story);
    $publish_list = $publisher->asset_list(story => $story, mode => 'preview', version_check => 1);
    test_publish_list($publish_list, \%expected);

    # clear asset lists to not interfere with tests.
    $publisher->_clear_asset_lists();

    # test that asset_list(story2) returns story2 + story + media
    $publish_list = $publisher->asset_list(story => $story2, mode => 'preview', version_check => 1);
    %expected = (
        media => {$media[0]->media_id => $media[0]},
        story => {
            $story->story_id  => $story,
            $story2->story_id => $story2
        }
    );

    test_publish_list($publish_list, \%expected);

    # clear asset lists to not interfere with tests.
    $publisher->_clear_asset_lists();

    # mark story as previewed - it should no longer show up when story2 is 'previewed'.
    $story->mark_as_previewed();
    delete $expected{story}{$story->story_id};
    $publish_list = $publisher->asset_list(story => $story2, mode => 'preview', version_check => 1);
    test_publish_list($publish_list, \%expected);

    # clear asset lists to not interfere with tests.
    $publisher->_clear_asset_lists();

    # undo the preview by marking as an unsaved preview (which forces preview next time).
    $story->mark_as_previewed(unsaved => 1);
    $expected{story}{$story->story_id} = $story;

    # add links to all of @stories to story2.
    # test that asset_list(story2) returns story2 + story + @stories + media
    foreach (@stories) {
        &link_story($story2, $_);
        $expected{story}{$_->story_id} = $_;
    }
    $publish_list = $publisher->asset_list(story => $story2, mode => 'preview', version_check => 1);
    test_publish_list($publish_list, \%expected);

    # clear asset lists to not interfere with tests.
    $publisher->_clear_asset_lists();

    # add links to all of @stories to story -- duplicates story requirements.
    # test that asset_list(story2) returns story2 + story + @stories + media
    foreach (@stories) {
        link_story($story, $_);
    }
    $publish_list = $publisher->asset_list(story => $story2, mode => 'preview', version_check => 1);
    test_publish_list($publish_list, \%expected);

    # clear asset lists to not interfere with tests.
    $publisher->_clear_asset_lists();

    # add links to all of @media to story2.
    # test that asset_list(story2) returns story2 + story + @stories + media + @media
    foreach (@media) {
        link_media($story2, $_);
        $expected{media}{$_->media_id} = $_;
    }
    $publish_list = $publisher->asset_list(story => $story2, mode => 'preview', version_check => 1);
    test_publish_list($publish_list, \%expected);

    # clear asset lists to not interfere with tests.
    $publisher->_clear_asset_lists();

    # add links to all of @media to story -- duplicates media requirements.
    # test that asset_list(story2) returns story2 + story + @stories + media + @media
    foreach (@media) {
        link_media($story, $_);
    }
    $publish_list = $publisher->asset_list(story => $story2, mode => 'preview', version_check => 1);
    test_publish_list($publish_list, \%expected);

    # clear asset lists to not interfere with tests.
    $publisher->_clear_asset_lists();

    # add link to story2 to story -- creates a full cycle.
    # test that asset_list(story2) returns story2 + story + @stories + media + @media
    link_story($story, $story2);
    $publish_list = $publisher->asset_list(story => $story2, mode => 'preview', version_check => 1);
    test_publish_list($publish_list, \%expected);

    # clear asset lists to not interfere with tests.
    $publisher->_clear_asset_lists();

    # stress test - create multiple cycles, create as many interlinking dependencies as possible.
    # final publish list shouldn't change.
    foreach (@stories) {
        link_story($_, $story);
        link_story($_, $story2);
    }
    $publish_list = $publisher->asset_list(story => $story2, mode => 'preview', version_check => 1);
    test_publish_list($publish_list, \%expected);

    # clear asset lists to not interfere with tests.
    $publisher->_clear_asset_lists();

    # asset test - mark all @stories as previewed - they shouldn't show up in the publish list.
    foreach (@stories) {
        $_->mark_as_previewed();
        delete $expected{story}{$_->story_id};
    }
    $publish_list = $publisher->asset_list(story => $story2, mode => 'preview', version_check => 1);
    test_publish_list($publish_list, \%expected);

    # clear asset lists to not interfere with tests.
    $publisher->_clear_asset_lists();

    foreach (@media) {
        $_->mark_as_previewed();
        delete $expected{media}{$_->media_id};
    }
    $publish_list = $publisher->asset_list(story => $story2, mode => 'preview', version_check => 1);
    test_publish_list($publish_list, \%expected);

    # clear asset lists to not interfere with tests.
    $publisher->_clear_asset_lists();

    # undo the marking
    foreach (@stories, @media) {
        $_->mark_as_previewed(unsaved => 1);
        if ($_->isa('Krang::Story')) {
            $expected{story}{$_->story_id} = $_;
        } else {
            $expected{media}{$_->media_id} = $_;
        }
    }

    # now check publish
    $publish_list = $publisher->asset_list(story => $story2, mode => 'publish', version_check => 1);
    test_publish_list($publish_list, \%expected);

    # clear asset lists to not interfere with tests.
    $publisher->_clear_asset_lists();

    # mark @stories as published - they should not show up in $publish_list.
    foreach (@stories) {
        $_->mark_as_published();
        delete $expected{story}{$_->story_id};
    }
    $publish_list = $publisher->asset_list(story => $story2, mode => 'publish', version_check => 1);
    test_publish_list($publish_list, \%expected);

    # clear asset lists to not interfere with tests.
    $publisher->_clear_asset_lists();

    # test linked $story that has been retired (should not publish)
    $story->retire();
    delete $expected{story}{$story->story_id};
    $publish_list = $publisher->asset_list(story => $story2, mode => 'publish', version_check => 1);
    test_publish_list($publish_list, \%expected);

    # clear asset lists to not interfere with tests, unretire and 'expect' $story again
    $publisher->_clear_asset_lists();

    # test linked $story that has been trashed (should not publish)
    $story->trash();
    $publish_list = $publisher->asset_list(story => $story2, mode => 'publish', version_check => 1);
    test_publish_list($publish_list, \%expected);

   # clear asset lists to not interfere with tests, also untrash, unretire and 'expect' $story again
    $publisher->_clear_asset_lists();
    $story->untrash();
    $story->unretire();
    $expected{story}{$story->story_id} = $story;

    # test linked $media that has been retired (should not publish)
    my $media = $media[0];
    $media->retire();
    delete $expected{media}{$media->media_id};
    $publish_list = $publisher->asset_list(story => $story2, mode => 'publish', version_check => 1);
    test_publish_list($publish_list, \%expected);

    # clear asset lists to not interfere with tests, unretire and 'expect' $media again
    $publisher->_clear_asset_lists();

    # test linked $media that has been trashed (should not publish)
    $media->trash();
    $publish_list = $publisher->asset_list(story => $story2, mode => 'publish', version_check => 1);
    test_publish_list($publish_list, \%expected);

   # clear asset lists to not interfere with tests, also untrash, unretire and 'expect' $media again
    $publisher->_clear_asset_lists();
    $media->untrash();
    $media->unretire();
    $expected{media}{$media->media_id} = $media;

    # mark @media as published - they too should no longer show up.
    foreach (@media) {
        $_->mark_as_published();
        delete $expected{media}{$_->media_id};
    }
    $publish_list = $publisher->asset_list(story => $story2, mode => 'publish', version_check => 1);
    test_publish_list($publish_list, \%expected);

    # clear asset lists to not interfere with tests.
    $publisher->_clear_asset_lists();

    # restore everything, test one last time.
    foreach (@stories, @media) {
        $_->checkout();
        $_->save();    # this will bump the version number.
        if ($_->isa('Krang::Story')) {
            $expected{story}{$_->story_id} = $_;
        } else {
            $expected{media}{$_->media_id} = $_;
        }
    }

    $publish_list = $publisher->asset_list(story => $story2, mode => 'publish', version_check => 1);
    test_publish_list($publish_list, \%expected);

    # cleanup
    foreach (@paths) {
        $_ =~ /^(.*\/)[^\/]+/;
        my $dir = $1;
        unlink $_ if -e $_;
        rmtree($dir);
    }

    # clear asset lists to not interfere with tests.
    $publisher->_clear_asset_lists();

}

# test to confirm the publish list returned is the list expected.
# confirm that each element exists in %expected, and then
# confirm that %expected does not contain anything not in the publish list.

sub test_publish_list {

    my ($publist, $expected) = @_;
    my %lookup = ();

    # test to see if what returned was expected
    foreach (@$publist) {
        if ($_->isa('Krang::Story')) {
            unless (ok(exists($expected->{story}{$_->story_id}), 'asset_list() - story check')) {
                note("Found story that should not be in publish list");
            }
            $lookup{story}{$_->story_id} = 1;
        } elsif ($_->isa('Krang::Media')) {
            unless (ok(exists($expected->{media}{$_->media_id}), 'asset_list() - media check')) {
                note("Found media that should not be in publish list");
            }
            $lookup{media}{$_->media_id} = 1;
        } else {
            fail("Krang::Publisher->asset_list - returned '" . $_->isa() . "'");
        }
    }

    # test to see if everything expected was returned
    foreach (qw(story media)) {
        foreach my $key (keys %{$expected->{$_}}) {
            my $obj = $expected->{$_}{$key};
            if ($_ eq 'story') {
                unless (ok(exists($lookup{story}{$obj->story_id}), 'asset_list() - story check')) {
                    note("Missing expected story in publish list");
                }
            } elsif ($_ eq 'media') {
                unless (ok(exists($lookup{media}{$obj->media_id}), 'asset_list() - media check')) {
                    note("Missing expected media in publish list");
                }
            }
        }
    }
}

# Test to make sure Krang::Publisher->publish/preview_media works.
sub test_media_deploy {

    my $media = $creator->create_media();

    # test media deployment.
    my $pub_expected_path = catfile($publish_path, $media->url());

    my ($pub_media_url) = $publisher->publish_media(media => $media);

    my $pub_media_path = catfile($publish_path, $pub_media_url);

    ok($pub_expected_path eq $pub_media_path, 'Krang::Publisher->publish_media()');

    my $prev_expected_path = catfile($preview_path, $media->preview_url());

    my $prev_media_url = $publisher->preview_media(media => $media);

    my $prev_media_path = catfile($preview_path, $prev_media_url);

    ok($prev_expected_path eq $prev_media_path, 'Krang::Publisher->preview_media()');

    $creator->delete_item(item => $media);

}

# test to make sure that Krang::Template templates are removed from the filesystem properly.
sub test_undeploy_template {

    my $tmpl = shift;

    my $category = $tmpl->category();

    my @tmpls = $publisher->template_search_path(category => $category);
    my $path = $tmpls[0];

    my $file = catfile($path, $tmpl->filename());

    # undeploy template
    eval { $publisher->undeploy_template(template => $tmpl); };

    if ($@) {
        note($@);
        fail('Krang::Publisher->undeploy_template()');
    } else {
        ok(!(-e $file), 'Krang::Publisher->undeploy_template()');
    }
}

sub test_deploy_template {

    my $tmpl = shift;
    my $result;

    my $category = $tmpl->category();

    my @tmpls = $publisher->template_search_path(category => $category);
    my $path = $tmpls[0];

    my $file = catfile($path, $tmpl->filename());

    eval { $result = $publisher->deploy_template(template => $tmpl); };

    if ($@) {
        note($@);
        fail('Krang::Publisher->deploy_template()');
    } else {
        ok(-e $file && ($file eq $result), 'Krang::Publisher->deploy_template()');
    }

    return $file;
}

# test to make sure Krang::ElementClass::StoryLink->publish works as expected.
sub test_storylink {

    my $dest_story = $creator->create_story();
    my $src_story = $creator->create_story(linked_stories => [$dest_story]);

    $publisher->_set_publish_mode();

    # test related story - add a storylink from one story to the other.
    $publisher->{story} = $src_story;

    my $page      = $src_story->element->child('page');
    my $storylink = $page->child('leadin');

    # w/ deployed template - make sure it works w/ template.
    my $story_href = $storylink->publish(element => $storylink, publisher => $publisher);
    my $resulting_link =
      '<a href="http://' . $dest_story->url() . '">' . $dest_story->title() . '</a>';
    chomp($story_href);

    ok($story_href eq $resulting_link,
        'Krang::ElementClass::StoryLink->publish() -- publish w/ template');

    $publisher->_set_preview_mode();

    $story_href = $storylink->publish(element => $storylink, publisher => $publisher);
    $resulting_link =
      "<a href=\"$scheme://" . $dest_story->preview_url() . '">' . $dest_story->title() . '</a>';
    chomp($story_href);

    ok($story_href eq $resulting_link,
        'Krang::ElementClass::StoryLink->publish() -- preview w/ template');

    $publisher->_set_publish_mode();

    is('http://'.$publish_url, $publisher->url_for(object => $site), 'Krang::Site publish URL');

    # undeploy template - make sure it works w/ no template.
    $publisher->undeploy_template(template => $template_deployed{leadin});

    $story_href = $storylink->publish(element => $storylink, publisher => $publisher);

##    ok($story_href eq 'http://' . $dest_story->url(), 'Krang::ElementClass::StoryLink->publish() -- publish-no template');

    ok(
        $story_href eq $publisher->url_for(object => $dest_story),
        'Krang::ElementClass::StoryLink->publish() -- publish-no template'
    );

    $publisher->_set_preview_mode();

    is('http://'.$preview_url, $publisher->url_for(object => $site), 'Krang::Site preview URL');

    $story_href = $storylink->publish(element => $storylink, publisher => $publisher);

##    ok($story_href eq "$scheme://" . $dest_story->preview_url(), 'Krang::ElementClass::StoryLink->publish() -- preview-no template');

    ok(
        $story_href eq $publisher->url_for(object => $dest_story),
        'Krang::ElementClass::StoryLink->publish() -- preview-no template'
    );

    # re-deploy template.
    $publisher->deploy_template(template => $template_deployed{leadin});

    $creator->delete_item(item => $src_story);
    $creator->delete_item(item => $dest_story);

}

# test to make sure Krang::ElementClass::StoryLink->publish works as expected.
sub test_medialink {

    my $media = $creator->create_media();
    my $story = $creator->create_story(linked_media => [$media]);

    # test related media - add a medialink to a story.
    $publisher->{story} = $story;

    $publisher->_set_publish_mode();

    my $page      = $story->element()->child('page');
    my $medialink = $page->child('photo');

    # w/ deployed template - make sure it works w/ template.
    my $media_href = $medialink->publish(element => $medialink, publisher => $publisher);
    my $resulting_link =
      '<img src="http://' . $media->url() . '">' . $media->caption() . '<BR>' . $media->title();

    $media_href =~ s/\n//g;

    ok($media_href eq $resulting_link,
        'Krang::ElementClass::MediaLink->publish() -- publish w/ template');

    $publisher->_set_preview_mode();

    $media_href = $medialink->publish(element => $medialink, publisher => $publisher);
    $resulting_link =
        "<img src=\"$scheme://"
      . $media->preview_url() . '">'
      . $media->caption() . '<BR>'
      . $media->title();
    chomp($media_href);

    ok($media_href eq $resulting_link,
        'Krang::ElementClass::MediaLink->publish() -- preview w/ template');

    $publisher->_set_publish_mode();

    # undeploy template - make sure it works w/ no template.
    $publisher->undeploy_template(template => $template_deployed{photo});

    $media_href = $medialink->publish(element => $medialink, publisher => $publisher);

    ok(
        $media_href eq $publisher->url_for(object => $media),
        'Krang::ElementClass::MediaLink->publish() -- publish-no template'
    );

    $publisher->_set_preview_mode();

    $media_href = $medialink->publish(element => $medialink, publisher => $publisher);

    ok(
        $media_href eq $publisher->url_for(object => $media),
        'Krang::ElementClass::MediaLink->publish() -- preview-no template'
    );

    # re-deploy template.
    $publisher->deploy_template(template => $template_deployed{photo});

    $creator->delete_item(item => $media);
    $creator->delete_item(item => $story);

}

# test to make sure Krang::ElementClass::CategoryLink->publish works as expected.
sub test_categorylink {

    my $category = $creator->create_category();
    my $story    = $creator->create_story(category => [$category]);
    my $navlink  = $creator->create_category(parent => $category);

    $publisher->_set_publish_mode();

    # test related story - add a storylink from one story to the other.
    $publisher->{story}    = $story;
    $publisher->{category} = $category;

    my $categorylink = $category->element->add_child(class => 'leftnav_link');
    $categorylink->data($navlink);

    # w/ deployed template - make sure it works w/ template.
    my $nav_href = $categorylink->publish(element => $categorylink, publisher => $publisher);
    my $resulting_link = '<a href="http://' . $navlink->url() . '"></a>';
    chomp($nav_href);

    ok($nav_href eq $resulting_link,
        'Krang::ElementClass::CategoryLink->publish() -- publish w/ template');

    $publisher->_set_preview_mode();

    $nav_href = $categorylink->publish(element => $categorylink, publisher => $publisher);
    $resulting_link = "<a href=\"$scheme://" . $navlink->preview_url() . '"></a>';
    chomp($nav_href);

    ok($nav_href eq $resulting_link,
        'Krang::ElementClass::CategoryLink->publish() -- preview w/ template');

    $publisher->_set_publish_mode();

    # undeploy template - make sure it works w/ no template.
    $publisher->undeploy_template(template => $template_deployed{leftnav_link});

    $nav_href = $categorylink->publish(element => $categorylink, publisher => $publisher);

    ok(
        $nav_href eq $publisher->url_for(object => $navlink),
        'Krang::ElementClass::Categorylink->publish() -- publish-no template'
    );

    $publisher->_set_preview_mode();

    $nav_href = $categorylink->publish(element => $categorylink, publisher => $publisher);

    ok(
        $nav_href eq $publisher->url_for(object => $navlink),
        'Krang::ElementClass::Categorylink->publish() -- preview-no template'
    );

    # re-deploy template.
    $publisher->deploy_template(template => $template_deployed{leftnav_link});

    $creator->delete_item(item => $navlink);
    $creator->delete_item(item => $story);
    $creator->delete_item(item => $category);
}

sub test_story_build {

    my ($story, $category) = @_;

    # make sure the publisher knows where we are..
    $publisher->{is_publish} = 1;
    $publisher->{is_preview} = 0;

    $publisher->{story}    = $story;
    $publisher->{category} = $category;

    my $page = $element->child('page');
    my $para = $page->child('paragraph');
    my $head = $page->child('header');

    # test publish() on paragraph element -
    # it should return $paragraph_element->data()
    my $para_pub = $para->publish(element => $para, publisher => $publisher);
    ok($para_pub eq $para1, 'Krang::ElementClass->publish()');

    # test publish() on header element -
    # it should return $header_element->data() wrapped in <h1></h1>.
    # NOTE - HTML::Template::Expr throws in a newline at the end.
    my $head_pub = $head->publish(element => $head, publisher => $publisher);
    ok($head_pub eq $head_output, 'Krang::ElementClass->publish() -- header');

    # test publish() on page element -
    # it should contain header (formatted), note about wide page, 3 paragraphs.
    # Add pagination args as well
    my %pagination_hack = (
        is_first_page       => 1,
        is_last_page        => 1,
        current_page_number => 1,
        total_pages         => 1
    );
    my $page_pub = $page->publish(
        element       => $page,
        publisher     => $publisher,
        template_args => \%pagination_hack
    );
    $page_pub =~ s/\n//g;
    my $page_string = ($page_output . $pagination1);
    ok($page_pub eq $page_string, 'Krang::ElementClass->publish() -- page');

    # undeploy header tmpl & attempt to publish - should
    # return $header->data().
    $publisher->undeploy_template(template => $template_deployed{header});
    $head_pub = $head->publish(element => $head, publisher => $publisher);
    ok($head_pub eq $head1, 'Krang::ElementClass->publish() -- no tmpl');

    # undeploy page tmpl & attempt to publish - should croak.
    $publisher->undeploy_template(template => $template_deployed{page});
    eval { $page_pub = $page->publish(element => $page, publisher => $publisher); };
    if ($@) {
        pass('Krang::ElementClass->publish() -- missing tmpl');
    } else {
        note('page.tmpl was undeployed - publish should croak.');
        fail('Krang::ElementClass->publish() -- missing tmpl');
    }

    # redeploy page/header templates.
    $publisher->deploy_template(template => $template_deployed{page});
    $publisher->deploy_template(template => $template_deployed{header});

    # test publish() for category element.
    my $category_el = $category->element();

    my $cat_pub = $category_el->publish(element => $category_el, publisher => $publisher);
    $cat_pub =~ s/\n//g;
    ok($cat_pub eq $category1_output, 'Krang::ElementClass->publish() -- category');

    my $child_element_para = $category_el->add_child(class => 'paragraph', data => $para1);
    $cat_pub = $category_el->publish(element => $category_el, publisher => $publisher);
    $cat_pub =~ s/\n//g;
    ok($cat_pub eq ($category1_output . $para1),
        'Krang::ElementClass->publish() -- category w/ child');
    $category_el->remove_children($child_element_para);

}

sub test_publish_story {

    my $story = shift;

    $publisher->publish_story(story => $story);

    my @story_paths = build_publish_paths($story);

    foreach (my $i = $#story_paths ; $i >= 0 ; $i--) {
        my $story_txt = load_story_page($story_paths[$i]);
        $story_txt =~ s/\n//g;
        if ($story_txt =~ /\w/) {
            ok(
                $article_output{($i + 1)} eq $story_txt,
                'Krang::Publisher->publish_story() -- compare'
            );
            if ($article_output{($i + 1)} ne $story_txt) {
                note('Story content on filesystem does not match expected results');
                die Dumper($article_output{($i + 1)}, $story_txt);
            }
        } else {
            note('Missing story content in ' . $story_paths[$i]);
            fail('Krang::Publisher->publish_story() -- compare');
        }
    }
}

sub test_cgistory_publish {
    my $story = $creator->create_story(class => 'cgi_story', category => [$category]);
    my ($dyn_vars_block) = $story->element->child('dyn_vars_block');
    my $unique = "test_var_" . time;
    $dyn_vars_block->data('Test: <dyn_var ' . $unique . '>');
    $story->checkout();
    $story->save();
    $story->checkin();

    my $tmpl = $creator->create_template(element => $story->element);
    $tmpl->deploy();

    $publisher->publish_story(story => $story);

    my @story_paths = build_publish_paths($story);

    # Just test first path
    my $story_path = $story_paths[0];
    my $story_txt  = load_story_page($story_path);
    ok(($story_txt =~ /dyn\_var $unique/), "HTML page has dyn var");

    # Check to make sure there is a template
    my $tmpl_path = $story_path;
    $tmpl_path =~ s/index\.html$/cgi_story\.tmpl/;
    my $tmpl_text = load_story_page($tmpl_path);
    ok(($tmpl_text =~ /tmpl\_var $unique/i), "Template has tmpl var");

    # Check to make sure there is a stub file
    my $stub_path = $story_path;
    $stub_path =~ s/index\.html$/cgi_story\.cgi/;
    my $stub_text = load_story_page($stub_path);
    ok(($stub_text =~ /use CGI\:\:Application/i), "Stub looks right");

    # Test that fill_template works as expected for published templates
    my $diff = `/usr/bin/diff -I $unique $story_path $tmpl_path`;
    ok($diff =~ /^\s*$/, "No difference between CGI tmpl and story");

    # clean up
    $creator->delete_item(item => $tmpl);
    $creator->delete_item(item => $story);
}

sub test_publish_flattened {

    # create new story
    my $story = $creator->create_story(class => 'cgi_story', category => [$category]);
    $story->checkout();
    $story->save();
    $story->checkin();
    my @paragraphs = $story->element->match('/page[0]/paragraph');

    # publish story twice - once with flattened template, once without
    my @tmpl_content;
    my @output_text;
    for (0 .. 1) {

        # create template (using <element_loop> built by Test::Content)
        my ($tmpl, $content) = $creator->create_template(
            element     => $story->element,
            flattened   => $_,
            predictable => 1
        );
        $tmpl->deploy();

        # publish with it
        $publisher->publish_story(story => $story);

        # save results
        push @tmpl_content, $content;
        my @story_paths = build_publish_paths($story);
        my $output_text = load_story_page($story_paths[0]);
        push @output_text, $output_text;

        # clean up
        $creator->delete_item(item => $tmpl);
    }
    $creator->delete_item(item => $story);

    # make sure the templates were both non-empty
    ok($tmpl_content[0] && $tmpl_content[1], "Flattened & unflattened tmpls non-empty");

    # make sure the templates were different from each other
    ok($tmpl_content[0] ne $tmpl_content[1], "Flattened & unflattened tmpls different");

    # make sure both templates managed to publish all three paragraphs
    for my $flattened (0 .. 1) {
        for (0 .. 2) {
            my $paragraph = $paragraphs[$_]->data;
            ok($output_text[$flattened] =~ /$paragraph/, "Flattened/unflattened output correct");
        }
    }
}

sub test_fill_flattened_page_loop {

    # set up publisher
    my $story = shift;
    $publisher->{story} = $story;

    # fill story's 'page_loop' (as opposed to publish test above, which fills 'element_loop')
    my $tags =
      '<TMPL_LOOP PAGE_LOOP><TMPL_LOOP PARAGRAPH_LOOP><TMPL_VAR PARAGRAPH></TMPL_LOOP></TMPL_LOOP>';
    my $tmpl = HTML::Template->new(scalarref => \$tags, die_on_bad_params => 0);
    $story->element->fill_template(
        element   => $story->element,
        tmpl      => $tmpl,
        publisher => $publisher
    );

    # check results
    ok(ref $tmpl->param('page_loop'),                           "Flattened page_loop built");
    ok(ref $tmpl->param('page_loop')->[0],                      "Flattened page 1 built");
    ok(ref $tmpl->param('page_loop')->[0]->{'paragraph_loop'},  "Flattened paragraph loop built");
    ok($tmpl->param('page_loop')->[0]->{'paragraph_loop'}->[0], "Flattened paragraph 1 built");
    ok($tmpl->param('page_loop')->[0]->{'paragraph_loop'}->[1], "Flattened paragraph 2 built");
    ok($tmpl->param('page_loop')->[0]->{'paragraph_loop'}->[2], "Flattened paragraph 3 built");
}

sub test_fill_flattened_missing_template {

    # set up publisher
    my $story = shift;
    $publisher->{story} = $story;

    # fill page-loop twice...
    my @params;
    my $tags =
      '<TMPL_LOOP PAGE_LOOP><TMPL_VAR PAGE><TMPL_LOOP PARAGRAPH_LOOP></TMPL_LOOP></TMPL_LOOP>';
    my $tmpl = HTML::Template->new(scalarref => \$tags, die_on_bad_params => 0);

    # ...once when page.tmpl is missing
    $publisher->undeploy_template(template => $template_deployed{page});
    $story->element->fill_template(
        element   => $story->element,
        tmpl      => $tmpl,
        publisher => $publisher
    );
    ok(
        ref $tmpl->param('PAGE_LOOP')->[0]->{'paragraph_loop'},
        "Paragraph loop built due to missing page.tmpl"
    );

    # ...once when it's not
    $publisher->deploy_template(template => $template_deployed{page});
    $story->element->fill_template(
        element   => $story->element,
        tmpl      => $tmpl,
        publisher => $publisher
    );
    ok(
        !$tmpl->param('PAGE_LOOP')->[0]->{'paragraph_loop'},
        "Paragraph loop missing - page.tmpl takes precedence"
    );
}

sub test_preview_story {
    my $story = shift;

    my $prevurl = $publisher->preview_story(story => $story);

    my $preview_path_url = (build_preview_paths($story))[0];

    if (-e $preview_path_url) {
        my $story_txt = load_story_page($preview_path_url);
        $story_txt =~ s/\n//g;
        if ($story_txt =~ /\w/) {
            is($story_txt, $article_output{1}, 'Krang::Publisher->preview_story() -- compare');
        } else {
            fail('Krang::Publisher->preview_story() -- content missing from ' . $preview_path_url);
        }
    } else {
        fail('Krang::Publisher->preview_story() -- exists');
    }
}

sub test_maintain_versions {

    # get story & make sure it's been published (along with media)
    my $story = shift;
    $publisher->publish_story(story => $story);
    ($story) = pkg('Story')->find(story_id => $story->story_id);

    # get latest media object (linked to by story)
    my $media = $story->element->child('page')->child_data('photo');
    ok($story->published_version > 0);
    ok($media->published_version > 0);
    ok($media->published);

    # increment version numbers (so latest versions are newer than published versions)
    $story->checkout;
    $story->save;
    $story->checkin;
    $media->checkout;
    $media->save;
    $media->checkin;

    # make sure the above worked
    my $published_version_of_story = $story->published_version;
    my $published_version_of_media = $media->published_version;
    my $latest_version_of_story    = $story->version;
    my $latest_version_of_media    = $media->version;
    ok(
        $latest_version_of_story > $published_version_of_story,
        "latest version of story > published version of story"
    );
    ok(
        $latest_version_of_media > $published_version_of_media,
        "latest version of media > published version of media"
    );

    # get assets without using maintain-versions (which should yield latest versions)
    $publisher->_clear_asset_lists();
    my $publish_list = $publisher->asset_list(
        story             => $story,
        mode              => 'publish',
        maintain_versions => 0,
        version_check     => 0
    );
    is(scalar @$publish_list, 3);
    is($publish_list->[0]->story_id, $story->story_id);
    is($publish_list->[0]->version, $latest_version_of_story, "--maintain-versions=0 on story");
    ok($publish_list->[1]->story_id != $story->story_id);
    is($publish_list->[2]->media_id, $media->media_id);
    is($publish_list->[2]->version, $latest_version_of_media, "--maintain-versions=0 on media");

    # get assets using maintain-versions (which should yield published versions)
    $publisher->_clear_asset_lists();
    $publish_list = $publisher->asset_list(
        story             => $story,
        mode              => 'publish',
        maintain_versions => 1,
        version_check     => 0
    );
    is(scalar @$publish_list, 3);
    is($publish_list->[0]->story_id, $story->story_id);
    is($publish_list->[0]->version, $published_version_of_story, "--maintain-versions=1 on story");
    ok($publish_list->[1]->story_id != $story->story_id);
    is($publish_list->[2]->media_id, $media->media_id);
    is($publish_list->[2]->version, $published_version_of_media, "--maintain-versions=1 on media");
}

sub test_story_unpublish {

    # create a story in all three categories
    my $story = $creator->create_story(category => [$category, $child_cat, $child_subcat]);
    $publisher->preview_story(story => $story);
    my $preview_path_url = (build_preview_paths($story))[0];
    ok(-e $preview_path_url);

    # remove the primary category and re-preview
    $story->categories($child_cat, $child_subcat);
    $publisher->preview_story(story => $story);
    my $new_preview_path_url = (build_preview_paths($story))[0];
    ok(-e $new_preview_path_url);
    ok((not -e $preview_path_url), 'expired preview path cleaned up');

    # now publish
    $publisher->publish_story(story => $story);
    my @paths = build_publish_paths($story);
    ok(-e $_) for @paths;

    # remove another category and republish
    $story->categories($child_subcat);
    $publisher->publish_story(story => $story);
    my @new_paths = build_publish_paths($story);
    ok(-e $_) for @new_paths;
    my %new = map { ($_, 1) } @new_paths;
    foreach my $old (@paths) {
        next if $new{$old};
        ok((not -e $old), "expired publish path '$old' cleaned up");
    }

    # un-publish it
    $publisher->unpublish_story(story => $story);
    ok(!$story->published_version, 'published_version reset');
    ok(!$story->publish_date,      'published_date reset');

    # make sure it's really gone
    ok((not -e $_), 'delete removed dead paths') for @new_paths;

    # delete it
    $creator->delete_item(item => $story);
}

# test for a bug when a story was moved and then republished - it
# could delete files it no longer owns
sub test_story_disappearing {

    # create a story in one
    my $story1 = $creator->create_story(
        category => [$child_cat],
        slug     => "disappear"
    );

    # now publish it, files exist
    $publisher->publish_story(story => $story1);
    my @paths = build_publish_paths($story1);
    ok(-e $_) for @paths;
    my $url = $story1->url;

    # now move the story to a new cat
    $story1->categories([$child_subcat]);
    $story1->checkout();
    $story1->save();
    ok($story1->url ne $url);

    # make a new story in the original place
    my $story2 = $creator->create_story(
        category => [$child_cat],
        slug     => "disappear"
    );

    # now publish it, files exist
    $publisher->publish_story(story => $story2);
    my @paths2 = build_publish_paths($story2);
    ok(-e $_) for @paths2;
    is($paths[$_], $paths2[$_]) for (0 .. $#paths);
    is($story2->url, $url);

    # publish first story again, make sure it doesn't erase story 2's files
    $publisher->publish_story(story => $story1);
    my @new_paths = build_publish_paths($story1);
    ok(-e $_) for @new_paths;
    ok(-e $_, "original files haven't disappeared ($_)") for @paths2;

    $creator->delete_item(item => $story1);
    $creator->delete_item(item => $story2);
}

sub test_media_unpublish {

    # create media
    my $media = $creator->create_media(category => $category);

    # preview
    $publisher->preview_media(media => $media);
    my $old_preview_path = $media->preview_path;
    ok(-e $old_preview_path);

    # publish
    $publisher->publish_media(media => $media);
    my $old_publish_path = $media->publish_path;
    ok(-e $old_publish_path);

    # upload a new file, changing the URL
    my $filepath = catfile(KrangRoot, 't', 'media', 'krang.jpg');
    my $fh = new FileHandle $filepath;
    $media->upload_file(filename => 'krang.jpg', filehandle => $fh);
    $media->save;
    like($media->url, qr/krang.jpg$/);
    isnt($media->publish_path, $old_publish_path);
    isnt($media->preview_path, $old_preview_path);

    # preview
    $publisher->preview_media(media => $media);
    my $preview_path = $media->preview_path;
    ok(-e $preview_path);
    ok((not -e $old_preview_path), 'changed URL removed obsolete file');

    # publish
    $publisher->publish_media(media => $media);
    my $publish_path = $media->publish_path;
    ok(-e $publish_path);
    ok((not -e $old_publish_path), 'changed URL removed obsolete file');

    $publisher->unpublish_media(media => $media);
    ok(!$media->published_version, 'published_version reset');
    ok(!$media->publish_date,      'published_date reset');
    ok(!$media->published,         'published flag reset');

    # make sure it's really gone
    ok((not -e $preview_path), 'delete removed published media');
    ok((not -e $publish_path), 'delete removed published media');

    # delete it
    $creator->delete_item(item => $media);
}

#
# test_find_templates()
# Run through all the elements in the story, attempting to find the
# appropriate templates.  If the templates are not found, make sure
# there's a good reason for there not being one (e.g. element has no
# children).
#
sub test_find_templates {

    my $e = shift;
    my $s;

    unless ($e) {
        $s = $creator->create_story();
        $e = $s->element;
    }

    my $tmpl;

    eval { $tmpl = $e->class->find_template(publisher => $publisher, element => $e); };
    if ($@) {
        if (scalar($e->children())) {
            note($@);
            fail("Krang::ElementClass->find_template(" . $e->name() . ")");
            die;
        } else {
            pass("Krang::ElementClass->find_template()");
        }
    } else {
        pass("Krang::ElementClass->find_template()");
    }

    my @children = $e->children();

    return unless @children;

    # iterate over the children, repeating the process.
    foreach (@children) {
        &test_find_templates($_);
    }

    $creator->delete_item(item => $s) if ($s);

}

#
# deploy_test_templates() -
# Places the template files found in t/publish/*.tmpl out on the filesystem
# using Krang::Publisher->deploy_template().
#
sub deploy_test_templates {

    my ($category) = @_;

    my $template;

    undef $/;

    opendir(TEMPLATEDIR, $template_dir) || die "ERROR: cannot open dir $template_dir: $!\n";

    my @files = readdir(TEMPLATEDIR);
    closedir(TEMPLATEDIR);

    foreach my $file (@files) {
        next unless ($file =~ s/^(.*)\.tmpl$/$template_dir\/$1\.tmpl/);

        my $element_name = $1;

        open(TMPL, "<$file") || die "ERROR: cannot open file $file: $!\n";
        my $content = <TMPL>;
        close TMPL;

        $template = pkg('Template')->new(
            content  => $content,
            filename => "$element_name.tmpl",
            category => $category
        );

        eval { $template->save(); };

        if ($@) {
            note("ERROR: $@");
            fail('Krang::Template->new()');
        } else {
            push @test_templates_delete, $template;
            $test_template_lookup{$element_name} = $template;

            $template_paths{$element_name} = &test_deploy_template($template);

            unless (exists($template_deployed{$element_name})) {
                $template_deployed{$element_name} = $template;
            }
        }

    }

    $/ = "\n";

    return;

}

#
# test Krang::Publisher->additional_content_block()
#
sub test_additional_content_block {

    my $category = $creator->create_category();
    my $story = $creator->create_story(category => [$category]);

    my @expected;

    for (my $count = 0 ; $count < 10 ; $count++) {
        my $filename = "test$count.txt";
        my $bool     = $count % 2;
        my $data     = "text$count " x 40;

        $publisher->additional_content_block(
            content      => $data,
            filename     => $filename,
            use_category => $bool
        );

        push @expected, {content => $data, filename => $filename, use_category => $bool};
    }

    for (my $i = 0 ; $i <= $#expected ; $i++) {
        foreach (qw/content filename use_category/) {
            ok($expected[$i]{$_} eq $publisher->{additional_content}[$i]{$_},
                'Krang::Publisher->additional_content_block');
        }
    }

    # Try writing one executable file
    $publisher->additional_content_block(
        content      => "Exe Title",
        filename     => "foo.pl",
        use_category => 0,
        mode         => 0755,
    );

    $publisher->_set_publish_mode();
    my @files = $publisher->_build_story_single_category(story => $story, category => $category);

    # check to see that the files got written
    for (my $i = 0 ; $i <= $#expected ; $i++) {
        my $path = catfile($story->publish_path(category => $category), "test$i.txt");
        ok(-e $path, 'Krang::Publisher->additional_content_block');

        # Should NOT be executable
        my $found_mode = sprintf("%lo", (stat($path))[2] & 07777);
        ok($found_mode ne "755", "$path is NOT executable (0755)");
    }

    # Test mode of exe file
    my $exe_file_path = catfile($story->publish_path(category => $category), "foo.pl");
    ok((-e $exe_file_path), "File '$exe_file_path' exists");
    my $found_mode = sprintf("%lo", (stat($exe_file_path))[2] & 07777);
    ok($found_mode eq "755", "$exe_file_path is executable (0755)");

    $creator->delete_item(item => $story);
    $creator->delete_item(item => $category);
}

# test Krang::Publisher->publish_context().
sub test_publish_context {

    # First, try to call publish_context() without ever setting a publish_context
    my %first_pc = ();
    eval { %first_pc = $publisher->publish_context(); };
    ok((not($@) and not(each %first_pc)), 'publish_context() works even if never set');

    my %vars;

    for (1 .. 10) {
        $vars{$creator->get_word} = $creator->get_word;
    }

    $publisher->publish_context(%vars);

    my %context = $publisher->publish_context();

    foreach (keys %context) {
        is($context{$_}, $vars{$_}, 'Krang::Publisher->publish_context');
        $context{$_} = 'aaa';
    }

    # see if the new vars set properly.
    $publisher->publish_context(%context);

    my %changes = $publisher->publish_context();

    foreach (keys %changes) {
        is($changes{$_}, 'aaa', 'Krang::Publisher->publish_context');
    }

    # clear context
    $publisher->clear_publish_context();

    my %last_laugh = $publisher->publish_context();

    is((keys %last_laugh), 0, 'Krang::Publisher->publish_context');

}

sub _add_page_data {

    my $page = shift;

    $page->child('header')->data($head1);
    $page->child('wide_page')->data(1);

    # add three paragraphs
    $page->add_child(class => "paragraph", data => $para1);
    $page->add_child(class => "paragraph", data => $para2);
    $page->add_child(class => "paragraph", data => $para3);

}

sub build_contrib_hash {

    my %contrib = (
        prefix => 'Mr.',
        first  => $creator->get_word(),
        middle => $creator->get_word(),
        last   => $creator->get_word(),
        suffix => 'MD',
        email  => $creator->get_word('ascii') . '@' . $creator->get_word('ascii') . '.com',
        phone  => '111-222-3333',
        bio    => join(' ', map { $creator->get_word() } (0 .. 20)),
        url    => 'http://www.' . $creator->get_word('ascii') . '.com'
    );

    return %contrib;

}

# create a storylink in $story to $dest
sub link_story {

    my ($story, $dest) = @_;

    my $page = $story->element->child('page');

    $page->add_child(class => "leadin", data => $dest);

}

# create a medialink in $story to $media.
sub link_media {

    my ($story, $media) = @_;

    my $page = $story->element->child('page');

    $page->add_child(class => "photo", data => $media);

}

sub build_publish_paths {

    my $story = shift;
    my $filename = shift || 'index.html';

    my @cats = $story->categories;
    my @paths;

    foreach my $cat (@cats) {
        push @paths, catfile($story->publish_path(category => $cat), $filename);
    }

    return @paths;
}

sub build_preview_paths {

    my $story = shift;

    my @cats = $story->categories;
    my @paths;

    foreach my $cat (@cats) {
        push @paths, catfile($story->preview_path(category => $cat), 'index.html');
    }

    return @paths;

}

# load a story from the filesystem, based on supplied filename.
# return text string containing content
sub load_story_page {

    my $filename = shift;
    my $data;

    ok(-e $filename, 'Krang::Publisher->publish/preview_story() -- exists');

    undef $/;

    if (my $PAGE = pkg('IO')->io_file("<$filename")) {
        $data = <$PAGE>;
        close $PAGE;
    } else {
        note("Cannot open $filename: $!");
        fail('Krang::Publisher->publish_story();');
    }

    $/ = "\n";
    return $data;

}

# walk element tree, return child names at each point.
# Debug - not used in actual testing at this point.
sub walk_tree {

    my ($el) = shift;

    my $level = shift || 0;

    my $tabs = "\t" x $level;

    foreach ($el->children()) {
        my $txt = sprintf("WALK: $tabs p='%s' n='%s'", $el->name(), $_->name());
        note($txt);
        &walk_tree($_, ++$level);
    }

    return;
}

sub test_is_modified {
    for my $name (qw(story media)) {
        my $meth = "create_$name";
        my $asset = $creator->$meth;
        ok($asset->is_modified(), ucfirst($name) . "->is_modified() - after creation and saving");
        $meth = "publish_$name";
        $publisher->$meth($name => $asset);
        ok(!$asset->is_modified(), ucfirst($name) . "->is_modified() - after publishing");
        sleep 1;
        $asset->checkout;
        $asset->save;
        $asset->checkin;
        ok($asset->is_modified(), ucfirst($name) . "->is_modified() - after publishing and saving again");
    }
}

sub test_publish_if_modified_in_category {

    $ENV{KRANG_TEST} = 0;
    $publisher->_set_publish_mode();

    # create nested categories /color and /color/red
    my $cat_color = $creator->create_category(
        dir    => 'color',
        parent => $category->category_id,
    );
    my $cat_red = $creator->create_category(
        dir    => 'red',
        parent => $cat_color->category_id,
    );

    #
    # Story
    #

    # add stories to these categories
    my $story_color = $creator->create_story(category => [$cat_color], title => 'story_color');
    my $story_red   = $creator->create_story(category => [$cat_red], title => 'story_red');

    # create an index story (has no CategoryLink yet)
    my $index = $creator->create_story(title => 'story_index');
    $index->checkout;

    # newly created without CategoryLink: index should NOT publish
    not_published_index($story_color, $index, "no catlink");

    # add CategoryLink: index should still NOT publish
    my $catlink_story_in = $index->element->add_child(class => 'story_in_cat');
    $index->save;
    not_published_index($story_color, $index, "added catlink: don't publish indexstory");

    # set CategoryLink to category cat_color: index should now publish
    $index->element->child('story_in_cat')->data($cat_color);
    $index->save;
    published_index($story_color, $index, "set category 'color' in catlink: publish index story");

    # publish story in category 'red': index should NOT publish
    not_published_index($story_red, $index, "published story in 'red' cat: don't publish index");

    # add CategoryLink : index should NOT publish
    my $catlink_story_below = $index->element->add_child(class => 'story_below_cat');
    $index->save;

    # publish story in category 'red': index should NOT publish
    not_published_index($story_red, $index, "published story in 'red' cat with unset index 'below': don't publish index");

    # set CategoryLink to category cat_color: index should now publish
    $index->element->child('story_below_cat')->data($cat_color);
    $index->save;
    published_index($story_color, $index, "set category 'color' in catlink 'below': publish index story");

    # remove 'in_cat' CatLink
    $index->element->remove_children($catlink_story_in);
    $index->save;

    # color story should trigger the index to be published
    published_index($story_color, $index, "set category 'color' below catlink: publish index story");

    # publish 'color' story: index should NOT be published
    $publisher->publish_story(story => $story_color);
    not_published_index($story_color, $index, "publish color story: don't publish index story");

    # publish 'red' story: index should NOT be published
    published_index($story_red, $index, "set category 'red' below catlink: publish index story");
    $publisher->publish_story(story => $story_red);
    not_published_index($story_red, $index, "published red story: don't publish index story");

    # save them again: index should be published
    sleep 2;
    $story_color->checkout; $story_color->save;
    $story_red->checkout; $story_red->save;
    published_index($story_color, $index, "saved color story: publish index story");
    published_index($story_red, $index, "saved red story: publish index story");

    # remove catlink and test again
    $index->element->remove_children($catlink_story_below);
    $index->save;
    not_published_index($story_color, $index, "deleted catlink: don't publish index story");
    not_published_index($story_red, $index, "deleted catlink: don't publish index story");

    #
    # Media
    #
    # add media to these categories
    my $media_color = $creator->create_media(category => $cat_color, title => 'media_color');
    my $media_red   = $creator->create_media(category => $cat_red, title => 'media_red');

##    # create an index story (has no CategoryLink yet)
##    my $index = $creator->create_story(title => 'story_index');
##    $index->checkout;

    # newly created without CategoryLink: index should NOT publish
    not_published_index($media_color, $index, "no catlink");

    # add CategoryLink: index should still NOT publish
    my $catlink_media_in = $index->element->add_child(class => 'media_in_cat');
    $index->save;
    not_published_index($media_color, $index, "added catlink: don't publish index media");

    # set CategoryLink to category cat_color: index should now publish
    $index->element->child('media_in_cat')->data($cat_color);
    $index->save;
    published_index($media_color, $index, "set category 'color' in catlink: publish index media");

    # publish media in category 'red': index should NOT publish
    not_published_index($media_red, $index, "published media in 'red' cat: don't publish index");

    # add CategoryLink : index should NOT publish
    my $catlink_media_below = $index->element->add_child(class => 'media_below_cat');
    $index->save;

    # publish media in category 'red': index should NOT publish
    not_published_index($media_red, $index, "published media in 'red' cat with unset index 'below': don't publish index");

    # set CategoryLink to category cat_color: index should now publish
    $index->element->child('media_below_cat')->data($cat_color);
    $index->save;
    published_index($media_color, $index, "set category 'color' in catlink 'below': publish index media");

    # remove 'in_cat' CatLink
    $index->element->remove_children($catlink_media_in);
    $index->save;

    # color media should trigger the index to be published
    published_index($media_color, $index, "set category 'color' below catlink: publish index media");

    # publish 'color' media: index should NOT be published
    $publisher->publish_media(media => $media_color);
    not_published_index($media_color, $index, "publish color media: don't publish index media");

    # publish 'red' media: index should NOT be published
    published_index($media_red, $index, "set category 'red' below catlink: publish index media");
    $publisher->publish_media(media => $media_red);
    not_published_index($media_red, $index, "published red media: don't publish index media");

    # save them again: index should be published
    sleep 2;
    $media_color->checkout; $media_color->save;
    $media_red->checkout; $media_red->save;
    published_index($media_color, $index, "saved color media: publish index media");
    published_index($media_red, $index, "saved red media: publish index media");

    # stories again: index should still not be published
    not_published_index($story_color, $index, "publish story: don't publish index story");
    not_published_index($story_red, $index, "publish story: don't publish index story");

    # remove catlink and test again
    $index->element->remove_children($catlink_media_below);
    $index->save;
    not_published_index($media_color, $index, "deleted catlink: don't publish index media");
    not_published_index($media_red, $index, "deleted catlink: don't publish index media");
}


sub published_index {
    my ($object, $index, $msg) = @_;
    my $key = $object->isa('Krang::Story') ? 'story' : 'media';
    my $to_publish;
    if ($key eq 'story') {
        $to_publish = $publisher->asset_list($key => $object);
    } else {
        $to_publish = [$object];
        $publisher->_maybe_add_index_story($to_publish);
    }
    is($to_publish->[-1]->title, $index->title, "publish catlink $key: $msg");
    $publisher->_clear_asset_lists;
}

sub not_published_index {
    my ($object, $index, $msg) = @_;
    my $key = $object->isa('Krang::Story') ? 'story' : 'media';
    my $to_publish;
    if ($key eq 'story') {
        $to_publish = $publisher->asset_list($key => $object);
    } else {
        $to_publish = [$object];
        $publisher->_maybe_add_index_story($to_publish);
    }
    isnt($to_publish->[-1]->title, $index->title, "publish catlink $key: $msg");
    $publisher->_clear_asset_lists;
}
