#!/usr/bin/perl -w
use Krang;
use Krang::Element;
use Krang::Benchmark qw(run_benchmark);

$|++;

# set magnitude for tests here
$n = 100;

# time creating new element trees, without saving them
run_benchmark(module => 'Krang::Element',
              name   => 'create tree in memory',
              count  => $n * 4, 
              code   => \&create_tree);

# time creating new element trees, saving to the database
my @ids;
run_benchmark(module => 'Krang::Element',
              name   => 'create tree in db',
              count  => $n, 
              code   => sub {
                  my $e = create_tree();
                  $e->save(); 
                  push(@ids, $e->element_id);
              });

# time loading element trees by id
my $i = 0;
run_benchmark(module => 'Krang::Element',
              name   => 'load by ID',
              count  => $n, 
              code   => sub {
                  my $e = Krang::Element->find(element_id => $ids[$i++]);
              });

# time deleting element trees by id
$i = 0;
run_benchmark(module => 'Krang::Element',
              name   => 'delete',
              count  => $n, 
              code   => sub {
                  Krang::Element->delete($ids[$i++]);
              });

# create a "normal" element tree
sub create_tree {
    my $element = Krang::Element->new(class => "article");
    
    # make a five page story
    $element->add_child(class => "page") for (1 .. 4);

    # foreach page, add 10 paragraphs
    foreach my $page (grep { $_->name eq 'page' } $element->children()) {
        $page->add_child(class => "paragraph", data => "para $_ " x 100)
          for (1 .. 10);
    }

    return $element;
}

