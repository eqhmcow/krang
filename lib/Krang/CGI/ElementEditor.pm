package Krang::CGI::ElementEditor;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

=head1 NAME

Krang::CGI::ElementEditor - element editor CGI base class

=head1 SYNOPSIS

  http://krang/instance_name/element_editor

=head1 DESCRIPTION

Element editor CGI for Krang.  This module is a super-class upon which
element editing CGIs (story and category editors) may be built.  It
supplies some full run-modes as well as some helper functions which
the child classes will use to implement their run-modes.

=head1 INTERFACE

=head2 Provided Run Modes

This module implements the following run modes:

=over

=item add

Called when the user clicks the "Add Element" button in the element
editor.  Returns to the 'edit' mode when complete.

=item delete_children

Called to delete sub-elements.  Returns to the 'edit' mode when
complete without modifying 'path'.

=item reorder

Called to reorder sub-elements.  Returns to the 'edit' mode when
complete without modifying 'path'.

=item delete_element

Called to delete an element.  This should called when the user clicks
the delete button, except on the root screen where delete refers to
the containing object.

=item find_story_link

Called to find a story to link to a Krang::ElementClass::StoryLink (or
subclass) element.  Requires a path to the element and will set
$element->data() to the chosen story.  When finished, returns to the
edit mode.

=item find_media_link

Called to find a media to link to a Krang::ElementClass::MediaLink (or
subclass) element.  Requires a path to the element and will set
$element->data() to the chosen media.  When finished, returns to the
edit mode.

=back

=head2 Provided Methods

The following methods are available to perform interface tasks
involving elements.  These should be called from within the child
class' run-modes.

=over

=item $self->element_edit(template => $template, element  => $element)

Called to fill in template parameters for the element editor
(F<ElementEditor/edit.tmpl>).  Both the template and element are
required parameters.  When it returns the template will contain all
necessary parameters to display the element editor.

This method will show the bulk edit interface if the CGI param
'bulk_edit' is set.

The bulk edit screen's standard edit area is a big textarea
field. This is triggered by setting an elementclasse's 'bulk_edit'
property to the legacy value '1' or better to 'textarea'. See
<Krang::BulkEdit::Textarea>.

Another possibility is to use the Xinha editor for bulk editing. Set
the elementclass's 'bulk_edit' property to 'xinha' if you wish this
behavior. See L<Krang::BulkEdit::Xinha>

=item $self->element_view(template => $template, element  => $element)

Called to fill in template parameters for the element viewer
(F<element_editor_view.tmpl>).  Both the template and element are
required parameters.  When it returns the template will contain all
necessary parameters to display the element viewer.

=item $ok = $self->element_save(element  => $element)

Called to save element data to the element passed to the method.  Will
return a boolean value indicating whether or not the save was
successful.  If the save was not successful then messages will have
been registered with Krang::Message to explain the problem to the
user.

=back

=head2 Required Runmodes

You must implement the following run-modes in any child class:

=over 4

=item edit

The edit run mode is called after a number of the run-modes available
complete their work.

=item save_and_add

This mode should do a save and then go to the add run-mode described
above.  It will only be called when adding container elements.

=item save_and_jump

This mode is called with a 'jump_to' parameter set.  It must save,
substitute the 'jump_to' value for 'path' in query and return to edit.

=item save_and_go_up

This mode should save, hack off the last part of path (s!/.*$!!) and
return to edit.

=item save_and_find_media

This mode is called with a 'jump_to' parameter set.  It must save,
substitute the 'jump_to' value for 'path' in query and return to the
find_media_link mode.

=item save_and_find_story

This mode is called with a 'jump_to' parameter set.  It must save,
substitute the 'jump_to' value for 'path' in query and return to the
find_story_link mode.

=back

=head2 Required Methods

Your sub-class must define the following helper methods:

=over

=item _get_element

Must return the element currently being edited from the session.

=item _get_script_name

Must return the name of the C<.pl> script in htdocs directory which
uses this module. This allows the C<action> attribute for forms
to be filled in.

=back

=cut

