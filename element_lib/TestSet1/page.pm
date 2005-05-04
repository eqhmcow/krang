package TestSet1::page;
use strict;
use warnings;

=head1 NAME

TestSet1::page

=head1 DESCRIPTION

Example page element class for Krang.  Pages have one header and one
or more paragraphs.  Pages also have a wide_page checkbox.  Pages may
have a bg_color and a set of ad_links defined.  Additionally, photo
and leadin elements are available.

=cut


use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'page',
                min  => 1,
                pageable => 1,
                children => 
                [ 
                 Krang::ElementClass::Text->new(name         => "header",
                                                required     => 1,
                                                min          => 1,
                                                max          => 1,
                                                allow_delete => 0,
                                                reorderable  => 0),
                 Krang::ElementClass::CheckBox->new(name => "wide_page",
                                                    min  => 1,
                                                    max  => 0,
                                                    allow_delete => 0,
                                                    reorderable => 0),
                 Krang::ElementClass::PopupMenu->new(name => "bg_color",
                                                  display_name => "Background Color",
                                                  values => ['', qw(white blue
                                                                red grey)],
                                                 ),
                 Krang::ElementClass::ListBox->new(name => "ad_links",
                                                   display_name => "Ad Links",
                                                   values => [ "Sprinks",
                                                               "Classifieds",
                                                               "Subscriptions"],
                                                   multiple => 1,
                                                   default => ["Sprinks",
                                                               "Classifieds",
                                                              ]),
                 Krang::ElementClass::XinhaEditor->new(name => "paragraph",
                                                     required => 1,
                                                     bulk_edit => 0,
                                                    ),
                 Krang::ElementClass::XinhaEditor->new(name => "std_paragraph",
                                                       toolbar_config => 'standard',
                                                     required => 1,
                                                     bulk_edit => 0,
                                                    ),
                 Krang::ElementClass::XinhaEditor->new(name => "fancy_paragraph",
                                                       toolbar_config => 'all',
                                                     required => 1,
                                                     bulk_edit => 0,
                                                    ),
                 Krang::ElementClass::Textarea->new(name => "pull_quote",
                                                    required => 1,
                                                    rows     => 2,
                                                   ),
                 Krang::ElementClass::MediaLink->new(name => "photo"),
                 Krang::ElementClass::StoryLink->new(name => "leadin"),
                ],
                @_);
   return $pkg->SUPER::new(%args);
}

sub input_form {
    my ($self, %arg) = @_;
    my ($query, $element, $order) = @arg{qw(query element order)};
    my ($header, $data);
    if ($header = $element->child('header') and
        $data   = $header->data) {
        return "&quot;$data&quot;";
    }
    return '';
}

sub view_data {
    my ($self, %arg) = @_;
    my ($element) = @arg{qw(element)};
    my ($header, $data);
    if ($header = $element->child('header') and
        $data   = $header->data) {
        return "&quot;$data&quot;";
    }
    return '';
}


1;
