use strict;
use warnings;
use Imager;
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
use Data::Dumper;

BEGIN {
    if (InstanceElementSet eq 'TestSet1') {
        eval 'use Test::More qw(no_plan)';
    } else {
        eval 'use Test::More skip_all=>"Publish tests only work for TestSet1"';
    }
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

# create a site and category for dummy story
my $site = Krang::Site->new(preview_url  => $preview_url,
                            url          => $publish_url,
                            preview_path => $preview_path,
                            publish_path => $publish_path
                           );
$site->save();

END {
    $site->delete();
    rmtree $preview_path;
    rmtree $publish_path;
}


my ($category) = Krang::Category->find(site_id => $site->site_id());
$category->element()->data($category1);
$category->save();

# create child & subchild categories
my $child_cat = new Krang::Category (dir => 'testdir_a', parent_id => $category->category_id());
$child_cat->element()->data($category2);
$child_cat->save();

my $child_subcat = new Krang::Category (dir => 'testdir_b', parent_id => $child_cat->category_id());
$child_subcat->element()->data($category3);
$child_subcat->save();

END { 
    $child_subcat->delete();
    $child_cat->delete();
}

# Directory structures for template paths.
my @rootdirs = (KrangRoot, 'data', 'templates', Krang::Conf->instance());

my @dirs_a = (File::Spec->catfile(@rootdirs, $site->url(), 'testdir_a', 'testdir_b'), File::Spec->catfile(@rootdirs, $site->url(), 'testdir_a'), File::Spec->catfile(@rootdirs, $site->url()), File::Spec->catfile(@rootdirs));


############################################################
# testing template seach path.

$publisher->{category} = $child_subcat;  # internal hack - set currently running category.
my @paths = $publisher->template_search_path();

ok(@paths == @dirs_a, 'Krang::Publisher->template_search_path()');
for (my $i = 0; $i <= $#paths; $i++) { ok($paths[$i] eq $dirs_a[$i], 'Krang::Publisher->template_search_path()'); }


############################################################
# testing Krang::ElementClass->find_template().

# create new stories -- get root element.
my @media;
my @stories;
for (1..10) {
    push @media, &create_media();
}

for (1..10) {
    push @stories, &create_story([$category]);
}




my $story   = &create_story([$category, $child_cat, $child_subcat]);
my $story2  = &create_story([$category], [$story], [$media[0]]);

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

    $story2->delete();
    $story->delete();
    foreach (@stories) {
        $_->delete();
    }
    foreach (@media) {
        $_->delete();
    }
}


############################################################
# Testing the publish process.

#test_multi_page_story($category);

# test finding templates.
find_templates($element);

test_contributors($category);

# test story construction
test_story_build($story, $category);

# test publisher->publish_story
test_publish_story($story);

# test publisher->preview_story
test_preview_story($story);

test_media_deploy($media[0]);

test_storylink($story2, $story);

test_medialink($story2, $media[0]);

test_linked_assets();

test_template_testing($story, $category);

test_full_preview();

test_full_publish();


############################################################
#
# SUBROUTINES.
#

# test Krang::Contrib section of story
# add contributor to story.
# test Krang::ElementClass->_build_contrib() to see if the
# returning hash is consistent with what's expected.

sub test_contributors {

    my @categories = @_;

    my %contributor = build_contrib_hash();
    my %contrib_types = Krang::Pref->get('contrib_type');

    my $story   = create_story(\@categories);
    my $contrib = create_contributor(%contributor);

    $story->contribs({contrib_id => $contrib->contrib_id, contrib_type_id => 1});

    my $story_element = $story->element();

    $publisher->{story} = $story;

    my $contributors = $story_element->class->_build_contrib_loop(publisher => $publisher,
                                                                  element   => $story_element);

    foreach my $schmoe (@$contributors) {
        foreach (keys %contributor) {
            ok($schmoe->{$_} eq $contributor{$_}, 'Krang::ElementClass->_build_contrib_loop()');
        }
        ok($schmoe->{contrib_id} eq $contrib->contrib_id(), 'Krang::ElementClass->_build_contrib_loop()');

        # make sure contrib types are ok as well.
        foreach my $gig (@{$schmoe->{contrib_type_loop}}) {
            ok((exists($contrib_types{$gig->{contrib_type_id}}) && 
                $contrib_types{$gig->{contrib_type_id}} eq $gig->{contrib_type_name}),
               'Krang::ElementClass->_build_contrib_loop()');
        }
    }

    $story->delete();
    $contrib->delete();

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
    $publisher->{is_preview} = 1;
    $publisher->{is_publish} = 0;

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
    $publisher->{is_preview} = 0;
    $publisher->{is_publish} = 1;
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
        my $path = build_preview_path($_);
        ok(-e $path, 'Krang::Publisher->preview_story() -- complete story writeout');
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
        my $path = $_->preview_path();
        ok (-e $path, 'Krang::Publisher->publish_story() -- complete media writeout');
    }

}


