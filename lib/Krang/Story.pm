package Krang::Story;
use strict;
use warnings;

=head1 NAME

Krang::Story - the Krang story class

=head1 SYNOPSIS

  $story = Krang::Story->new();

  # checkin/checkout
  $story->checkout();
  $story->checkin();

  # basic setable fields
  $story->title("Life is very long");
  $story->slug("life");
  $story->cover_date(Time::Piece->strptime("%D %R", "1/1/2004 12:00"));


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
L<Krang::Contributor>), assigned scheduled actions (objects of type
L<Krang::CronTask>).

Stories are checked-in, checked-out and versioned like media
(L<Krang::Media>) and templates (L<Krang::Template>).  However, unlike
media and templates, they may also be moved to desks (L<Krang::Desk>).

Stories, unlike media and templates, may be assigned to multiple
categories.  However, one category is the primary category and
determines the primary URI.

=head1 INTERFACE

=head2 Attributes

Story objects are composed of the following attributes.  Unless
otherwise noted all attributes are accessible via standard
accessor/mutators.  For example, the C<title> attribute can be set
with:

  $story->title("New title here");

And accessed with:

  $title = $story->title();

=over

=item story_id (readonly)

=item title

=item slug

=item notes

=item cover_date

=item version

=item category

The primary category for the story.

=item uri (readonly)

The primary URI for the story.

=item categories

A list of category objects associated with the story.

=item uris (readonly)

A list of URIs for this story.

=item contributors

A list of contributor objects associated with the story.

=item element

The root element for this story.  The children of this element contain
the content for the story.

=item schedules

A list of scheduled events for the story.  This is a list of hashes,
each of which has the following keys:

=over

=item type

Will be 'absolute', 'hourly', 'daily', or 'weekly'.

=item date

A Time::Piece object representing the time of the scheduled event.
Its interpretation depends on the type of the schedule.  For
'absolute' this will be a full date.  For 'hourly', this will contain
the minute for the event.  For 'daily', this will contain the time for
the event.  For 'weekly', this will contain the day of the event.

=item action

Either 'publish' or 'expire'.

=item version

For 'publish' events, a specific version may be specified.  If not,
this will be C<undef>.

=back

=item checked_out (readonly)

=item checked_out_by (readonly)

=back

=head2 Methods

=over

=item C<< $story = Krang::Story->new(key => 'val', ...) >>

Creates a new story object.  Any of the available attributes may be
set with key/value pairs passed to new().

=item C<< $copy = Krang::Story->clone() >>

Creates a copy of the story object, with all fields identical except
C<story_id> which will be C<undef>.

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

=item uri 

Search by uri.

=item primary_uri 

Search by primary uri.

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

Checkout the story, preventing other users from editing it.  Croaks if
the story is already checked out.

=item C<< $story->checkin() >>

Checkin the story, allow other users to check it out.  This will only
fail if the story is not checked out.

=back

=cut


1;
