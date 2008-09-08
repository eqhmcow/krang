package Krang::CGI::Category;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader 'Category';
use Krang::ClassLoader 'ElementLibrary';
use Krang::ClassLoader Log     => qw(debug assert ASSERT);
use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader Message => qw(add_message add_alert);
use Krang::ClassLoader Widget =>
  qw(category_chooser datetime_chooser decode_datetime format_url autocomplete_values);
use Krang::ClassLoader 'CGI::Workspace';
use Carp qw(croak);
use Krang::ClassLoader 'Pref';
use Krang::ClassLoader 'HTMLPager';
use Krang::ClassLoader 'Site';
use Krang::ClassLoader Localization => qw(localize);

use Krang::ClassLoader base => 'CGI::ElementEditor';

sub _get_element     { $session{category}->element; }
sub _get_script_name { "category.pl" }

=head1 NAME

Krang::CGI::Category - web interface to manage categories

=head1 SYNOPSIS

  use Krang::ClassLoader 'CGI::Category';
  pkg('CGI::Category')->new()->run();

=head1 DESCRIPTION

=head1 INTERFACE

Following are descriptions of all the run-modes provided by
Krang::CGI::Category.

=head2 Run-Modes

=over 4

=cut

sub setup {
    my $self = shift;
    $self->SUPER::setup();
    $self->mode_param('rm');
    $self->start_mode('find');

    # add category specific modes to existing set
    $self->run_modes(
        $self->run_modes(),
        new_category    => 'new_category',
        create          => 'create',
        edit            => 'edit',
        find            => 'find',
        delete          => 'delete',
        delete_selected => 'delete_selected',

        db_save                       => 'db_save',
        db_save_and_stay              => 'db_save_and_stay',
        save_and_jump                 => 'save_and_jump',
        save_and_add                  => 'save_and_add',
        save_and_go_up                => 'save_and_go_up',
        save_and_bulk_edit            => 'save_and_bulk_edit',
        save_and_leave_bulk_edit      => 'save_and_leave_bulk_edit',
        save_and_change_bulk_edit_sep => 'save_and_change_bulk_edit_sep',
        save_and_find_story_link      => 'save_and_find_story_link',
        save_and_find_media_link      => 'save_and_find_media_link',
        autocomplete                  => 'autocomplete',
        prepare_copy                  => 'prepare_copy',
        execute_copy                  => 'execute_copy',
    );

    $self->tmpl_path('Category/');
}

=item find (default)

Show the category find screen.

=cut

sub find {
    my $self = shift;
    my $q    = $self->query();
    my $t    = $self->load_tmpl("find.tmpl", associate => $q, loop_context_vars => 1);

    # Do simple search based on search field
    my $search_filter = $q->param('search_filter');
    if (!defined $search_filter) {
        $search_filter = $session{KRANG_PERSIST}{pkg('Category')}{search_filter}
          || '';
    }

    # Configure pager
    my $pager = pkg('HTMLPager')->new(
        cgi_query    => $q,
        persist_vars => {
            rm            => 'find',
            search_filter => $search_filter,
        },
        use_module  => pkg('Category'),
        find_params => {
            may_see       => 1,
            simple_search => $search_filter
        },
        columns                 => [qw(category_id url command_column checkbox_column)],
        column_labels           => {category_id => 'ID', url => 'URL',},
        columns_sortable        => [qw( category_id url )],
        command_column_commands => [qw( edit_category copy_category )],
        command_column_labels   => {edit_category => 'Edit', copy_category => 'Copy'},
        row_handler => sub { $self->find_row_handler(@_) },
        id_handler  => sub { return $_[0]->category_id },
    );

    # fill the template
    $t->param(
        pager_html    => $pager->output(),
        row_count     => $pager->row_count(),
        search_filter => $search_filter,
    );

    return $t->output();
}

sub find_row_handler {
    my ($self, $row, $category, $pager) = @_;
    $row->{category_id} = $category->category_id();
    $row->{url} = format_url(url => $category->url(), length => 60);
    unless($category->may_edit) {
        $row->{command_column}  = "&nbsp;";
        $row->{checkbox_column} = "&nbsp;";
    }
}

=item new_category

Shows the new category form which submits to the create runmode.

=cut

