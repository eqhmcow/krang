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
is(@children, 9, "Number of children");
is($children[0]->name, "issue_date", 
   'Child class: '.pkg('ElementClass::Date') . " - name => issue_date");
is($children[1]->name, "deck",
   'Child class: '.pkg('ElementClass::Textarea') . " - name => deck");
is($children[2]->name, "cbg_values", 
   'Child class: '.pkg('ElementClass::CheckBoxGroup') . " - name => cgb_values");
is($children[3]->name, "cbg_listgroup", 
   'Child class: '.pkg('ElementClass::CheckBoxGroup') . " - name => cbg_listgroup");
is($children[4]->name, "cbg_listgroup_2", 
   'Child class: '.pkg('ElementClass::CheckBoxGroup') . " - name => cbg_listgroup_2");
is($children[5]->name, "auto_segments", 
   'Child class: '.pkg('ElementClass::ListGroup') . " - name => auto_segments");
is($children[6]->name, "fancy_keyword", 
   'Child class: '.'TestSet1::fancy_keyword'  . " - name => fancy_keyword");
is($children[7]->name, "radio_cost", 
   'Child class: '.pkg('ElementClass::Textarea') . " - name => radio_cost");
is($children[8]->name, "page", 
   'Child class: '.pkg('ElementClass::RadioGroup') . " - name => page");

# try push on another deck, should fail
eval { $element->add_child(class => "deck") };
like($@, qr/Unable to add another/, "fail to add another child with attrib 'max => 1'");

# poke around with page
my $page = ($element->children())[8];
isa_ok($page, "Krang::Element");
is($page->name, $page->class->name, '$page->name eq $page->class->name');
is($page->display_name, "Page", '$page->display_name');
is($page->children, 2, 'Number of $page children');

# test parent()
is($page->parent(), $element, '$page->parent');
is($page->parent()->parent(), undef, '$page->parent->parent');
my $clone = $element->clone();
is($clone->child('page')->parent, $clone, '$element->clone');

# add five paragraphs
ok($page->add_child(class => "paragraph", data => "bla1 "x40), '$page->add_child(...)');
ok($page->add_child(class => "paragraph", data => "bla2 "x40), '$page->add_child(...)');
ok($page->add_child(class => "paragraph", data => "bla3 "x40), '$page->add_child(...)');
ok($page->add_child(class => "paragraph", data => "bla4 "x40), '$page->add_child(...)');
ok($page->add_child(class => "paragraph", data => "bla5 "x40), '$page->add_child(...)');
is($page->children, 7, 'New number of $page children');

# test root()
is($page->root(), $element, '$page->root');
is($page->child('paragraph')->root(), $element, '$page->child(...)->root');

# test xpath
is($element->xpath(), '/', '$element->xpath()');
is($page->xpath(), '/page[0]', '$page->xpath()');
is($page->child('paragraph')->xpath(), '/page[0]/paragraph[0]', '$page->child(...)->xpath');

# test match
is($element->match('/page[0]/paragraph[0]'), 1, '$element->match(...)');
isa_ok(($element->match('/page[0]/paragraph[0]'))[0], 'Krang::Element');
is(($element->match('/page[0]/paragraph[3]'))[0]->data(), "bla4 "x40, 
   '$element->match(...)->data');
is(($element->match('/page[0]/paragraph[-1]'))[0]->data(), "bla5 "x40, 
   '$element->match(...)->data');
is(($element->match('/page[0]/paragraph[-1]'))[0]->xpath(), 
   '/page[0]/paragraph[4]', '$element->match(...)->xpath()');
is($element->match('//paragraph'), 5, '$element->match(...), number of matched children');
is($page->match('//paragraph'), 5, '$page->match(...), number of matched children');
is($page->match('paragraph'), 5, '$page->match(...), number of matched children');
is($element->match('paragraph'), 0, '$element->match(...), number of matched children');
is($element->match('/page[1]/paragraph[6]'),0, '$element->match(...), number of matched children');
is($element->match('/page[0]/paragraph[@data="' . ("bla4 " x 40) . '"]'), 1, 
   '$element->match(...), number of matched children');
is(($element->match('/page[0]/paragraph[@data="' . ("bla4 " x 40) . '"]'))[0],
   ($element->match('/page[0]/paragraph[3]'))[0],
   '$element->match(...), number of matched children');
# fill in deck
($element->children())[1]->data("deck deck deck");
is(($element->children())[1]->data, "deck deck deck", '($element->children)[1]->data');
is($element->child('deck')->data, "deck deck deck", '$element->child(...)->data');


# walk through elements with foreach_element
my $count = 0;
eval <<END;
  use Krang::ClassLoader Element => qw(foreach_element);
  foreach_element { \$count++ } \$element;
END
die $@ if $@;
is($count, 17, 'foreach_element{}');

# save to DB
$element->save();
my $element_id = $element->element_id;

# make some changes and save again
$element->child('page')
  ->child('paragraph')
  ->data('some new paragraph data...');
$element->remove_children(6);  # Remove fancy_keyword
$element->add_child(class => 'page');
$element->save();

# destroy in memory copies
undef $page;
undef $element;

