package TestSet1::category;
use strict;
use warnings;

=head1 NAME

TestSet1::category

=head1 DESCRIPTION

Example category element class for Krang.  It has no subelements at the
moment.

=cut


use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'category',
                children => [
                             Krang::ElementClass::Text->new(name => 'display_name',
                                                            allow_delete => 0,
                                                            min => 1,
                                                            max => 1,
                                                            reorderable => 0,
                                                            required => 1),
                             Krang::ElementClass::Text->new(name => 'header',
                                                            allow_delete => 1,
                                                            min => 0,
                                                            max => 1,
                                                            reorderable => 1,
                                                            required => 1),
                             Krang::ElementClass::Textarea->new(name => 'paragraph',
                                                            allow_delete => 1,
                                                            min => 0,
                                                            max => 0,
                                                            bulk_edit => 1,
                                                            reorderable => 1,
                                                            required => 0),
                             Krang::ElementClass::MediaLink->new(name => "photo"),
                             Krang::ElementClass::StoryLink->new(name => "leadin"),
                             Krang::ElementClass::CategoryLink->new(name => "leftnav_link"),

                            ],
                @_);
   return $pkg->SUPER::new(%args);
}

1;

   
