use Test::More qw(no_plan);
use strict;
use warnings;
use Krang;
BEGIN { use_ok('Krang::Element') }

my $element = Krang::Element->new(class => "article");
isa_ok($element, 'Krang::Element');

# article has two default children, page and deck
is(@{$element->children()}, 2);
is($element->children()->[1]->name, "page");
is($element->children()->[0]->name, "deck");

# try push on another deck, should fail
eval { $element->add_child(class => "deck") };
like($@, qr/Unable to add another/);

# poke around with page
my $page = $element->children()->[1];
isa_ok($page, "Krang::Element");
is($page->name, $page->class->name);
is($page->display_name, "Page");
is(@{$page->children}, 2);

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
is(@{$page->children}, 7);

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

# fill in deck
$element->children()->[0]->data("deck deck deck");
is($element->children()->[0]->data, "deck deck deck");
is($element->child('deck')->data, "deck deck deck");


# walk through elements with foreach_element
my $count = 0;
eval <<END;
  use Krang::Element qw(foreach_element);
  foreach_element { print \$_->name, "\n"; \$count++ } \$element;
END
die $@ if $@;
is($count, 10);

# remember the current state of the page and make some changes
$page->remember();
$page->children([]);
$page->add_child(class => "paragraph", data => "a new para");
is(@{$page->children}, 1);

# get back to where we once belonged
$page->rollback();
is(@{$page->children}, 7);

# can't forget or rollback with no memory
eval { $page->rollback(); };
like($@, qr/\QCall to rollback() without prior call to remember()!\E/);
eval { $page->forget(); };
like($@, qr/\QCall to forget() without prior call to remember()!\E/);

# save to DB
$element->save();
my $element_id = $element->element_id;

# make some changes and save again
$element->child('page')
  ->child('paragraph')
  ->data('some new paragraph data...');
my @kids = $element->children();
$element->children(@kids[0 .. $#kids - 1]);
$element->add_child(class => 'page');
$element->save();

# destroy in memory copies
undef $page;
undef $element;

# reload
my $loaded = Krang::Element->find(element_id => $element_id);
isa_ok($loaded, 'Krang::Element');
is($loaded->name, "article");
is(@{$loaded->children()}, 2);
is($loaded->children()->[1]->name, "page");
is($loaded->children()->[0]->name, "deck");
my $lpage = $loaded->children()->[1];
my $x = 0;
foreach my $para ($lpage->children) {
    if ($x > 1) {
        ok($para->data);
        like($para->data, qr/bla$x/);
    }
    $x++;
}

# delete from the db
ok($loaded->delete());

# make sure it's gone
eval { $loaded = Krang::Element->find(element_id => $element_id) };
like($@, qr/No element found/);

# leak test
#for(0 .. 1000) {