sub new_category {
    my $self     = shift;
    my $query    = $self->query;
    my $template = $self->load_tmpl('new.tmpl', associate => $query);
    my %args     = @_;

    # throw error if there are no sites in the system
    my $site_count = pkg('Site')->find(count => 1);
    unless ($site_count) {
        add_alert('no_sites');
        return $self->find;
    }

    # setup error message if passed in
    if ($args{bad}) {
        $template->param("bad_$_" => 1) for @{$args{bad}};
    }

    # setup parent selector
    $template->param(
        parent_chooser => scalar(
            category_chooser(
                name       => 'parent_id',
                formname   => 'new_category',
                title      => 'Choose Parent Category',
                query      => $query,
                may_edit   => 1,
                persistkey => 'NEW_CATEGORY_DIALOGUE'
            )
        )
    );

    return $template->output();
}

=item create

Creates a new category object and proceeds to edit_category.  Expects the
form parameters from new_category.  Upon error, returns to new_category with
an error message.  Upon success, goes to edit_category.

=cut

sub create {
    my $self  = shift;
    my $query = $self->query;

    my $parent_id = $query->param('parent_id');
    my $dir       = $query->param('dir');

    # remember parent for duration of session
    $session{KRANG_PERSIST}{NEW_CATEGORY_DIALOGUE}{cat_chooser_id_new_category_parent_id} =
      $parent_id;

    # detect bad fields
    my @bad;
    push(@bad, 'parent_id'), add_alert('missing_parent_id')
      unless $parent_id;
    push(@bad, 'dir'), add_alert('missing_dir')
      unless $dir;
    push(@bad, 'dir'), add_alert('bad_dir')
      unless $dir =~ /^[-\w]+$/;
    return $self->new_category(bad => \@bad) if @bad;

    # create the object
    my $category;
    eval { $category = pkg('Category')->new(parent_id => $parent_id, dir => $dir) };

    if ($@ and ref($@) and $@->isa('Krang::Category::NoEditAccess')) {

        # User isn't allowed to add a descendant category
        my ($parent_cat) = pkg('Category')->find(category_id => $@->category_id);
        add_alert('add_not_allowed', url => $parent_cat->url);
        return $self->new_category(bad => ['parent_id']);
    } elsif ($@) {

        # rethrow
        die($@);
    }

    # try saving
    eval { $category->save(); };

    # is there an existing category or story with our URL?
    if ($@ and ref($@) and $@->isa('Krang::Category::DuplicateURL')) {

        if ($@->category_id) {

            # there's an existing category...
            add_alert(
                'duplicate_url',
                url         => $@->url,
                category_id => $@->category_id
            );
            return $self->new_category(bad => ['parent_id', 'dir']);

        } elsif ($@->story_id) {

            # there's an existing story; turn it into a category cover
            # (after making sure we can edit it!)
            my ($story) = pkg('Story')->find(story_id => $@->story_id);

            unless ($story->turn_into_category_index(category => $category, steal => 1)) {
                add_alert('uneditable_story_has_url', id => $story->story_id);
                return $self->new_category(bad => ['parent_id', 'dir']);
            }
            add_message(
                'story_had_category_url',
                id     => $story->story_id,
                cat_id => $category->{category_id}
            );
        } else {
            croak("DuplicateURL didn't include category_id OR story_id!");
        }
    } elsif ($@) {

        # rethrow
        die($@);
    }

    # store category in session for edit
    $session{category} = $category;

    # toss to edit
    return $self->edit;
}

=item edit

The category editing interface. Expects to find a category to edit in
$session{category} or a category_id in they query params.

=cut

sub edit {
    my $self     = shift;
    my $query    = $self->query;
    my $template = $self->load_tmpl(
        'edit.tmpl',
        associate         => $query,
        die_on_bad_params => 0,
        loop_context_vars => 1
    );
    my %args = @_;

    # load category from query or sessions
    my $category = $self->_load_category(param => 'category_id');

    # run the element editor edit
    $self->element_edit(
        template => $template,
        element  => $category->element
    );

    # static data
    $template->param(
        category_id => $category->category_id || "",
        url => format_url(
            url    => $category->url,
            length => 50,
        )
    );

    # edit fields for top-level
    my $path = $query->param('path') || '/';
    if ($path eq '/' and not $query->param('bulk_edit')) {
        $template->param(is_root => 1);
    }

    return $template->output();
}

=item db_save

This mode saves the category to the database and leaves the category editor,
sending control to the find screen.

=cut

sub db_save {
    my $self = shift;

    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    # save category to the database
    my $category = $session{category};
    $self->category_save();

    add_message('category_save', url => $category->url);

    # remove category from session
    delete $session{category};

    # return to find screen
    return $self->find;
}

