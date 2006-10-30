package Krang::Story;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader Element => qw(foreach_element);
use Krang::ClassLoader 'Category';
use Krang::ClassLoader History => qw( add_history );
use Krang::ClassLoader Log => qw(assert ASSERT affirm debug info critical);
use Krang::ClassLoader DB => qw(dbh);
use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader 'Pref';
use Krang::ClassLoader 'UUID';
use Carp           qw(croak);
use Storable       qw(nfreeze thaw);
use Time::Piece::MySQL;
use File::Spec::Functions qw(catdir canonpath);

# setup exceptions
use Exception::Class 
  'Krang::Story::DuplicateURL'         => { fields => [ 'story_id' ] },
  'Krang::Story::MissingCategory'      => { fields => [ ] },
  'Krang::Story::NoCategoryEditAccess' => { fields => [ 'category_id' ] },
  'Krang::Story::NoEditAccess'         => { fields => [ 'story_id' ] },
  ;
  
# create accessors for object fields
use Krang::ClassLoader MethodMaker => 
  new_with_init => 'new',
  new_hash_init => 'hash_init',
  get           => [ qw(
                        story_id
                        story_uuid
                        version
                        checked_out
                        checked_out_by
                        may_see
                        may_edit
                        hidden
                       ) ],
  get_set_with_notify => [ { 
                            method => '_notify',
                            attr => [ qw(
                                         title
                                         slug
                                         notes
                                         cover_date
                                         publish_date
                                         published_version
                                         preview_version
                                         priority
                                         desk_id
                                        ) ]
                           } ];

# fields in the story table, aside from story_id
use constant STORY_FIELDS =>
  qw( story_id
      story_uuid
      version
      title
      slug
      cover_date
      publish_date
      published_version
      preview_version
      notes
      priority
      element_id
      class
      checked_out
      checked_out_by
      desk_id
      hidden
    );

# called by get_set_with_notify attibutes.  Catches changes that must
# invalidate the URL cache.
sub _notify {
    my ($self, $which, $old, $new) = @_;
    $self->{url_attributes} ||=
      { map { $_ => 1 } $self->class->url_attributes };
    return unless exists $self->{url_attributes}{$which};
    return if defined $old and defined $new and $old eq $new;
    return if not defined $old and not defined $new;
    $self->{url_cache} = [];
}

=head1 NAME

Krang::Story - the Krang story class

=head1 SYNOPSIS

  # create a new story
  $story = pkg('Story')->new(title      => "Foo",
                             slug       => 'foo',
                             class      => 'article',
                             categories => [10, 20]);

  # basic setable fields
  $story->title("Life is very long");
  $story->slug("life");
  $story->cover_date(Time::Piece->strptime("%D %R", "1/1/2004 12:00"));
  $story->priority(3);

  # get the root element for this story
  my $element = $story->element();

  # add contributors
  $story->contribs(@contribs);

  # find some stories about Sam
  my @stories = pkg('Story')->find(title_like => '%sam%');

  # load a single story by id
  my ($story) = pkg('Story')->find(story_id => 1);

  # load a group of stories by id
  my ($story) = pkg('Story')->find(story_ids => [1, 20, 30, 100]);

  # save a story, incrementing version
  $story->save();

  # check it in, now other people can check it out
  $story->checkin();

  # checkout the story, no one else can edit it now
  $story->checkout();

  # revert to version 1
  $story->revert(1);

  # get list of stories linked to from this story
  my @linked_stories = $story->linked_stories;

  # get list of media linked to from this story
  my @linked_media = $story->linked_media;

=head1 DESCRIPTION

This class provides methods to operate on story objects.  A story
contains some story-specific data (title, cover date, etc.) and an
element tree rooted in C<element>, an object of the L<Krang::Element>
class.

Stories may be associated with contributors (objects of
L<Krang::Contrib>) and assigned scheduled actions (publish and
expire).

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

=item C<story_uuid> (readonly)

Unique ID for stories, valid across different machines when the story
is moved via krang_export and krang_import.

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

=item C<desk_id>

Returns the ID of the L<Krang::Desk> that the story is currently on,
if any.  Also see $story->C<move_to_desk()> below.

=item C<version> (readonly)

The current version of the story.  Starts at 1, incremented every time
the story is saved.

=item C<published_version> (readonly)

Returns the version of the story that is currently published on the
website.

Returns 0 if the story has never been published.

=item C<preview_version> (readonly)

Returns the version of the story that has most recently been
previewed.

Returns 0 if the story has never been previewed.

=item C<category> (readonly)

The primary category for the story.  C<undef> until at least one
category is assigned.  This is just a convenience method that returns
the first category in C<categories>.

=cut

sub category {
    my $self = shift;
    return undef unless @{$self->{category_ids}};

    # return from the category cache if available
    return $self->{category_cache}[0]
      if $self->{category_cache} and $self->{category_cache}[0];

    # otherwise, lookup from id list
    my ($category) = 
      pkg('Category')->find(category_id => $self->{category_ids}[0]);
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
    return undef unless @{$self->{category_ids}};

    # return from the url cache if available
    return $self->{url_cache}[0]
      if $self->{url_cache} and $self->{url_cache}[0];

    # otherwise, compute using element 
    my $url = $self->class->build_url(story => $self,
                                      category => $self->category);
    $self->{url_cache}[0] = $url;

    return $url;
}

=item C<preview_url> (readonly)

The primary preview URL for the story.  C<undef> until at least one
category is assigned.

=cut

sub preview_url {
    my $self = shift;
    croak "illegal attempt to set readonly attribute 'preview_url'.\n"
      if @_;
    my $url = $self->url;
    my $site = $self->category->site;
    my $site_url = $site->url;
    my $site_preview_url = $site->preview_url;
    $url =~ s/^\Q$site_url\E/$site_preview_url/;

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

This method may throw a Krang::Story::DuplicateURL exception if you
add a new category and it generates a duplicate URL.  When this
exception is thrown the category list is still changed and you may
continue to operate on the story.  However, if you try to call save()
you will receive the same exception.

=cut

sub categories {
    my $self = shift;

    # get
    unless (@_) {
        # load the cache as necessary
        for (0 .. $#{$self->{category_ids}}) {
            next if  $self->{category_cache}[$_];
            ($self->{category_cache}[$_]) =
              pkg('Category')->find(category_id => $self->{category_ids}[$_]);
            croak("Unable to load category '$self->{category_ids}[$_]'")
              unless $self->{category_cache}[$_];
        }
        return $self->{category_cache} ? @{$self->{category_cache}} : ();
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

    # invalidate url cache
    $self->{url_cache} = [];

    # make sure this change didn't cause a conflict
    $self->_verify_unique();
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
              pkg('Category')->find(category_id => $self->{category_ids}[$_]);
        }

        # build url
        $self->{url_cache}[$_] = 
          $self->element->build_url(story => $self,
                                    category => $self->{category_cache}[$_]);
    }
    return @{$self->{url_cache}};
}

=item C<preview_urls> (readonly)

A list of preview URLs for this story, in order by category.

=cut

sub preview_urls {
    my $self = shift;
    croak "illegal attempt to set readonly attribute 'preview_url'.\n"
      if @_;
    my @urls = $self->urls;
    my @cats = $self->categories;

    for (my $i = 0; $i <= $#urls; $i++) {
        my $url         = $cats[$i]->url;
        my $preview_url = $cats[$i]->preview_url;

        $urls[$i] =~ s/^\Q$url\E/$preview_url/;
    }

    return @urls;
}

=item C<contribs>

A list of contributor objects associated with the story.  See the
contribs() method for interface details.

