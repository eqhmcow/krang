package Krang::CGI::Story;
use strict;
use warnings;

use Krang::Story;
use Krang::ElementLibrary;
use Krang::Log qw(debug assert ASSERT);
use Krang::Session qw(%session);
use Krang::Message qw(add_message);
use Krang::Widget qw(category_chooser);
use Time::Piece;

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
                     'new_story' => 'new_story',
                     'create'    => 'create');

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
    }

    # prepare story for editing
    $story->prepare_for_edit();   

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
    
    my $story = $session{story};
    croak("Unable to load story from session!")
      unless $story;

    # run the element editor edit
    $self->SUPER::element_edit(template => $template);
    
    # static data
    $template->param(story_id          => $story->story_id,
                     type              => $story->element->display_name,
                     version           => $story->version,
                     published_version => $story->published_version,
                     url               => $story->url);

    # edit fields for top-level
    if (not defined $query->param('path') or $query->param('path') eq '/') {
        $template->param(root_edit         => 1,
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
    }

    return $template->output();
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

