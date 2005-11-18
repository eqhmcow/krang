use Krang::ClassFactory qw(pkg);
use Test::More qw(no_plan);
use strict;
use warnings;
use Krang::ClassLoader 'Script';
use Krang::ClassLoader 'Site';
use Krang::ClassLoader 'Category';
use Krang::ClassLoader 'Story';
use Krang::ClassLoader Conf => qw(InstanceElementSet);
BEGIN { use_ok(pkg('Element')) }

# use the TestSet1 instance, if there is one
foreach my $instance (pkg('Conf')->instances) {
    pkg('Conf')->instance($instance);
    if (InstanceElementSet eq 'TestSet1') {
        last;
    }
}

# create a site and category for dummy story
my $site = pkg('Site')->new(preview_url  => 'storytest.preview.com',
                            url          => 'storytest.com',
                            publish_path => '/tmp/storytest_publish',
                            preview_path => '/tmp/storytest_preview');
isa_ok($site, 'Krang::Site');
$site->save();
END { $site->delete() }
my ($category) = pkg('Category')->find(site_id => $site->site_id());

# create a new story
my $story;
eval { $story = pkg('Story')->new(categories => [$category],
                                     title      => "Test",
                                     slug       => "test",
                                     class      => "article"); };

# Was story creation successful?
if ($@) {
    if ($@ =~ qr/Unable to find top-level element named 'article'/) {
        # Story type "article" doesn't exist in this set.  Exit test now.
        SKIP: { skip("Unable to find top-level element named 'article' in element lib"); }
        exit(0);
    } else {
        # We've encountered some other unexpected error.  Re-throw.
        die($@);
    }
}


my $element = pkg('Element')->new(class => "article", object => $story);
isa_ok($element, 'Krang::Element');

# article has two default children, page and deck
SKIP: {
    skip('Element tests only work for TestSet1', 100)
      unless (InstanceElementSet eq 'TestSet1');

my @children = $element->children();
is(@children , 5);
is($children[0]->name, "issue_date");
is($children[1]->name, "deck");
is($children[2]->name, "auto_segments");
is($children[3]->name, "fancy_keyword");
is($children[4]->name, "page");

# try push on another deck, should fail
eval { $element->add_child(class => "deck") };
like($@, qr/Unable to add another/);

# poke around with page
my $page = ($element->children())[4];
isa_ok($page, "Krang::Element");
is($page->name, $page->class->name);
is($page->display_name, "Page");
is($page->children, 2);

# test parent()
is($page->parent(), $element);
is($page->parent()->parent(), undef);
my $clone = $element->clone();
is($clone->child('page')->parent, $clone);

# add five paragraphs
ok($page->add_child(class => "paragraph", data => "bla1 "x40));
ok($page->add_child(class => "paragraph", data => "bla2 "x40));
ok($page->add_child(class => "paragraph", data => "bla3 "x40));
ok($page->add_child(class => "paragraph", data => "bla4 "x40));
ok($page->add_child(class => "paragraph", data => "bla5 "x40));
is($page->children, 7);

# test root()
is($page->root(), $element);
is($page->child('paragraph')->root(), $element);

# test xpath
is($element->xpath(), '/');
is($page->xpath(), '/page[0]');
is($page->child('paragraph')->xpath(), '/page[0]/paragraph[0]');

# test match
is($element->match('/page[0]/paragraph[0]'), 1);
isa_ok(($element->match('/page[0]/paragraph[0]'))[0], 'Krang::Element');
is(($element->match('/page[0]/paragraph[3]'))[0]->data(), "bla4 "x40);
is(($element->match('/page[0]/paragraph[-1]'))[0]->data(), "bla5 "x40);
is(($element->match('/page[0]/paragraph[-1]'))[0]->xpath(), 
   '/page[0]/paragraph[4]');
is($element->match('//paragraph'), 5);
is($page->match('//paragraph'), 5);
is($page->match('paragraph'), 5);
is($element->match('paragraph'), 0);
is($element->match('/page[1]/paragraph[6]'),0);
is($element->match('/page[0]/paragraph[@data="' . ("bla4 " x 40) . '"]'), 1);
is(($element->match('/page[0]/paragraph[@data="' . ("bla4 " x 40) . '"]'))[0],
   ($element->match('/page[0]/paragraph[3]'))[0]);
# fill in deck
($element->children())[1]->data("deck deck deck");
is(($element->children())[1]->data, "deck deck deck");
is($element->child('deck')->data, "deck deck deck");


# walk through elements with foreach_element
my $count = 0;
eval <<END;
  use Krang::ClassLoader Element => qw(foreach_element);
  foreach_element { \$count++ } \$element;
END
die $@ if $@;
is($count, 13);

# save to DB
$element->save();
my $element_id = $element->element_id;

# make some changes and save again
$element->child('page')
  ->child('paragraph')
  ->data('some new paragraph data...');
$element->remove_children(3);
$element->add_child(class => 'page');
$element->save();

# destroy in memory copies
undef $page;
undef $element;

# reload
my $loaded = pkg('Element')->load(element_id => $element_id, object => $story);
isa_ok($loaded, 'Krang::Element');
is($loaded->name, "article");
@children = $loaded->children();
is(@children, 5);
is($children[0]->name, "issue_date");
is($children[1]->name, "deck");
is($children[2]->name, "auto_segments");
is($children[3]->name, "page");
is($children[4]->name, "page");
my $lpage = $children[4];
my $x = 0;
foreach my $para ($lpage->children) {
    if ($x > 1) {
        ok($para->data);
        like($para->data, qr/bla$x/);
    }
    $x++;
}

# try some reordering
$loaded->reorder_children(reverse($loaded->children));
@children = $loaded->children();
is(@children, 5);
is($children[4]->name, "issue_date");
is($children[3]->name, "deck");
is($children[2]->name, "auto_segments");
is($children[1]->name, "page");
is($children[0]->name, "page");

$loaded->reorder_children(reverse(0 .. $loaded->children_count - 1));
@children = $loaded->children();
is(@children, 5);
is($children[0]->name, "issue_date");
is($children[1]->name, "deck");
is($children[2]->name, "auto_segments");
is($children[3]->name, "page");
is($children[4]->name, "page");

# prepare to check that delete_hook is working
my $delete_count = $TestSet1::article::DELETE_COUNT;

# delete from the db
ok($loaded->delete());

# check that delete_hook is working
is($TestSet1::article::DELETE_COUNT, $delete_count + 1);

# make sure it's gone
eval { $loaded = pkg('Element')->load(element_id => $element_id, object => $story) };
like($@, qr/No element found/);

};
