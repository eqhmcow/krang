package PBMM::top;
use base 'Krang::ElementClass::TopLevel';

=head1 NAME

PBMM::top - base class for PBMM top-level story types

=head1 DESCRIPTION

This class serves as a base class for all PBMM top-level story types.
It provides the basic META fields used by PBMM stories which are
placed at the top of the element list.  These are:

  Meta Title (optional)
  Meta Keywords
  Meta Description
  Meta Categories
  Meta Related Properties
  Meta Topics
  Meta Geography
  Meta Sources

=cut

# text field meta elements
our @SMALL_META = qw(title);

# textarea meta elements
our @LARGE_META = qw(keywords description categories related_properties 
                     topics geography sources);

sub new {
    my $pkg = shift;
    my %args = @_;
    unshift @{$args{children}}, 
      (map { 
          Krang::ElementClass::Text->new( name => "meta_$_",
                                          reorderable  => 0,
                                          allow_delete => 0,
                                          min  => 1,
                                          max  => 1 ) 
        } @SMALL_META),
      (map { 
          Krang::ElementClass::Textarea->new( name => "meta_$_",
                                              min  => 1,
                                              max  => 1,
                                              reorderable  => 0,
                                              allow_delete => 0,
                                              rows => 2,
                                              cols => 40 )
        } @LARGE_META);

    return $pkg->SUPER::new(%args);
}

1;