=item db_save_and_stay

This mode saves the category to the database and returns to edit.

=cut

sub db_save_and_stay {
    my $self = shift;

    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    # save category to the database
    my $category = $session{category};
    $self->category_save();

    add_message('category_save', url => $category->url);

    # return to edit
    return $self->edit();
}

=item save_and_jump

This mode saves the current data to the session and jumps to editing
an element within the category.

=cut

sub save_and_jump {
    my $self = shift;

    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    # get target
    my $query   = $self->query;
    my $jump_to = $query->param('jump_to');
    croak("Missing jump_to on save_and_jump!") unless $jump_to;

    # set target and show edit screen
    $query->param(path      => $jump_to);
    $query->param(bulk_edit => 0);
    return $self->edit();
}

=item save_and_add

This mode saves the current data to the session and passes control to
Krang::ElementEditor::add to add a new element.

=cut

sub save_and_add {
    my $self = shift;

    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    return $self->add();
}

=item save_and_bulk_edit

This mode saves the current element data to the session and goes to
the bulk edit mode.

=cut

sub save_and_bulk_edit {
    my $self = shift;

    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    $self->query->param(bulk_edit => 1);
    return $self->edit();
}

=item save_and_change_bulk_edit_sep

Saves and changes the bulk edit separator, returning to edit.

=cut

sub save_and_change_bulk_edit_sep {
    my $self = shift;

    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    my $query = $self->query;
    $query->param(bulk_edit_sep => $query->param('new_bulk_edit_sep'));
    $query->delete('new_bulk_edit_sep');
    return $self->edit();
}

=item save_and_leave_bulk_edit

This mode saves the current element data to the session and goes to
the edit mode.

=cut

sub save_and_leave_bulk_edit {
    my $self = shift;

    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    $self->query->param(bulk_edit => 0);
    return $self->edit();
}

=item save_and_find_story_link

This mode saves the current element data to the session and goes to
the find_story_link mode in Krang::CGI::ElementEditor.

=cut

sub save_and_find_story_link {
    my $self = shift;

    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    # get target
    my $query   = $self->query;
    my $jump_to = $query->param('jump_to');
    croak("Missing jump_to on save_and_find_story_link!") unless $jump_to;

    # set target and show find screen
    $query->param(path => $jump_to);
    return $self->find_story_link();
}

=item save_and_find_media_link

This mode saves the current element data to the session and goes to
the find_media_link mode in Krang::CGI::ElementEditor.

=cut

sub save_and_find_media_link {
    my $self = shift;

    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    # get target
    my $query   = $self->query;
    my $jump_to = $query->param('jump_to');
    croak("Missing jump_to on save_and_find_media_link!") unless $jump_to;

    # set target and show find screen
    $query->param(path => $jump_to);
    return $self->find_media_link();
}

=item save_and_go_up

This mode saves the current element data to the session and jumps to
edit the parent of this element.

=cut

sub save_and_go_up {
    my $self = shift;

    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    # compute target
    my $query = $self->query;
    my $path  = $query->param('path');
    $path =~ s!/[^/]+$!!;

    # set target and show edit screen
    $query->param(path => $path);
    return $self->edit();
}

# underlying save routine.  returns false on success or HTML to show
# to the user on failure.
sub _save {
    my $self  = shift;
    my $query = $self->query;

    my $category = $session{category};
    croak("Unable to load category from session!")
      unless $category;

    # run element editor save and return to edit mode if errors were found.
    my $elements_ok = $self->element_save(element => $category->element);
    return $self->edit() unless $elements_ok;

    # success, no output
    return '';
}

=item delete

Deletes the category permanently from the database.  Expects a category in
the session.

=cut

sub delete {
    my $self     = shift;
    my $query    = $self->query();
    my $category = $session{category};
    croak("Unable to load category from session!")
      unless $category;

    eval { $category->delete(); };
    if ($@ and ref $@ and $@->isa('Krang::Category::RootDeletion')) {
        add_alert('cant_delete_root', url => $category->url);
        return $self->edit;
    } elsif ($@ and ref $@ and $@->isa('Krang::Category::Dependent')) {
        my $dep = $@->dependents;
        add_alert('category_has_children', url => $category->url)
          if $dep->{category} and @{$dep->{category}};
        add_alert('category_has_stories', url => $category->url)
          if $dep->{story} and @{$dep->{story}};
        add_alert('category_has_media', url => $category->url)
          if $dep->{media} and @{$dep->{media}};
        add_alert('category_has_templates', url => $category->url)
          if $dep->{template} and @{$dep->{template}};
        return $self->edit;
    } elsif ($@) {
        die $@;
    }

    add_message('category_delete', url => $category->url);

    # return to find
    return $self->find;
}

