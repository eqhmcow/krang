package Krang::Story;
use strict;
use warnings;

use Krang::Element;
use Krang::Category;
use Krang::Log qw(assert ASSERT affirm debug info critical);

use Carp qw(croak);

# create accessors for object fields
use Krang::MethodMaker 
  new_with_init => 'new',
  new_hash_init => 'hash_init',
  get           => [ qw(
                        story_id                        
                        version
                        class
                        checked_out
                        checked_out_by
                       ) ],
  get_set       => [ qw(
                        title
                        slug
                        notes
                        cover_date
                        publish_date
                        priority
                        schedules
                       ) ];

=head1 NAME

Krang::Story - the Krang story class

=head1 SYNOPSIS

  $story = Krang::Story->new(title      => "Foo",
                             slug       => 'foo',
                             class      => 'article',
                             categories => [10, 20]);

  # checkin/checkout
  $story->checkout();
  $story->checkin();

  # basic setable fields
  $story->title("Life is very long");
  $story->slug("life");
  $story->cover_date(Time::Piece->strptime("%D %R", "1/1/2004 12:00"));
  $story->priority(3);

  # get the root element for this story
  my $element = $story->element();

  # add a schedule
  my $sched = $story->schedules();
  push(@$sched, { type   => "absolute",
                  date   => Time::Piece->new(),
                  action => "publish" });


  # find some stories about Sam
  my @stories = Krang::Story->find(title_like => '%sam%');

  # load a single story by id
  my ($story) = Krang::Story->find(story_id => 1);

  # load a group of stories by id
  my ($story) = Krang::Story->find(story_ids => [1, 20, 30, 100]);

  

=head1 DESCRIPTION

This class provides methods to operate on story objects.  A story
contains some story-specific data (title, cover date, etc.) and an
element tree rooted in C<element>, an object of the L<Krang::Element>
class.

Stories may be associated with contributors (objects of
L<Krang::Contributor>) and assigned scheduled actions (publish and expire).

Stories are checked-in, checked-out and versioned like media
(L<Krang::Media>) and templates (L<Krang::Template>).  However, unlike
media and templates, they may also be moved to desks (L<Krang::Desk>).

Stories may be assigned to multiple categories.  However, one category
is the primary category and determines the primary URL.

=head1 INTERFACE

=head2 Attributes

Story objects are composed of the following attributes.  Unless
otherwise noted all attributes are accessible via standard
accessor/mutators.  For example, the C<title> attribute can be set
with:

  $story->title("New title here");

And accessed with:

  $title = $story->title();

If an attribute is marked (readonly) then its value cannot be set.
For example, you may not set C<checked_out> directly; instead, call
the checkout() method.

=over

=item C<story_id> (readonly)

=item C<title>

=item C<slug>

=item C<notes>

=item C<priority>

A number from 1 (meaning low priority) to 3 (meaning high priority).

=item C<cover_date>

A Time::Piece object representing an arbitrary cover date.

=item C<publish_date>

A Time::Piece object containing the date and time this story was last
published.

=item C<version> (readonly)

=item C<category> (readonly)

The primary category for the story.  C<undef> until at least one
category is assigned.  This is just a convenience method that returns
the first category in categories.

=cut

sub category {
    my $self = shift;

    # return from the category cache if available
    return $self->{category_cache}[0]
      if $self->{category_cache} and $self->{category_cache}[0];

    # otherwise, lookup from id list
    my ($category) = 
      Krang::Category->find(category_id => $self->{category_ids}[0]);
    $self->{category_cache}[0] = $category;

    return $category;
}

=item C<url> (readonly)

The primary URL for the story.  C<undef> until at least one category
is assigned.

=cut

sub url {
    my $self = shift;
    croak "illegal attempt to set readonly attribute 'url'.\n"
      if @_;
    
    # return from the url cache if available
    return $self->{url_cache}[0]
      if $self->{url_cache} and $self->{url_cache}[0];

    # otherwise, compute using element 
    my $url = $self->element->build_url(story => $self,
                                        category => $self->category);
    $self->{url_cache}[0] = $url;

    return $url;
}

=item C<categories>

A list of category objects associated with the story.  The first
category in this list is the primary category.

This attribute may be assigned with category_ids or Krang::Category
objects.  Only objects will be returned.

This attribute may be set with a list or an array-ref.  For example:

  # same result
  $story->categories(1024, 1028);
  $story->categories([1024, 1028]);

But a list of objects is always returned:

  @categories = $story->categories;

=cut

sub categories {
    my $self = shift;

    # get
    unless (@_) {
        # load the cache as necessary
        for (0 .. $#{$self->{category_ids}}) {
            next if  $self->{category_cache}[$_];
            ($self->{category_cache}[$_]) =
              Krang::Category->find(category_id => $self->{category_ids}[$_]);
            croak("Unable to load category '$self->{category_ids}[$_]'")
              unless $self->{category_cache}[$_];
        }
        return @{$self->{category_cache}};
    }

    # else, set

    # transform array ref to list
    @_ = @{$_[0]} if @_ == 1 and ref($_[0]) and ref($_[0]) eq 'ARRAY';
    
    # fill in category_id list
    $self->{category_ids} = 
      [ map { ref $_ ? $_->category_id : $_ } @_ ];
    
    # fill cache with objects passed in, delay loading if just passed IDs
    $self->{category_cache} = 
      [ map { ref $_ ? $_ : undef } @_ ];
    
    # invalidate url cahce
    $self->{url_cache} = [];

    # they should all fetch correctly now, which won't be true
    # if a bad ID was passed in
    assert($self->categories) if ASSERT;
}

