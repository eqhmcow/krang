package Krang::CGI::Story;
use strict;
use warnings;

use Krang::Story;
use Krang::ElementLibrary;
use Krang::Log qw(debug assert ASSERT);
use Krang::Session qw(%session);
use Krang::Message qw(add_message);
use Krang::Widget qw(category_chooser date_chooser decode_date);
use Krang::CGI::Workspace;
use Carp qw(croak);
use Krang::Pref;
use Krang::HTMLPager;

use base 'Krang::CGI::ElementEditor';

sub _get_element { $session{story}->element; }

=head1 NAME

Krang::CGI::Story - web interface to manage stories

=head1 SYNOPSIS

  use Krang::CGI::Story;
  Krang::CGI::Story->new()->run();

=head1 DESCRIPTION

=head1 INTERFACE

Following are descriptions of all the run-modes
provided by Krang::CGI::Story.

=head2 Run-Modes

=over 4

=cut

sub setup {
    my $self = shift;
    $self->SUPER::setup();
    $self->mode_param('rm');
    $self->start_mode('new_story');
    
    # add story specific modes to existing set
    $self->run_modes($self->run_modes(),
                     new_story        => 'new_story',
                     create           => 'create',
                     edit             => 'edit',
                     view             => 'view',
                     revert           => 'revert',
                     find             => 'find',
                     delete           => 'delete',
                     delete_selected  => 'delete_selected',
                     checkout_selected => 'checkout_selected',
                     delete_categories    => 'delete_categories',
                     add_category         => 'add_category',
                     set_primary_category => 'set_primary_category',

                     db_save          => 'db_save',
                     db_save_and_stay => 'db_save_and_stay',
                     save_and_jump    => 'save_and_jump',
                     save_and_add     => 'save_and_add',
                     save_and_view    => 'save_and_view',
                     save_and_stay    => 'save_and_stay',
                     save_and_edit_contribs => 'save_and_edit_contribs',
                     save_and_stay    => 'save_and_stay',
                     save_and_go_up   => 'save_and_go_up',
                     save_and_bulk_edit => 'save_and_bulk_edit',
                     save_and_leave_bulk_edit => 'save_and_leave_bulk_edit',
                     save_and_change_bulk_edit_sep => 'save_and_change_bulk_edit_sep',
                     save_and_find_story_link    => 'save_and_find_story_link',
                     save_and_find_media_link    => 'save_and_find_media_link',
                    );

    $self->tmpl_path('Story/');
}

=item new_story (default)

Allows the user to create a new story.  Users choose the type, title,
slug, site/category and cover date on this screen.  Requires no
parameters.  Produces a form which is submitted to the create runmode.

=cut

sub new_story {
    my $self = shift;
    my $query = $self->query;
    my $template = $self->load_tmpl('new.tmpl', associate => $query);
    my %args = @_;
    
    # setup error message if passed in
    if ($args{bad}) {
        $template->param("bad_$_" => 1) for @{$args{bad}}
    }

    
    # setup the type selector
    my @types = grep { $_ ne 'category' } Krang::ElementLibrary->top_levels;
    my %type_labels = 
      map { ($_, Krang::ElementLibrary->top_level(name => $_)->display_name) }
        @types;
    $template->param(type_selector => scalar
                     $query->popup_menu(-name      => 'type',
                                        -default   => '',
                                        -values    => [ ('', @types) ],
                                        -labels    => \%type_labels));    

    $template->param(category_chooser => 
                     category_chooser(name => 'category_id',
                                      query => $query));
    
    # setup date selector
    $template->param(cover_date_selector => date_chooser(name=>'cover_date', query=>$query));

    return $template->output();
}

=item create

Creates a new story object and proceeds to edit_story.  Expects the
form parameters from new_story.  Upon error, returns to new_story with
an error message.  Upon success, goes to edit_story.

=cut