=item C<element> (readonly)

The root element for this story.  The children of this element contain
the content for the story.

=cut

sub element { 
    my $self = shift;
    return $self->{element} if $self->{element};
    ($self->{element}) = 
      pkg('Element')->load(element_id => $self->{element_id}, object => $self);
    return $self->{element};
}

=item C<class> (readonly)

The element class of the root element.  This may be set with a string
or a Krang::ElementClass object, but only through new().  After new()
this method returns the class object for the root element, a
descendent of Krang::ElementClass.  Another way to access the same
object is object is through C<< $story->element->class >>, but calling
C<< $story->class >> avoids loading the element tree for the story if
it hasn't already been loaded.

=cut

sub class {
    return pkg('ElementLibrary')->top_level(name => $_[0]->{class});
}

=item C<checked_out> (readonly)

=item C<checked_out_by> (readonly)

=item C<hidden> (readonly)

Whether or not the story is by default hidden from C<find()>.  This is
determined by the story class, and set in
L<Krang::ElementClass::TopLevel>.

=back

=cut

=head2 Methods

=over

=item C<< $story = Krang::Story->new(class => 'Article', categories => [$cat, 1024, 1034], slug => "foo", title => "Foo") >>

Creates a new story object.  Any object attribute listed can be set in
new(), but C<class>, C<categories>, C<slug> and C<title> are all
required.  After this call the object is guaranteed to be in a valid
state and may be saved immediately with C<save()>.

Will throw a Krang::Story::DuplicateURL exception with a story_id
field if saving this story would conflict with an existing story.

=cut

sub init {
    my ($self, %args) = @_;
    exists $args{$_} or croak("Missing required parameter '$_'.")
      for ('class', 'categories', 'slug', 'title');
    croak("categories parameter must be an ARRAY ref.")
      unless ref $args{categories} and ref $args{categories} eq 'ARRAY';
    croak("categories parameter must contain at least one catgeory")
      unless @{$args{categories}} and 
        ( UNIVERSAL::isa($args{categories}[0], 'Krang::Category') or
          ( defined $args{categories}[0] and $args{categories}[0] =~ /^\d+$/));

    # create a new element based on class
    $self->{class} = delete $args{class};
    croak("Missing required 'class' parameter to pkg('Story')->new()")
      unless $self->{class};
    $self->{element} = pkg('Element')->new(class => $self->{class}, 
                                           object => $self);

    # get hash of url_attributes
    $self->{url_attributes} = 
      { map { $_ => 1 } $self->class->url_attributes };

    # determine if this story should be hidden or not
    $self->{hidden} = $self->class->hidden;

    # setup defaults
    $self->{version}           = 0;
    $self->{published_version} = 0;
    $self->{preview_version}   = 0;
    $self->{priority}          = 2;
    $self->{checked_out}       = 1;
    $self->{checked_out_by}    = $ENV{REMOTE_USER};
    $self->{cover_date}        = Time::Piece->new();
    $self->{story_uuid}        = pkg('UUID')->new;

    # Set up temporary permissions
    $self->{may_see} = 1;
    $self->{may_edit} = 1;

    # handle categories setup specially since it needs to call
    # _verify_unique which won't work right without an otherwise
    # complete object.
    my $categories = delete $args{categories};

    # finish the object, calling set methods for each key/value pair
    $self->hash_init(%args);

    # setup categories
    $self->categories(@$categories);

    return $self;
}

=item @contribs = $story->contribs();

=item $story->contribs({ contrib_id => 10, contrib_type_id => 1 }, ...);

=item $story->contribs(@contribs);

Called with no arguments, returns a list of contributor
(Krang::Contrib) objects.  These objects will have
C<selected_contrib_type> set according to their use with this story
object.

May be set two ways.  First, a contributor may specified as a two-key
hash containing the contrib_id and the contrib_type_id for the
contributor.  A single contributor can be present in the list multiple
times with different contrib_type_ids.

Second, a list of contributor objects with selected_contrib_type() set
may be passed in.

=cut

sub contribs {
    my $self = shift;
    my @contribs;

    unless (@_) {
        my $contrib;
        # return contributor objects
        foreach my $id (@{$self->{contrib_ids}}) {
            ($contrib) = pkg('Contrib')->find(contrib_id => $id->{contrib_id});
            croak("No contributor found with contrib_id ". $id->{contrib_id})
              unless $contrib;
            $contrib->selected_contrib_type($id->{contrib_type_id});
            push @contribs, $contrib;
        }
        return @contribs; 
    }

    # store list of contributors, passed as either objects or hashes
    foreach my $rec (@_) {
        if (ref($rec) and ref($rec) eq 'HASH') {
            croak("invalid data passed to contribs: hashes must contain contrib_id and contrib_type_id.")
              unless $rec->{contrib_id} and $rec->{contrib_type_id};

            push(@contribs, $rec);
        } elsif (ref($rec) and $rec->isa(pkg('Contrib'))) {
            croak("invalid data passed to contrib: contributor objects must have contrib_id and selected_contrib_type set.")
              unless $rec->contrib_id and $rec->selected_contrib_type;

            push(@contribs, { contrib_id     => $rec->contrib_id,
                              contrib_type_id=> $rec->selected_contrib_type });

        } else {
            croak("invalid data passed to contribs");
        }

        $self->{contrib_ids} = \@contribs;
    }    
}

=item $story->clear_contribs()

Removes all contributor associatisons.

=cut

sub clear_contribs { shift->{contrib_ids} = []; }


=item C<< $story->save() >>

=item C<< $story->save(keep_version => 1) >>

Save the story to the database.  This is the only call which will make
permanent changes in the database (checkin/checkout make transient
changes).  Increments the version number unless called with
'keep_version' set to 1.

Will throw a Krang::Story::DuplicateURL exception with a story_id
field if saving this story would conflict with an existing story.

Will throw a Krang::Story::MissingCategory exception if this story
doesn't have at least one category.  This can happen when a clone()
results in a story with no categories.

Will throw a Krang::Story::NoCategoryEditAccess exception if the
current user doesn't have edit access to the primary category set for
the story.

Will throw a Krang::Story::NoEditAccess exception if the
current user doesn't have edit access to the story.

=cut

sub save {
    my $self = shift;
    my %args = @_;

    # make sure it's ok to save
    $self->_verify_checkout();

    # make sure we've got at least one category
    Krang::Story::MissingCategory->throw(message => "missing category")
        unless $self->category;

    # Is user allowed to otherwise edit this object?
    Krang::Story::NoEditAccess->throw( message => "Not allowed to edit story", story_id => $self->story_id )
        unless ($self->may_edit);

    # make sure we have edit access to the primary category
    Krang::Story::NoCategoryEditAccess->throw( 
       message => "Not allowed to edit story in this category",
       category_id => $self->category->category_id)
        unless ($self->category->may_edit);
    
    # make sure it's got a unique URI
    $self->_verify_unique();

    # update the version number
    $self->{version}++ unless $args{keep_version};

    # save element tree, populating $self->{element_id}
    $self->_save_element();

    # save core data, populating story_id
    $self->_save_core();

    # save categories
    $self->_save_cat();

    # save schedules
    $self->_save_schedules($args{keep_version});

    # save contributors
    $self->_save_contrib;

    # save a serialized copy in the version table
    $self->_save_version;

    # register creation if is the first version
    add_history(    object => $self, 
                    action => 'new',
               )
      if $self->{version} == 1 and not $args{keep_version};

    # register the save
    add_history(    object => $self, 
                    action => 'save',
               );
}