use Krang::ClassLoader 'ElementLibrary';
use Krang::ClassLoader 'Element';
use Krang::ClassLoader DB => qw(dbh);
use Carp qw(croak);
use Krang::ClassLoader Session      => qw(%session);
use Krang::ClassLoader Log          => qw(debug assert affirm ASSERT);
use Krang::ClassLoader Message      => qw(add_message get_messages add_alert);
use Krang::ClassLoader Widget       => qw(category_chooser date_chooser decode_date);
use Krang::ClassLoader Localization => qw(localize);
use Krang::ClassLoader 'BulkEdit::Textarea';
use Krang::ClassLoader 'BulkEdit::Xinha';

use File::Spec::Functions qw(catdir);

use Krang::ClassLoader base => 'CGI';

# For *Link hard find feature
use Storable qw(thaw);
use MIME::Base64 qw(decode_base64);

sub setup {
    my $self = shift;
    $self->mode_param('rm');
    $self->run_modes(
        add             => 'add',
        delete_children => 'delete_children',
        reorder         => 'reorder',
        delete_element  => 'delete_element',
        find_story_link => 'find_story_link',
        select_story    => 'select_story',
        find_media_link => 'find_media_link',
        select_media    => 'select_media',
    );
}

# show the edit screen
sub element_edit {
    my ($self, %args) = @_;
    my $query    = $self->query();
    my $template = $args{template};
    my $path     = $query->param('path') || '/';

    # pass to bulk edit it bulk editing
    return $self->element_bulk_edit(%args) if $query->param('bulk_edit');

    # find the root element, loading from the session or the DB
    my $root = $args{element};
    croak("Unable to load element from session.")
      unless defined $root;

    # find the element being edited using path
    my $element = $self->_find_element($root, $path);

    # store current element's name
    $template->param(done_with_this_element => localize('Done With ' . $element->display_name));
    $template->param(delete_this_element    => localize('Delete ' . $element->display_name));

    # crumbs let the user jump up the tree
    my @crumbs = $self->_make_crumbs(element => $element);
    $template->param(crumbs => \@crumbs) unless @crumbs == 1;

    # decide whether to show the delete element button
    $template->param(allow_delete => $element->allow_delete);

    # load invalid list, generated by save()
    my %invalid;
    %invalid = map { ($_ => 1) } (split(',', $query->param('invalid')))
      if defined $query->param('invalid');

    my @child_loop;
    my $index = 0;
    my $order;
    my @children = $element->children;

    # figure out list of slots that are reorderable
    my @avail_ord = grep { $children[$_ - 1]->reorderable } (1 .. @children);
    my $avail_del = grep { $_->allow_delete } @children;

    # let the template know if none are reorderable/deleteable so no
    # button displayed
    $template->param(no_reorder => 1) if not @avail_ord;
    $template->param(no_delete  => 1) if not $avail_del;

    # find out how many children are reorderable
    my $multiple_reorders = 0;
    foreach my $child (@children) {
        $multiple_reorders++ if $child->reorderable;
        last                 if $multiple_reorders > 1;
    }
    $multiple_reorders = 0 if $multiple_reorders < 2;

    # the chooser logic is separately sent to the template
    my @categorylink_chooser_loop = ();

    foreach my $child (@children) {
        next if $child->hidden;

        # setup form, making it invalid if needed
        # Krang::ElementClass::CategoryLink objects
        # return the category chooser separately
        my ($form, $cat_link_chooser) = $child->input_form(
            query   => $query,
            order   => $index,
            invalid => $invalid{$index}
        );
        $form = $child->mark_form_invalid(html => $form) if $invalid{$index};

        push(
            @child_loop,
            {
                form => $form,
                name => localize($child->display_name),
                path => $child->xpath(),
                (
                    order_select => $child->reorderable && $multiple_reorders
                    ? $query->popup_menu(
                        -name     => "order_$index",
                        -values   => \@avail_ord,
                        -default  => $index + 1,
                        -onchange => "Krang.update_order(this, 'order_')",
                        -override => 1
                      )
                    : ($index + 1)
                      . $query->hidden(
                        -name     => "order_$index",
                        -default  => $index + 1,
                        -override => 1
                      )
                ),
                is_container => $child->is_container,
                index        => $index,
                allow_delete => $child->allow_delete,
                required     => $child->required,
                invalid      => $invalid{$index},
            }
        );

        push(@categorylink_chooser_loop, {categorylink_chooser => $cat_link_chooser})
          if $cat_link_chooser;

        $index++;
    }

    $template->param(child_loop                => \@child_loop);
    $template->param(categorylink_chooser_loop => \@categorylink_chooser_loop)
      if scalar(@categorylink_chooser_loop);

    # whip up child element picker from available classes
    my @available = $element->available_child_classes();
    if (@available) {
        my (@values, %labels);
        if (my @elements_in_order = $element->class->order_of_available_children) {

            # if the element class defines the order, use it
            my %element_order;
            if (ref $elements_in_order[0] eq 'HASH') {

                # build the menu with optgroups
                for (my $i = 0 ; $i < @elements_in_order ; ++$i) {
                    %element_order = ();

                    # get elements for this group
                    my @element_names = @{$elements_in_order[$i]->{elements}};
                    for (my $j = 0 ; $j < @element_names ; ++$j) {
                        $element_order{$element_names[$j]} = $j;
                    }

                    # we only care about available elements
                    my @elements = grep { exists $element_order{$_->name} } @available;
                    next unless @elements;

                    my @sorted =
                      sort { ($element_order{$a} || 0) <=> ($element_order{$b} || 0) }
                      map { $_->name } @elements;
                    my %group_labels = map { ($_->name, localize($_->display_name)) } @elements;

                    push @values,
                      $query->optgroup(
                        -name   => $elements_in_order[$i]->{optgroup},
                        -values => \@sorted,
                        -labels => \%group_labels,
                      );
                }
            } else {

                # single list
                for (my $i = 0 ; $i < @elements_in_order ; ++$i) {
                    $element_order{$elements_in_order[$i]} = $i;
                }
                @values =
                  sort { ($element_order{$a} || 0) <=> ($element_order{$b} || 0) }
                  map { $_->name } @available;
                %labels = map { ($_->name, localize($_->display_name)) } @available;
            }
        } else {

            # otherwise sort by display name
            @values =
              map  { $_->name }
              sort { localize($a->display_name) cmp localize($b->display_name) } @available;
            %labels = map { ($_->name, localize($_->display_name)) } @available;
        }

        $template->param(
            child_select => $query->popup_menu(
                -name   => "child",
                -values => \@values,
                -labels => \%labels
            )
        );
    }

    # bulk edit selector
    my @bulk_edit = grep { $_->bulk_edit } $element->class->children;
    if (@bulk_edit) {
        my @values = map { $_->name } @bulk_edit;
        my %labels = map { ($_->name, localize($_->display_name)) } @bulk_edit;
        my @global = grep { $_->bulk_edit ne '1' and $_->bulk_edit ne 'textarea' } @bulk_edit;
        if (scalar(@global) > 1) {
            my $global = join($self->concat_string, map { $_->name } @global);
            push @values, $global;
            $labels{$global} = localize('All WYSIWYG Elements');
        }
        $template->param(
            bulk_edit_select => $query->popup_menu(
                -name   => "bulk_edit_child",
                -values => \@values,
                -labels => \%labels
            )
        );
    }

    $template->param(
        container_loop => [
            map { {name => $_->name} }
              grep { $_->is_container } @available
        ]
    );

}