sub create {
    my $self = shift;
    my $query = $self->query;

    my $type = $query->param('type');
    my $title = $query->param('title');
    my $slug = $query->param('slug');
    my $category_id = $query->param('category_id');
    my $cover_date = decode_date(name=>'cover_date', query=>$query);

    # detect bad fields
    my @bad;
    push(@bad, 'type'),        add_message('missing_type')
      unless $type;
    push(@bad, 'title'),       add_message('missing_title')
      unless $title;
    push(@bad, 'slug'),        add_message('missing_slug')
      unless $slug;
    push(@bad, 'category_id'), add_message('missing_category')
      unless $category_id;
    push(@bad, 'cover_date'),  add_message('missing_cover_date')
      unless $cover_date;
    return $self->new_story(bad => \@bad) if @bad;

    # create the object
    my $story;
    eval {
        $story = Krang::Story->new(class => $type,
                                   title => $title,
                                   slug  => $slug,
                                   categories => [ $category_id ],
                                   cover_date => $cover_date);   
    };
    
    # is it a dup?
    if ($@ and ref($@) and $@->isa('Krang::Story::DuplicateURL')) {
        # load duplicate story
        my ($dup) = Krang::Story->find(story_id => $@->story_id);
        my $class = Krang::ElementLibrary->find_class(name => $type);
        add_message('duplicate_url', 
                    story_id => $dup->story_id,
                    url      => $dup->url,                    
                    which    => join(' and ', 
                                     join(', ', $class->url_attributes),
                                     "site/category"),
                   );

        return $self->new_story(bad => ['category_id',$class->url_attributes]);
    } elsif ($@) {
        # rethrow
        die($@);
    }

    # save it
    $story->save();

    # store in session for edit
    $session{story} = $story;

    # toss to edit
    return $self->edit;
}

=item edit

The story editing interface.  Expects to find a story to edit in
$session{story}.

=cut

sub edit {    
    my $self = shift;
    my $query = $self->query;
    my $template = $self->load_tmpl('edit.tmpl', associate => $query, die_on_bad_params => 0, loop_context_vars => 1);
    my %args = @_;
              
    my $story;
    if ($query->param('story_id')) {
        # load story from DB
        ($story) = Krang::Story->find(story_id => $query->param('story_id'));
        croak("Unable to load story '" . $query->param('story_id') . "'.")
          unless $story;

        $query->delete('story_id');
        $session{story} = $story;
    } else {
        $story = $session{story};
        croak("Unable to load story from session!")
          unless $story;
    }
        
    # run the element editor edit
    $self->element_edit(template => $template, 
                        element => $story->element);
    
    # static data
    $template->param(story_id          => $story->story_id,
                     type              => $story->element->display_name,
                     url               => $story->url);

    # edit fields for top-level
    my $path  = $query->param('path') || '/';
    if ($path eq '/' and not $query->param('bulk_edit')) {
        $template->param(is_root           => 1,
                         title             => $story->title,
                         slug              => $story->slug,
                         version           => $story->version,
                         published_version => $story->published_version,
                        );
                             # select boxes
        $template->param(cover_date_selector =>
                         date_chooser(name=>'cover_date', date=>$story->cover_date, query=>$query));
        
        $template->param(priority_selector => scalar
                         $query->popup_menu(-name => 'priority',
                                            -default => $story->priority,
                                            -values => [ 1, 2, 3],
                                            -labels => { 1 => "Low",
                                                         2 => "Medium",
                                                         3 => "High" }));
        my @contribs_loop;
        my %contrib_types = Krang::Pref->get('contrib_type');
        foreach my $contrib ($story->contribs) {
            push(@contribs_loop, { first_name => $contrib->first,
                                   last_name  => $contrib->last,
                                   type       => $contrib_types{$contrib->selected_contrib_type}});
        }
        $template->param(contribs_loop => \@contribs_loop);

        my @category_loop;
        foreach my $cat ($story->categories) {
            my $url = $cat->url;
            my ($site, $dir) = split('/', $url, 2);
            $dir = "/" . $dir;

            push(@category_loop, {
                                  site        => $site,
                                  category    => $dir,
                                  category_id => $cat->category_id });
        }
        $template->param(category_loop => \@category_loop);
        $template->param(category_chooser => 
                         category_chooser(name     => 'new_category_id',
                                          query    => $query,
                                          label    => 'Add Site / Category',
                                          display  => 0,
                                          onchange => 'add_category',
                                         ));

        $template->param(version_selector => scalar
                         $query->popup_menu(-name    => 'version',
                                            -values  => [1 .. $story->version],
                                            -default => $story->version));
    }

    return $template->output();
}


=item view

The story viewing interface.  Requires a return_script parameter with
the name of the script to return to and a list of return_params
parameters containing key/value pairs for the return request.
Optionally, a story_id and a version may be passed.  If a story_id is
not present then a story must be available in the session.

=cut