# save core Story data
sub _save_core {
    my $self   = shift;
    my $dbh    = dbh();
    my $update = $self->{story_id} ? 1 : 0;

    # write an insert or update query for the story
    my $query;
    if ($update) {
        # update version
        $query = 'UPDATE story SET ' . 
          join(', ', map { "$_ = ?" } STORY_FIELDS) . ' WHERE story_id = ?';
    } else {
        $query = 'INSERT INTO story (' . join(', ', STORY_FIELDS) .
          ') VALUES (' . join(',', ("?") x STORY_FIELDS) . ')';
    }

    my @data;
    foreach (STORY_FIELDS) {
        if (/_date$/) {
            push(@data, $self->{$_} ? $self->{$_}->mysql_datetime : undef);
        } else {
            push(@data, $self->{$_});
        }
    }

    # do the insert or update
    $dbh->do($query, undef, @data,
             ($update ? $self->{story_id} : ()));

    # extract the ID on insert
    $self->{story_id} = $dbh->{mysql_insertid}
      unless $update;
}


# save the element tree
sub _save_element {
    my $self = shift;
    return unless $self->{element}; # if the element tree was never
                                    # loaded, it can't have changed
    $self->{element}->save();
    $self->{element_id} = $self->{element}->element_id;
}

# save schedules
sub _save_schedules {
    my $self = shift;
    my $keep_version = shift;
    
    # if this is the first save, save default schedules with story
    return unless $self->{version} == 1 and not $keep_version;
    foreach my $sched ($self->element->default_schedules) {
        $sched->save();
    }
}

# save category assignments
sub _save_cat {
    my $self = shift;
    my $dbh = dbh();

    # delete existing relations
    $dbh->do('DELETE FROM story_category WHERE story_id = ?',
             undef, $self->{story_id});

    # insert category relations, including urls
    my @urls       = $self->urls;
    my @cat_ids    = @{$self->{category_ids}};
    for (0 .. $#cat_ids) {
        $dbh->do('INSERT INTO story_category (story_id, category_id, ord, url)
                  VALUES (?,?,?,?)', undef,
                 $self->{story_id}, $cat_ids[$_], $_, $urls[$_]);
    }
}

# save contributors
sub _save_contrib {
    my $self = shift;
    my $dbh = dbh();

    $dbh->do('DELETE FROM story_contrib WHERE story_id = ?',
             undef, $self->{story_id});

    my $ord = 0;
    $dbh->do('INSERT INTO story_contrib 
                    (story_id, contrib_id, contrib_type_id, ord)
                  VALUES (?,?,?,?)', undef,
             $self->{story_id}, $_->{contrib_id}, 
             $_->{contrib_type_id}, ++$ord)
      for @{$self->{contrib_ids}};
}

# save to the version table
sub _save_version {
    my $self = shift;
    my $dbh  = dbh;

    # save version
    $dbh->do('REPLACE INTO story_version (story_id, version, data) 
              VALUES (?,?,?)', undef, 
            $self->{story_id}, $self->{version}, nfreeze($self));

}

# check for duplicate URLs
sub _verify_unique {
    my $self   = shift;
    my $dbh    = dbh;

    # lookup dup
    my @urls  = $self->urls;
    return unless @urls;

    my $query = 'SELECT story_id FROM story_category WHERE ('.
      join(' OR ', ('url = ?') x @urls) . ')' . 
        ($self->{story_id} ? ' AND story_id != ?' : '');
    my ($dup_id) = $dbh->selectrow_array($query, undef, $self->urls, 
                                         ($self->{story_id} ? 
                                          ($self->{story_id}) : ()));

    # throw exception on dup
    Krang::Story::DuplicateURL->throw(message => "duplicate URL",
                                      story_id => $dup_id)
        if $dup_id;

}

=item C<< @stories = Krang::Story->find(title => "Turtle Soup") >>

=item C<< @story_ids = Krang::Story->find(title => "Turtle Soup", ids_only => 1) >>

=item C<< $count = Krang::Story->find(title => "Turtle Soup", count => 1) >>

Finds stories in the database based on supplied criteria.  

Fields may be matched using SQL matching.  Appending "_like" to a
field name will specify a case-insensitive SQL match.  For example, to
match a sub-string inside title:

  @stories = pkg('Story')->find(title_like => '%' . $search . '%');

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

=item non_primary_url

Search by non-primary url.

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

Set to a contributor_id to find stories associated with that contributor.  B<NOT IMPLEMENTED>

=item link_to_story

Set to a story_id to find stories that link to a specified story.  B<NOT IMPLEMENTED>

=item link_to_media

Set to a media_id to find stories that link to a specified media
object. B<NOT IMPLEMENTED>

=item cover_date

May be either a single date (a L<Time::Piece> object) or an
array of dates specifying a range.  In ranges either member may be
C<undef>, specifying no limit in that direction.

=item publish_date

May be either a single date (a L<Time::Piece> object) or an
array of dates specifying a range.  In ranges either member may be
C<undef>, specifying no limit in that direction.

=item class

Set this to an element class name to limit results to only those
containing that class.  Multiple classes may be passed via an array
ref.

=item contrib_simple

This performs a simple search against contributors and finds stories
which link to the contributor.

=item story_id

Load a story by ID.  Given an array of story IDs, loads all the identified
stories.

=item story_uuid

Load a story by UUID.

=item version

Combined with C<story_id> (and only C<story_id>), loads a specific
version of a story.  Unlike C<revert()>, this object has C<version>
set to the actual version number of the loaded object.

=item simple_search

Performs a per-word LIKE match against title and URL, and an exact
match against story_id if a word is a number.

=item exclude_story_ids

Pass an array ref of IDs to be excluded from the result set

=item below_category_id

Returns stories in the category and in categories below as well.

=item below_primary_category_id

Returns stories in the category and in categories below as well,
looking only at primary category relationships.

=item published

If set to 0, returns stories that are not published, set to 1 
returns published stories.

=item creator_simple

This performs a simple search against users and finds stories created
by matching users.

=item may_see

If set to 1 then only items which the current user has at least read
permissions to are returned.  Defaults to 0.

=item may_edit

If set to 1 then only items which the current user has edit
permissions to are returned.  Defaults to 0.

=item element_index

This find option allows you to search againt indexed element data.
For details on element indexing, see L<Krang::ElementClass>.  This
option should be set with an array containing the element name and the
value to match against.  For example, to search for stories containing
'foo' in their deck, assuming deck is an indexed element:

  @stories = pkg('Story')->find(element_index_like => [deck => '%foo%']);

=back

Options affecting the search and the results returned:

=over

=item ids_only

Return only IDs, not full story objects.

=item count

Return just a count of the results for this query.

=item limit

Return no more than this many results.

=item offset

Start return results at this offset into the result set.

=item order_by

Output field to sort by.  Defaults to 'story_id'.

=item order_desc

Results will be in sorted in ascending order unless this is set to 1
(making them descending).

=item show_hidden

Returns all stories, not just those where C<< Krang::Story->hidden() >>
is false.

If you are developing an element set, you may or may not want this
option - See L<Krang::ElementClass::TopLevel> for more information on
C<hidden()>.

B<NOTE:> C<show_hidden> is automatically enabled if any of the
following search terms are used: C<story_id>, C<checked_out>,
C<checked_out_by>, C<class>, C<desk_id>, C<may_see>, C<may_edit>.

B<WARNING - A NOTE TO KRANG DEVELOPERS:> Be aware that unless the
above search terms are used, you B<MUST> use this modifier whenever UI
or bin/ scripts make calls to C<find()>!

=back

=cut