# reload
my $loaded = pkg('Element')->load(element_id => $element_id, object => $story);
isa_ok($loaded, 'Krang::Element', "after pkg('Element')->load(...), \$loaded ");
is($loaded->name, "article", '$loaded->name');
@children = $loaded->children();
is(@children, 9, 'Number of $loaded->children()');
is($children[0]->name, "issue_date",
 'Child class: '.pkg('ElementClass::Date')." - name => issue_date");
is($children[1]->name, "deck",
   'Child class: '.pkg('ElementClass::Textarea') . " - name => deck");
is($children[2]->name, "cbg_values",
   'Child class: '.pkg('ElementClass::CheckBoxGroup') . " - name => cgb_values");
is($children[3]->name, "cbg_listgroup",
   'Child class: '.pkg('ElementClass::CheckBoxGroup') . " - name => cbg_listgroup");
is($children[4]->name, "cbg_listgroup_2",
   'Child class: '.pkg('ElementClass::CheckBoxGroup') . " - name => cbg_listgroup_2");
is($children[5]->name, "auto_segments",
   'Child class: '.pkg('ElementClass::ListGroup') . " - name => auto_segments");
is($children[6]->name, "radio_cost",
   'Child class: '.pkg('ElementClass::Textarea') . " - name => radio_cost");
is($children[7]->name, "page", 
   'Child class: '.pkg('ElementClass::RadioGroup') . " - name => page");
is($children[8]->name, "page",
   'Child class: '.pkg('ElementClass::RadioGroup') . " - name => page");
my $lpage = $children[8];
my $x = 0;
foreach my $para ($lpage->children) {
    if ($x > 1) {
        ok($para->data, '$loaded\'s child \'page\' has data()');
        like($para->data, qr/bla$x/, '$loaded\'s child \'page\' has correct data()');
    }
    $x++;
}

# try some reordering
$loaded->reorder_children(reverse($loaded->children));
@children = $loaded->children();
is(@children, 9, 'Number of $loaded\'s children after $loaded->reorder_children(REVERSE)');
is($children[8]->name, "issue_date",
   'Child class: '.pkg('ElementClass::Date') . " - name => issue_date");
is($children[7]->name, "deck",
   'Child class: '.pkg('ElementClass::Textarea') . " - name => deck");
is($children[6]->name, "cbg_values",
   'Child class: '.pkg('ElementClass::CheckBoxGroup') . " - name => cgb_values");
is($children[5]->name, "cbg_listgroup",
   'Child class: '.pkg('ElementClass::CheckBoxGroup') . " - name => cbg_listgroup");
is($children[4]->name, "cbg_listgroup_2",
   'Child class: '.pkg('ElementClass::CheckBoxGroup') . " - name => cbg_listgroup_2");
is($children[3]->name, "auto_segments",
   'Child class: '.pkg('ElementClass::ListGroup') . " - name => auto_segments");
is($children[2]->name, "radio_cost",
   'Child class: '.pkg('ElementClass::Textarea') . " - name => radio_cost");
is($children[1]->name, "page",
   'Child class: '.pkg('ElementClass::RadioGroup') . " - name => page");
is($children[0]->name, "page",
   'Child class: '.pkg('ElementClass::RadioGroup') . " - name => page");

$loaded->reorder_children(reverse(0 .. $loaded->children_count - 1));
@children = $loaded->children();
is(@children, 9, 'Number of $loaded\'s children after $loaded->reorder_children(REVERSE)');
is($children[0]->name, "issue_date",
   'Child class: '.pkg('ElementClass::Date') . " - name => issue_date");
is($children[1]->name, "deck",
   'Child class: '.pkg('ElementClass::Textarea') . " - name => deck");
is($children[2]->name, "cbg_values",
   'Child class: '.pkg('ElementClass::CheckBoxGroup') . " - name => cgb_values");
is($children[3]->name, "cbg_listgroup",
   'Child class: '.pkg('ElementClass::CheckBoxGroup') . " - name => cbg_listgroup");
is($children[4]->name, "cbg_listgroup_2",
   'Child class: '.pkg('ElementClass::CheckBoxGroup') . " - name => cbg_listgroup_2");
is($children[5]->name, "auto_segments",
   'Child class: '.pkg('ElementClass::ListGroup') . " - name => auto_segments");
is($children[6]->name, "radio_cost",
   'Child class: '.pkg('ElementClass::Textarea') . " - name => radio_cost");
is($children[7]->name, "page",
   'Child class: '.pkg('ElementClass::RadioGroup') . " - name => page");
is($children[8]->name, "page",
   'Child class: '.pkg('ElementClass::RadioGroup') . " - name => page");

# prepare to check that delete_hook is working
my $delete_count = $TestSet1::article::DELETE_COUNT;

# delete from the db
ok($loaded->delete(), 'Delete $loaded from DB');

# check that delete_hook is working
is($TestSet1::article::DELETE_COUNT, $delete_count + 1, 'delete_hook()');

# make sure it's gone
eval { $loaded = pkg('Element')->load(element_id => $element_id, object => $story) };
like($@, qr/No element found/, '$loaded is gone after delete()');

};