sub view {    
    my $self = shift;
    my $query = $self->query;
    my $template = $self->load_tmpl('view.tmpl', 
                                    associate         => $query,
                                    die_on_bad_params => 0,
                                    loop_context_vars => 1);
    my %args = @_;
              
    # get story_id from params or from the story in the session
    my $story_id = $query->param('story_id') ? $query->param('story_id') :
                   $session{story}->story_id;
    croak("Unable to get story_id!") unless $story_id;
    
    # load story from DB
    my $version = $query->param('version');
    my ($story) = Krang::Story->find(story_id => $story_id,
                                     (length $version ? 
                                      (version => $version) : ()),
                                    );
    croak("Unable to load story '" . $query->param('story_id') . "'" . 
          (defined $version ? ", version '$version'." : "."))
      unless $story;
    
    # run the element editor edit
    $self->element_view(template => $template, 
                        element  => $story->element);
    
    # static data
    $template->param(story_id          => $story->story_id,
                     type              => $story->element->display_name,
                     url               => $story->url,
                     version           => $story->version);

    if (not $query->param('path') or $query->param('path') eq '/') {
        # fields for top-level
        $template->param(is_root           => 1,
                         title             => $story->title,
                         slug              => $story->slug,
                         published_version => $story->published_version,
                         priority => 
                         ("Low","Medium","High")[$story->priority - 1],
                        );

        $template->param(cover_date => $story->cover_date->mdy("/"))
          if $story->cover_date;

        my @contribs_loop;
        my %contrib_types = Krang::Pref->get('contrib_type');
        foreach my $contrib ($story->contribs) {
            push(@contribs_loop, { first_name => $contrib->first,
                                   last_name  => $contrib->last,
                                   type       => $contrib_types{$contrib->selected_contrib_type}});
        }
        $template->param(contribs_loop => \@contribs_loop);
        
        $template->param(category_loop => 
                         [ map { { url => $_->url } } $story->categories ]);
        
    }

    # setup return form
    croak("Missing return_script and return_params!") 
      unless $query->param('return_params') and $query->param('return_script');
    my %return_params = $query->param('return_params');
    $template->param(return_script => $query->param('return_script'),
                     return_params_loop => 
                     [ map { { name => $_, value => $return_params{$_} } } keys %return_params ]);
    

    return $template->output();
}

=item revert

Revert contents of a story to that of an older version.  Expects a
story in the session and 'version' parameter.  Returns to edit mode
after C<< $story->revert() >>.

=cut

sub revert {
    my $self = shift;
    my $query = $self->query;
    my $version = $query->param('version');
    my $story = $session{story};
    croak("Unable to load story from session!")
      unless $story;

    $story->revert($version);
    add_message('reverted_story', version => $version);

    return $self->edit();
}

=item db_save

This mode saves the story to the database and leaves the story editor,
sending control to workspace.pl.

=cut

sub db_save {
    my $self = shift;

    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    # save story to the database
    my $story = $session{story};
    $story->save();
    
    add_message('story_save', story_id => $story->story_id,
                url      => $story->url,
                version  => $story->version);

    # remove story from session
    delete $session{story};

    # return to my workspace
    $self->header_props(-uri => 'workspace.pl');
    $self->header_type('redirect');
    return;
}


=item db_save_and_stay

This mode saves the story to the database and returns to edit.

=cut

sub db_save_and_stay {
    my $self = shift;

    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    # save story to the database
    my $story = $session{story};
    $story->save();
    
    add_message('story_save', story_id => $story->story_id,
                url      => $story->url,
                version  => $story->version);

    # return to edit
    return $self->edit();
}

=item save_and_jump

This mode saves the current data to the session and jumps to editing
an element within the story.

=cut