sub test_multi_page_story {
    my @categories = @_;

    # create a new story, create multiple pages for it.
    # publish it, find all the pages, compare them to what's expected.

    my $story = create_story(\@categories);

    $story->checkout();

    my $page2 = $story->element->add_child(class => 'page');
    _add_page_data($page2);
    my $page3 = $story->element->add_child(class => 'page');
    _add_page_data($page3);
    my $page4 = $story->element->add_child(class => 'page');
    _add_page_data($page4);

    $story->save();
    $story->checkin();

    my $category = $story->category();

    $publisher->{is_publish} = 1;
    $publisher->{is_preview} = 0;

    my $pages = $publisher->_assemble_pages(story => $story, category => $category);

    foreach (@$pages) {
        $_ =~ s/\n//g;
    }

    $story->delete();

    die Dumper($pages);
}

############################################################
# Testing related stories/media list.

sub test_linked_assets {

    # test that get_publish_list(story) returns story.
    my $publish_list = $publisher->get_publish_list(story => $story);
    my %expected = (media => {}, story => {$story->story_id => $story});
    test_publish_list($publish_list, \%expected);

    # link story to story.
    # nothing changes in terms of what's expected.
    link_story($story, $story);
    $publish_list = $publisher->get_publish_list(story => $story);
    test_publish_list($publish_list, \%expected);

    # test that get_publish_list(story2) returns story2 + story + media
    $publish_list = $publisher->get_publish_list(story => $story2);
    %expected = (media => { $media[0]->media_id => $media[0] },
                 story => { $story->story_id => $story,
                            $story2->story_id => $story2});

    test_publish_list($publish_list, \%expected);

    # add links to all of @stories to story2.
    # test that get_publish_list(story2) returns story2 + story + @stories + media
    foreach (@stories) {
        &link_story($story2, $_);
        $expected{story}{$_->story_id} = $_;
    }
    $publish_list = $publisher->get_publish_list(story => $story2);
    test_publish_list($publish_list, \%expected);

    # add links to all of @stories to story -- duplicates story requirements.
    # test that get_publish_list(story2) returns story2 + story + @stories + media
    foreach (@stories) {
        link_story($story, $_);
    }
    $publish_list = $publisher->get_publish_list(story => $story2);
    test_publish_list($publish_list, \%expected);


    # add links to all of @media to story2.
    # test that get_publish_list(story2) returns story2 + story + @stories + media + @media
    foreach (@media) {
        link_media($story2, $_);
        $expected{media}{$_->media_id} = $_;
    }
    $publish_list = $publisher->get_publish_list(story => $story2);
    test_publish_list($publish_list, \%expected);

    # add links to all of @media to story -- duplicates media requirements.
    # test that get_publish_list(story2) returns story2 + story + @stories + media + @media
    foreach (@media) {
        link_media($story, $_);
    }
    $publish_list = $publisher->get_publish_list(story => $story2);
    test_publish_list($publish_list, \%expected);

    # add link to story2 to story -- creates a full cycle.
    # test that get_publish_list(story2) returns story2 + story + @stories + media + @media
    link_story($story, $story2);
    $publish_list = $publisher->get_publish_list(story => $story2);
    test_publish_list($publish_list, \%expected);

    # stress test - create multiple cycles, create as many interlinking dependencies as possible.
    # final publish list shouldn't change.
    foreach (@stories) {
        link_story($_, $story);
        link_story($_, $story2);
    }
    $publish_list = $publisher->get_publish_list(story => $story2);
    test_publish_list($publish_list, \%expected);

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
            ok(exists($expected->{story}{$_->story_id}), 'Krang::Publisher->get_publish_list() - expected story');
            $lookup{story}{$_->story_id} = 1;
        }
        elsif ($_->isa('Krang::Media')) {
            ok(exists($expected->{media}{$_->media_id}), 'Krang::Publisher->get_publish_list() - expected media');
            $lookup{media}{$_->media_id} = 1;
        } else {
            fail("Krang::Publisher->get_publish_list - returned '" . $_->isa() . "'");
        }
    }

    # test to see if everything expected was returned
    foreach (qw(story media)) {
        foreach my $key (keys %{$expected->{$_}}) {
            my $obj = $expected->{$_}{$key};
            if ($_ eq 'story') {
                ok(exists($lookup{story}{$obj->story_id}), 'Krang::Publisher->get_publish_list() - found story'); 
            } elsif ($_ eq 'media') {
                ok(exists($lookup{media}{$obj->media_id}), 'Krang::Publisher->get_publish_list() - found media'); 
            }
        }
    }
}