sub element_bulk_edit {
    my ($self, %args) = @_;
    my $query    = $self->query();
    my $template = $args{template};
    my $path     = $query->param('path') || '/';

    # find the root element, loading from the session or the DB
    my $root = $args{element};
    croak("Unable to load element from session.")
      unless defined $root;

    # find the element being edited using path
    my $element = $self->_find_element($root, $path);

    # bulk_edit: in textarea or WYSIWYG editor
    my $at_boundary = "\\" . $self->concat_string();
    my @names       = split(/$at_boundary/, $query->param('bulk_edit_child'));
    my $bulk_edit   = $element->class->child($names[0])->bulk_edit;
    $bulk_edit = 'textarea' if $bulk_edit eq '1';

    # pass the bulk_edit type around
    $template->param(
        bulk_edit                 => $bulk_edit,
        "is_bulk_edit_$bulk_edit" => 1
    );

    # dispatch to bulk edit class
    pkg("BulkEdit::" . ucfirst($bulk_edit))->edit(
        element_editor => $self,
        element        => $element,
        child_names    => \@names,
        template       => $template,
    );

    return 1;
}

sub find_story_link {
    my ($self, %args) = @_;
    my $query    = $self->query();
    my $template = $self->load_tmpl(
        'find_story_link.tmpl',
        path      => [catdir('ElementEditor', $session{language}), 'ElementEditor'],
        associate => $query,
    );
    my $path = $query->param('path') || '/';

    my $hard_find_froz = $query->param("hard_find_$path");
    my $hard_find      = thaw(decode_base64($hard_find_froz));
    $template->param(hard_find_hidden => $query->hidden("hard_find_$path", $hard_find_froz));

    # find the root element, loading from the session or the DB
    my $root = $self->_get_element;
    my $element = $self->_find_element($root, $path);

    $template->param(parent_path => $element->parent->xpath());

    # determine appropriate find params for search
    my %find_params;
    my %persist_vars = ();
    if ($query->param('advanced')) {
        my %tmpl_data;

        # Set up advanced search
        my @auto_search_params = qw(
          title
          url
          class
          below_category_id
          story_id
          contrib_simple
        );

        for (@auto_search_params) {
            my $key = $_;
            my $val = $query->param("search_" . $_);

            # If no data, skip parameter
            next unless (defined($val) && length($val));

            # Persist parameter
            $persist_vars{"search_" . $_} = $val;

            # Like search
            if (grep { $_ eq $key } (qw/title url/)) {
                $key .= '_like';
                $val =~ s/\W+/\%/g;
                $val = "\%$val\%";
            }

            # Set up search in pager
            $find_params{$key} = $val;
        }

        # Set up cover and publish date search
        for my $datetype (qw/cover publish/) {
            my $from = decode_date(query => $query, name => $datetype . '_from');
            my $to   = decode_date(query => $query, name => $datetype . '_to');
            if ($from || $to) {
                my $key = $datetype . '_date';
                my $val = [$from, $to];

                # Set up search in pager
                $find_params{$key} = $val;
            }

            # Persist parameter
            for my $interval (qw/month day year/) {
                my $from_pname = $datetype . '_from_' . $interval;
                my $to_pname   = $datetype . '_to_' . $interval;

                # Only persist date vars if they are complete and valid
                if ($from) {
                    my $from_pname = $datetype . '_from_' . $interval;
                    $persist_vars{$from_pname} = $query->param($from_pname);
                } else {

                    # Blow away var
                    $query->delete($from_pname);
                }

                if ($to) {
                    $persist_vars{$to_pname} = $query->param($to_pname);
                } else {

                    # Blow away var
                    $query->delete($to_pname);
                }
            }

        }

        # If we're showing an advanced search, set up the form
        $tmpl_data{category_chooser} = category_chooser(
            name  => 'search_below_category_id',
            query => $query,
        );

        # Date choosers
        $tmpl_data{date_chooser_cover_from} =
          date_chooser(query => $query, name => 'cover_from', nochoice => 1);
        $tmpl_data{date_chooser_cover_to} =
          date_chooser(query => $query, name => 'cover_to', nochoice => 1);
        $tmpl_data{date_chooser_publish_from} =
          date_chooser(query => $query, name => 'publish_from', nochoice => 1);
        $tmpl_data{date_chooser_publish_to} =
          date_chooser(query => $query, name => 'publish_to', nochoice => 1);

        # Story class
        my $media_class = pkg('ElementClass::Media')->element_class_name;
        my @classes =
          grep { $_ ne 'category' && $_ ne $media_class } pkg('ElementLibrary')->top_levels;
        my %class_labels =
          map { $_ => localize(pkg('ElementLibrary')->top_level(name => $_)->display_name) }
          @classes;
        $tmpl_data{search_class_chooser} = scalar(
            $query->popup_menu(
                -name    => 'search_class',
                -default => '',
                -values  => [('', @classes)],
                -labels  => \%class_labels
            )
        );
        $template->param(\%tmpl_data);

    } else {
        my $search_filter = $query->param('search_filter');
        %find_params  = (simple_search => $search_filter);
        %persist_vars = (search_filter => $search_filter);
    }

    # always show only what should be seen
    $find_params{may_see} = 1;

    # when editing a story, exclude it from story search
    if ($self->isa('Krang::CGI::Story') and $session{story}->story_id) {
        $find_params{exclude_story_ids} = [$session{story}->story_id];
    }

    # Apply hard find params
    while (my ($k, $v) = each(%$hard_find)) {
        $find_params{$k} = $v;
    }

    my $pager = pkg('HTMLPager')->new(
        cgi_query    => $query,
        persist_vars => {
            rm                => 'find_story_link',
            path              => $query->param('path'),
            advanced          => ($query->param('advanced') || 0),
            "hard_find_$path" => $hard_find_froz,
            %persist_vars,
        },
        use_module  => pkg('Story'),
        find_params => \%find_params,
        columns     => [
            qw(
              pub_status
              story_id
              url
              title
              cover_date
              command_column
              )
        ],
        column_labels => {
            pub_status => '',
            story_id   => 'ID',
            url        => 'URL',
            title      => 'Title',
            cover_date => 'Date',
        },
        columns_sortable        => [qw( story_id url title cover_date )],
        command_column_commands => [qw( select_story )],
        command_column_labels   => {select_story => 'Select',},
        row_handler             => sub { $self->find_story_link_row_handler(@_) },
        id_handler              => sub { shift->story_id },
    );

    $template->param(
        pager_html => $pager->output(),
        row_count  => $pager->row_count,
        action     => $self->_get_script_name,
    );

    return $template->output;
}

