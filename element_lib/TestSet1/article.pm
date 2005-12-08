package TestSet1::article;
use strict;
use warnings;

=head1 NAME

TestSet1::article

=head1 DESCRIPTION

Example article element class for Krang.  This article element
contains a single 'deck', a single 'fancy_keyword', zero or more
blurbs and one or more pages.

=cut

use base 'Krang::ElementClass::TopLevel';

sub new {
   my $pkg = shift;
   my %args = ( name => 'article',
                children => 
                 [
                  Krang::ElementClass::Date->new(name => 'issue_date',
                                                 min  => 1,
                                                 max  => 1,
                                                 reorderable => 0,
                                                 allow_delete => 0),
                  Krang::ElementClass::Textarea->new(name => 'deck', 
                                                     min => 1, 
                                                     max => 1,
                                                     reorderable => 0,
                                                     allow_delete => 0,
                                                     indexed => 1,
                                                    ),
                  Krang::ElementClass::ListGroup->new(  name => 'auto_segments',
                                                        list_group => 'Segments',
                                                        multiple => 1,
                                                        min => 1,
                                                        max => 1,
                                                        allow_delete => 1,
                                                        reorderable => 1 ),
                  TestSet1::fancy_keyword->new(min          => 1,
                                               max          => 1,
                                               reorderable  => 0,
                                               allow_delete => 0,
                                               indexed => 1,
                                              ),
                  Krang::ElementClass::Textarea->new(name => 'blurb',
                                                     bulk_edit => 1),

                  Krang::ElementClass::RadioGroup->new(name => 'mood',
                                                       values => [qw/happy sad confused manic depressive cynical/],
                                                       labels => { happy      => "Happy",
                                                                   sad        => "Sad",
                                                                   confused   => "Confused",
                                                                   manic      => "Manic",
                                                                   depressive => "Depressive",
                                                                   cynical    => "Cynical" },
                                                       columns => 2 ),

                  'page',
                ],
                @_);
   return $pkg->SUPER::new(%args);
}

# test delete_hook
our $DELETE_COUNT = 0;
sub delete_hook { $DELETE_COUNT++ };

1;