# Test to make sure Krang::Publisher->publish/preview_media works.
sub test_media_deploy {

    my $media = shift;

    # test media deployment.
    my $pub_expected_path = catfile($publish_path, $media->url());

    my ($pub_media_url) = $publisher->publish_media(media => $media);

    my $pub_media_path = catfile($publish_path, $pub_media_url);

    ok($pub_expected_path eq $pub_media_path, 'Krang::Publisher->publish_media()');

    my $prev_expected_path = catfile($preview_path, $media->preview_url());

    my $prev_media_url = $publisher->preview_media(media => $media);

    my $prev_media_path = catfile($preview_path, $prev_media_url);

    ok($prev_expected_path eq $prev_media_path, 'Krang::Publisher->preview_media()');

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

    my ($src_story, $dest_story) = @_;

    # test related story - add a storylink from one story to the other.
    $publisher->{story} = $src_story;
    $publisher->{is_publish} = 1;
    $publisher->{is_preview} = 0;

    my $page = $src_story->element()->child('page');
    my $storylink = $page->child('leadin');

    # w/ deployed template - make sure it works w/ template.
    my $story_href = $storylink->publish(element => $storylink, publisher => $publisher);
    my $resulting_link = '<a href="http://' . $dest_story->url() . '">' . $dest_story->title() . '</a>';
    chomp ($story_href);

    ok($story_href eq $resulting_link, 'Krang::ElementClass::StoryLink->publish() -- publish w/ template');

    $publisher->{is_publish} = 0;
    $publisher->{is_preview} = 1;

    $story_href = $storylink->publish(element => $storylink, publisher => $publisher);
    $resulting_link = '<a href="http://' . $dest_story->preview_url() . '">' . $dest_story->title() . '</a>';
    chomp ($story_href);

    ok($story_href eq $resulting_link, 'Krang::ElementClass::StoryLink->publish() -- preview w/ template');


    $publisher->{is_publish} = 1;
    $publisher->{is_preview} = 0;

    # undeploy template - make sure it works w/ no template.
    $publisher->undeploy_template(template => $template_deployed{leadin});

    $story_href = $storylink->publish(element => $storylink, publisher => $publisher);

    ok($story_href eq 'http://' . $dest_story->url(), 'Krang::ElementClass::StoryLink->publish() -- publish-no template');

    $publisher->{is_publish} = 0;
    $publisher->{is_preview} = 1;

    $story_href = $storylink->publish(element => $storylink, publisher => $publisher);

    ok($story_href eq 'http://' . $dest_story->preview_url(), 'Krang::ElementClass::StoryLink->publish() -- preview-no template');

    # re-deploy template.
    $publisher->deploy_template(template => $template_deployed{leadin});


}