# Pager row handler for story find run-mode
sub find_story_link_row_handler {
    my $self = shift;
    my $q    = $self->query;
    my ($row, $story, $pager) = @_;

    # Columns:
    #

    # story_id
    $row->{story_id} = $story->story_id();

    # format url to fit on the screen and to link to preview
    my $url       = $story->url();
    my @parts     = split('/', $url);
    my @url_lines = (shift(@parts), "");
    for (@parts) {
        if ((length($url_lines[-1]) + length($_)) > 15) {
            push(@url_lines, "");
        }
        $url_lines[-1] .= "/" . $_;
    }
    $row->{url} = join('<wbr>',
        map { qq{<a href="javascript:Krang.preview('story',$row->{story_id})">$_</a>} } @url_lines);

    # title
    $row->{title} = $q->escapeHTML($story->title);

    # cover_date
    my $tp = $story->cover_date();
    $row->{cover_date} = $self->_numeric_date_format($tp);

    # pub_status
    $row->{pub_status} = $story->published_version() ? '<b>' . localize('P') . '</b>' : '&nbsp;';
}

sub find_media_link {
    my ($self, %args) = @_;
    my $query    = $self->query();
    my $template = $self->load_tmpl(
        'find_media_link.tmpl',
        path      => [catdir('ElementEditor', $session{language}), 'ElementEditor'],
        associate => $query
    );
    my $path = $query->param('path') || '/';

    my $hard_find_froz = $query->param("hard_find_$path");
    my $hard_find      = thaw(decode_base64($hard_find_froz));
    $template->param(hard_find_hidden => $query->hidden("hard_find_$path", $hard_find_froz));

    # find the root element, loading from the session or the DB
    my $root = $self->_get_element;
    my $element = $self->_find_element($root, $path);

    $template->param(parent_path => $element->parent->xpath());

    # determine appropriate find params for search
    my %find;
    my %persist;
    if ($query->param('advanced')) {
        my $search_below_category_id = $query->param('search_below_category_id');
        if ($search_below_category_id) {
            $persist{search_below_category_id} = $search_below_category_id;
            $find{below_category_id}           = $search_below_category_id;
        }

        my $search_creation_date = decode_date(
            query => $query,
            name  => 'search_creation_date'
        );
        if ($search_creation_date) {

            # If date is valid send it to search and persist it.
            $find{creation_date} = $search_creation_date;
            for (qw/day month year/) {
                my $varname = "search_creation_date_$_";
                $persist{$varname} = $query->param($varname);
            }
        } else {

            # Delete date chooser if date is incomplete
            for (qw/day month year/) {
                my $varname = "search_creation_date_$_";
                $query->delete($varname);
            }
        }

        # search_filename
        my $search_filename = $query->param('search_filename');
        if ($search_filename) {
            $search_filename =~ s/\W+/\%/g;
            $find{filename_like}      = "\%$search_filename\%";
            $persist{search_filename} = $search_filename;
        }

        # search_title
        my $search_title = $query->param('search_title');
        if ($search_title) {
            $search_title =~ s/\W+/\%/g;
            $find{title_like}      = "\%$search_title\%";
            $persist{search_title} = $search_title;
        }

        # search_media_id
        my $search_media_id = $query->param('search_media_id');
        if ($search_media_id) {
            $find{media_id}           = $search_media_id;
            $persist{search_media_id} = $search_media_id;
        }

        # search_no_attributes
        my $search_no_attributes = $query->param('search_no_attributes');
        if ($search_no_attributes) {
            $find{no_attributes}           = $search_no_attributes;
            $persist{search_no_attributes} = $search_no_attributes;
        }
    } else {
        my $search_filter =
          defined($query->param('search_filter'))
          ? $query->param('search_filter')
          : $session{KRANG_PERSIST}{pkg('Media')}{search_filter};
        %find    = (simple_search => $search_filter);
        %persist = (search_filter => $search_filter);
        $template->param(search_filter => $search_filter);
    }

    # always show only what should be seen
    $find{may_see} = 1;

    # when editing a media object, exclude it from media search
    if ($self->isa('Krang::CGI::Media') and $session{media}->media_id) {
        $find{exclude_media_ids} = [$session{media}->media_id];
    }

    # Apply hard find params
    while (my ($k, $v) = each(%$hard_find)) {
        $find{$k} = $v;
    }

    my $pager = pkg('HTMLPager')->new(
        cgi_query    => $query,
        persist_vars => {
            rm                => 'find_media_link',
            path              => $query->param('path'),
            advanced          => ($query->param('advanced') || 0),
            "hard_find_$path" => $hard_find_froz,
            %persist,
        },
        use_module  => pkg('Media'),
        find_params => \%find,
        columns     => [
            qw(
              pub_status
              media_id
              thumbnail
              url
              creation_date
              command_column
              )
        ],
        column_labels => {
            pub_status    => '',
            media_id      => 'ID',
            thumbnail     => '',
            url           => 'URL',
            creation_date => 'Date',
        },
        columns_sortable        => [qw( media_id url creation_date )],
        command_column_commands => [qw( select_media )],
        command_column_labels   => {select_media => 'Select',},
        row_handler             => sub { $self->find_media_link_row_handler(@_) },
        id_handler              => sub { shift->media_id },
    );

    # Set up advanced search form
    $template->param(
        category_chooser => scalar(
            category_chooser(
                query => $query,
                name  => 'search_below_category_id',
            )
        )
    );
    $template->param(
        date_chooser => date_chooser(
            query    => $query,
            name     => 'search_creation_date',
            nochoice => 1,
        )
    );

    $template->param(pager_html => $pager->output());
    $template->param(action     => $self->_get_script_name);

    return $template->output;
}

