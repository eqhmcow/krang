package Default::double_cover_column;
use strict;
use warnings;

=head1 NAME

Default::double_cover_column

=head1 DESCRIPTION

Default double cover column (uses cover_column) element class for Krang. 

=cut

use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => 'ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'double_cover_column',
                children => 
                [ 
                  Default::cover_column->new(   name => "left_column",
                                                allow_delete => '0',
                                                    display_name => 'Left Column',
                                                    min => 1,
                                                    max => 1 ),
                Default::cover_column->new(   name => "right_column",
                                                allow_delete => '0',
                                                    display_name => 'Right Column',
                                                    min => 1,
                                                    max => 1 ),
                ],
                @_);
   return $pkg->SUPER::new(%args);
}

1;
