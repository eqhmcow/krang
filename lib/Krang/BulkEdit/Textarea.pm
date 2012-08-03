package Krang::BulkEdit::Textarea;
use warnings;
use strict;

use Krang::ClassFactory qw(pkg);

use Krang::ClassLoader Message      => qw(add_message);
use Krang::ClassLoader Localization => qw(localize);

use Krang::ClassLoader MethodMaker => new => 'new';

=head1 NAME

Krang::BulkEdit::Textarea - Class for Textarea-based bulk editing

=head1 SYNOPSIS

Krang::BulkEdit::Textarea - Class for Textarea-based bulk editing

=head1 DESCRIPTION

This class implements methods to handle bulk editing in a textarea
field.  Textareas are used for bulk editing if an elementclass's
'bulk_edit' attribute is set to either '1' (legacy value) or
'textarea' (recommended explicit value).

=head1 INTERFACE

=over

=item pkg('BulkEdit::Textarea')->edit(element_editor => $elementeditor, element => $element, template => $template, child_names => \@bulk_edit_child_names)

This method is called from
C<pkg('CGI::ElementEditor')->element_bulk_edit()> and takes care of
initializing the textarea with all relevant element data.

It's arguments include:

=over

=item editor

The element editor object

=item element

The element whose children are to be bulk edited

=item template

The template loaded by C<pkg('CGI::ElementEditor')->element_bulk_edit()>

=item element_children

For the textarea-flavour of bulk editing this list always has just one
member representing the name of the elementclass whose elements are about
to be bulk edited.

=cut

sub edit {
    my ($self, %arg) = @_;

    my $editor   = $arg{element_editor};
    my $template = $arg{template};
    my $element  = $arg{element};
    my $query    = $editor->query;

    # get list of existing elements to be bulk edited
    my $name = $arg{child_names}[0];

    my @children = grep { $_->name eq $name } $element->children;

    my $sep = $query->param('bulk_edit_sep');
    $sep = (defined $sep and length $sep) ? $sep : "__TWO_NEWLINE__";

    $template->param(
        bulk_edit_sep_selector => scalar $query->radio_group(
            -name   => 'new_bulk_edit_sep',
            -values => ["__TWO_NEWLINE__", "<p>", "<br>"],
            -labels   => {"__TWO_NEWLINE__" => localize("One Blank Line")},
            -default  => $sep,
            -override => 1,
            -class    => 'radio',
        ),
        bulk_edit_sep => $sep
    );

    $template->param(
        bulk_data => join(
            ($sep eq "__TWO_NEWLINE__" ? "\n\n" : "\n" . $sep . "\n"),
            grep  { defined }
              map { $_->bulk_edit_data } @children
        ),
        bulk_edit_word_count => 1
    );

    # crumbs let the user jump up the tree
    my @crumbs = $editor->_make_crumbs(element => $element);
    push @crumbs, {name => localize($element->class->child($name)->display_name)};
    $template->param(crumbs => \@crumbs) unless @crumbs == 1;

    # Done button label
    $template->param(bulk_done_with_this_element =>
          localize('Done Bulk Editing ' . $element->class->child($name)->display_name));
}

=item pkg('BulkEdit::Textarea')->save(element_editor => $elementeditor, element => $element)

This method is called from
pkg('CGI::ElementEditor')->element_bulk_save().

It breaks the incoming text into meaningfull chunks and records the
latter in children of $element (the legacy bulk edit behavior).

=cut

sub save {
    my ($self, %arg) = @_;
    my $editor      = $arg{element_editor};
    my $element     = $arg{element};
    my $query       = $editor->query;
    my $sep         = $query->param('bulk_edit_sep');
    my $sep_pattern = ($sep eq "__TWO_NEWLINE__") ? "\r?\n[ \t]*\r?\n" : "\r?\n?[ \t]*${sep}[ \t]*\r?\n?";
    my $data        = $query->param('bulk_data');
    my $name        = $query->param('bulk_edit_child');
    my @children    = grep { $_->name eq $name } $element->children;
    my @data        = split(/$sep_pattern/, $data);

    # if the separator is <p> then strip off any closing </p> tags
    @data = map { $_ =~ s|\s*<\s*/\s*p\s*>\s*$||; $_; } @data if $sep eq '<p>';

    # don't create empty elements, so make sure there is more than just empty space
    @data = grep { $_ =~ /\S/ } @data;

    # filter data through class's bulk_edit_filter
    @data = $element->class->child($name)->bulk_edit_filter(data => \@data);

    # match up one to one as possible
    while (@children and @data) {
        my $child = shift @children;
        my $data  = shift @data;
        $child->data($data);
    }

    # left over data, create new children
    if (@data) {
        $element->add_child(
            class => $name,
            data  => $_
        ) for @data;
    }

    # left over children, remove them from this element
    elsif (@children) {
        $element->remove_children(@children);
    }

    add_message(
        'saved_bulk',
        name        => localize($element->class->child($name)->display_name),
        from_module => 'Krang::CGI::ElementEditor'
    );
}

=back

=cut

1;