# Pager row handler for media find run-mode
sub find_media_link_row_handler {
    my $self = shift;
    my ($row, $media, $pager) = @_;

    # Columns:
    #

    # media_id
    $row->{media_id} = $media->media_id();

    # format url to fit on the screen and to link to preview
    my $url       = $media->url();
    my @parts     = split('/', $url);
    my @url_lines = (shift(@parts), "");
    for (@parts) {
        if ((length($url_lines[-1]) + length($_)) > 15) {
            push(@url_lines, "");
        }
        $url_lines[-1] .= "/" . $_;
    }
    $row->{url} = join('<wbr>',
        map { qq{<a href="javascript:Krang.preview('media',$row->{media_id})">$_</a>} } @url_lines);

    my $thumbnail_path = $media->thumbnail_path(relative => 1);
    if ($thumbnail_path) {
        $row->{thumbnail} =
          qq{<a href="javascript:Krang.preview('media',$row->{media_id})"><img alt="" src="$thumbnail_path"></a>};
    } else {
        $row->{thumbnail} = "&nbsp;";
    }

    # creation_date
    my $tp = $media->creation_date();
    $row->{creation_date} = $self->_numeric_date_format($tp);

    # pub_status
    $row->{pub_status} = $media->published_version() ? '<b>' . localize('P') . '</b>' : '&nbsp;';
}

