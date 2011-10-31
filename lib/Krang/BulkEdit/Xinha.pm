package Krang::BulkEdit::Xinha;
use warnings;
use strict;

use Krang::ClassFactory qw(pkg);

use Krang::ClassLoader 'Markup::IE';
use Krang::ClassLoader 'Markup::Gecko';
use Krang::ClassLoader 'Markup::WebKit';
use Krang::ClassLoader 'BulkEdit::Xinha::Config';
use Krang::ClassLoader Localization => qw(localize);
use Krang::ClassLoader Log          => qw(debug);
use Krang::ClassLoader Message      => qw(add_message);

use HTML::TreeBuilder;
use HTML::Element;

use Carp qw(croak);

use Krang::ClassLoader MethodMaker => new_with_init => 'new';

=head1 NAME

Krang::BulkEdit::Xinha - Class for Xinha-based bulk editing

=head1 SYNOPSIS

Krang::BulkEdit::Xinha - Class for Xinha-based bulk editing

=head1 DESCRIPTION

This class implements methods to handle bulk editing via the Xinha
WYSIWYG editor.  Its methods are used for elementclasses specifying
the string 'xinha' for their 'bulk_edit' attribute.

If there are sibling classes that also have 'bulk_edit => xinha', then
the Bulk Edit Selector will have an additional member named "All
WYSIWYG Elements".  Selecting "All WYSIGWYG Elements" will pass all
elements of sibling classes having 'bulk_edit => xinha' to the Xinha
bulk editor.

Xinha-based bulk edit classes map to HTMLElements via their attribute
'bulk_edit_tag', which may be any of the allowed block-level elements.
Allowed block-level elements are configurable. The default
configuration resides in L<Krang::BulkEdit::Xinha::Config>. Different
configurations may be achieved through subclassing.

For some elementclasses Xinha's formatblock selector will contain the
corresponding display_names.  This pertains to element classes whose
'bulk_edit_tag' is one of:

=over

=item HTMLHeadingElements (H1 .. H6)

=item HTMLParagraphElement (P)

=item HTMLPreElement (pre)

=item HTMLAdressElement (address)

=back

Allowed block-level HTMLElements that do not have their own
elementclass will end up in the default 'paragraph' elementclass.
When no elementclass with 'bulk_edit_tag => p' is found, a class
name'd 'paragraph' will be looked up.  If none exists, Krang croaks.

This default behavior means that, say, HTMLTableElments will end up in
the 'paragraph' element class unless some element class specially
caters for table elements by specifying 'bulk_edit_tag => table'.

In this case - when the HTMLTableElement ends up in the paragraph
element - the 'table' start and end tags will be part of the element's
data.  For HTMLElements having their own element class, the start and
end tags are not part of the element's data, hence are not stored in
the database.

=head1 CONFIGURATION

Xinha's toolbar and the set of allowed HTMLElements (and allowed
attributes of allowed HTMLElements) may be configured by subclassing
L<Krang::BulkEdit::Xinha::Config> which provides the default
configuration.

=head1 INTERFACE

=over

=item pkg('BulkEdit::Xinha')->edit(editor => $krang_cgi_elementeditor_instance, element => $element, template => $template, child_names => @bulk_edit_child_names)

This method is called from
C<pkg('CGI::ElementEditor')->element_bulk_edit()> and takes care of
initializing Xinha with all relevant element data.

It's arguments include:

=over

=item editor

The element editor object

=item element

The element whose children are to be bulk edited

=item template

The template loaded by C<pkg('CGI::ElementEditor')->element_bulk_edit()>

=item element_children

A list of element class names (coming from the ElementEditor's bulk
edit selector).  Elements belonging to these element classes will be
edited via Xinha.

This method makes sure that the HTML markup passed to Xinha is
understood my the WYSIWYG commands of Gecko, WebKit and IE's engine.
See L<Krang::Markup> for more information.

=cut