=item delete_selected

Delete all the categories which were checked on the find screen.

=cut

sub delete_selected {
    my $self = shift;

    my $q                    = $self->query();
    my @category_delete_list = ($q->param('krang_pager_rows_checked'));
    $q->delete('krang_pager_rows_checked');

    # No selected categories?  Just return to find without any message
    return $self->find() unless (@category_delete_list);

    # load all objects and sort by URL length, sorts children before
    # parents maximizing chances of delete success
    my @categories = sort { length($b->url) <=> length($a->url) }
      map { pkg('Category')->find(category_id => $_) } @category_delete_list;

    my $err = 0;
    foreach my $category (@categories) {
        eval { $category->delete(); };

        if ($@ and ref $@ and $@->isa('Krang::Category::RootDeletion')) {
            add_alert('cant_delete_root', url => $category->url);
            $err = 1;
        } elsif ($@ and ref $@ and $@->isa('Krang::Category::Dependent')) {
            my $dep = $@->dependents;
            add_alert('category_has_children', url => $category->url)
              if $dep->{category} and @{$dep->{category}};
            add_alert('category_has_stories', url => $category->url)
              if $dep->{story} and @{$dep->{story}};
            add_alert('category_has_media', url => $category->url)
              if $dep->{media} and @{$dep->{media}};
            add_alert('category_has_templates', url => $category->url)
              if $dep->{template} and @{$dep->{template}};
            $err = 1;
        } elsif ($@) {
            die $@;
        }
    }

    add_message('selected_categories_deleted') unless $err;
    return $self->find();
}

=item prepare_copy

Show the Category Copy screen, providing controls to tune the category copy.

=cut

sub prepare_copy {
    my $self = shift;

    my $q = $self->query;

    my $t = $self->load_tmpl('copy.tmpl', associate => $q);

    # get URL of source category and put into template
    my $src_cat = $self->_load_category(param => 'src_category_id');
    $t->param(src_category_url => $src_cat->url);

    # confirm after conflict?
    if ($q->param('confirm_copy')) {
        $t->param(confirm_copy => $q->param('confirm_copy'));
        $q->delete('confirm_copy');
    }

    # remember destination category
    my $dst_cat = $q->param('dst_category');
    $session{KRANG_PERSIST}{pkg('Category')}{category_copy_dst} = $dst_cat
      if $dst_cat;

    # preserve checkbox state
    $self->_preserve_copy_checkbox_state($t);

    # destination category chooser
    my ($cat_chooser_button, $cat_chooser_logic) = category_chooser(
        name        => 'dst_category_id',
        query       => $q,
        label       => localize('Choose'),
        may_edit    => 1,
        allow_clear => 1,
        persistkey  => 'category_copy_dst',
        formname    => 'copy_category',
    );
    $t->param(
        category_chooser_button => $cat_chooser_button,
        category_chooser_logic  => $cat_chooser_logic
    );

    return $t->output;
}

=item execute_copy

Execute the category copy operation.

=cut