=item C<urls> (readonly)

A list of URLs for this story, in order by category.

=cut

sub urls {
    my $self = shift;
    croak "illegal attempt to set readonly attribute 'urls'.\n"
      if @_;

    # load the url cache as necessary
    for (0 .. $#{$self->{category_ids}}) {
        next if $self->{url_cache}[$_];

        # load category if needed
        unless ($self->{category_cache}[$_]) {
            ($self->{category_cache}[$_]) =
              Krang::Category->find(category_id => $self->{category_ids}[$_]);
        }

        # build url
        $self->{url_cache}[$_] = 
          $self->element->build_url(story => $self,
                                    category => $self->{category_cache}[$_]);
    }
    return @{$self->{url_cache}};
}

=item C<contributors>

A list of contributor objects associated with the story.

=item C<element>

The root element for this story.  The children of this element contain
the content for the story.

=cut

sub element { shift->{element} }

=item C<class> (readonly)

The element class of the root element (i.e. $story->element->class).

=item C<schedules>

A list of scheduled events for the story.  This is a list of hashes,
each of which has the following keys:

=over

=item C<type>

Must be one of 'absolute', 'hourly', 'daily', or 'weekly'.

=item C<date>

A Time::Piece object representing the time of the scheduled event.
Its interpretation depends on the type of the schedule.  For
'absolute' this will be a full date.  For 'hourly', this will contain
the minute for the event.  For 'daily', this will contain the time for
the event.  For 'weekly', this will contain the day of the event.

=item C<action>

Either 'publish' or 'expire'.

=item C<version>

For 'publish' events, a specific version may be specified.  If not,
this will be C<undef>.

=back

=item C<checked_out> (readonly)

=item C<checked_out_by> (readonly)

=back

=cut

=head2 Methods

=over

=item C<< $story = Krang::Story->new(class => 'Article', categories => [$cat, 1024, 1034], slug => "foo", title => "Foo") >>

Creates a new story object.  Any object attribute listed can be set in
new(), but C<class>, C<categories>, C<slug> and C<title> are all
required.  After this call the object is guaranteed to be in a valid
state and may be saved immediately with C<save()>.

=cut

sub init {
    my ($self, %args) = @_;
    exists $args{$_} or croak("Missing required parameter '$_'.")
      for ('class', 'categories', 'slug', 'title');

    # create a new element based on class
    $self->{class} = delete $args{class};
    $self->{element} = Krang::Element->new(class => $self->{class});

    # finish the object, calling set methods for each key/value pair
    $self->hash_init(%args);

    return $self;
}

=item C<< @stories = Krang::Story->find(title => "Turtle Soup") >>

=item C<< @story_ids = Krang::Story->find(title => "Turtle Soup", ids_only => 1) >>

=item C<< $count = Krang::Story->find(title => "Turtle Soup", count => 1) >>

Finds stories in the database based on supplied criteria.  

Fields may be matched using SQL matching.  Appending "_like" to a
field name will specify a case-insensitive SQL match.  For example, to
match a sub-string inside title:

  @stories = Krang::Story->find(title_like => '%' . $search . '%');

Notice that it is necessary to surround terms with '%' to perform
sub-string matches.

Available search options are:

=over

=item title 

Search by title.

=item slug 

Search by slug.

=item url 

Search by url.

=item primary_url 

Search by primary url.

=item category_id

Find stories by category.

=item primary_category_id

Find stories by category, looking only at the primary location.

=item site_id

Find stories by site.

=item primary_site_id

Find stories by site, looking only at the primary location.

=item checked_out

Set to 0 to find only non-checked-out stories.  Set to 1 to find only
checked out stories.  The default, C<undef> returns all stories.

=item checked_out_by

Set to a user_id to find stories checked-out by a user.

=item contributor_id

Set to a contributor_id to find stories associated with that contributor.

=item link_to_story

Set to a story_id to find stories that link to a specified story.

=item link_to_media

Set to a media_id to find stories that link to a specified media
object.

=item cover_date

May be either a single date (a L<Time::Piece> object) or an array of
dates specifying a range.  In ranges either member may be C<undef>,
specifying no limit in that direction.

=item story_id

Load a story by ID.

=item story_ids

Given an array of story IDs, loads the identified stories.

=back

Options affecting the search and the results returned:

=over

=item ids_only

Return only IDs, not full story objects.

=item count

Return just a count of the results for this query.

=item limit

=item offset

=item order_by

=item order_desc

=back

=item C<< $story->save() >>

Save the story to the database.  This is the only call which will make
permanent changes in the database (checkin/checkout make transient
changes).

=item C<< $story->checkout() >>

=item C<< Krang::Story->checkout($story_id) >>

Checkout the story, preventing other users from editing it.  Croaks if
the story is already checked out.

=item C<< $story->checkin() >>

Checkin the story, allow other users to check it out.  This will only
fail if the story is not checked out.

=item C<< $story->prepare_for_edit() >>

Copy current version of story into versioning table.  Will only work
for objects that have been saved (not new objects).

=item C<< $story->revert($version) >>

Loads an old version of this story into the current story object.
Saving this object will create a new version, but with the contents of
the old version, thus reverting the contents of the story.

=item C<< $story->delete() >>

=item C<< Krang::Story->delete($story_id) >>

Deletes a story from the database.  This is a permanent operation.

=item C<< $copy = Krang::Story->clone() >>

Creates a copy of the story object, with all fields identical except
for C<story_id> and C<< element->element_id >> which will both be
C<undef>.

=back

=cut


1;