{

# used to detect normal story fields versus more exotic searches
my %simple_fields = map { $_ => 1 } grep { $_ !~ /_date$/ } STORY_FIELDS;

sub find {
    my $pkg = shift;
    my %args = @_;
    my $dbh = dbh();

    # get search parameters out of args, leaving just field specifiers
    my $order_by    = delete $args{order_by}    || 's.story_id';
    my $order_dir   = delete $args{order_desc}  ? 'DESC' : 'ASC';
    my $limit       = delete $args{limit}       || 0;
    my $offset      = delete $args{offset}      || 0;
    my $count       = delete $args{count}       || 0;
    my $ids_only    = delete $args{ids_only}    || 0;

    # determine whether or not to display hidden stories.
    my $show_hidden = delete $args{show_hidden} || 0;

    foreach (qw/story_id checked_out checked_out_by class desk_id may_see may_edit/) {
        if (exists($args{$_})) { $show_hidden = 1; last; }
    }

    # set bool to determine whether to use $row or %row for binding below
    my $single_column = $ids_only || $count ? 1 : 0;

    # check for invalid argument sets
    croak(__PACKAGE__ . "->find(): 'count' and 'ids_only' were supplied. " .
          "Only one can be present.")
      if $count and $ids_only;
    croak(__PACKAGE__ . "->find(): can't use 'version' without 'story_id'.")
      if $args{version} and not $args{story_id};

    # loading a past version is handled by _load_version()
    return $pkg->_load_version($args{story_id}, $args{version})
      if $args{version};

    my (@where, @param, %from, $like);
    while (my ($key, $value) = each %args) {
        # strip off and remember _like specifier
        $like = ($key =~ s/_like$//) ? 1 : 0;

        # handle story_id => [1, 2, 3]
        if ($key eq 'story_id' and ref($value) and ref($value) eq 'ARRAY') {
            # an array of IDs selects a list of stories by ID
            push @where, 's.story_id IN (' . 
              join(',', ("?") x @$value) . ')';
            push @param, @$value;
            next;
        }

        # handle class => ['article', 'cover']
        if ($key eq 'class' and ref($value) and ref($value) eq 'ARRAY') {
            # an array of IDs selects a list of stories by ID
            push @where, 's.class IN (' . 
              join(',', ("?") x @$value) . ')';
            push @param, @$value;
            next;
        }

        # handle simple fields
        if (exists $simple_fields{$key}) {
            if (defined $value) {
                push @where, $like ? "s.$key LIKE ?" : "s.$key = ?";
                push @param, $value;
            } else {
                push @where, "s.$key IS NULL";
            }
            next;
        }

        # handle search by category_id
        if ($key eq 'category_id') {
            $from{"story_category as sc"} = 1;
            push(@where, 's.story_id = sc.story_id');
            push(@where, 'sc.category_id = ?');
            push(@param, $value);
            next;
        }

        # handle search by primary_category_id
        if ($key eq 'primary_category_id') {
            $from{"story_category as sc"} = 1;
            push(@where, 's.story_id = sc.story_id');
            push(@where, 'sc.category_id = ?', 'sc.ord = 0');
            push(@param, $value);
            next;
        }

        # handle below_category_id
        if ($key eq 'below_category_id') {
            $from{"story_category as sc"} = 1;
            push(@where, 's.story_id = sc.story_id');
            my ($cat) = pkg('Category')->find(category_id => $value);
            my @ids = ($value, $cat->descendants( ids_only => 1 ));
            push(@where, 's.story_id = sc.story_id');
            push(@where, 
                 'sc.category_id IN (' . join(',', ('?') x @ids) . ')');
            push(@param, @ids);
            next;
        }

        # handle below_primary_category_id
        if ($key eq 'below_primary_category_id') {
            $from{"story_category as sc"} = 1;
            push(@where, 's.story_id = sc.story_id');
            my ($cat) = pkg('Category')->find(category_id => $value);
            my @ids = ($value, $cat->descendants( ids_only => 1 ));
            push(@where, 's.story_id = sc.story_id AND sc.ord = 0');
            push(@where, 
                 'sc.category_id IN (' . join(',', ('?') x @ids) . ')');
            push(@param, @ids);
            next;
        }

        # handle search by site_id
        if ($key eq 'site_id') {
            # need to bring in category
            $from{"story_category as sc"} = 1;
            $from{"category as c"} = 1;
            push(@where, 's.story_id = sc.story_id');
            push(@where, 'sc.category_id = c.category_id');
            if (ref $args{$key} eq 'ARRAY') {
                push(@where,
                     'c.site_id IN (' . join(',', ('?') x @{$args{$key}}) . ')');
                push(@param, @{$args{site_id}});
            } else {
                push(@where, 'c.site_id = ?');
                push(@param, $value);
            }
            next;
        }

        # handle search by primary_site_id
        if ($key eq 'primary_site_id') {
            # need to bring in category
            $from{"story_category as sc"} = 1;
            $from{"category as c"} = 1;
            push(@where, 's.story_id = sc.story_id');
            push(@where, 'sc.category_id = c.category_id');
            if (ref $args{$key} eq 'ARRAY') {
                push(@where,
                     'c.site_id IN (' . join(',', ('?') x @{$args{$key}}) . ')');
                push(@param, @{$args{$key}});
            } else {
                push(@where, 'c.site_id = ?', 'sc.ord = 0');
                push(@param, $value);
            }
            next;
        }

        # handle search by url
        if ($key eq 'url') {
            $from{"story_category as sc"} = 1;
            push(@where, 's.story_id = sc.story_id');
            push(@where, ($like ? 'sc.url LIKE ?' : 'sc.url = ?'));
            push(@param, $value);
            next;
        }

        # handle search by primary_url
        if ($key eq 'primary_url') {
            $from{"story_category as sc"} = 1;
            push(@where, 's.story_id = sc.story_id');
            push(@where, ($like ? 'sc.url LIKE ?' : 'sc.url = ?'),
                         'sc.ord = 0');
            push(@param, $value);
            next;
        }

        # handle search by non-primary_url
        if ($key eq 'non_primary_url') {
            $from{"story_category as sc"} = 1;
            push(@where, 's.story_id = sc.story_id');
            push(@where, ($like ? 'sc.url LIKE ?' : 'sc.url = ?'),
                         'sc.ord != 0');
            push(@param, $value);
            next;
        }
 
        # handle contrib_simple
        if ($key eq 'contrib_simple') {
            $from{"story_contrib as scon"} = 1;
            $from{"contrib as con"} = 1;
            push(@where, 's.story_id = scon.story_id');
            push(@where, 'con.contrib_id = scon.contrib_id');

            my @words = split(/\s+/, $args{'contrib_simple'});
            foreach my $word (@words){
                push(@where, 
                    q{concat(
		        coalesce(con.first,''), ' ',
		        coalesce(con.middle,''), ' ',
		        coalesce(con.last),'') LIKE ?
		     });
                push(@param, "%${word}%");
            }
            next;
        }

        # handle creator_simple
        if ($key eq 'creator_simple') {
            $from{"history as h"} = 1;
            $from{"user as u"} = 1;
            push(@where, 's.story_id = h.object_id');
            push(@where, "(h.object_type = 'Krang::Story' or h.object_type ='"
                          .pkg('Story')."')");
            push(@where, "h.action = 'new'");
            push(@where, 'h.user_id = u.user_id');

            my @words = split(/\s+/, $args{'creator_simple'});
            foreach my $word (@words){
                push(@where, 
                     q{concat(u.first_name,' ',u.last_name) LIKE ?});
                push(@param, "%${word}%");
            }
            next;
        }

        # handle simple_search
        if ($key eq 'simple_search') {            
            $from{"story_category as sc"} = 1;
            push(@where, 's.story_id = sc.story_id');

            my @words = split(/\s+/, ($args{'simple_search'} || ""));
            foreach my $word (@words){
                my $numeric = ($word =~ /^\d+$/) ? 1 : 0;
                  push(@where, '(' .                      
                     join(' OR ', 
                          ($numeric ? 's.story_id = ?' : ()),
                          's.title LIKE ?', 
                          'sc.url LIKE ?') . ')');
                # escape any literal SQL wildcard chars
                if( !$numeric ) {
                    $word =~ s/_/\\_/g;
                    $word =~ s/%/\\%/g;
                } 
                push(@param, ($numeric ? ($word) : ()),
                     "%${word}%", "%${word}%");
            }
            next;
        }

        # handle dates
        if ($key eq 'cover_date' or $key eq 'publish_date') {
            if (ref $value and UNIVERSAL::isa($value, 'Time::Piece')) {
                push @where, "$key = ?";
                push @param, $value->mysql_datetime;
            } elsif (ref $value and UNIVERSAL::isa($value, 'ARRAY')) {
                if ($value->[0] and $value->[1]) {
                    push @where, "$key BETWEEN ? AND ?";
                    push @param, $value->[0]->mysql_datetime,
                                 $value->[1]->mysql_datetime;
                } elsif ($value->[0]) {
                    push @where, "$key >= ?";
                    push @param, $value->[0]->mysql_datetime;
                } elsif ($value->[1]) {
                    push @where, "$key <= ?";
                    push @param, $value->[1]->mysql_datetime;
                }
            } else {
                croak("Bad date aguement, must be either an array of two Time::Piece objects or one Time::Piece object.");
            }
            next;
        }

        # handle exclude_story_ids => [1, 2, 3]
        if ($key eq 'exclude_story_ids') {
            if(@$value) {
                push(@where, ('s.story_id != ?') x @$value);
                push(@param, @$value);
            }
            next;
        }

        # handle published flag
        if ($key eq 'published') {
            my $ps = ($args{published} eq '1') ? 
	        's.published_version > 0' : 
		'(s.published_version IS NULL OR s.published_version = 0)';
            push(@where, $ps);
            next;
        }

        # handle may_see
        if ($key eq 'may_see') {
            push(@where, 'ucpc.may_see = ?');
            push(@param, 1);
            next;
        }

        # handle may_edit
        if ($key eq 'may_edit') {
            push(@where, 'ucpc.may_edit = ?');
            push(@param, 1);
            next;
        }

        # handle element_index
        if ($key eq 'element_index') {
            # setup join to element_index
            $from{"element as e"} = 1;
            $from{"element_index as ei"} = 1;
            push(@where, 's.element_id = e.root_id');
            push(@where, 'e.element_id = ei.element_id');

            # produce where clause
            push(@where, 
                 'e.class = ?',
                 ($like ? 'ei.value LIKE ?' : 'ei.value = ?'));
            push(@param, $value->[0], $value->[1]);
            next;
        }

        croak("Unknown find key '$key'");
    }

    # Add user_id into the query
    my $user_id = $ENV{REMOTE_USER} || croak("No user_id in REMOTE_USER");
    push(@where, "ucpc.user_id = ?");
    push(@param, $user_id);

    # handle ordering by primary URL, which is in story_category
    if ($order_by eq 'url') {
        $from{"story_category as sc"} = 1;
        push(@where, 's.story_id = sc.story_id');
        push(@where, 'sc.ord = 0');
        $order_by = 'sc.url';
    } elsif ($order_by !~ /\w+\./) {
        $order_by = "s." . $order_by;
    }

    # restrict to visible stories unless show_hidden is passed.
    unless ($show_hidden) {
        push(@where, 's.hidden = 0');
    }

    # always restrict perm checking to primary category
    push(@where, 'sc_p.ord = 0');

    # construct base query
    my $query;
    my $from = " FROM story AS s 
                 LEFT JOIN story_category AS sc_p 
                   ON s.story_id = sc_p.story_id
                 LEFT JOIN user_category_permission_cache as ucpc
                   ON sc_p.category_id = ucpc.category_id ";
    my $group_by = 0;

    if ($count) {        
        $query = "SELECT COUNT(DISTINCT(s.story_id)) $from";
    } elsif ($ids_only) {
        $query = "SELECT DISTINCT(s.story_id) $from";
    } else {
        # Get user asset permissions -- overrides may_edit if false
        my $may_edit;
        if (pkg('Group')->user_asset_permissions('story') eq "edit") {
            $may_edit = "ucpc.may_edit as may_edit";
        } else {
            $may_edit = $dbh->quote("0") . " as may_edit";
        }

        $query = "SELECT " .
           join(', ', map { "s.$_" } STORY_FIELDS) .
             ",ucpc.may_see as may_see, $may_edit" .
             $from;
        $group_by = 1;
    }

    # add joins, if any
    $query .= ", " . join(', ', keys(%from)) if (%from);
    
    # add WHERE, GROUP BY and ORDER BY clauses, if any
    $query .= " WHERE " . join(' AND ', @where) if @where;
    $query .= " GROUP BY s.story_id" if $group_by;
    $query .= " ORDER BY $order_by $order_dir " if $order_by and not $count;

    # add LIMIT clause, if any
    if ($limit) {
        $query .= $offset ? " LIMIT $offset, $limit" : " LIMIT $limit";
    } elsif ($offset) {
        $query .= " LIMIT $offset, -1";
    }

    debug(__PACKAGE__ . "::find() SQL: " . $query);
    debug(__PACKAGE__ . "::find() SQL ARGS: " . join(', ', @param));
    
    # return count results
    if ($count) {
        my ($result) = $dbh->selectrow_array($query, undef, @param);
        return $result;
    }

    # return ids
    if ($ids_only) {
        my $result = $dbh->selectcol_arrayref($query, undef, @param);
        return $result ? @$result : ();
    }
    
    # execute an object search
    my $sth = $dbh->prepare($query);
    $sth->execute(@param);

    # construct objects from results
    my ($row, @stories, $result);
    while ($row = $sth->fetchrow_arrayref()) {
        my $obj = bless({}, $pkg);
        @{$obj}{(STORY_FIELDS, 'may_see', 'may_edit')} = @$row;

        # objectify dates
        for (qw(cover_date publish_date)) {
            if ($obj->{$_} and $obj->{$_} ne '0000-00-00 00:00:00') {
                $obj->{$_} = Time::Piece->from_mysql_datetime($obj->{$_});
            } else {
                $obj->{$_} = undef;
            }
        }
       

        # load category_ids and urls
        $result = $dbh->selectall_arrayref('SELECT category_id, url '.
                                           'FROM story_category '.
                                           'WHERE story_id = ? ORDER BY ord', 
                                           undef, $obj->{story_id});
        @{$obj}{('category_ids', 'urls')} = ([], []);
        foreach my $row (@$result) {
            push @{$obj->{category_ids}}, $row->[0];
            push @{$obj->{url_cache}},         $row->[1];
        }

        # load contribs
        $result = $dbh->selectall_arrayref(
                 'SELECT contrib_id, contrib_type_id FROM story_contrib '.
                 'WHERE story_id = ? ORDER BY ord',
                                           undef, $obj->{story_id});
        $obj->{contrib_ids} = @$result ?
          [ map { { contrib_id      => $_->[0],
                    contrib_type_id => $_->[1] 
                  } } @$result ] :
          [];

        push @stories, $obj;
    }

    # finish statement handle
    $sth->finish();

    return @stories;
}}

sub _load_version {
    my ($pkg, $story_id, $version) = @_;
    my $dbh = dbh;

    my ($data) = $dbh->selectrow_array('SELECT data FROM story_version
                                        WHERE story_id = ? AND version = ?',
                                       undef, $story_id, $version);
    croak("Unable to load version '$version' of story '$story_id'")
      unless $data;

    my @result;
    eval { @result = (thaw($data)) };
    croak("Error loading version '$version' of story '$story_id' : $@")
      unless @result;

    # restore a bunch of now out-of-date params to default values
    foreach my $s (@result) {
        foreach (qw/checked_out checked_out_by published_version/) {
            $s->{$_} = 0;
        }
    }

    return @result;
}

=item C<< $story->move_to_desk($desk_id) >>

Move story to selected desk.  Cannot move it if checked out. 
Will return 1 if successful, else 0.

=cut

sub move_to_desk {
    my ($self, $desk_id) = @_;
    my $dbh      = dbh();

    croak(__PACKAGE__."->move_to_desk requires a desk_id") if not $desk_id;

    # check status
    my ($co) = $dbh->selectrow_array(
         'SELECT checked_out FROM story
           WHERE story_id = ?', undef, $self->story_id);

    return 0 if $co;

    $dbh->do('UPDATE story SET desk_id = ? where story_id = ?', undef, $desk_id, $self->story_id);

    $self->{desk_id} = $desk_id;
    add_history(    action => 'move',
                    object => $self,
                    desk_id => $desk_id );
    return 1;     
}

=item C<< $story->checkout() >>

=item C<< Krang::Story->checkout($story_id) >>

Checkout the story, preventing other users from editing it.  Croaks if
the story is already checked out.

=cut

sub checkout {
    my ($self, $story_id) = @_;
    croak("Invalid call: object method takes no parameters")
      if ref $self and @_ > 1;
    $self = (pkg('Story')->find(story_id => $story_id))[0]
      unless $self;
    my $dbh      = dbh();
    my $user_id  = $ENV{REMOTE_USER};

    # Is user allowed to otherwise edit this object?
    Krang::Story::NoEditAccess->throw( message => "Not allowed to edit story", story_id => $self->story_id )
        unless ($self->may_edit);

    # short circuit checkout
    return if  $self->{checked_out} and 
      $self->{checked_out_by} == $user_id;

    eval {
        # lock story for an atomic test and set on checked_out
        $dbh->do("LOCK TABLES story WRITE");

        # check status
        my ($co, $uid) = $dbh->selectrow_array(
             'SELECT checked_out, checked_out_by FROM story
              WHERE story_id = ?', undef, $self->{story_id});
        
        croak("Story '$self->{story_id}' is already checked out by user '$uid'")
          if ($co and $uid != $user_id);


        # checkout the story
        $dbh->do('UPDATE story
                  SET checked_out = ?, checked_out_by = ?
                  WHERE story_id = ?', undef, 1, $user_id, $self->{story_id});

        # unlock template table
        $dbh->do("UNLOCK TABLES");
    };

    if ($@) {
        my $eval_error = $@;
        # unlock the table, so it's not locked forever
        $dbh->do("UNLOCK TABLES");
        croak($eval_error);
    }

    # update checkout fields
    $self->{checked_out} = 1;
    $self->{checked_out_by} = $user_id;

    add_history(    object => $self,
                    action => 'checkout',
               );
}

=item C<< Krang::Story->checkin($story_id) >>

=item C<< $story->checkin() >>

Checkin the story, allow other users to check it out.  This will only
fail if the story is not checked out.

=cut

sub checkin {
    my $self     = ref $_[0] ? $_[0] : 
      (pkg('Story')->find(story_id => $_[1]))[0];
    my $story_id = $self->{story_id};
    my $dbh      = dbh();
    my $user_id  = $ENV{REMOTE_USER};

    # Is user allowed to otherwise edit this object?
    Krang::Story::NoEditAccess->throw( message => "Not allowed to edit story", story_id => $self->story_id )
        unless ($self->may_edit);

    # get admin permissions
    my %admin_perms = pkg('Group')->user_admin_permissions();

    # make sure we're checked out, unless we have may_checkin_all powers
    $self->_verify_checkout() unless $admin_perms{may_checkin_all};

    # checkin the story
    $dbh->do('UPDATE story
              SET checked_out = ?, checked_out_by = ?
              WHERE story_id = ?', undef, 0, 0, $story_id);

    # update checkout fields
    $self->{checked_out} = 0;
    $self->{checked_out_by} = 0;

    add_history(    object => $self,
                    action => 'checkin',
               );
}


=item C<< $story->mark_as_published() >>

Mark the story as published.  This will update the C<publish_date> and
C<published_version> attributes, and will also check the story back
in, removing it from any desk it's currently on.

This will also make an entry in the log that the story has been published.

=cut

sub mark_as_published {
    my $self = shift;

    croak __PACKAGE__ . ": Cannot publish unsaved story" unless ($self->{story_id});

    $self->{published_version} = $self->{version};
    $self->{publish_date} = localtime;

    $self->{desk_id} = undef;

    $self->{checked_out} = 0;
    $self->{checked_out_by} = 0;

    # update the DB.
    my $dbh = dbh();
    $dbh->do('UPDATE story
              SET checked_out = ?,
                  checked_out_by = ?,
                  desk_id = ?,
                  published_version = ?,
                  publish_date = ?
              WHERE story_id = ?',

             undef,
             $self->{checked_out},
             $self->{checked_out_by},
             $self->{desk_id},
             $self->{published_version},
             $self->{publish_date}->mysql_datetime,
             $self->{story_id}
            );
}

=item C<< $story->mark_as_previewed(unsaved => 1) >>

Mark the story as previewed.  This will update the C<preview_version>
attribute, setting it equal to C<version>.  This is used as a sanity
check by L<Krang::Publisher> to prevent re-generation of content.

The argument C<unsaved> defaults to 0.  If true, it indicates that the
story being previewed is in the process of being edited, in which case
any previews made cannot be trusted for future use.  In that case,
preview_version is set to -1.

=cut

sub mark_as_previewed {
    my ($self, %args) = @_;

    my $unsaved = $args{unsaved} || 0;

    $self->{preview_version} = $unsaved ? -1 : $self->{version};

    # update the DB
    my $dbh = dbh();
    $dbh->do('UPDATE story SET preview_version = ? WHERE story_id = ?',
             undef,
             $self->{preview_version},
             $self->{story_id}
            );

}


=item $path = $story->publish_path(category => $category)

Returns the publish path for the story object, using the site's
publish_path and the story's URL.  This is the filesystem path where
the story object will be published.

If a category is not passed the primary category for the story is
returned.

=cut

sub publish_path {
    my $self = shift;
    my %arg  = @_;
    my $category = $arg{category} ? $arg{category} : $self->category;

    my $path = $category->site->publish_path;
    my $url  = $self->element->build_url(story    => $self,
                                         category => $category);

    # remove the site part
    $url =~ s![^/]+/!!;

    # paste them together
    return canonpath(catdir($path, $url));
}


=item $path = $story->preview_path(category => $category)

Returns the preview path for the story object, using the site's
preview_path and the story's URL.  This is the filesystem path where
the story object will be previewed.

Takes an optional category argument, or will return a url based on the
story's primary category.

=cut

sub preview_path {
    my $self = shift;
    my %arg  = @_;

    my $category = $arg{category} ? $arg{category} : $self->category;

    my $path = $category->site->preview_path;
    my $url  = $self->element->build_url(story    => $self,
                                         category => $category);

    # remove the site part
    $url =~ s![^/]+/!!;

    # paste them together
    return canonpath(catdir($path, $url));
}



# make sure the object is checked out, or croak
sub _verify_checkout {
    my $self = shift;

    croak("Story '$self->{story_id}' is not checked out.")
      unless $self->{checked_out};

    croak("Story '$self->{story_id}' is already checked out by another user '$self->{checked_out_by}'")
      unless $self->{checked_out_by} == $ENV{REMOTE_USER};
}


=item C<< $story->revert($version) >>

Loads an old version of this story into the current story object.
This does not change the value returned by C<< $story->version >>.
Saving this object will create a new version, but with the contents of
the old version, thus reverting the contents of the story.  

If you want to load an old version directly, see C<find()>.

=cut

sub revert {
    my ($self, $target) = @_;
    $self->_verify_checkout();
    my $dbh = dbh;

    # persist certain data from current version
    my %persist = (
                   version           => $self->{version},
                   checked_out_by    => $self->{checked_out_by},
                   checked_out       => $self->{checked_out_by},
                   published_version => $self->{published_version},
                   publish_date      => $self->{publish_date},
                   url_cache         => [],
                  );
    my ($obj) = $self->_load_version($self->{story_id}, $target);

    # copy in data, preserving contents of %persist
    %$self = (%$obj, %persist);

    add_history(    object => $self, 
                    action => 'revert',
               );

    return $self; 
}

=item C<< $story->delete() >>

=item C<< Krang::Story->delete($story_id) >>

Deletes a story from the database.  This is a permanent operation.
Stories will be checked-out before they are deleted, which will fail
if the story is checked out to another user.

=cut

sub delete {
    my $self = shift;
    unless(ref $self) {
        my $story_id = shift;
        ($self) = pkg('Story')->find(story_id => $story_id);
        croak("Unable to load story '$story_id'.") unless $self;
    }
    $self->checkout;

    # Is user allowed to otherwise edit this object?
    Krang::Story::NoEditAccess->throw( message => "Not allowed to edit story", story_id => $self->story_id )
        unless ($self->may_edit);

    # unpublish
    pkg('Publisher')->new->unpublish_story(story => $self);

    # first delete history for this object
    pkg('History')->delete(object => $self);

    my $dbh = dbh;
    $dbh->do('DELETE FROM story WHERE story_id = ?', 
             undef, $self->{story_id});
    $dbh->do('DELETE FROM story_category WHERE story_id = ?', 
             undef, $self->{story_id});
    $dbh->do('DELETE FROM story_version WHERE story_id = ?', 
             undef, $self->{story_id});
    $dbh->do('DELETE FROM story_contrib WHERE story_id = ?',
             undef, $self->{story_id});
    $self->element->delete;

    # delete schedules for this story
    $dbh->do('DELETE FROM schedule WHERE object_type = ? and object_id = ?', undef, 'story', $self->{story_id});

    add_history(    object => $self,
                    action => 'delete',
               );

}

=item C<< $copy = $story->clone() >>

Creates a copy of the story object, with most fields identical except
for C<story_id> and C<< element->element_id >> which will both be
C<undef>.  Sets to title to "Copy of $title".  Sets slug to
"$slug_copy" if slug is set.  Will remove categories as necessary to
generate a story without duplicate URLs.  Cloned stories get a new
story_uuid.

=cut

sub clone {
    my $self = shift;
    my $copy = bless({ %$self }, ref($self));

    # clone the element tree
    $copy->{element} = $self->element->clone();

    # zap ids
    $copy->{story_id} = undef;
    $copy->{element}{element_id} = undef;

    # mangle title
    $copy->{title} = "Copy of $copy->{title}";

    # start at version 0
    $copy->{version} = 0;

    # never been published
    $copy->{publish_date} = undef;
    $copy->{published_version} = 0;

    # get a new UUID
    $copy->{story_uuid} = pkg('UUID')->new;

    # returns 1 if there is a dup, 0 otherwise
    my $is_dup = sub {  
        eval { shift->_verify_unique; };
        return 1 if $@ and ref $@ and $@->isa('Krang::Story::DuplicateURL');
        die($@) if $@;
        return 0;
    };

    # if changing the slug will help, do that until it works
    my @url_attributes = $copy->element->class->url_attributes;
    if (grep { $_ eq 'slug' } @url_attributes) {
        # find a slug that works
        my $x = 1;
        do {
            $copy->slug("$self->{slug}_copy" . ($x > 1 ? $x : ""));
            $x++;
        } while ($is_dup->($copy));
    } else {
        # erase category associations
        $copy->{category_ids} = [];
        $copy->{category_cache} = [];
        $copy->{url_cache} = [];
    }

    return $copy;
}

=item C<< @linked_stories = $story->linked_stories >>

Returns a list of stories linked to from this story.  These will be
Krang::Story objects.  If no stories are linked, returns an empty
list.  This list will not contain any duplicate stories, even if a
story is linked more than once.

=cut

sub linked_stories {
    my $self = shift;
    my $element = $self->element;

    # find StoryLinks and index by id
    my %story_links;
    my $story;
    foreach_element { 
        if ($_->class->isa(pkg('ElementClass::StoryLink')) and 
            $story = $_->data) {
            $story_links{$story->story_id} = $story;
        }
    } $element;
    
    return values %story_links;
}

=item C<< @linked_media = $story->linked_media >>

Returns a list of media linked to from this story.  These will be
Krang::Media objects.  If no media are linked, returns an empty list.
This list will not contain any duplicate media, even if a media object
is linked more than once.

=cut

sub linked_media {
    my $self = shift;
    my $element = $self->element;

    # find StoryLinks and index by id
    my %media_links;
    my $media;
    foreach_element { 
        if ($_->class->isa(pkg('ElementClass::MediaLink')) and
            $media = $_->data) {
            $media_links{$media->media_id} = $media;
        }
    } $element;

    # check contributors for additional media objects
    foreach my $contrib ($self->contribs()) {
        if ($media = $contrib->image()) {
            $media_links{$media->media_id} = $media;
        }
    }

    return values %media_links;

}

=item C<< $data = Storable::freeze($story) >>

Serialize a story.  Krang::Story implements STORABLE_freeze() to
ensure this works correctly.

=cut

sub STORABLE_freeze {
    my ($self, $cloning) = @_;
    return if $cloning;

    # avoid serializing category cache since they contain objects not
    # owned by the story
    my $category_cache = delete $self->{category_cache};

    # make sure element tree is loaded
    $self->element();
    
    # serialize data in $self with Storable
    my $data;
    eval { $data = nfreeze({%$self}) };
    croak("Unable to freeze story: $@") if $@;

    # reconnect cache
    $self->{category_cache} = $category_cache if defined $category_cache;

    return $data;
}

=item C<< $story = Storable::thaw($data) >>

Deserialize a frozen story.  Krang::Story implements STORABLE_thaw()
to ensure this works correctly.

=cut

sub STORABLE_thaw {
    my ($self, $cloning, $data) = @_;

    # FIX: is there a better way to do this?
    # Krang::Element::STORABLE_thaw needs a reference to the story in
    # order to thaw the element tree, but thaw() doesn't let you pass
    # extra arguments.
    local $Krang::Element::THAWING_OBJECT = $self;

    # retrieve object
    eval { %$self = %{thaw($data)} };
    croak("Unable to thaw story: $@") if $@;

    return $self;
}

=item C<< $story->serialize_xml(writer => $writer, set => $set) >>

Serialize as XML.  See Krang::DataSet for details.

=cut

sub serialize_xml {
    my ($self, %args) = @_;
    my ($writer, $set) = @args{qw(writer set)};
    local $_;

    # open up <story> linked to schema/story.xsd
    $writer->startTag('story',
                      "xmlns:xsi" => 
                        "http://www.w3.org/2001/XMLSchema-instance",
                      "xsi:noNamespaceSchemaLocation" =>
                        'story.xsd');

    # basic fields
    $writer->dataElement(story_id   => $self->story_id);
    $writer->dataElement(story_uuid => $self->story_uuid);
    $writer->dataElement(class      => $self->class->name);
    $writer->dataElement(title      => $self->title);
    $writer->dataElement(slug       => $self->slug);
    $writer->dataElement(version    => $self->version);
    $writer->dataElement(cover_date => $self->cover_date->datetime);
    $writer->dataElement(priority   => $self->priority);
    $writer->dataElement(notes      => $self->notes);
    
    # categories
    for my $category ($self->categories) {
        $writer->dataElement(category_id => $category->category_id);

        $set->add(object => $category, from => $self);
    }

    # urls
    $writer->dataElement(url => $_) for $self->urls;

    # contributors
    my %contrib_type = pkg('Pref')->get('contrib_type');
    for my $contrib ($self->contribs) {
        $writer->startTag('contrib');
        $writer->dataElement(contrib_id => $contrib->contrib_id);
        $writer->dataElement(contrib_type => 
                             $contrib_type{$contrib->selected_contrib_type()});
        $writer->endTag('contrib');

        $set->add(object => $contrib, from => $self);
    }

    # schedules
    foreach my $schedule ( pkg('Schedule')->find( object_type => 'story', object_id => $self->story_id ) ) {
        $set->add(object => $schedule, from => $self);
    }
    
    # serialize elements
    $self->element->serialize_xml(writer => $writer,
                                  set    => $set);
    
    # all done
    $writer->endTag('story');
}

=item C<< $story = Krang::Story->deserialize_xml(xml => $xml, set => $set, no_update => 0) >>

Deserialize XML.  See Krang::DataSet for details.

If an incoming story has the same primary URL as an existing story
then an update will occur, unless no_update is set.

=cut

sub deserialize_xml {
    my ($pkg, %args) = @_;
    my ($xml, $set, $no_update) = @args{qw(xml set no_update)};
    local $_;

    # parse it up
    my $data = pkg('XML')->simple(xml           => $xml, 
                                  forcearray    => ['contrib',
                                                    'category_id',
                                                    'url',
                                                    'element',
                                                    'data',
                                                   ],
                                  suppressempty => 1);

    # is there an existing object?
    my $story;
    
    # start with a UUID lookup
    my $match_type;
    unless ($args{no_uuid} and $data->{story_uuid}) {
        ($story) =
          $pkg->find(story_uuid  => $data->{story_uuid},
                     show_hidden => 1);

        # if not updating this is fatal
        Krang::DataSet::DeserializationFailed->throw(message =>
                  "A story object with the UUID '$data->{story_uuid}' already"
                  . " exists and no_update is set.")
          if $story and $no_update;
    }
    
    # proceed to URL lookup if no dice
    unless ($story or $args{require_uuid}) {
        ($story) =
          pkg('Story')->find(url => $data->{url}[0], show_hidden => 1);

        # if not updating this is fatal
        Krang::DataSet::DeserializationFailed->throw(
            message => "A story object with the url '$data->{url}[0]' already".
                       " exists and no_update is set.")
            if $story and $no_update;
    }

    if ($story) {
        # if primary url of this imported story matches a non-primary
        # url of an existing story, reject
        my ($fail) =
          $pkg->find(non_primary_url => $data->{url}[0],
                     ids_only        => 1);
        Krang::DataSet::DeserializationFailed->throw(
                           message => "A story object with a non-primary url "
                             . "'$data->{url}[0]' already exists.")
          if $fail;

        # check it out to make changes
        $story->checkout;

        # update slug and title
        $story->slug($data->{slug} || "");
        $story->title($data->{title} || "");

        # get category objects for story
        my @category_ids = map { $set->map_id(class => "Krang::Category",
                                              id    => $_) }
                             @{$data->{category_id}};
        
        # set categories, which might have changed if this was a match
        # by UUID
        $story->categories(\@category_ids);

    } else {

        # check primary URL for conflict - can happen with require_uuid on
        my ($fail) =
          $pkg->find(primary_url => $data->{url}[0],
                     ids_only    => 1);
        Krang::DataSet::DeserializationFailed->throw(
                           message => "A story object with a primary url "
                             . "'$data->{url}[0]' already exists.")
          if $fail;

        # check if any of the secondary urls match existing stories
        # and fail if so
        for (my $count = 1; $count < @{$data->{url}}; $count++) {
            my ($found) = pkg('Story')->find(url => $data->{url}[$count], show_hidden => 1);
            Krang::DataSet::DeserializationFailed->throw(
                message => "A story object with url '$data->{url}[$count]' already exists, which conflicts with one of this story's secondary URLs.") if $found;
        }
 
        # get category objects for story
        my @categories = map { pkg('Category')->find(category_id => $_) }
                           map { $set->map_id(class => "Krang::Category",
                                              id    => $_) }
                             @{$data->{category_id}};

        # this might have caused this Story to get completed via a
        # circular link, end early if it did
        my ($dup) = pkg('Story')->find(url => $data->{url});
        return $dup if( $dup );

        # create a new story object using categories, slug, title,
        # and class
        $story = pkg('Story')->new(categories => \@categories,
                                   slug       => $data->{slug} || "",
                                   title      => $data->{title} || "",
                                   class      => $data->{class});
    }
    
    # preserve UUID if available
    $story->{story_uuid} = $data->{story_uuid} 
      if $data->{story_uuid} and not $args{no_uuid};

    $story->cover_date(Time::Piece->strptime($data->{cover_date},
                                             '%Y-%m-%dT%T'))
      if exists $data->{cover_date};
    $story->priority($data->{priority})
      if exists $data->{priority};
    $story->notes($data->{notes})
      if exists $data->{notes};

    # save changes
    $story->save();

    # register id before deserializing elements, since they may
    # contain circular references
    $set->register_id(class     => 'Krang::Story',
                      id        => $data->{story_id},
                      import_id => $story->story_id);

    # deserialize elements, may contain circular references
    my $element = pkg('Element')->deserialize_xml(data => $data->{element}[0],
                                                  set       => $set,
                                                  no_update => $no_update,
                                                  object    => $story);

    # update element
    $story->{element}->delete(skip_delete_hook => 1) if $story->{element};   
    $story->{element} = $element;

    # get hash of contrib type names to ids
    my %contrib_types = reverse pkg('Pref')->get('contrib_type');
                                                                              
    # handle contrib association
    if ($data->{contrib}) {
        my @contribs = @{$data->{contrib}};
        my @altered_contribs;
        foreach my $c (@contribs) {
            my $contrib_type_id = $contrib_types{$c->{contrib_type}} ||
                            Krang::DataSet::DeserializationFailed->throw(
                                 "Unknown contrib_type '".$c->{contrib_type}."'.");
                                                                              
            push (@altered_contribs, { contrib_id => $set->map_id(class => "Krang::Contrib", id => $c->{contrib_id}), contrib_type_id => $contrib_type_id });
        }
                                                                              
        $story->contribs(@altered_contribs);
    }

    # finish the story, not incrementing version
    $story->save(keep_version => 1);
    $story->checkin;

    return $story;
}

=back

=cut


1;