sub select_story {
    my $self  = shift;
    my $query = $self->query;

    # gather params
    my $path     = $query->param('path');
    my $story_id = $self->query->param('selected_story_id');

    my $root = $self->_get_element;
    my $element = $self->_find_element($root, $path);

    # find story and set it in element data
    my ($story) = pkg('Story')->find(story_id => $story_id);
    $element->data($story);

    # back to edit, in the parent and out of find_story_link mode
    $query->delete_all();
    $query->param(path => $element->parent->xpath());

    # brag
    add_message('selected_story', id => $story_id);

    return $self->edit;
}

sub select_media {
    my $self  = shift;
    my $query = $self->query;

    # gather params
    my $path = $query->param('path') || '/';
    my $media_id = $self->query->param('selected_media_id');

    my $root = $self->_get_element;
    my $element = $self->_find_element($root, $path);

    # find media and set it in element data
    my ($media) = pkg('Media')->find(media_id => $media_id);
    $element->data($media);

    # back to edit, in the parent and out of find_media_link mode
    $query->delete_all();
    $query->param(path => $element->parent->xpath());

    # brag
    add_message('selected_media', id => $media_id);

    return $self->edit;
}

sub element_view {
    my ($self, %args) = @_;
    my $query    = $self->query();
    my $template = $args{template};
    my $root     = $args{element};
    my $path     = $query->param('path') || '/';

    # find the element being edited using path
    my $element = $self->_find_element($root, $path);

    # crumbs let the user jump up the tree
    my @crumbs = $self->_make_crumbs(element => $element);
    $template->param(crumbs => \@crumbs) unless @crumbs == 1;

    my @child_loop;
    my @children = $element->children;

    # figure out list of slots that are reorderable
    foreach my $child (@children) {
        next if $child->hidden;
        push(
            @child_loop,
            {
                data         => $child->view_data(),
                name         => localize($child->display_name),
                path         => $child->xpath(),
                is_container => $child->is_container,
            }
        );
    }
    $template->param(
        child_loop  => \@child_loop,
        parent_path => ($element->parent ? $element->parent->xpath : 0),
    );

}

