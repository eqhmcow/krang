use strict;
use warnings;

use File::Spec::Functions;
use File::Path;
use Krang::Contrib;
use Krang::Pref;
use Krang::Conf qw(KrangRoot instance InstanceElementSet);
use Krang::Site;
use Krang::Category;
use Krang::Story;
use Krang::Element;
use Krang::Template;
use Krang::Script;

use Krang::Test::Content;

use Data::Dumper;



# skip all tests unless a TestSet1-using instance is available
BEGIN {
    my $found;
    foreach my $instance (Krang::Conf->instances) {
        Krang::Conf->instance($instance);
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

# instantiate publisher
use_ok('Krang::Publisher');

############################################################
# PRESETS

my $template_dir = 't/publish/';


# Site params
my $preview_url = 'publishtest.preview.com';
my $publish_url = 'publishtest.com';
my $preview_path = '/tmp/krangpubtest_preview';
my $publish_path = '/tmp/krangpubtest_publish';

# Content params
my $para1       = "para1 "x40;
my $para2       = "para2 "x40;
my $para3       = "para3 "x40;
my $head1       = "header "x10;
my $head_output = "<h1>$head1</h1>\n";
my $deck1       = 'DECK DECK DECK';
my $page_output = "<h1>$head1</h1>THIS IS A VERY WIDE PAGE<p>$para1</p><p>$para2</p><p>$para3</p>";
my $category1   = 'CATEGORY1 'x5;
my $category2   = 'CATEGORY2 'x5;
my $category3   = 'CATEGORY3 'x5;
my $story_title = 'Test Title';

my $pagination1 = '<P>Page number 1 of 1.</p>';

my $page_break = Krang::Publisher->page_break();

my $category1_head = 'THIS IS HEADS' . $category1 . '---';
my $category1_tail = '---' . $category1 . 'THIS IS TAILS';
my $category1_output = $category1_head . Krang::Publisher->content() . $category1_tail;

my $category2_head = 'THIS IS HEADS' . $category2 . '---';
my $category2_tail = '---' . $category2 . 'THIS IS TAILS';
my $category2_output = $category2_head . Krang::Publisher->content() . $category2_tail;

my $category3_head = 'THIS IS HEADS' . $category3 . '---';
my $category3_tail = '---' . $category3 . 'THIS IS TAILS';
my $category3_output = $category3_head . Krang::Publisher->content() . $category3_tail;

my %article_output = (3 => $category3_head .  "<title>$story_title</title>" . $page_output . $pagination1 . '1' . $category3_tail,
                      2 => $category2_head .  "<title>$story_title</title>" . $page_output . $pagination1 . '1' . $category2_tail,
                      1 => $category1_head .  "<title>$story_title</title>" . $page_output . $pagination1 . '1' . $category1_tail
);

# list of templates to delete at the end of this all.
my @test_templates_delete = ();
my %test_template_lookup = ();

# file path of element template
my %template_paths = ();
my %template_deployed = ();

my %slug_id_list;

my @non_test_deployed_templates = ();

my $publisher = new Krang::Publisher ();

isa_ok($publisher, 'Krang::Publisher');

can_ok($publisher, ('publish_story', 'preview_story', 'unpublish_story',
                    'publish_media', 'preview_media', 'unpublish_media',
                    'asset_list', 'deploy_template', 'undeploy_template',
                    'PAGE_BREAK', 'story', 'category', 'story_filename'));

############################################################
# remove all currently deployed templates from the system
#
@non_test_deployed_templates = Krang::Template->find(deployed => 1);

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

my $creator = Krang::Test::Content->new;


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


my ($category) = Krang::Category->find(site_id => $site->site_id());
$category->element()->data($category1);
$category->save();

# create child & subchild categories
my $child_cat = $creator->create_category(dir    => 'testdir_a', 
                                          parent => $category->category_id,
                                          data   => $category2
                                         );

my $child_subcat = $creator->create_category(dir    => 'testdir_b',
                                             parent => $child_cat->category_id,
                                             data   => $category3
                                            );


############################################################
# testing template seach path.

# Directory structures for template paths.
my @rootdirs = (KrangRoot, 'data', 'templates', Krang::Conf->instance());

my @dirs_a = (
              File::Spec->catfile(@rootdirs, $site->url(), 'testdir_a', 'testdir_b'),
              File::Spec->catfile(@rootdirs, $site->url(), 'testdir_a'),
              File::Spec->catfile(@rootdirs, $site->url()),
              File::Spec->catfile(@rootdirs)
             );



$publisher->{category} = $child_subcat;  # internal hack - set currently running category.
my @paths = $publisher->template_search_path();

ok(@paths == @dirs_a, 'Krang::Publisher->template_search_path()');

for (my $i = 0; $i <= $#paths; $i++) { 
    ok($paths[$i] eq $dirs_a[$i], 'Krang::Publisher->template_search_path()');
}


############################################################
# testing Krang::ElementClass->find_template().

# create new stories -- get root element.
my @media;
my @stories;
for (1..10) {
    push @media, $creator->create_media(category => $category);
}

for (1..10) {
    push @stories, $creator->create_story(category => [$category]);
}




my $story   = $creator->create_story(category  => [$category, $child_cat, $child_subcat],
                                     paragraph => [$para1, $para2, $para3],
                                     header    => $head1,
                                     deck      => $deck1,
                                     title     => $story_title
                                    );
my $story2  = $creator->create_story(category       => [$category],
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

test_media_deploy();

test_storylink();

test_medialink();

test_template_testing($story, $category);

test_full_preview();

test_full_publish();

test_story_unpublish();

test_media_unpublish();

test_additional_content_block();

test_multi_page_story();

test_publish_category_per_page();

############################################################
#
# SUBROUTINES.
#

# test Krang::Contrib section of story
# add contributor to story.
# test Krang::ElementClass->_build_contrib() to see if the
# returning hash is consistent with what's expected.

sub test_contributors {

    my $cat = $creator->create_category();
    my @categories = ($cat);

    my %contributor = build_contrib_hash();
    my %contrib_types = Krang::Pref->get('contrib_type');

    $publisher->_set_publish_mode();

    my $story   = $creator->create_story(category => \@categories);
    my $contrib = $creator->create_contrib(%contributor);
    my $media   = $creator->create_media(category => $categories[0]);

    $contrib->image($media);
    $contrib->save();

    $story->contribs({contrib_id => $contrib->contrib_id, contrib_type_id => 1});

    my $story_element = $story->element();

    $publisher->{story} = $story;

    my $contributors = $story_element->class->_build_contrib_loop(publisher => $publisher,
                                                                  element   => $story_element);

    foreach my $schmoe (@$contributors) {
        foreach (keys %contributor) {
            next if ($_ eq 'image_url');
            ok($schmoe->{$_} eq $contributor{$_}, "Krang::ElementClass->_build_contrib_loop() -- $_");
        }
        ok($schmoe->{contrib_id} eq $contrib->contrib_id(), 'Krang::ElementClass->_build_contrib_loop()');

        # make sure contrib types are ok as well.
        foreach my $gig (@{$schmoe->{contrib_type_loop}}) {
            ok((exists($contrib_types{$gig->{contrib_type_id}}) && 
                $contrib_types{$gig->{contrib_type_id}} eq $gig->{contrib_type_name}),
               'Krang::ElementClass->_build_contrib_loop()');
        }

        # test image
        ok($media->url eq $schmoe->{image_url}, 'Krang::ElementClass->_build_contrib_loop() -- image_url');

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
    $header->save();  # clears testing flag

}


sub test_full_preview {

    $publisher->preview_story(story => $story);

    foreach ($story, $story2, @stories) {
        my @paths = build_preview_paths($_);
        foreach my $path (@paths) {
            diag("Missing $path")
              unless (ok(-e $path, 'Krang::Publisher->preview_story() -- complete story writeout'))
        }
    }

    foreach (@media) {
        my $path = $_->preview_path;
        ok (-e $path, 'Krang::Publisher->preview_story() -- complete media writeout');
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
        ok (-e $path, 'Krang::Publisher->publish_story() -- complete media writeout');
    }

}

# create a new story, create multiple pages for it.
# publish it, find all the pages, compare them to what's expected.
sub test_multi_page_story {

    my $category = $creator->create_category();
    my $story    = $creator->create_story(category => [$category]);

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
    my $story    = $creator->create_story(category => [$category],
                                          class    => 'publish_test');

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
        my $page = load_story_page($_);
        my $string = "page number=$i total=4";
        # find that page number!
        if ($page =~ /$string/) {
            pass('Krang::Publisher - publish_category_per_page');
        } else {
            diag("Cannot find '$string':\n\n$page");
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
    my $pub   = Krang::Publisher->new();

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

    $@ ? pass('Krang::Publisher->test_publish_status()') : fail('Krang::Publisher->test_publish_status()');

    my $bool;
    eval {
        # this should return true - the story should be published.
        $bool = $pub->test_publish_status(object => $story, mode => 'publish');
    };

    if ($@) {
        diag("Unexpected croak: $@");
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
    my ($publish_ok, $check_links) = $pub->_check_asset_status(object => $story,
                                                               mode   => 'publish',
                                                               version_check => 0,
                                                               initial_assets => 0);

    # should pass.
    is($publish_ok, 1, 'Krang::Publisher: version_check off');

    $pub->_init_asset_lists();
    ($publish_ok, $check_links) = $pub->_check_asset_status(object => $story,
                                                            mode   => 'publish',
                                                            version_check => 1,
                                                            initial_assets => 0);
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

    my $publisher = Krang::Publisher->new();

    # touch filesystem locations to simulate publishing story.
    my @paths;
    foreach ($story, $story2, @stories) {
        push @paths, build_publish_paths($_);
        push @paths, build_preview_paths($_);
    }
    foreach(@media) {
        push @paths, $_->preview_path(), $_->publish_path();
    }
    foreach (@paths) {
        $_ =~ /^(.*\/)[^\/]+/;
        my $dir = $1;
        mkpath($dir, 0, 0755);
        `touch $_`;
    }


    # test that asset_list(story) returns story.
    my $publish_list = $publisher->asset_list(story => $story, mode => 'preview', version_check => 1);
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
    %expected = (media => { $media[0]->media_id => $media[0] },
                 story => { $story->story_id => $story,
                            $story2->story_id => $story2});

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
        $_->save();  # this will bump the version number.
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
                diag("Found story that should not be in publish list");
            }
            $lookup{story}{$_->story_id} = 1;
        }
        elsif ($_->isa('Krang::Media')) {
            unless (ok(exists($expected->{media}{$_->media_id}), 'asset_list() - media check')) {
                diag("Found media that should not be in publish list") ;
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
                    diag("Missing expected story in publish list");
                }
            } elsif ($_ eq 'media') {
                unless (ok(exists($lookup{media}{$obj->media_id}), 'asset_list() - media check')) {
                    diag("Missing expected media in publish list");
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
        diag($@);
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
        diag($@);
        fail('Krang::Publisher->deploy_template()');
    } else {
        ok(-e $file && ($file eq $result), 'Krang::Publisher->deploy_template()');
    }

    return $file;
}


# test to make sure Krang::ElementClass::StoryLink->publish works as expected.
sub test_storylink {

    my $dest_story = $creator->create_story();
    my $src_story  = $creator->create_story(linked_stories => [$dest_story]);

    $publisher->_set_publish_mode();

    # test related story - add a storylink from one story to the other.
    $publisher->{story} = $src_story;

    my $page = $src_story->element->child('page');
    my $storylink = $page->child('leadin');

    # w/ deployed template - make sure it works w/ template.
    my $story_href = $storylink->publish(element => $storylink, publisher => $publisher);
    my $resulting_link = '<a href="http://' . $dest_story->url() . '">' . $dest_story->title() . '</a>';
    chomp ($story_href);

    ok($story_href eq $resulting_link, 'Krang::ElementClass::StoryLink->publish() -- publish w/ template');

    $publisher->_set_preview_mode();

    $story_href = $storylink->publish(element => $storylink, publisher => $publisher);
    $resulting_link = '<a href="http://' . $dest_story->preview_url() . '">' . $dest_story->title() . '</a>';
    chomp ($story_href);

    ok($story_href eq $resulting_link, 'Krang::ElementClass::StoryLink->publish() -- preview w/ template');


    $publisher->_set_publish_mode();

    # undeploy template - make sure it works w/ no template.
    $publisher->undeploy_template(template => $template_deployed{leadin});

    $story_href = $storylink->publish(element => $storylink, publisher => $publisher);

    ok($story_href eq 'http://' . $dest_story->url(), 'Krang::ElementClass::StoryLink->publish() -- publish-no template');

    $publisher->_set_preview_mode();

    $story_href = $storylink->publish(element => $storylink, publisher => $publisher);

    ok($story_href eq 'http://' . $dest_story->preview_url(), 'Krang::ElementClass::StoryLink->publish() -- preview-no template');

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

    my $page = $story->element()->child('page');
    my $medialink = $page->child('photo');

    # w/ deployed template - make sure it works w/ template.
    my $media_href = $medialink->publish(element => $medialink, publisher => $publisher);
    my $resulting_link = '<img src="http://' . $media->url() . '">' . $media->caption() . '<BR>' . $media->title();

    $media_href =~ s/\n//g;

    ok($media_href eq $resulting_link, 'Krang::ElementClass::MediaLink->publish() -- publish w/ template');

    $publisher->_set_preview_mode();

    $media_href = $medialink->publish(element => $medialink, publisher => $publisher);
    $resulting_link = '<img src="http://' . $media->preview_url() . '">' . $media->caption() . '<BR>' . $media->title();
    chomp ($media_href);

    ok($media_href eq $resulting_link, 'Krang::ElementClass::MediaLink->publish() -- preview w/ template');

    $publisher->_set_publish_mode();

    # undeploy template - make sure it works w/ no template.
    $publisher->undeploy_template(template => $template_deployed{photo});

    $media_href = $medialink->publish(element => $medialink, publisher => $publisher);

    ok($media_href eq "http://" . $media->url(), 'Krang::ElementClass::MediaLink->publish() -- publish-no template');

    $publisher->_set_preview_mode();

    $media_href = $medialink->publish(element => $medialink, publisher => $publisher);

    ok($media_href eq "http://" . $media->preview_url(), 'Krang::ElementClass::MediaLink->publish() -- preview-no template');
    # re-deploy template.
    $publisher->deploy_template(template => $template_deployed{photo});

    $creator->delete_item(item => $media);
    $creator->delete_item(item => $story);


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
    my %pagination_hack = (is_first_page => 1, is_last_page => 1, current_page_number => 1,
                          total_pages => 1);
    my $page_pub = $page->publish(element => $page, publisher => $publisher,
                                  template_args => \%pagination_hack
                                 );
    $page_pub =~ s/\n//g;
    my $page_string = ($page_output. $pagination1);
    ok($page_pub eq $page_string, 'Krang::ElementClass->publish() -- page');

    # undeploy header tmpl & attempt to publish - should
    # return $header->data().
    $publisher->undeploy_template(template => $template_deployed{header});
    $head_pub = $head->publish(element => $head, publisher => $publisher);
    ok($head_pub eq $head1, 'Krang::ElementClass->publish() -- no tmpl');

    # undeploy page tmpl & attempt to publish - should croak.
    $publisher->undeploy_template(template => $template_deployed{page});
    eval {$page_pub = $page->publish(element => $page, publisher => $publisher);};
    if ($@) {
        pass('Krang::ElementClass->publish() -- missing tmpl');
    } else {
        diag('page.tmpl was undeployed - publish should croak.');
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
    ok($cat_pub eq ($category1_output . $para1), 'Krang::ElementClass->publish() -- category w/ child');
    $category_el->remove_children($child_element_para);

}


sub test_publish_story {

    my $story = shift;

    $publisher->publish_story(story => $story);

    my @story_paths = build_publish_paths($story);

    foreach (my $i = $#story_paths; $i >= 0; $i--) {
        my $story_txt = load_story_page($story_paths[$i]);
        $story_txt =~ s/\n//g;
        if ($story_txt =~ /\w/) {
            ok($article_output{($i+1)} eq $story_txt, 'Krang::Publisher->publish_story() -- compare');
            if ($article_output{($i+1)} ne $story_txt) {
                diag('Story content on filesystem does not match expected results');
                die Dumper($article_output{($i+1)}, $story_txt);
            }
        } else {
            diag('Missing story content in ' . $story_paths[$i]);
            fail('Krang::Publisher->publish_story() -- compare');
        }
    }
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

sub test_story_unpublish {
    # create a story in all three categories
    my $story   = $creator->create_story(category => [$category, $child_cat, $child_subcat]);
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
    my %new = map {($_,1)} @new_paths;
    foreach my $old (@paths) {
        next if $new{$old};
        ok((not -e $old), "expired publish path '$old' cleaned up");
    }

    # delete it
    $creator->delete_item(item => $story);

    # make sure it's really gone
    ok((not -e $_), 'delete removed dead paths') for @new_paths;    
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
    my $filepath = catfile(KrangRoot,'t','media','krang.jpg');
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

    # delete it
    $creator->delete_item(item => $media);

    # make sure it's really gone
    ok((not -e $preview_path), 'delete removed published media');
    ok((not -e $publish_path), 'delete removed published media');
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

    eval {
        $tmpl = $e->class->find_template(publisher => $publisher, element => $e);
    };
    if ($@) {
        if (scalar($e->children())) {
            diag($@);
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

        open (TMPL, "<$file") || die "ERROR: cannot open file $file: $!\n";
        my $content = <TMPL>;
        close TMPL;

        $template = Krang::Template->new(
                                         content => $content,
                                         filename => "$element_name.tmpl",
                                         category => $category
                                        );

        eval { $template->save(); };

        if ($@) {  
            diag("ERROR: $@");
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

    my $content  = $para1;
    my $story = $content;

    for (my $count = 0; $count < 10; $count++) {
        my $filename = "test$count.txt";
        my $bool = $count % 2;
        my $data = "text$count "x40;

        my $open  = qq{<KRANG_ADDITIONAL_CONTENT filename="$filename" use_category="$bool">};
        my $close = "</KRANG_ADDITIONAL_CONTENT>";

        my $txt = $publisher->additional_content_block(content => $data, filename => $filename, use_category => $bool);

        my $expected = $open . $data . $close;

        ok($txt eq $expected, "Krang::Publisher->additional_content_block");

        $story .= $txt;
    }

    my ($additional_ref, $final_story) = $publisher->_parse_additional_content(text => $story);

    ok($final_story eq $content, "Krang::Publisher->_parse_additional_content()");

    for (my $i = 0; $i <= $#$additional_ref; $i++) {
        my $block = $additional_ref->[$i];
        my $bool = $i % 2;
        my $data = "text$i "x40;

        ok($block->{filename} eq "test$i.txt", "Krang::Publisher->_parse_additional_content -- filename");
        ok($block->{use_category} eq $bool, "Krang::Publisher->_parse_additional_content -- use_category");
        ok($block->{content} eq $data, "Krang::Publisher->_parse_additional_content -- content");
    }
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

    my %contrib =   (prefix => 'Mr.',
                     first => $creator->get_word(),
                     middle => $creator->get_word(),
                     last => $creator->get_word(),
                     suffix => 'MD',
                     email => $creator->get_word() . '@' . $creator->get_word() . '.com',
                     phone => '111-222-3333',
                     bio => join(' ', map { $creator->get_word() } (0 .. 20)),
                     url => 'http://www.' . $creator->get_word() . '.com'
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

    my @cats = $story->categories;
    my @paths;

    foreach my $cat (@cats) {
        push @paths, catfile($story->publish_path(category => $cat), 'index.html');
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
    if (open(PAGE, "<$filename")) {
        $data = <PAGE>;
        close PAGE;
    } else {
        diag("Cannot open $filename: $!");
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

    my $tabs = "\t"x$level;

    foreach ($el->children()) {
        my $txt = sprintf("WALK: $tabs p='%s' n='%s'", $el->name(), $_->name());
        diag($txt);
        &walk_tree($_, ++$level);
    }

    return;
}