# test to make sure Krang::ElementClass::StoryLink->publish works as expected.
sub test_medialink {

    my ($story, $media) = @_;

    # test related media - add a medialink to a story.
    $publisher->{story} = $story;
    $publisher->{is_publish} = 1;
    $publisher->{is_preview} = 0;

    my $page = $story->element()->child('page');
    my $medialink = $page->child('photo');

    # w/ deployed template - make sure it works w/ template.
    my $media_href = $medialink->publish(element => $medialink, publisher => $publisher);
    my $resulting_link = '<img src="http://' . $media->url() . '">' . $media->caption() . '<BR>' . $media->title();

    $media_href =~ s/\n//g;

    ok($media_href eq $resulting_link, 'Krang::ElementClass::MediaLink->publish() -- publish w/ template');

    $publisher->{is_publish} = 0;
    $publisher->{is_preview} = 1;

    $media_href = $medialink->publish(element => $medialink, publisher => $publisher);
    $resulting_link = '<img src="http://' . $media->preview_url() . '">' . $media->caption() . '<BR>' . $media->title();
    chomp ($media_href);

    ok($media_href eq $resulting_link, 'Krang::ElementClass::MediaLink->publish() -- preview w/ template');

    $publisher->{is_publish} = 1;
    $publisher->{is_preview} = 0;

    # undeploy template - make sure it works w/ no template.
    $publisher->undeploy_template(template => $template_deployed{photo});

    $media_href = $medialink->publish(element => $medialink, publisher => $publisher);

    ok($media_href eq "http://" . $media->url(), 'Krang::ElementClass::MediaLink->publish() -- publish-no template');

    $publisher->{is_publish} = 0;
    $publisher->{is_preview} = 1;

    $media_href = $medialink->publish(element => $medialink, publisher => $publisher);

    ok($media_href eq "http://" . $media->preview_url(), 'Krang::ElementClass::MediaLink->publish() -- preview-no template');
    # re-deploy template.
    $publisher->deploy_template(template => $template_deployed{photo});

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


    # test _assemble_pages() - should return single-element array-ref.
    # category top/bottom & page content should both exist.
    my $assembled_ref = $publisher->_assemble_pages(story => $story, category => $category);
    ok(@$assembled_ref == 1, 'Krang::Publisher->_assemble_pages() -- page count');

    my $page_one = $assembled_ref->[0];
    $page_one =~ s/\n//g;
    ok($article_output{1} eq $page_one, 'Krang::Publisher->_assemble_pages() -- compare');

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

    my $preview_path_url = build_preview_path($story);

    if (-e $preview_path_url) {
        my $story_txt = load_story_page($preview_path_url);
        $story_txt =~ s/\n//g;
        if ($story_txt =~ /\w/) {
            ok($article_output{1} eq $story_txt, 'Krang::Publisher->preview_story() -- compare');
        } else {
            fail('Krang::Publisher->preview_story() -- content missing from ' . $preview_path_url);
        }
    } else {
        fail('Krang::Publisher->preview_story() -- exists');
    }
}

