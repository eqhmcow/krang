package Krang::CGI::Story;
use strict;
use warnings;

use Krang::Story;
use Krang::ElementLibrary;
use Krang::Log qw(debug assert ASSERT);
use Krang::Session qw(%session);
use Krang::Message qw(add_message);
use Krang::Widget qw(category_chooser);
use Krang::CGI::Workspace;
use Time::Piece;
use Carp qw(croak);

# use base qw(Krang::CGI);
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

The default run-mode (start_mode) for Krang::CGI::Contrib
is 'new_story'.

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
                     find             => 'find',
                     save             => 'save',
                     save_and_jump    => 'save_and_jump',
                     save_and_stay    => 'save_and_stay',
                     delete           => 'delete',
                     delete_categories => 'delete_categories',
                     add_category     => 'add_category',
                     set_primary_category => 'set_primary_category',
                    );

    $self->tmpl_path('Story/');
}

=item new_story

Allows the user to create a new story.  Users choose the type, title,
slug, site/category and cover date on this screen.  Requires no
parameters.  On success, sends user to edit_story with a new story in
their session.  On error, returns to new_story with an error message.

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
    debug("TYPES: " . join(', ', @types));
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
    $template->param(cover_date_selector => $self->_date_input('cover_date'));

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
    my $cover_date = $self->_decode_date('cover_date');

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
    my $story = Krang::Story->new(class => $type,
                                  title => $title,
                                  slug  => $slug,
                                  categories => [ $category_id ],
                                  cover_date => $cover_date);

    # try to save it
    eval { $story->save() };

    # is it a dup?
    if ($@ and ref($@) and $@->isa('Krang::Story::DuplicateURL')) {
        # load duplicate story
        my ($dup) = Krang::Story->find(story_id => $@->story_id);
        add_message('duplicate_url', 
                    story_id => $dup->story_id,
                    url      => $dup->url,
                    which    => join(' and ', 
                                     join(', ',
                                          $story->element->url_attributes),
                                     "site/category"));

        return $self->new_story(bad => ['category_id', 
                                        $story->element->url_attributes] );
    } elsif ($@) {
        # rethrow
        die($@);
    }

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
    $self->SUPER::element_edit(template => $template);
    
    # static data
    $template->param(story_id          => $story->story_id,
                     type              => $story->element->display_name,
                     version           => $story->version,
                     published_version => $story->published_version,
                     url               => $story->url);

    # edit fields for top-level
    if ($self->is_root()) {
        $template->param(is_root           => 1,
                         title             => $story->title,
                         slug              => $story->slug,
                        );
                             # select boxes
        $template->param(cover_date_selector =>
                         $self->_date_input('cover_date', $story->cover_date));
        
        $template->param(priority_selector => scalar
                         $query->popup_menu(-name => 'priority',
                                            -default => $story->priority,
                                            -values => [ 1, 2, 3],
                                            -labels => { 1 => "Low",
                                                         2 => "Medium",
                                                         3 => "High" }));
        my @contribs_loop;
        foreach my $contrib ($story->contribs) {
            push(@contribs_loop, { first_name => $contrib->first_name,
                                   last_name  => $contrib->last_name,
                                   type       => $contrib->selected_contrib_type});
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

=item save

If editing at the root (path = '/') then this mode saves the story to
the database and leaves the story editor.  Otherwise the
Krang::CGI::ElementEditor::save controls the action.

=cut

sub save {
    my $self = shift;
    my %arg  = @_;
    my $query = $self->query;

    # get current path, before element_save gets to it
    my $path  = $query->param('path') || '/';

    my $story = $session{story};
    croak("Unable to load story from session!")
      unless $story;

    # run element editor save and return to edit mode if errors were found.
    my $elements_ok = $self->element_save(@_);
    return $self->edit() unless $elements_ok;
    debug "HERE";

    # if we're saving in the root then save the story itself
    if ($path eq '/') {
        my $title = $query->param('title');
        my $slug = $query->param('slug');
        my $cover_date = $self->_decode_date('cover_date');
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


        my $dest_path = $query->param('path') || '/';
        if ($dest_path eq '/') {
            $story->save();
            
            add_message('story_save', story_id => $story->story_id,
                        url      => $story->url,
                        version  => $story->version);
        }

        # return to workspace if no jump or stay
        return $self->Krang::CGI::Workspace::show_workspace()
          unless $arg{stay} or $arg{jump_to};
        
    }
    
    return $self->edit();
}

sub save_and_stay {
    my $self = shift;
    return $self->save(stay => 1);
}

sub save_and_jump {
    my $self = shift;
    my $query = $self->query();
    return $self->save(jump_to => $query->param("jump_to"));
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
    $story->categories(@categories);
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

    return $self->Krang::CGI::Workspace::show_workspace();
}

=item find

Temporary find stories run-mode.  Just lists all stories and provides
edit links.

=cut

sub find {
    my $self = shift;
    my $template = $self->load_tmpl('find.tmpl');
    
    my @stories = Krang::Story->find();
    my @loop;
    foreach my $story (@stories) {
        push(@loop, {
                     story_id => $story->story_id,
                     url      => $story->url,
                     title    => $story->title,
                    });
    }
    $template->param(story_loop => \@loop);

    return $template->output;
}


# takes a name and an optional date object (Time::Piece::MySQL).
# returns HTML for the widget interface.  If no date is passed
# defaults to now.
sub _date_input {
    my $self = shift;
    my $query = $self->query;
    my ($name, $date) = @_;
    $date ||= localtime;

    my $m_sel = $query->popup_menu(-name      => $name . "_month",
                                   -default   => $date->mon,
                                   -values    => [ 1 .. 12 ],
                                   -labels    => { 1  => 'Jan',
                                                   2  => 'Feb',
                                                   3  => 'Mar',
                                                   4  => 'Apr',
                                                   5  => 'May',
                                                   6  => 'Jun',
                                                   7  => 'Jul',
                                                   8  => 'Aug',
                                                   9  => 'Sep',
                                                   10 => 'Oct',
                                                   11 => 'Nov',
                                                   12 => 'Dec' });
    my $d_sel = $query->popup_menu(-name      => $name . "_day",
                                   -default   => $date->mday,
                                   -values    => [ 1 .. 31 ]);
    my $y_sel = $query->popup_menu(-name      => $name . "_year",
                                   -default   => $date->year,
                                   -values    => [ $date->year - 30 .. 
                                                   $date->year + 10 ]);


    return $m_sel . " " . $d_sel . " " . $y_sel;
}

# decode a date from query input.  Takes a form name, returns a date
# object.
sub _decode_date {
    my ($self, $name) = @_;
    my $query = $self->query;
    
    my $m = $query->param($name . '_month');
    my $d = $query->param($name . '_day');
    my $y = $query->param($name . '_year');
    return undef unless $m and $d and $y;
    debug("$m/$d/$y");

    return Time::Piece->strptime("$m/$d/$y", '%m/%d/%Y');
}

1;

=back

=cut

