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
is(@{$page->children}, 1);

# add five paragraphs
ok($page->add_child(class => "paragraph", data => "bla1 "x40));
ok($page->add_child(class => "paragraph", data => "bla2 "x40));
ok($page->add_child(class => "paragraph", data => "bla3 "x40));
ok($page->add_child(class => "paragraph", data => "bla4 "x40));
ok($page->add_child(class => "paragraph", data => "bla5 "x40));
is(@{$page->children}, 6);

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
is($count, 9);

# remember the current state of the page and make some changes
$page->remember();
$page->children([]);
$page->add_child(class => "paragraph", data => "a new para");
is(@{$page->children}, 1);

# get back to where we once belonged
$page->rollback();
is(@{$page->children}, 6);

# can't forget or rollback with no memory
eval { $page->rollback(); };
like($@, qr/\QCall to rollback() without prior call to remember()!\E/);
eval { $page->forget(); };
like($@, qr/\QCall to forget() without prior call to remember()!\E/);

# save to DB
$element->save();
my $element_id = $element->element_id;

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
    if ($x) {
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
