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

my @rootdirs = (KrangRoot, 'data', 'templates', Krang::Conf->instance());

my @dirs_a = (File::Spec->catfile(@rootdirs, 'publishtest.com', 'testdir_a', 'testdir_b'), File::Spec->catfile(@rootdirs, 'publishtest.com', 'testdir_a'), File::Spec->catfile(@rootdirs, 'publishtest.com'));




# list of templates to delete at the end of this all.
my @delete_templates = ();

my %element_paths = ();

# create a site and category for dummy story
my $site = Krang::Site->new(preview_url  => 'publishtest.preview.com',
                            url          => 'publishtest.com',
                            publish_path => '/tmp/krangpubtest_publish',
                            preview_path => '/tmp/krangpubtest_preview');
$site->save();

END { $site->delete(); }

my ($category) = Krang::Category->find(site_id => $site->site_id());

# create child categories
my $child_cat = new Krang::Category (dir => '/testdir_a', parent_id => $category->category_id());
$child_cat->save();

my $child_subcat = new Krang::Category (dir => 'testdir_b', parent_id => $child_cat->category_id());
$child_subcat->save();

#die Dumper($category->url(), $child_cat->url(), $child_subcat->url());

END { 
    $child_subcat->delete();
    $child_cat->delete();
}


# instantiate publisher
use_ok('Krang::Publisher');

my $publisher = new Krang::Publisher (category => $child_subcat);

isa_ok($publisher, 'Krang::Publisher');

# testing template search path.
my @paths = $publisher->template_search_path();

ok(@paths == @dirs_a);

for (my $i = 0; $i <= $#paths; $i++) { ok($paths[$i] eq $dirs_a[$i]); }

# create a new story -- get root element.
my $story = Krang::Story->new(categories => [$category],
                              title      => "Test",
                              slug       => "test",
                              class      => "article");

my $element = $story->element();


# iterate over the elements of the article, creating templates.
&create_templates($element);

END { foreach (@delete_templates) { $_->delete() }; } # delete created templates

&find_templates($element);


# iterate over the elements, testing find_template()
sub find_templates {

    my ($element) = @_;

    my $tmpl = $element->class->find_template(publisher => $publisher, element => $element);

#    diag($tmpl->output());

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

    (rand(100) % 2) ? $cat = $category : $cat = $child_cat;

    my $template = Krang::Template->new(category_id => $cat->category_id(),
                                        content => "TEMPLATE NAME=" . $el->name() . "\n",
                                        element_class_name => $el->name());

    $template->save();
    push @delete_templates, $template;


    $element_paths{$el->name()} = $publisher->deploy_template(template => $template);
#    diag($template->template_id(), $element_paths{$el->name()});

    my @children = $el->children();

    return unless @children;

    # iterate over the children, repeating the process.
    foreach (@children) {
        &create_templates($_, $cat);
    }

}