# add sub-elements
sub add {
    my $self  = shift;
    my $query = $self->query();

    # gather params
    my $path = $query->param('path') || '/';
    my $child = $query->param('child');

    # find our element
    my $root = $self->_get_element;
    my $element = $self->_find_element($root, $path);

    # add the child element and save the element tree
    my $kid = $element->add_child(class => $child);

    # does this element have children?
    if ($kid->is_container) {

        # start editing the new element
        $query->param(path => $kid->xpath());
        add_message(
            'added_element',
            child  => localize($kid->display_name),
            parent => localize($element->display_name)
        );
    }

    # toss to edit
    return $self->edit();
}

# finds an element given the root and a path
sub _find_element {
    my ($self, $root, $path) = @_;

    my ($element) = $root->match($path);
    croak("Unable to find element for path '$path'.")
      unless $element;

    return $element;
}

sub element_bulk_save {
    my ($self, %args) = @_;

    my $query   = $self->query;
    my $path    = $query->param('path') || '/';
    my $root    = $args{element};
    my $element = $self->_find_element($root, $path);

    my $type = ucfirst($query->param('bulk_edit')) || 'Textarea';

    pkg("BulkEdit::$type")->save(
        element_editor => $self,
        element        => $element,
    );

    # success
    return 1;
}

sub element_save {
    my ($self, %args) = @_;
    my $query = $self->query();
    my $path = $query->param('path') || '/';

    # pass to bulk edit if bulk editing
    return $self->element_bulk_save(%args) if $query->param('bulk_edit');

    # saving should check for reorder, else confusing to the editor
    $self->revise('reorder', 1);

    my $root = $args{element};
    my $element = $self->_find_element($root, $path);

    # validate data
    my @msgs;
    my $clean = 1;
    my $index = 0;
    my @invalid;
    my $rm = $self->get_current_runmode();
    foreach my $child ($element->children()) {

        # ignore storylinks and medialinks if entering find_story or
        # find_media modes.  Doing otherwise will make it impossible
        # to satisfy their requirements.
        unless (
            (
                   $rm eq 'save_and_find_story_link'
                or $rm eq 'save_and_find_media_link'
            )
            and (  $child->class->isa('Krang::ElementClass::StoryLink')
                or $child->class->isa('Krang::ElementClass::MediaLink'))
          )
        {
            my ($valid, $msg) = $child->validate(query => $query);
            if (not $valid) {
                add_alert('invalid_element_data', msg => $msg);
                push @invalid, $index;
                $clean = 0;
            }
        }
        $index++;
    }

    # let the parent take a crack at it if all else is ok
    if ($clean) {
        my ($valid, $msg) = $element->validate_children(query => $query);
        if (not $valid) {
            add_alert('invalid_element_data', msg => $msg);
            $clean = 0;
        }
    }

    # toss back to edit with an error message if not clean
    if (not $clean) {
        $query->param(invalid => join(',', @invalid)) if @invalid;
        return 0;
    }

    # save data
    $index = 0;
    foreach my $child ($element->children()) {
        $child->load_query_data(query => $query) unless $child->hidden;
        $index++;
    }

    # notify user of the save
    add_message('saved_element', name => localize($element->display_name))
      if ($element->parent() && !$args{previewing_story});

    # success
    return 1;
}