#
# find_templates()
# Run through all the elements in the story, attempting to find the
# appropriate templates.  If the templates are not found, make sure
# there's a good reason for there not being one (e.g. element has no
# children).
#
sub find_templates {

    my ($element) = @_;

    my $tmpl;

    eval {
        $tmpl = $element->class->find_template(publisher => $publisher, element => $element);
    };
    if ($@) {
        if (scalar($element->children())) {
            diag($@);
            fail("Krang::ElementClass->find_template(" . $element->name() . ")");
            die;
        } else {
            pass("Krang::ElementClass->find_template()");
        }
    } else {
        pass("Krang::ElementClass->find_template()");
    }

    my @children = $element->children();

    return unless @children;

    # iterate over the children, repeating the process.
    foreach (@children) {
        &find_templates($_);
    }

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
# create a fleshed-out story for testing purposes.
#
sub create_story {

    my ($categories, $linked_story, $linked_media) = @_;

    my $slug_id;
    do {
        $slug_id = int(rand(16777216));
    } until (!exists($slug_id_list{$slug_id}));

    $slug_id_list{$slug_id} = 1;

    my $story = Krang::Story->new(categories => $categories,
                                  title      => $story_title,
                                  slug       => 'TEST-SLUG-' . $slug_id,
                                  class      => "article");

    # add some content
    $story->element->child('deck')->data($deck1);

    my $page = $story->element->child('page');

    _add_page_data($page);

    # add storylink if it exists
    if (defined($linked_story)) {
        foreach (@$linked_story) {
            &link_story($story, $_);
        }
    }

    # add medialink if it exists
    if (defined($linked_media)) {
        foreach (@$linked_media) {
            &link_media($story, $_);
        }
    }

    $story->save();

    $story->checkin();

    return ($story);

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


# create a contributor for testing of contrib section.
sub create_contributor {

    my %contrib_hash = @_;

    my %contrib_types = Krang::Pref->get('contrib_type');

    my $contrib = Krang::Contrib->new(%contrib_hash);

    # add contrib types - let's make them all 3.
    $contrib->contrib_type_ids(keys %contrib_types);

    $contrib->save();

    return $contrib;

}

sub build_contrib_hash {

    my %contrib =   (prefix => 'Mr.',
                     first => get_word(),
                     middle => get_word(),
                     last => get_word(),
                     suffix => 'MD',
                     email => get_word() . '@' . get_word() . '.com',
                     phone => '111-222-3333',
                     bio => join(' ', map { get_word() } (0 .. 20)),
                     url => 'http://www.' . get_word() . '.com'
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

#
# create a media object - stolen from floodfill.
#
sub create_media {

    # create a random image
    my ($x, $y);
    my $img = Imager->new(xsize => $x = (int(rand(300) + 50)),
                          ysize => $y = (int(rand(300) + 50)),
                          channels => 3,
                         );

    # fill with a random color
    $img->box(color => Imager::Color->new(map { int(rand(255)) } 1 .. 3),
              filled => 1);

    # draw some boxes and circles
    for (0 .. (int(rand(8)) + 2)) {
        if ((int(rand(2))) == 1) {
            $img->box(color =>
                      Imager::Color->new(map { int(rand(255)) } 1 .. 3),
                      xmin => (int(rand($x - ($x/2))) + 1),
                      ymin => (int(rand($y - ($y/2))) + 1),
                      xmax => (int(rand($x * 2)) + 1),
                      ymax => (int(rand($y * 2)) + 1),
                      filled => 1);
        } else {
            $img->circle(color =>
                         Imager::Color->new(map { int(rand(255)) } 1 .. 3),
                         r => (int(rand(100)) + 1),
                         x => (int(rand($x)) + 1),
                         'y' => (int(rand($y)) + 1));
        }
    }

    # pick a format
    my $format = (qw(jpg png gif))[int(rand(3))];

    $img->write(file => catfile(KrangRoot, "tmp", "tmp.$format"));
    my $fh = IO::File->new(catfile(KrangRoot, "tmp", "tmp.$format"))
      or die "Unable to open tmp/tmp.$format: $!";

    # Pick a type
    my %media_types = Krang::Pref->get('media_type');
    my @media_type_ids = keys(%media_types);
    my $media_type_id = $media_type_ids[int(rand(scalar(@media_type_ids)))];

    # create a media object
    my $media = Krang::Media->new(title      => get_word(),
                                  filename   => get_word() . ".$format",
                                  caption    => get_word(),
                                  filehandle => $fh,
                                  category_id => $category->category_id,
                                  media_type_id => $media_type_id,
                                  );
    eval { $media->save };
    if ($@) {
        if (ref($@) and ref($@) eq 'Krang::Media::DuplicateURL') {
            redo;
        } else {
            die $@;
        }
    }
    unlink(catfile(KrangRoot, "tmp", "tmp.$format"));


    $media->checkin();

    return $media;

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

sub build_preview_path {

    my $story = shift;
    return catfile($story->preview_path, 'index.html');

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




# get a random word
BEGIN {
    my @words;
    open(WORDS, "/usr/dict/words")
      or open(WORDS, "/usr/share/dict/words")
        or die "Can't open /usr/dict/words or /usr/share/dict/words: $!";
    while (<WORDS>) {
        chomp;
        push @words, $_;
    }
    srand (time ^ $$);

    sub get_word {
        return lc $words[int(rand(scalar(@words)))];
    }
}