sub edit {
    my ($self, %arg) = @_;

    my $editor   = $arg{element_editor};
    my $template = $arg{template};
    my $element  = $arg{element};

    # get children to put in Xinha
    my %names = map { $_ => 1 } @{$arg{child_names}};

    my @children = grep { $names{$_->name} } $element->children;

    # put the configured html tag around them
    my $full_text = '';
    foreach my $child (@children) {
        my $tag  = $child->class->bulk_edit_tag;
        my $html = $child->data;

        # no empty elements
        next unless $html || $self->is_empty_tag($tag) || ref($child->before_bulk_edit) eq 'CODE';

        # our default tag
        $tag ||= 'p';

        # maybe filter the data
        my $data =
          ref($child->before_bulk_edit) eq 'CODE'
          ? $child->before_bulk_edit->(element => $child)
          : $html;

        # concat it
        $full_text .= "<$tag>$data</$tag>";
    }

    # make formatblock selector, using the elementclass's display_name
    my ($display_name_for, $formatblock) = $self->make_formatblock(
        element     => $element,
        child_names => \%names
    );

    # xinha-specific tmpl-var
    my $serverbase = ($ENV{SERVER_PROTOCOL} =~ /^HTTP\//) ? "http://" : "https://";
    $serverbase .= $ENV{HTTP_HOST} . '/';

    # make sure the browser finds markup his WYSIWYG commands can handle
    my $html = pkg("Markup::$ENV{KRANG_BROWSER_ENGINE}")->db2browser(html => $full_text);

    # crumbs let the user jump up the tree
    my @crumbs = $editor->_make_crumbs(element => $element);
    my @display_names = values %$display_name_for;
    my ($curr_loc) =
      (scalar(@display_names) == 1)
      ? $display_names[0]
      : localize("All WYSIWYG Elements");
    push @crumbs, {name => $curr_loc};

    # fill template
    $template->param(
        bulk_data                   => $html,
        formatblock                 => $formatblock,
        serverbase                  => $serverbase,
        crumbs                      => \@crumbs,
        bulk_done_with_this_element => localize('Done Bulk Editing ' . $curr_loc),
        toolbar => $self->xinha_toolbar(include_formatblock => $formatblock),
    );
}

=item pkg('BulkEdit::Xinha')->save(editor => $krang_cgi_elementeditor_instance, element => $element)

This method is called from
pkg('CGI::ElementEditor')->element_bulk_save().

It sanitizes the incoming HTML, breaks it up into meaningfull chunks
and records the latter in children of $element.

The sanitizing rules may be (re-)configured by overriding C<html_scrubber()> in
L<Krang::BulkEdit::Xinha::Config>.

=cut

sub save {
    my ($self, %arg) = @_;
    my $editor  = $arg{element_editor};
    my $element = $arg{element};
    my $query   = $editor->query;

    # filter and sanitize the incoming HTML
    my $html =
      $self->html_scrubber(html =>
          pkg("Markup::$ENV{KRANG_BROWSER_ENGINE}")->browser2db(html => $query->param('bulk_data'))
      );

    # remove old children
    my $at_boundary = "\\" . pkg('CGI::ElementEditor')->concat_string();
    my %names = map { $_ => 1 } split(/$at_boundary/, $query->param('bulk_edit_child'));
    $element->remove_children(grep { $names{$_->name} } $element->children);

    # which block elements *may* be distributed across elementclasses?
    # some of these elements might have been scrubbed away!
    # See Krang::BulkEdit::Xinha::Config::html_scrubber()
    my $block_re = $self->block_re();

    # which HTML block elements have their own elementclass
    my $elementclass_for = $self->tag2class_map(element => $element);
    my $tmp = join('|', keys %$elementclass_for);
    my $elementclass_re = qr($tmp);

    # make a HTML::Tree
    my $tree = $self->make_html_tree(html => $html);

    # make Krang elements from tree
    for my $block ($tree->look_down('_tag' => $block_re)) {

        # got an interesting tag
        my $tag = $block->tag || next;

        # skip empty content tags
        next unless $block->as_text() or $self->is_empty_tag($tag);

        $self->add_element(
            tag              => $tag,
            element          => $element,
            block            => $block,
            elementclass_for => $elementclass_for,
            elementclass_re  => $elementclass_re
        );
    }

    # cleanup
    $tree->delete();

    # and keep user informed
    add_message(
        'saved_bulk',
        name        => $element->display_name,
        from_module => 'Krang::CGI::ElementEditor'
    );
}

###################
#                 #
# Private methods #
#                 #
###################

# add a Krang element
sub add_element {
    my ($self, %arg) = @_;
    my $block   = $arg{block};
    my $tag     = $arg{tag};
    my $element = $arg{element};

    my @html = ();

    # consider BR inside P as paragraph limit?
    if ($tag eq 'p' && $self->split_p_on_br()) {
        @html = $self->split_block_on_br(block => $block);
    } else {

        # see HTML::Element for those args
        my $html = $block->as_HTML('<>&', undef, {});

        # strip the element's tag if the element set has a class
        # for this tag (otherwise put it in the class for the
        # paragraph tag 'p'
        if ($tag =~ /$arg{elementclass_re}/) {
            $html = $self->extract_children(html => $html, tag => $tag);
        }

        @html = ($html);
    }

    # add elements
    for my $html (@html) {

        # remove left over junk
        pkg("Markup::$ENV{KRANG_BROWSER_ENGINE}")->remove_junk(\$html);

        # look up the elementclass for HTML tag
        my $class = $arg{elementclass_for}->{$tag} || $arg{elementclass_for}->{p};

        # maybe change the element's class
        ($class, $html) = $element->bulk_save_change(class => $class, data => $html);

        # make a new Krang element for this tag's content
        my $child = $element->add_child(class => $class);

        # maybe filter the element's html before storing it
        my $data =
          ref($child->class->before_bulk_save) eq 'CODE'
          ? $child->class->before_bulk_save->(data => $html, element => $child)
          : $html;

        $child->data($data);

        debug(  "Making element for HTML tag '" 
              . $tag
              . "' with data: "
              . (defined $html ? $html : '<none>'));
    }
}

### sanitize incoming HTML
##sub scrub {
##    my ($self, %arg) = @_;
##
##    # scrub disallowed HTML tags and attribs
##    return pkg('BulkEdit::Xinha::Config')->html_scrubber(%arg);
##}

# all possible block elements
sub block_re {
    my ($self, %arg) = @_;

    return qr[^(?:p|ul|ol|h1|h2|h3|h4|h5|h6|hr|table|address|blockquote|pre|iframe)$];
}

# workaround HTML::Element::as_HTML()
sub extract_children {
    my ($self, %arg) = @_;
    my $html = $arg{html};

    # chop the block's tag
    $html =~ s!^\s*<$arg{tag}>!!;
    $html =~ s!</$arg{tag}>\s*$!!;

    # chop newline added by HTML::Element's as_HTML() method
    $html =~ s/\n$//;

    # return filtered HTML
    return $html;
}

# make the format selector in Xinha's toolbar. When overriding this
# method it is save to return the empty string
sub make_formatblock {
    my ($self, %arg) = @_;

    my $child_named = $arg{child_names};
    my $element     = $arg{element};
    my @children    = $element->class->children;

    my %allowed_in_formatblock = (
        'h1'      => 1,
        'h2'      => 1,
        'h3'      => 1,
        'h4'      => 1,
        'h5'      => 1,
        'h6'      => 1,
        'p'       => 1,
        'address' => 1,
        'pre'     => 1,
    );

    my %display_name_for = ();
    for my $class (grep { lc($_->bulk_edit) eq 'xinha' && $child_named->{$_->name} } @children) {
        my $tag = $class->bulk_edit_tag;
        if ($tag) {
            $display_name_for{$tag} = localize($class->display_name);
        }
    }

    # look for a default Krang element name'd "paragraph"
    if ($child_named->{paragraph} && not($display_name_for{p})) {

        # no child class has a 'bulk_edit_tag => p'
        my ($default) = grep { lc($_->name) eq 'paragraph' } @children;

        croak(__PACKAGE__
              . "::->save() - No elementclass having either 'bulk_edit_tag => p' or 'name => paragraph' found. Can't make 'Paragraph' entry in Xinha's formatblock selector."
        ) unless $default;

        debug("Adding default 'Paragraph' to Xinha's formatblock selector");

        $display_name_for{p} = localize('Paragraph');
    }

    # format as JavaScript object litteral (element order matters in this case,
    # so don't use JSON::Any to convert a Perl Hash into a JavaScript litteral!
    my $formatblock = join(',',
        map    { "'$display_name_for{$_}' : '$_'" }
          sort { $a cmp $b }
          grep { $allowed_in_formatblock{$_} }
          keys %display_name_for);

    # add first '--format--' element to selector
    $formatblock = "'&mdash; " . localize('format') . " &mdash;' : '', " . $formatblock
      if $formatblock;

    return (\%display_name_for, $formatblock);
}

# map HTMLElement tags to Krang element classes
sub tag2class_map {
    my ($self, %arg) = @_;

    my $element = $arg{element};

    my @bulk_edit_classes = grep { lc($_->bulk_edit) eq 'xinha' } $element->class->children;
    my %class_for = map { $_->bulk_edit_tag => $_ }
      grep { defined($_->bulk_edit_tag) } @bulk_edit_classes;

    # make sure we have our default 'paragraph' class
    unless ($class_for{p}) {
        my ($default) = grep { lc($_->name) eq 'paragraph' } @bulk_edit_classes;
        croak(__PACKAGE__
              . "::->save() - No elementclass having 'bulk_edit_tag => p' found. Don't know where to put HTML coming from bulk edit in Xinha."
        ) unless $default;
        $class_for{p} = $default;
    }

    return \%class_for;
}

sub make_html_tree {
    my ($self, %arg) = @_;

    my $tree = HTML::TreeBuilder->new(
        implicit_body_p_tag => 1,    # wrap inline nodes with P if outside of block-level elements
        p_strict            => 1,    # add closing P tag before all block-level elements
    );

    $tree->parse($arg{html});
    $tree->eof;
    $tree->elementify();             # change $tree's class to HTML::Element

    return $tree;
}

sub split_block_on_br {
    my ($self, %arg) = @_;
    my $block = $arg{block};

    my @html  = ();                        # return acc
    my @nodes = $block->content_list();    # a list of nodes being children of $block

    my $html = '';
    while (@nodes) {
        my $node = shift(@nodes);

        if (ref($node)) {                  # element node
            if ($node->tag eq 'br') {      # split here
                push(@html, $html);
                $html = '';
            } else {
                my $tmp = $node->as_HTML('<>&', undef, {});
                $tmp =~ s/\n$//;
                $html .= $tmp;
            }
        } else {    # text node
            $html .= $node;
        }
    }

    # filter empty pieces
    return grep { $_ } @html, $html;
}

sub is_empty_tag {
    my ($self, $tag) = @_;

    my $is_empty = $self->get_empty_tags();

    return $is_empty->{$tag};
}

sub get_empty_tags {
    return {hr => 1, iframe => 1};
}

# store subclassable config object
sub init {
    my $self = shift;

    $self->{config} = pkg('BulkEdit::Xinha::Config')->new();
}

# proxy config methods
BEGIN {
    no strict qw(refs);

    for my $meth (qw(xinha_toolbar html_scrubber split_p_on_br)) {
        *{"Krang::BulkEdit::Xinha::$meth"} = sub { (shift)->{config}->$meth(@_) };
    }

    use strict qw(refs);
}

=back

=cut

1;
