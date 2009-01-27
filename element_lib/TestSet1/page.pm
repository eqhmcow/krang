package TestSet1::page;
use strict;
use warnings;
use Krang::ClassFactory qw(pkg);

=head1 NAME

TestSet1::page

=head1 DESCRIPTION

Example page element class for Krang.  Pages have one header and one
or more paragraphs.  Pages also have a wide_page checkbox.  Pages may
have a bg_color and a set of ad_links defined.  Additionally, photo
and leadin elements are available.

=cut

use Krang::ClassLoader base => 'ElementClass';

sub new {
    my $pkg  = shift;
    my %args = (
        name     => 'page',
        min      => 1,
        pageable => 1,
        children => [
            pkg('ElementClass::Text')->new(
                name         => "header",
                required     => 1,
                min          => 1,
                max          => 1,
                allow_delete => 0,
                reorderable  => 0
            ),
            pkg('ElementClass::CheckBox')->new(
                name         => "wide_page",
                min          => 1,
                max          => 0,
                allow_delete => 0,
                reorderable  => 0
            ),
            pkg('ElementClass::PopupMenu')->new(
                name         => "bg_color",
                display_name => "Background Color",
                values       => [
                    '', qw(white blue
                      red grey)
                ],
            ),
            pkg('ElementClass::ListBox')->new(
                name         => "ad_links",
                display_name => "Ad Links",
                values       => ["Sprinks", "Classifieds", "Subscriptions"],
                multiple     => 1,
                default => ["Sprinks", "Classifieds",]
            ),
            pkg('ElementClass::XinhaEditor')->new(
                name      => "paragraph",
                required  => 1,
                bulk_edit => 0,
            ),
            pkg('ElementClass::XinhaEditor')->new(
                name           => "std_paragraph",
                toolbar_config => 'standard',
                required       => 1,
                bulk_edit      => 0,
            ),
            pkg('ElementClass::XinhaEditor')->new(
                name           => "fancy_paragraph",
                toolbar_config => 'all',
                required       => 1,
                bulk_edit      => 0,
            ),
            pkg('ElementClass::Textarea')->new(
                name     => "pull_quote",
                required => 1,
                rows     => 2,
            ),
            pkg('ElementClass::MediaLink')->new(name => "photo"),
            pkg('ElementClass::StoryLink')->new(name => "leadin"),

            pkg('ElementClass::StoryLink')->new(
                name => "leadin_covers",
                find => {class => 'cover'}
            ),
            pkg('ElementClass::MediaLink')->new(
                name => "photo_image_only",
                find => {media_type_id => 1}
            ),
            pkg('ElementClass::Text')->new(
                name          => 'xinha_bulk_edit_header_1',
                bulk_edit     => 'xinha',
                bulk_edit_tag => 'h1'
            ),
            pkg('ElementClass::Text')->new(
                name          => 'xinha_bulk_edit_header_2',
                bulk_edit     => 'xinha',
                bulk_edit_tag => 'h2'
            ),
            pkg('ElementClass::Textarea')->new(
                name          => 'xinha_paragraph',
                cols          => 30,
                rows          => 4,
                bulk_edit     => 'xinha',
                bulk_edit_tag => 'p'
            ),
            pkg('ElementClass::Textarea')->new(
                name             => 'correction',
                cols             => 30,
                rows             => 4,
                bulk_edit        => 'xinha',
                bulk_edit_tag    => 'pre',
                before_bulk_edit => sub {
                    my (%arg) = @_;
                    my $element = $arg{element};
                    return "Correction: " . $element->data;
                },
                before_bulk_save => sub {
                    my (%arg) = @_;
                    my $data = $arg{data};
                    $data =~ s/^Correction: //;
                    return $data;
                },
            ),
            pkg('ElementClass::PoorText')->new(
                name               => 'poortext_header',
                type               => 'text',
                commands           => 'basic_with_special_chars',
                command_button_bar => 1,
                special_char_bar   => 0,
            ),
            pkg('ElementClass::PoorText')->new(
                name               => 'poortext_paragraph',
                type               => 'textarea',
                commands           => 'all',
                required           => 1,
                command_button_bar => 1,
                special_char_bar   => 0,
            ),

            pkg('ElementClass::TextInputList')->new(
                name          => 'unordered_list',
                allow_delete  => 1,
                reorderable   => 1,
                required      => 0,
                bulk_edit     => 'xinha',
                bulk_edit_tag => 'ul',
            ),

            pkg('ElementClass::TextInputList')->new(
                name          => 'ordered_list',
                allow_delete  => 1,
                reorderable   => 1,
                required      => 0,
                bulk_edit     => 'xinha',
                bulk_edit_tag => 'ol',
            ),
            pkg('ElementClass::TextInputList')->new(name => 'keyword_list',),

            pkg('ElementClass::PoorTextList')->new(
                name         => 'poortext_list',
                type         => 'text',
                width        => 300,
                height       => 100
            ),

            pkg('ElementClass::PoorTextList')->new(
                name         => 'poortext_list_area',
                type         => 'textarea',
                width        => 300,
                height       => 50,
            ),

        ],
        @_
    );

    return $pkg->SUPER::new(%args);
}

sub input_form {
    my ($self, %arg) = @_;
    my ($query, $element, $order) = @arg{qw(query element order)};
    my ($header, $data);
    if (    $header = $element->child('header')
        and $data = $header->data)
    {
        return "&quot;$data&quot;";
    }
    return '';
}

sub view_data {
    my ($self, %arg) = @_;
    my ($element) = @arg{qw(element)};
    my ($header, $data);
    if (    $header = $element->child('header')
        and $data = $header->data)
    {
        return "&quot;$data&quot;";
    }
    return '';
}

sub bulk_save_change {
    my ($self, %arg) = @_;

    if (   $arg{class}->name eq 'xinha_bulk_edit_paragraph'
        && $arg{data} =~ /^\s*<strong>(.{1,50})<\/strong>/)
    {
        return ('xinha_bulk_edit_header_2', $1);
    }

    return ($arg{class}, $arg{data});
}

1;
