#!/usr/bin/perl -w
use Benchmark qw(timethis);
use Krang;
use Krang::Element;

$|++;

# set magnitude for tests here
$n = 100;

# time creating new element trees, without saving them
print "\n", "=" x 79, "\nCreating ", ($n * 4), " element trees in memory.\n";
timethis($n * 4, \&create_tree);
print "=" x 79, "\n\n";

# time creating new element trees, saving to the database
print "\n", "=" x 79, "\nCreating $n element trees in the db.\n";
my @ids;
timethis($n, 
         sub {
             my $e = create_tree();
             $e->save(); 
             push(@ids, $e->element_id);
         });
print "=" x 79, "\n\n";

# time loading element trees by id
print "\n", "=" x 79, "\nLoading $n element trees by ID.\n";
my $i = 0;
timethis($n, 
         sub {
             my $e = Krang::Element->find(element_id => $ids[$i++]);
         });
print "=" x 79, "\n\n";


# create a "normal" element tree
sub create_tree {
    my $element = Krang::Element->new(class => "article");
    
    # add a couple more pages
    $element->add_child(class => "page");
    $element->add_child(class => "page");

    # foreach page, add 10 paragraphs
    foreach my $page (grep { $_->name eq 'page' } $element->children()) {
        $page->add_child(class => "paragraph", data => "para $_ " x 100)
          for (1 .. 10);
    }

    return $element;
}

