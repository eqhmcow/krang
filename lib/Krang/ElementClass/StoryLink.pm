package Krang::ElementClass::StoryLink;
use strict;
use warnings;

use base 'Krang::ElementClass';

use Krang::MethodMaker
  get_set => [ qw( allow_upload show_thumbnail ) ];

sub new {
    my $pkg = shift;
    my %args = ( allow_upload   => 1,
                 show_thumbnail => 1,
                 @_
               );
    
    return $pkg->SUPER::new(%args);
}

sub input_form {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my $param = $element->xpath;

    return scalar $query->button(-name    => "find_story_$param",
                                 -value   => "Find Story",
                                 -onClick => "find_story('$param')",
                                );
}


=head1 NAME

Krang::ElementClass::Textarea - textarea element class

=head1 SYNOPSIS

   $class = Krang::ElementClass::StoryLink->new(name => "leadin")
                                                
=head1 DESCRIPTION

Provides an element to link to story.

=head1 INTERFACE

All the normal L<Krang::ElementClass> attributes are available.

=over

=back

=cut

1;