sub execute_copy {
    my $self  = shift;
    my $query = $self->query;

    my $src_category_id = $query->param('src_category_id');
    my $dst_category_id = $query->param('dst_category_id');

    # validate the copy form
    return $self->prepare_copy
      unless $self->_validate_copy_form;

    # load template
    my $t = $self->load_tmpl('copy.tmpl', associate => $query);

    # preserve checkbox state
    $self->_preserve_copy_checkbox_state($t);

    # load source category
    my $src_cat = $self->_load_category(param => 'src_category_id');
    my $dst_cat = $self->_load_category(param => 'dst_category_id');

    # we asked the user after some conflict had occured
    if (defined($query->param('non_conflicting'))
        and $query->param('non_conflicting'))
    {
        $self->_do_execute_copy(message => 'copied_category_no_overwrite');

        return $self->find;
    }

    # see if we can copy the category subtree and if asset URL conflicts occur
    eval {
        $src_cat->can_copy_test(
            dst_category => $dst_cat,
            story        => $query->param('copy_story'),
            media        => $query->param('copy_media'),
            template     => $query->param('copy_template'),
            overwrite    => $query->param('overwrite')
        );
    };

    # handle conflicts
    if ($@ and ref($@)) {
        if ($@->isa('Krang::Category::NoEditAccess')) {
            add_alert(
                'no_edit_access_to_existing_destination_category',
                id  => $@->category_id,
                url => $@->category_url
            );
            return $self->prepare_copy;
        } elsif ($@->isa('Krang::Story::CantCheckOut')) {

            # can't copy category subtree, return to copy form
            if (my @stories = @{$@->stories}) {
                add_alert(
                    'cant_checkout_stories_to_resolve_url_conflict',
                    stories => join('<br/>', map { "Story $_->{id} ($_->{url})" } @stories),
                    story_sp => (scalar(@stories) == 1 ? 'story' : 'stories')
                );
                return $self->prepare_copy;
            }
        } elsif ($@->isa('Krang::Category::CopyAssetConflict')) {
            $query->param(confirm_copy => 1);
            return $self->prepare_copy;
        } elsif( $@->isa('Krang::Category::InfiniteRecursion')) {
            add_alert(
                'cant_copy_parent_to_child',
                parent_id => $src_cat->category_id,
                parent_url => $src_cat->url,
                child_id  => $dst_cat->category_id,
                child_url => $dst_cat->url,
            );
            return $self->prepare_copy;
        } else {
            croak("Unknow error: " . $@);
        }
    } elsif ($@) {
        croak $@;
    }

    # we may copy, maybe overwriting existing files
    add_message("conflicting_assets_moved_to_trash") if $query->param('overwrite');
    $self->_do_execute_copy(message => 'copied_category');

    return $self->find;
}

=back

=cut

###########################
####  PRIVATE METHODS  ####
###########################

# Encapculate category save (in case we need to handle permissions)
sub category_save {
    my $self = shift;

    # save category to the database
    my $category = $session{category};
    $category->save();
}

sub autocomplete {
    my $self = shift;
    return autocomplete_values(
        table  => 'category',
        fields => [qw(category_id url)],
    );
}

sub _preserve_copy_checkbox_state {
    my ($self, $template) = @_;
    # copy assets? overwrite exististing files?
    for my $checkbox (qw(copy_story copy_media copy_template overwrite)) {
        my $param       = $self->query->param($checkbox);
        my $session_val = $session{KRANG_PERSIST}{pkg('Category')}{$checkbox};

        my $final_val =
            defined($param)       ? $param
          : defined($session_val) ? $session_val
          : $checkbox eq 'overwrite' ? 0
          :                            1;

        $session{KRANG_PERSIST}{pkg('Category')}{$checkbox} = $final_val;
        $template->param($checkbox => $final_val);
    }
}

sub _load_category {
    my ($self, %args) = @_;
    my $query = $self->query;

    my $category;

    # load category from database or session
    if (my $id = $query->param($args{param})) {

        # load category from DB
        ($category) = pkg('Category')->find(category_id => $id);
        croak("Unable to load Category $id.")
          unless $category;

        $query->delete('category_id');
        $session{category} = $category;
    } else {
        $category = $session{category};
        croak("Unable to load category from session!")
          unless $category;
    }

    return $category;
}

sub _validate_copy_form {
    my $self  = shift;
    my $query = $self->query;

    my $src_category_id = $query->param('src_category_id');
    my $dst_category_id = $query->param('dst_category_id');

    my $src_cat = $self->_load_category(param => 'src_category_id');

    # do we have a destination category
    unless ($dst_category_id) {
        add_alert('missing_copy_destination', id => $src_category_id, url => $src_cat->url);
        $query->param(bad_dst_category => 1);
        return;
    }

    # is it different from the source category
    if ($src_category_id eq $dst_category_id) {
        add_alert(
            'destination_category_equals_source_category',
            id  => $src_category_id,
            url => $src_cat->url
        );
        $query->param(bad_dst_category => 1);
        return;
    }

    return 1;
}

sub _do_execute_copy {
    my ($self, %args) = @_;

    my $query = $self->query;

    my $src_cat = $self->_load_category(param => 'src_category_id');
    my $dst_cat = $self->_load_category(param => 'dst_category_id');

    $src_cat->copy(
        dst_category => $dst_cat,
        story        => $query->param('copy_story'),
        media        => $query->param('copy_media'),
        template     => $query->param('copy_template'),
        overwrite    => $query->param('overwrite'),
    );

    add_message(
        $args{message},
        src_id  => $src_cat->category_id,
        src_url => $src_cat->url,
        dst_id  => $dst_cat->category_id,
        dst_url => $dst_cat->url
    );
}

1;