sub save_and_jump {
    my $self = shift;

    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    # get target
    my $query = $self->query;
    my $jump_to = $query->param('jump_to');
    croak("Missing jump_to on save_and_jump!") unless $jump_to;
    
    # set target and show edit screen
    $query->param(path => $jump_to);
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

=item save_and_view

This mode saves the current data to the session and passes control to
view to view a version of the story.

=cut

sub save_and_view {
    my $self = shift;
    
    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    my $query = $self->query;
    $query->param('return_script' => 'story.pl');
    $query->param('return_params' => rm => 'edit');
    return $self->view();
}

=item save_and_edit_contribs

This mode saves the current data to the session and passes control to
Krang::CGI::Contrib to edit contributors

=cut

sub save_and_edit_contribs {
    my $self = shift;

    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    # send to contrib editor
    $self->header_props(-uri => 'contributor.pl?rm=associate_story');
    $self->header_type('redirect');
    return;    
}

=item save_and_stay

This mode saves the current element data to the session and returns to
edit.

=cut

sub save_and_stay {
    my $self = shift;

    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    return $self->edit();
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
    my $query = $self->query;
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
    my $query = $self->query;
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
    my $path = $query->param('path');
    $path =~ s!/.+$!!;

    # set target and show edit screen
    $query->param(path => $path);
    return $self->edit();
}


# underlying save routine.  returns false on success or HTML to show
# to the user on failure.
sub _save {
    my $self = shift;
    my $query = $self->query;

    my $story = $session{story};
    croak("Unable to load story from session!")
      unless $story;

    # run element editor save and return to edit mode if errors were found.
    my $elements_ok = $self->element_save(element => $story->element);
    return $self->edit() unless $elements_ok;

    # if we're saving in the root then save the story data
    my $path = $query->param('path') || '/';
    if ($path eq '/' 
        and not $query->param('bulk_edit')) {
        my $title = $query->param('title');
        my $slug = $query->param('slug');
        my $cover_date = decode_date(name=>'cover_date', query=>$query);
        my $priority = $query->param('priority');
        
        my @bad;
        push(@bad, 'title'),       add_message('missing_title')
          unless $title;
        push(@bad, 'slug'),        add_message('missing_slug')
          unless $slug;
        push(@bad, 'cover_date'),  add_message('missing_cover_date')
          unless $cover_date;
        # return to edit mode if there were problems
        return $self->edit(bad => \@bad) if @bad;

        # make changes permanent
        $story->title($title);
        $story->slug($slug);
        $story->cover_date($cover_date);
        $story->priority($priority);
    }
    
    # success, no output
    return '';
}

=item add_category

Adds a category to the story.  Expects a category ID in
new_category_id, which is filled in by the category chooser on the
edit screen.  Returns to edit mode on success and on failure with an
error message.

=cut

sub add_category {
    my $self = shift;
    my $query = $self->query;

    my $story = $session{story};
    croak("Unable to load story from session!")
      unless $story;

    my $category_id = $query->param('new_category_id');
    unless ($category_id) {
        add_message("added_no_category");
        return $self->edit();
    }

    # make sure this isn't a dup
    my @categories = $story->categories();
    if (grep { $_->category_id == $category_id } @categories) {
        add_message("duplicate_category");
        return $self->edit();
    }

    # look up category
    my ($category) = Krang::Category->find(category_id => $category_id);
    croak("Unable to load category '$category_id'!")
      unless $category;

    # push it on
    push(@categories, $category);

    # this might fail if a duplicate URL is created
    eval { $story->categories(@categories); };

    # is it a dup?
    if ($@ and ref($@) and $@->isa('Krang::Story::DuplicateURL')) {
        # load duplicate story
        my ($dup) = Krang::Story->find(story_id => $@->story_id);
        add_message('duplicate_url_on_category_add', 
                    story_id => $dup->story_id,
                    url      => $dup->url,                    
                    category => $category->url,
                   );

        # remove added category
        pop(@categories);
        $story->categories(@categories);

        return $self->edit;
    } elsif ($@) {
        # rethrow
        die($@);
    }

    # success
    add_message('added_category', url => $category->url);

    return $self->edit();
}

=item set_primary_category

Sets the primary category for the story.  Expects a category ID in
primary_category_id, which is filled in by the primary radio group in
the edit screen.  Returns to edit mode on success and on failure with
an error message.

=cut

sub set_primary_category {
    my $self = shift;
    my $query = $self->query;

    my $story = $session{story};
    croak("Unable to load story from session!")
      unless $story;

    my $category_id = $query->param('primary_category_id');
    return $self->edit() unless $category_id;

    # shuffle list of categories to put new primary first
    my (@categories, $url);
    foreach my $cat ($story->categories()) {
        if ($cat->category_id == $category_id) {
            $url = $cat->url;
            unshift(@categories, $cat);
        } else {
            push(@categories, $cat);
        }
    }

    # set it
    $story->categories(@categories);
    add_message('set_primary_category', url => $url);

    return $self->edit();
}


=item delete_categories

Removes categories from the story.  Expects one or more cat_remove_$id
variables set with checkboxes.  Returns to edit mode on success and on
failure with an error message.

=cut

sub delete_categories {
    my $self = shift;
    my $query = $self->query;

    my $story = $session{story};
    croak("Unable to load story from session!")
      unless $story;

    my %delete_ids = map { s/cat_remove_//; ($_, 1) } 
                       grep { /^cat_remove/ } $query->param();

    # shuffle list of categories to remove the deleted
    my (@categories, @urls);
    foreach my $cat ($story->categories()) {
        if ($delete_ids{$cat->category_id}) {
            push(@urls, $cat->url);
        } else {
            push(@categories, $cat);
        }
    }

    # set remaining cats
    $story->categories(@categories);

    # put together a reasonable summary of what happened
    if (@urls == 0) {
        add_message('deleted_no_categories');
    } elsif (@urls == 1) {
        add_message('deleted_a_category', url => $urls[0]);
    } else {
        add_message('deleted_categories', 
                    urls => join(', ', @urls[0..$#urls-1]) . 
                              ' and ' . $urls[-1]);
    }

    return $self->edit();
}

=item delete

Deletes the story permanently from the database.  Expects a story in
the session.

=cut

sub delete {
    my $self = shift;
    my $query = $self->query();
    my $story = $session{story};
    croak("Unable to load story from session!")
      unless $story;

    add_message('story_delete', story_id => $story->story_id,
                                url      => $story->url);
    $story->delete();

    # return to my workspace
    $self->header_props(-uri => 'workspace.pl');
    $self->header_type('redirect');
    return;
}

=item find

List all stories which match the search criteria.  Provide links to 
edit or view each story.  Provide a link to view the log for a story.

Also, provide checkboxes next to each story through which the user may 
select a set of stories to be deleted or checked out to Workplace.

=cut

sub find {
    my $self = shift;

    my $q = $self->query();
    my %tmpl_data = ();

    # Search mode
    my $do_advanced_search = $q->param('do_advanced_search');

    # Set up persist_vars for pager
    my %persist_vars = (
                        rm => 'find',
                        do_advanced_search => $do_advanced_search,
                       );

    # Set up find_params for pager
    my %find_params = ();
    if ($do_advanced_search) {

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
            my $val = $q->param("search_". $_);

            # If no data, skip parameter
            next unless (defined($val) && length($val));

            # Persist parameter
            $persist_vars{"search_". $_} = $val;

            # Like search
            if (grep {$_ eq $key} (qw/title url/)) {
                $key .= '_like';
                $val =~ s/\W+/\%/g;
                $val = "\%$val\%";
            }

            # Set up search in pager
            $find_params{$key} = $val;
        }

        # Set up cover and publish date search
        for my $datetype (qw/cover publish/) {
            my $from = decode_date(query=>$q, name => $datetype .'_from');
            my $to =   decode_date(query=>$q, name => $datetype .'_to');
            if ($from || $to) {
                my $key = $datetype .'_date';
                my $val = [$from, $to];
            
                # Set up search in pager
                $find_params{$key} = $val;
            }

            # Persist parameter
            for my $interval (qw/month day year/) {
                my $from_pname = $datetype .'_from_'. $interval;
                my $to_pname = $datetype .'_to_'. $interval;

                # Only persist date vars if they are complete and valid
                if ($from) {
                    my $from_pname = $datetype .'_from_'. $interval;
                    $persist_vars{$from_pname} = $q->param($from_pname);
                } else {
                    # Blow away var
                    $q->delete($from_pname);
                }

                if ($to) {
                    $persist_vars{$to_pname} = $q->param($to_pname);
                } else {
                    # Blow away var
                    $q->delete($to_pname);
                }
            }

        }

        # If we're showing an advanced search, set up the form
        $tmpl_data{category_chooser} = category_chooser(
                                                        name => 'search_below_category_id',
                                                        query => $q,
                                                        formname => 'search_form',
                                                       );

        # Date choosers
        $tmpl_data{date_chooser_cover_from}   = date_chooser(query=>$q, name=>'cover_from', nochoice=>1);
        $tmpl_data{date_chooser_cover_to}     = date_chooser(query=>$q, name=>'cover_to', nochoice=>1);
        $tmpl_data{date_chooser_publish_from} = date_chooser(query=>$q, name=>'publish_from', nochoice=>1);
        $tmpl_data{date_chooser_publish_to}   = date_chooser(query=>$q, name=>'publish_to', nochoice=>1);

        # Story class
        my @classes = grep { $_ ne 'category' } Krang::ElementLibrary->top_levels;
        my %class_labels = map {
            $_ => Krang::ElementLibrary->top_level(name => $_)->display_name()
        } @classes;
        $tmpl_data{search_class_chooser} = scalar($q->popup_menu(-name      => 'search_class',
                                                                 -default   => '',
                                                                 -values    => [ ('', @classes) ],
                                                                 -labels    => \%class_labels));
    } else {
        # Set up simple search
        my $search_filter = $q->param('search_filter');
        $search_filter = '' unless (defined($search_filter));
        $find_params{simple_search} = $search_filter;
        $persist_vars{search_filter} = $search_filter;
    }

    my $pager = Krang::HTMLPager->new(
                                      cgi_query => $q,
                                      persist_vars => \%persist_vars,
                                      use_module => 'Krang::Story',
                                      find_params => \%find_params,
                                      columns => [qw(
                                                     pub_status 
                                                     story_id 
                                                     url 
                                                     title 
                                                     cover_date 
                                                     command_column 
                                                     status 
                                                     checkbox_column
                                                    )],
                                      column_labels => {
                                                        pub_status => '',
                                                        story_id => 'ID',
                                                        url => 'URL',
                                                        title => 'Title',
                                                        cover_date => 'Date',
                                                        status => 'Status',
                                                       },
                                      columns_sortable => [qw( story_id url title cover_date )],
                                      command_column_commands => [qw( edit_story view_story view_story_log )],
                                      command_column_labels => {
                                                                edit_story     => 'Edit',
                                                                view_story     => 'View',
                                                                view_story_log => 'Log',
                                                               },
                                      row_handler => sub { $self->find_story_row_handler(@_); },
                                      id_handler => sub { return $_[0]->story_id },
                                     );

    # Set up output
    my $template = $self->load_tmpl('find.tmpl', associate=>$q);
    $template->param(%tmpl_data);
    $template->param(pager_html => $pager->output());
    $template->param(row_count => $pager->row_count());

    return $template->output;
}


=item delete_selected

Delete all the stories which were checked on the find screen.

=cut

sub delete_selected {
    my $self = shift;

    my $q = $self->query();
    my @story_delete_list = ( $q->param('krang_pager_rows_checked') );
    $q->delete('krang_pager_rows_checked');

    # No selected stories?  Just return to find without any message
    return $self->find() unless (@story_delete_list);

    foreach my $story_id (@story_delete_list) {
        Krang::Story->delete($story_id);
    }

    add_message('selected_stories_deleted');
    return $self->find();
}


=item checkout_selected

Check out to Workplace all the stories which were checked on the find screen.

=cut

sub checkout_selected {
     my $self = shift;

     my $q = $self->query();
     my @story_checkout_list = ( $q->param('krang_pager_rows_checked') );
     $q->delete('krang_pager_rows_checked');

     # No selected stories?  Just return to find without any message
     return $self->find() unless (@story_checkout_list);

     foreach my $story_id (@story_checkout_list) {
         my ($s) = Krang::Story->find(story_id=>$story_id);
         $s->checkout();
     }

     # Do we go to the edit screen (one story) or Workspace (N stories)?
     if (scalar(@story_checkout_list) > 1) {
         add_message('selected_stories_checkout');

         # Redirect to Workplace
         my $url = "workspace.pl";
         $self->header_props(-url=>$url);
         $self->header_type('redirect');
         return "Redirect: <a href=\"$url\">$url</a>";
     } else {
         add_message('selected_stories_checkout_one');
         return $self->edit();
     }
}





###########################
####  PRIVATE METHODS  ####
###########################


# Pager row handler for story find run-mode
sub find_story_row_handler {
    my $self = shift;
    my ($row, $story) = @_;

    # Columns:
    #

    # story_id
    $row->{story_id} = $story->story_id();

    # format url to fit on the screen and to link to preview
    my $url = $story->url();
    my @parts = split('/', $url);
    my @url_lines = (shift(@parts), "");
    for(@parts) {
        if ((length($url_lines[-1]) + length($_)) > 15) {
            push(@url_lines, "");
        }
        $url_lines[-1] .= "/" . $_;
    }
    $row->{url} = join('<br>', 
                       map { qq{<a href="javascript:preview_story($row->{story_id})">$_</a>} } @url_lines);

    # title
    $row->{title} = $story->title();

    # cover_date
    my $tp = $story->cover_date();
    $row->{cover_date} = (ref($tp)) ? $tp->mdy('/') : '[n/a]';

    # pub_status  -- NOT YET IMPLEMENTED
    $row->{pub_status} = '&nbsp;<b>P</b>&nbsp;';

    # status  -- NOT YET IMPLEMENTED
    $row->{status} = '[n/a]';
    
}


1;

=back

=cut