# revise sub-element list, reordering or deleting as requested.  This
# is combined because the complex parameter reordering has to be done
# in either case.
sub revise {
    my ($self, $op, $no_return) = @_;
    my $query = $self->query();

    my $path    = $query->param('path') || '/';
    my $root    = $self->_get_element;
    my $element = $self->_find_element($root, $path);

    # get list of existing children and their query parameters
    my @old       = grep { !$_->hidden } $element->children();
    my @old_names = map  { [$_->param_names] } @old;
    my @hidden    = grep { $_->hidden } $element->children();

    # compute new list of children and rearrange query data
    my (@new, @old_to_new, @msgs);
    if ($op eq 'reorder') {
        for (0 .. $#old) {
            $new[$query->param("order_$_") - 1] = $old[$_];
            $old_to_new[$_] = $query->param("order_$_") - 1;
        }
    } elsif ($op eq 'delete') {
        for (0 .. $#old) {
            if ($query->param("remove_$_")) {
                add_message("deleted_element", name => localize($old[$_]->display_name));

                # do the removal
                $element->remove_children($old[$_]);
            } else {
                push(@new, $old[$_]);
                $old_to_new[$_] = $#new;
            }
        }
    } else {
        croak("Unknown op: '$op'");
    }

    # the javascript should ensure all order_$n fields are present and
    # non-overlapping
    assert(@old == @new) if ASSERT and $op eq 'reorder';
    assert(not(grep { not defined $_ } @new)) if ASSERT;

    # do the reorder
    $element->reorder_children(@new, @hidden) if $op eq 'reorder';

    # get a list of new param names
    my @new_names = map { [$_->param_names] } @new;

    # fix up query data assignments, which depend on ordering
    my (%params, @old_params, @new_params);
    for my $index (0 .. $#old) {
        next unless defined $old_to_new[$index];
        @old_params = @{$old_names[$index]};
        @new_params = @{$new_names[$old_to_new[$index]]};
        foreach my $p (0 .. $#old_params) {
            $params{$new_params[$p]} = [$query->param($old_params[$p])];
        }
    }
    $query->param($_ => @{$params{$_}}) for keys %params;

    # deletions get a message listing deleted elements
    if ($op eq 'delete') {
        my %msg = get_messages(keys => 1);
        add_alert('no_elements_deleted') unless $msg{deleted_element};

    } else {
        add_message('reordered_elements') unless $no_return;
    }

    return $self->edit() unless $no_return;
}

# delete this element
sub delete_element {
    my $self  = shift;
    my $query = $self->query();

    my $path = $query->param('path') || '/';

    my $root    = $self->_get_element;
    my $element = $self->_find_element($root, $path);
    my $name    = localize($element->display_name);

    my $parent = $element->parent();
    if (not $parent) {

        # this is the root, aw crap
        croak("Element editor can't delete the root element!");
    }

    # remove this element from parent
    $parent->remove_children($element);

    $query->param(path => $parent->xpath());
    add_message('deleted_element', name => $name);
    return $self->edit();
}

sub delete_children { shift->revise('delete') }

sub reorder { shift->revise('reorder') }

sub _get_element {
    my $self = shift;
    croak "_get_element() must be defined in child class '" . ref($self) . "'";
}

sub _get_script_name {
    my $self = shift;
    croak "_get_script_name() must be defined in child class '" . ref($self) . "'";
}

sub _numeric_date_format {
    my ($self, $time_piece);

    # default numeric date format
    my $date_format    = 'mdy';
    my $date_separator = '/';

    # maybe change this format for other languages
    unless ($session{language} eq 'en') {
        ($date_format, $date_separator) = localize('NUMERIC_DATE_FORMAT');
    }

    return ref($time_piece)
      ? $self->query->escapeHTML($time_piece->date_format($date_separator))
      : localize('[n/a]');
}

sub _make_crumbs {
    my ($self, %args) = @_;

    my $element = $args{element};

    my @crumbs = ();
    do {
        unshift(
            @crumbs,
            {
                name => localize($element->display_name),
                path => $element->xpath,
            }
        );
        $element = $element->parent;
    } while ($element);

    return @crumbs;
}

sub concat_string { '|' }

1;
