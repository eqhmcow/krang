use Test::More qw(no_plan);
use strict;
use warnings;
use File::Spec;
use Krang::Conf qw(KrangRoot instance);
use Krang::Site;
use Krang::Category;
use Krang::Story;
use Krang::Element;
use Krang::Template;
use Krang::Script;

use Data::Dumper;

# list of templates to delete at the end of this all.
my @delete_templates = ();

# file path of element template
my %element_paths = ();

# create a site and category for dummy story
my $site = Krang::Site->new(preview_url  => 'publishtest.preview.com',
                            url          => 'publishtest.com',
                            publish_path => '/tmp/krangpubtest_publish',
                            preview_path => '/tmp/krangpubtest_preview');
$site->save();

END { $site->delete(); }


my ($category) = Krang::Category->find(site_id => $site->site_id());

# create child & subchild categories
my $child_cat = new Krang::Category (dir => 'testdir_a', parent_id => $category->category_id());
$child_cat->save();

my $child_subcat = new Krang::Category (dir => 'testdir_b', parent_id => $child_cat->category_id());
$child_subcat->save();

END { 
    $child_subcat->delete();
    $child_cat->delete();
}

# Directory structures for template paths.
my @rootdirs = (KrangRoot, 'data', 'templates', Krang::Conf->instance());

my @dirs_a = (File::Spec->catfile(@rootdirs, $site->url(), 'testdir_a', 'testdir_b'), File::Spec->catfile(@rootdirs, $site->url(), 'testdir_a'), File::Spec->catfile(@rootdirs, $site->url()));


# instantiate publisher
use_ok('Krang::Publisher');

my $publisher = new Krang::Publisher ();

isa_ok($publisher, 'Krang::Publisher');

############################################################
# testing template seach path.

$publisher->category($child_subcat);  # dev - set currently running category
my @paths = $publisher->template_search_path();

ok(@paths == @dirs_a);
for (my $i = 0; $i <= $#paths; $i++) { ok($paths[$i] eq $dirs_a[$i]); }


############################################################
# testing Krang::ElementClass->find_template().

# create a new story -- get root element.
my $story   = &create_story([$category, $child_cat, $child_subcat]);
my $element = $story->element();

# iterate over the elements of the article, creating templates.
&create_templates($element);

END { foreach (@delete_templates) { $_->delete() }; } # delete created templates

&find_templates($element);

# Attempt to publish the story.
my $html = $publisher->_assemble_pages(story => $story, category => $category, mode => 'publish');

#diag($html);








############################################################
#
# SUBROUTINES
#

#
# find_templates
# iterate over the elements, testing Krang::ElementClass->find_template()
# Basically, 
# 

sub find_templates {

    my ($element) = @_;

    eval {
        my $tmpl = $element->class->find_template(publisher => $publisher, element => $element);
    };
    if ($@) {
        diag($@);
        fail();
    } else {
        pass();
    }

    my @children = $element->children();

    return unless @children;

    # iterate over the children, repeating the process.
    foreach (@children) {
        &find_templates($_);
    }

}




#
# takes an element, creates its template.  
# if the element has children, repeats the process.
#
sub create_templates {

    my ($el) = @_;
    my $cat;

    (rand(100) % 2) ? ($cat = $category) : ($cat = $child_cat);

#    diag("CATEGORY = " . $cat->category_id . "\tURL = " . $cat->url());

    my $template = Krang::Template->new(category_id => $cat->category_id(),
                                        content => "TEMPLATE NAME=" . $el->name() . "\n",
                                        element_class_name => $el->name());

    $template->save();
    push @delete_templates, $template;

    # deploy template to the publish path.
    $element_paths{$el->name()} = $publisher->deploy_template(template => $template);
#    diag($template->template_id(), $element_paths{$el->name()});

    my @children = $el->children();

    return unless @children;

    # iterate over the children, repeating the process.
    foreach (@children) {
        &create_templates($_, $cat);
    }

}



#
# create a fleshed-out story for testing purposes.
#
sub create_story {

    my @categories = @_;

    my $story = Krang::Story->new(categories => \@categories,
                                  title      => "Test Title",
                                  slug       => "test-publish-test",
                                  class      => "article");

    # add some content
    $story->element->child('deck')->data('DECK DECK DECK');

    my $page = $story->element->child('page');

    # add five paragraphs
    $page->add_child(class => "paragraph", data => "para1 "x40);
    $page->add_child(class => "paragraph", data => "para2 "x40);
    $page->add_child(class => "paragraph", data => "para3 "x40);
    $page->add_child(class => "paragraph", data => "para4 "x40);
    $page->add_child(class => "paragraph", data => "para5 "x40);


    return $story;

}
