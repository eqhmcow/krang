package Krang::Story;
use strict;
use warnings;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader Element => qw(foreach_element);
use Krang::ClassLoader 'Category';
use Krang::ClassLoader History => qw(add_history);
use Krang::ClassLoader Log     => qw(assert ASSERT affirm debug info critical);
use Krang::ClassLoader Conf    => qw(SavedVersionsPerStory ReservedURLs);
use Krang::ClassLoader DB      => qw(dbh);
use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader 'Pref';
use Krang::ClassLoader 'UUID';
use Krang::ClassLoader Localization => qw(localize);
use Krang::ClassLoader 'Trash';
use Carp qw(croak);
use Storable qw(nfreeze thaw);
use Time::Piece;
use Time::Seconds;
use Time::Piece::MySQL;
use File::Spec::Functions qw(catdir canonpath);

# setup exceptions
use Exception::Class
  'Krang::Story::DuplicateURL'         => {fields => ['stories', 'categories']},
  'Krang::Story::ReservedURL'          => {fields => ['reserved']},
  'Krang::Story::MissingCategory'      => {fields => []},
  'Krang::Story::NoCategoryEditAccess' => {fields => ['category_id']},
  'Krang::Story::NoEditAccess'         => {fields => ['story_id']},
  'Krang::Story::CheckedOut'           => {fields => ['desk_id', 'user_id']},
  'Krang::Story::NoDesk'               => {fields => ['desk_id']},
  'Krang::Story::NoDeleteAccess'       => {fields => ['story_id']},
  'Krang::Story::NoRestoreAccess'      => {fields => ['story_id']},
  'Krang::Story::CantCheckOut'         => {fields => ['stories']},
  ;

# create accessors for object fields
use Krang::ClassLoader MethodMaker => new_with_init => 'new',
  new_hash_init                    => 'hash_init',
  get                              => [
    qw(
      story_id
      story_uuid
      version
      checked_out
      checked_out_by
      may_see
      may_edit
      hidden
      retired
      trashed
      )
  ],
  get_set_with_notify => [
    {
        method => '_notify',
        attr   => [
            qw(
              title
              slug
              notes
              cover_date
              publish_date
              published_version
              preview_version
              desk_id
              last_desk_id
              )
        ]
    }
  ];

# fields in the story table, aside from story_id
use constant STORY_FIELDS => qw( story_id
  story_uuid
  version
  title
  slug
  cover_date
  publish_date
  published_version
  preview_version
  notes
  element_id
  class
  checked_out
  checked_out_by
  desk_id
  last_desk_id
  hidden
  retired
  trashed
);

sub id_meth   { 'story_id' }
sub uuid_meth { 'story_uuid' }

# called by get_set_with_notify attibutes.  Catches changes that must
# invalidate the URL cache.
sub _notify {
    my ($self, $which, $old, $new) = @_;
    $self->{url_attributes} ||= {map { $_ => 1 } $self->class->url_attributes};
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
  $story->cover_date(Time::Piece->strptime("1/1/2004 12:00", "%D %R"));

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

  $story->tags(['foo', 'bar']);
  $story->tags([]);
  my @tags = $story->tags();

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

=item C<< $story->category(level => $integer) >>

=item C<< $story->category(level => $integer, dir_only => 1) >>

=item C<< $story->category(depth_only => 1) >>

Without arguments returns the primary category for the story.
C<undef> until at least one category is assigned.  This is just a
convenience method that returns the first category in C<categories>.

Given the C<level> argument, it returns the corresponding ancestor
category, level zero signifying the root category, level one the first
level category below the root category and so on.  If the specified
category does not exist, returns undef.

If C<dir_only> is true, the category's 'dir' property will be returned
If the category does not exist, returns undef.

Given the C<depth_only> argument, returns the depth of the story's
primary category, zero signifying that the story primarily lives in
the root category.

=cut

sub category {
    my $self = shift;
    return undef unless @{$self->{category_ids}};

    my (%arg);

    if ($self->{category_cache} and $self->{category_cache}[0]) {
        # return cached primary category
        return $self->{category_cache}[0]
          if scalar(@_) == 0;
    } else {
        # put primary category into cache and return it
        my ($category) = pkg('Category')->find(category_id => $self->{category_ids}[0]);
        $self->{category_cache}[0] = $category;
        return $category if scalar(@_) == 0;
    }

    # we've got 'dir_only', 'level' or 'depth'

    if (not scalar(@_) % 2) {
        %arg = @_;
        croak(__PACKAGE__ . "::category() - arguments 'level' and 'depth_only' are mutually exclusive")
          if defined($arg{level}) and $arg{depth_only};
    } else {
        croak(__PACKAGE__ . "::category() - uneven argument list");
    }

    # shortcut for $story->category->dir
    return $self->{category_cache}[0]->dir
      if $arg{dir_only} and not defined($arg{level});

    # return the category corresponding to $level in the category
    # hiearchy, level 0 being the root category
    if (defined(my $level = $arg{level})) {
        my $cat = (reverse($self->{category_cache}[0]->ancestors), $self->{category_cache}[0])[$level];
        unless ($cat) {
            return $arg{dir_only} ? '' : undef;
        }
        # maybe return only the category's dir property
        return $arg{dir_only} ? $cat->dir : $cat;
    }

    # return the depth of the story's category, depth 0 signifying the
    # root category
    if ($arg{depth_only}) {
        my $ret = scalar($self->{category_cache}[0]->ancestors());
        return (defined($ret) ? $ret : 0);
    }

    # unrecognized arguments

    delete @arg{ qw(level dir_only depth_only) };

    if (%arg) {
        my $wrong_args = join(', ', keys(%arg));
        croak(__PACKAGE__ . "::category() - unrecognized argument(s) '$wrong_args'");
    }
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
    my $url = $self->class->build_url(
        story    => $self,
        category => $self->category
    );
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
    my $url              = $self->url;
    my $site             = $self->category->site;
    my $site_url         = $site->url;
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

This method may throw a C<Krang::Story::DuplicateURL> exception if you
add a new category and it generates a duplicate URL.  When this
exception is thrown the category list is still changed and you may
continue to operate on the story.  However, if you try to call C<save()>
you will receive the same exception.

=cut

sub categories {
    my $self = shift;
    my $args = {};
    if( @_ && ref $_[$#_] && ref $_[$#_] eq 'HASH' ) {
        $args = pop(@_);
    }

    # get
    unless (@_) {
        # load the cache as necessary
        for (0 .. $#{$self->{category_ids}}) {
            next if $self->{category_cache}[$_];
            ($self->{category_cache}[$_]) =
              pkg('Category')->find(category_id => $self->{category_ids}[$_]);
            croak("Unable to load category '$self->{category_ids}[$_]'")
              unless $self->{category_cache}[$_];
        }
        return $self->{category_cache} ? @{$self->{category_cache}} : ();
    }

    # transform array ref to list
    @_ = @{$_[0]} if @_ == 1 and ref($_[0]) and ref($_[0]) eq 'ARRAY';

    # fill in category_id list
    $self->{category_ids} = [map { ref $_ ? $_->category_id : $_ } @_];

    # fill cache with objects passed in, delay loading if just passed IDs
    $self->{category_cache} = [map { ref $_ ? $_ : undef } @_];

    # invalidate url cache
    $self->{url_cache} = [];

    unless ($self->{slug} eq '_TEMP_SLUG_FOR_CONVERSION_') {
        # make sure this change didn't cause a conflict
        $self->_verify_unique()   unless $args->{no_verify_unique};
        $self->_verify_reserved() unless $args->{no_verify_reserved};
    }
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
        $self->{url_cache}[$_] = $self->element->build_url(
            story    => $self,
            category => $self->{category_cache}[$_]
        );
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

    for (my $i = 0 ; $i <= $#urls ; $i++) {
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
    ($self->{element}) = pkg('Element')->load(element_id => $self->{element_id}, object => $self);
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

Will throw a C<Krang::Story::DuplicateURL> exception with a C<story_id>
or C<category_id> field if saving this story would conflict with an 
existing story or category.


=cut

sub init {
    my ($self, %args) = @_;
    exists $args{$_}
      or croak("Missing required parameter '$_'.")
      for ('class', 'categories', 'slug', 'title');
    croak("categories parameter must be an ARRAY ref.")
      unless ref $args{categories} and ref $args{categories} eq 'ARRAY';
    croak("categories parameter must contain at least one category")
      unless @{$args{categories}}
          and (UNIVERSAL::isa($args{categories}[0], 'Krang::Category')
              or (defined $args{categories}[0] and $args{categories}[0] =~ /^\d+$/));

    # create a new element based on class
    $self->{class} = delete $args{class};
    croak("Missing required 'class' parameter to pkg('Story')->new()")
      unless $self->{class};
    $self->{element} = pkg('Element')->new(
        class  => $self->{class},
        object => $self
    );

    # get hash of url_attributes
    $self->{url_attributes} = {map { $_ => 1 } $self->class->url_attributes};

    # determine if this story should be hidden or not
    $self->{hidden} = $self->class->hidden;

    # setup defaults
    $self->{version}            = 0;
    $self->{published_version}  = 0;
    $self->{preview_version}    = 0;
    $self->{checked_out}        = 1;
    $self->{checked_out_by}     = $ENV{REMOTE_USER};
    $self->{cover_date}         = Time::Piece->new();
    $self->{story_uuid}         = pkg('UUID')->new;
    $self->{retired}            = 0;
    $self->{trashed}            = 0;

    # Set up temporary permissions
    $self->{may_see}  = 1;
    $self->{may_edit} = 1;

    # handle categories setup specially since it needs to call
    # _verify_unique which won't work right without an otherwise
    # complete object.
    my $categories         = delete $args{categories};
    my $no_verify_unique   = delete $args{no_verify_unique};
    my $no_verify_reserved = delete $args{no_verify_reserved};

    # finish the object, calling set methods for each key/value pair
    $self->hash_init(%args);

    # setup categories
    $self->categories(
        @$categories,
        {
            no_verify_unique   => $no_verify_unique,
            no_verify_reserved => $no_verify_reserved,
        },
    );

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
            croak("No contributor found with contrib_id " . $id->{contrib_id})
              unless $contrib;
            $contrib->selected_contrib_type($id->{contrib_type_id});
            push @contribs, $contrib;
        }
        return @contribs;
    }

    # store list of contributors, passed as either objects or hashes
    foreach my $rec (@_) {
        if (ref($rec) and ref($rec) eq 'HASH') {
            croak(
                "invalid data passed to contribs: hashes must contain contrib_id and contrib_type_id."
            ) unless $rec->{contrib_id} and $rec->{contrib_type_id};

            push(@contribs, $rec);
        } elsif (ref($rec) and $rec->isa(pkg('Contrib'))) {
            croak(
                "invalid data passed to contrib: contributor objects must have contrib_id and selected_contrib_type set."
            ) unless $rec->contrib_id and $rec->selected_contrib_type;

            push(
                @contribs,
                {
                    contrib_id      => $rec->contrib_id,
                    contrib_type_id => $rec->selected_contrib_type
                }
            );

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

=item $story->tags()

Get/Set the tags for this story

=cut

sub tags {
    my ($self, $tags) = @_;
    my $dbh = dbh;
    my $id  = $self->story_id;
    if ($tags) {
        die "invalid data passed to tags: must be an array reference"
          unless ref $tags && ref $tags eq 'ARRAY';

        local $dbh->{AutoCommit} = 0;
        my $sth = $dbh->prepare_cached('INSERT INTO story_tag (story_id, tag, ord) VALUES (?,?, ?)');
        eval {
            # clear out any old tags before we insert the new ones
            $dbh->do('DELETE FROM story_tag WHERE story_id = ?', {}, $id);
            my $ord = 1;
            foreach my $tag (@$tags) {
                $sth->execute($id, $tag, $ord++);
            }
        };
        if (my $e = $@) {
            $dbh->rollback();
            die $e;
        }
    } else {
        $tags = [];
        my $sth = $dbh->prepare_cached('SELECT tag FROM story_tag WHERE story_id = ? ORDER BY ord');
        $sth->execute($id);
        while (my $row = $sth->fetchrow_arrayref) {
            push(@$tags, $row->[0]);
        }
    }
    return @$tags;
}

=item C<< $all_version_numbers = $story->all_versions(); >>

Returns an arrayref containing all the existing version numbers for this story.

=cut

sub all_versions {
    my $self = shift;
    my $dbh  = dbh;
    return $dbh->selectcol_arrayref('SELECT version FROM story_version WHERE story_id=?',
        undef, $self->story_id);
}

=item C<< $story->prune_versions(number_to_keep => 10); >>

Deletes old versions of this story. By default prune_versions() keeps
the number of versions specified by SavedVersionsPerStory in krang.conf;
this can be overridden as above. In either case, it returns the number of 
versions actually deleted.

=cut

sub prune_versions {
    my ($self, %args) = @_;
    my $dbh = dbh;

    # figure out how many versions to keep
    my $number_to_keep = $args{number_to_keep} || SavedVersionsPerStory;
    return 0 unless $number_to_keep;

    # figure out how many versions can be deleted
    my @all_versions     = @{$self->all_versions};
    my $number_to_delete = @all_versions - $number_to_keep;
    return 0 unless $number_to_delete > 0;

    # delete the oldest ones (which will be first since the list is ascending)
    my @versions_to_delete = splice(@all_versions, 0, $number_to_delete);
    $dbh->do(
        'DELETE FROM story_version WHERE story_id = ? AND version IN ('
          . join(',', ("?") x @versions_to_delete) . ')',
        undef, $self->story_id, @versions_to_delete
    ) unless $args{test_mode};
    return $number_to_delete;
}

=item C<< $story->save() >>

=item C<< $story->save(keep_version => 1, no_history => 1, no_verify_checkout => 1) >>

Save the story to the database.  This is the only call which
will make permanent changes in the database (checkin/checkout make
transient changes).  Increments the version number unless called with
C<keep_version> is true. Add appropriate entries to the C<history>
and C<story_version> tables unless C<no_history> is true.

If the story is not checked out by the user attempting the save, then
an error will be thrown unless C<no_verify_checkout> is true.

Will throw a C<Krang::Story::DuplicateURL> exception with a C<story_id> field
if saving this story would conflict with an existing story or category.

Will throw a C<Krang::Story::MissingCategory> exception if this story
doesn't have at least one category.  This can happen when a C<clone()>
results in a story with no categories.

Will throw a C<Krang::Story::NoCategoryEditAccess> exception if the
current user doesn't have edit access to the primary category set for
the story.

Will throw a C<Krang::Story::NoEditAccess> exception if the current user
doesn't have edit access to the story.

=cut

sub save {
    my ($self, %args) = @_;

    # make sure it's ok to save
    $self->_verify_checkout() unless $args{no_verify_checkout};

    # make sure we've got at least one category
    Krang::Story::MissingCategory->throw(message => "missing category")
      unless $self->category;

    # Is user allowed to otherwise edit this object?
    unless($args{ignore_permissions}) {
        Krang::Story::NoEditAccess->throw(
            message  => "Not allowed to edit story",
            story_id => $self->story_id
        ) unless ($self->may_edit);

        # make sure we have edit access to the primary category
        Krang::Story::NoCategoryEditAccess->throw(
            message     => "Not allowed to edit story in this category",
            category_id => $self->category->category_id
        ) unless ($self->category->may_edit);
    }

    # unless we're halfway through a category-index conversion...
    unless ($self->{slug} eq '_TEMP_SLUG_FOR_CONVERSION_') {

        # make sure it's got a unique URL
        $self->_verify_unique() unless $args{no_verify_unique};

        # make sure it's not a reserved URL
        $self->_verify_reserved() unless $args{no_verify_reserved};

        # update the version number
        $self->{version}++ unless $args{keep_version};
    }

    # save element tree, populating $self->{element_id}
    $self->_save_element();

    # save core data, populating story_id
    $self->_save_core();

    # save categories
    $self->_save_cat() unless $args{skip_categories};

    # save schedules
    $self->_save_schedules($args{keep_version});

    # save contributors
    $self->_save_contrib;

    # save a serialized copy in the version table
    $self->_save_version unless $args{skip_save_version};

    # prune previous versions from the version table (see TopLevel.pm::versions_to_keep)
    $self->prune_versions(number_to_keep => $self->class->versions_to_keep);

    # save any category links
    $self->_save_category_links();

    # register creation if is the first version
    add_history(
        object => $self,
        action => 'new',
    ) if ($self->{version} == 1) && !$args{keep_version} && !$args{no_history};

    # register the save
    add_history(
        object => $self,
        action => 'save',
    ) unless $args{no_history};
}

sub _save_category_links {
    my $self = shift;
    my $dbh  = dbh();

    # remove any existing links
    $dbh->do('DELETE FROM story_category_link WHERE story_id = ?', {}, $self->story_id);

    # handle to update/insert links
    my $sth = $dbh->prepare_cached(
        q/INSERT INTO story_category_link
        (story_id, category_id,
        publish_if_modified_story_in_cat, publish_if_modified_story_below_cat, 
        publish_if_modified_media_in_cat, publish_if_modified_media_below_cat) 
        VALUES (?,?,?,?,?,?)/
    );
    my $update_sth = $dbh->prepare_cached(
        q/UPDATE story_category_link SET
        publish_if_modified_story_in_cat = ?, publish_if_modified_story_below_cat = ?,
        publish_if_modified_media_in_cat = ?, publish_if_modified_media_below_cat = ?
        WHERE story_id = ? AND category_id = ?/
    );
    my $find_entry_sth = $dbh->prepare_cached(
        q/SELECT publish_if_modified_story_in_cat, publish_if_modified_story_below_cat,
        publish_if_modified_media_in_cat, publish_if_modified_media_below_cat
        FROM story_category_link WHERE story_id = ? AND category_id = ?/
    );

    # look down for CategoryLink
    foreach_element {
        my $el = $_;
        return unless $el;
        return unless $el->class->isa(pkg('ElementClass::CategoryLink'));

        my $cat = $el->data;
        return unless $cat && $cat->isa(pkg('Category'));

        my %flags = (
            story_in    => $el->class->publish_if_modified_story_in_cat    ? 1 : 0,
            story_below => $el->class->publish_if_modified_story_below_cat ? 1 : 0,
            media_in    => $el->class->publish_if_modified_media_in_cat    ? 1 : 0,
            media_below => $el->class->publish_if_modified_media_below_cat ? 1 : 0,
        );

        eval {
            local $sth->{PrintError} = 0;
            $sth->execute(
                $self->story_id,     $cat->category_id, $flags{story_in},
                $flags{story_below}, $flags{media_in},  $flags{media_below},
            );
        };
        if (my $e = $@) {
            if ($e =~ /Duplicate entry/i) {
                # we have multiple category links for this cat/story combo so try and merge them
                $find_entry_sth->execute($self->story_id, $cat->category_id);
                my $row = $find_entry_sth->fetchrow_hashref;
                $find_entry_sth->finish();
                $flags{story_in}    ||= $row->{publish_if_modified_story_in_cat};
                $flags{story_below} ||= $row->{publish_if_modified_story_below_cat};
                $flags{media_in}    ||= $row->{publish_if_modified_media_in_cat};
                $flags{media_below} ||= $row->{publish_if_modified_media_below_cat};

                # now try the insert again
                $update_sth->execute(
                    $flags{story_in},    $flags{story_below}, $flags{media_in},
                    $flags{media_below}, $self->story_id,     $cat->category_id,
                );
            } else {
                die $e;
            }
        }
    }
    $self->element;
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
        $query =
          'UPDATE story SET ' . join(', ', map { "$_ = ?" } STORY_FIELDS) . ' WHERE story_id = ?';
    } else {
        $query =
            'INSERT INTO story ('
          . join(', ', STORY_FIELDS)
          . ') VALUES ('
          . join(',', ("?") x STORY_FIELDS) . ')';
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
    $dbh->do($query, undef, @data, ($update ? $self->{story_id} : ()));

    # extract the ID on insert
    $self->{story_id} = $dbh->{mysql_insertid}
      unless $update;
}

# save the element tree
sub _save_element {
    my $self = shift;
    return unless $self->{element};    # if the element tree was never
                                       # loaded, it can't have changed
    $self->{element}->save();
    $self->{element_id} = $self->{element}->element_id;
}

# save schedules
sub _save_schedules {
    my $self         = shift;
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
    my $dbh  = dbh();

    # delete existing relations
    $dbh->do('DELETE FROM story_category WHERE story_id = ?', undef, $self->{story_id});

    # insert category relations, including urls
    my @urls    = $self->urls;
    my @cat_ids = @{$self->{category_ids}};
    for (0 .. $#cat_ids) {
        $dbh->do(
            'INSERT INTO story_category (story_id, category_id, ord, url)
                  VALUES (?,?,?,?)', undef,
            $self->{story_id}, $cat_ids[$_], $_, $urls[$_]
        );
    }
}

# save contributors
sub _save_contrib {
    my $self = shift;
    my $dbh  = dbh();

    $dbh->do('DELETE FROM story_contrib WHERE story_id = ?', undef, $self->{story_id});

    my $ord = 0;
    $dbh->do(
        'INSERT INTO story_contrib 
                    (story_id, contrib_id, contrib_type_id, ord)
                  VALUES (?,?,?,?)', undef,
        $self->{story_id},           $_->{contrib_id},
        $_->{contrib_type_id},       ++$ord
    ) for @{$self->{contrib_ids}};
}

# save to the version table
sub _save_version {
    my $self = shift;
    my $dbh  = dbh;

    # save version
    $dbh->do(
        'REPLACE INTO story_version (story_id, version, data) 
              VALUES (?,?,?)', undef,
        $self->{story_id}, $self->{version}, nfreeze($self)
    );

}

# check for duplicate URLs
sub _verify_unique {
    my $self = shift;
    my $dbh  = dbh;

    my @urls = $self->urls;
    return unless @urls;

    # first - unless we're a category index - make sure no categories have one of our URLs
    if (!$self->is_category_index) {
        my $query =
          'SELECT category_id, url FROM category WHERE (' . join(' OR ', ('url = ?') x @urls) . ')';
        my $result = $dbh->selectall_arrayref($query, undef, @urls);
        if ($result && @$result) {
            my @dupes = map { {id => $_->[0], url => $_->[1]} } @$result;
            Krang::Story::DuplicateURL->throw(
                message    => "Category has our URL",
                categories => \@dupes
            );
        }
    }

    # then look for stories that have one of our URLs without being retired nor trashed
    my $query =
        'SELECT s.story_id, url, retired, trashed '
      . 'FROM   story s '
      . 'LEFT   JOIN story_category as sc '
      . 'ON     s.story_id = sc.story_id '
      . 'WHERE  retired = 0 AND trashed = 0 AND ('
      . join(' OR ', ('url = ?') x @urls) . ')'
      . ($self->{story_id} ? ' AND s.story_id != ?' : '');
    my $result = $dbh->selectall_arrayref($query, undef, @urls, $self->{story_id} || ());
    if ($result && @$result) {
        my @dupes = map { {id => $_->[0], url => $_->[1]} } @$result;
        @dupes = sort {
            $a->{id} > $b->{id} ? 1 :    # sort dupes by ID and then URL
              ($a->{id} < $b->{id} ? -1 : $a->{url} cmp $b->{url})
        } @dupes;
        Krang::Story::DuplicateURL->throw(message => "Duplicate URL", stories => \@dupes);
    }
}

# makes sure this story doesn't have a reserved URL
sub _verify_reserved {
    my $self = shift;
    return unless ReservedURLs;
    foreach my $url ($self->urls) {
        # make sure they end with a slash
        $url = "$url/" unless $url =~ /\/$/;
        $url = "$url/" unless $url =~ /\/$/;

        # create a relative version of this url
        my $relative_url = $url;
        $relative_url =~ s/^[^\/]+\//\//;

        # now compare them to the configured ReservedURLs
        foreach my $reserved (split(/\s+/, ReservedURLs)) {
            $reserved = "$reserved/" unless $reserved =~ /\/$/;
            my $compare = $reserved =~ /^\// ? $relative_url : $url;
            # throw exception
            Krang::Story::ReservedURL->throw(
                message  => "Reserved URL ($reserved)",
                reserved => $reserved,
            ) if $compare eq $reserved;
        }
    }
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

=item tag

Search for stories that have the given tag.

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

=item full_text_string

Find stories by performing a full-text search. (Any words
enclosed in quotes will be matched as a complete string, and
whitespace around the edges of a quoted phrase will cause
partial-word matches to be ignored.)

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

Set this to an arrayref of element class name(s) to find stories of
the corresponding type(s) only.

=item contrib_simple

This performs a simple search against contributors and finds stories
which link to the contributor.

=item story_id

Load a story by ID.  Given an array of story IDs, loads all the identified
stories.

=item story_uuid

Load a story by UUID. Given an array of story UUIDs, loads all the identified
stories.

=item version

Combined with C<story_id> (and only C<story_id>), loads a specific
version of a story.  Unlike C<revert()>, this object has C<version>
set to the actual version number of the loaded object.

=item simple_search

Performs a per-word LIKE match against title and URL, and an exact
match against story_id if a word is a number.

=item simple_search_check_full_text

If set to 1 and passed along with a simple_search, also
performs a full-text search on the input. 

=item exclude_story_ids

Pass an array ref of IDs to be excluded from the result set

=item exclude_story_uuids

Pass an array ref of UUIDs to be excluded from the result set

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

=item include_live

Include live stories in the search result. Live stories are stories
that are neither retired nor have been moved to the trashbin. Set
this option to 0, if find() should not return live stories.  The
default is 1.

=item include_retired

Set this option to 1 if you want to include retired stories in the
search result. The default is 0.

=item include_trashed

Set this option to 1 if you want to include trashed stories in the
search result. Trashed stories live in the trashbin. The default is 0.

B<NOTE:>When searching for story_id, these three include_* flags are
not taken into account!

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

=item ignore_permissions

When true, any permission restrictions of the stories are ignored.
B<WARNING> - Be very careful when using this option so that data isn't
exposed to the end user. This option should only be used in Admin scripts
or actions where the resulting data is not shown to the end user.

=back

=cut

{

    # used to detect normal story fields versus more exotic searches
    my %simple_fields = map { $_ => 1 } grep { $_ !~ /_date$/ } STORY_FIELDS;

    sub find {
        my $pkg  = shift;
        my %args = @_;
        my $dbh  = dbh();

        # get search parameters out of args, leaving just field specifiers
        my $order_by = delete $args{order_by} || 's.story_id';
        my $order_dir = delete $args{order_desc} ? 'DESC' : 'ASC';
        my $limit           = delete $args{limit}           || 0;
        my $offset          = delete $args{offset}          || 0;
        my $count           = delete $args{count}           || 0;
        my $ids_only        = delete $args{ids_only}        || 0;
        my $include_retired = delete $args{include_retired} || 0;
        my $include_trashed = delete $args{include_trashed} || 0;
        my $include_live    = delete $args{include_live};
        $include_live = 1 unless defined($include_live);
        my $simple_full_text = delete $args{simple_search_check_full_text} || 0;
        my $ignore_perms    = delete $args{ignore_permissions} || 0;

        # determine whether or not to display hidden stories.
        my $show_hidden = delete $args{show_hidden} || 0;

        foreach (qw/story_id checked_out checked_out_by class desk_id may_see may_edit/) {
            if (exists($args{$_})) { $show_hidden = 1; last; }
        }

        # set bool to determine whether to use $row or %row for binding below
        my $single_column = $ids_only || $count ? 1 : 0;

        # check for invalid argument sets
        croak(  __PACKAGE__
              . "->find(): 'count' and 'ids_only' were supplied. "
              . "Only one can be present.")
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
            if ($key eq 'story_id' && ref($value) && ref($value) eq 'ARRAY' && scalar(@$value) > 0)
            {

                # an array of IDs selects a list of stories by ID
                push @where, 's.story_id IN (' . join(',', ("?") x @$value) . ')';
                push @param, @$value;
                next;
            }

            # handle story_uuid => [1, 2, 3]
            if (   $key eq 'story_uuid'
                && ref($value)
                && ref($value) eq 'ARRAY'
                && scalar(@$value) > 0)
            {

                # an array of IDs selects a list of stories by ID
                push @where, 's.story_uuid IN (' . join(',', ("?") x @$value) . ')';
                push @param, @$value;
                next;
            }

            # handle class => ['article', 'cover']
            if ($key eq 'class' && ref($value) && ref($value) eq 'ARRAY' && scalar(@$value) > 0) {

                # an array of classes selects a list of stories by class
                push @where, 's.class IN (' . join(',', ("?") x @$value) . ')';
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
                push(@where, 's.story_id = sc.story_id');
                push(@where, 'sc.category_id = ?');
                push(@param, $value);
                next;
            }

            # handle search by primary_category_id
            if ($key eq 'primary_category_id') {
                push(@where, 's.story_id = sc.story_id');
                push(@where, 'sc.category_id = ?', 'sc.ord = 0');
                push(@param, $value);
                next;
            }

            # handle below_category_id
            if ($key eq 'below_category_id') {
                push(@where, 's.story_id = sc.story_id');
                my ($cat) = pkg('Category')->find(category_id => $value);
                if ($cat) {
                    my @ids = ($value, $cat->descendants(ids_only => 1));
                    push(@where, 's.story_id = sc.story_id');
                    push(@where, 'sc.category_id IN (' . join(',', ('?') x @ids) . ')');
                    push(@param, @ids);
                }
                next;
            }

            # handle below_primary_category_id
            if ($key eq 'below_primary_category_id') {
                push(@where, 's.story_id = sc.story_id');
                my ($cat) = pkg('Category')->find(category_id => $value);
                if ($cat) {
                    my @ids = ($value, $cat->descendants(ids_only => 1));
                    push(@where, 's.story_id = sc.story_id AND sc.ord = 0');
                    push(@where, 'sc.category_id IN (' . join(',', ('?') x @ids) . ')');
                    push(@param, @ids);
                }
                next;
            }

            # handle search by site_id
            if ($key eq 'site_id') {

                # need to bring in category
                $from{"category as c"}        = 1;
                push(@where, 's.story_id = sc.story_id');
                push(@where, 'sc.category_id = c.category_id');
                if (ref $args{$key} eq 'ARRAY') {
                    push(@where, 'c.site_id IN (' . join(',', ('?') x @{$args{$key}}) . ')');
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
                $from{"category as c"}        = 1;
                push(@where, 's.story_id = sc.story_id');
                push(@where, 'sc.category_id = c.category_id');
                if (ref $args{$key} eq 'ARRAY') {
                    push(@where, 'c.site_id IN (' . join(',', ('?') x @{$args{$key}}) . ')');
                    push(@param, @{$args{$key}});
                } else {
                    push(@where, 'c.site_id = ?', 'sc.ord = 0');
                    push(@param, $value);
                }
                next;
            }

            # make the urls consistent by striping the scheme and adding a trailing url
            if( $key eq 'url' || $key eq 'primary_url' || $key eq 'non_primary_url' ) {
                $value =~ s/^https?:\/\///;
                $value .= '/' if $value !~ /\/$/ && !$like;
            }

            # handle search by url
            if ($key eq 'url') {
                push(@where, 's.story_id = sc.story_id');
                push(@where, ($like ? 'sc.url LIKE ?' : 'sc.url = ?'));
                push(@param, $value);
                next;
            }

            # handle search by primary_url
            if ($key eq 'primary_url') {
                push(@where, 's.story_id = sc.story_id');
                push(@where, ($like ? 'sc.url LIKE ?' : 'sc.url = ?'), 'sc.ord = 0');
                push(@param, $value);
                next;
            }

            # handle search by non-primary_url
            if ($key eq 'non_primary_url') {
                push(@where, 's.story_id = sc.story_id');
                push(@where, ($like ? 'sc.url LIKE ?' : 'sc.url = ?'), 'sc.ord != 0');
                push(@param, $value);
                next;
            }

            # handle search by tag
            if( $key eq 'tag' ) {
                push(@where, 'st.tag = ?');
                push(@param, $value);
                next;
            }

            # handle contrib_simple
            if ($key eq 'contrib_simple') {
                $from{"story_contrib as scon"} = 1;
                $from{"contrib as con"}        = 1;
                push(@where, 's.story_id = scon.story_id');
                push(@where, 'con.contrib_id = scon.contrib_id');

                my @words = split(/\s+/, $args{'contrib_simple'});
                foreach my $word (@words) {
                    push(
                        @where,
                        q{concat(
                      coalesce(con.first,''), ' ',
                      coalesce(con.middle,''), ' ',
                      coalesce(con.last),'') LIKE ?
                }
                    );
                    push(@param, "%${word}%");
                }
                next;
            }

            # handle creator_simple
            if ($key eq 'creator_simple') {
                $from{"history as h"} = 1;
                $from{"user as u"}    = 1;
                push(@where, 's.story_id = h.object_id');
                push(@where,
                    "(h.object_type = 'Krang::Story' or h.object_type ='" . pkg('Story') . "')");
                push(@where, "h.action = 'new'");
                push(@where, 'h.user_id = u.user_id');

                my @words = split(/\s+/, $args{'creator_simple'});
                foreach my $word (@words) {
                    push(@where, q{concat(u.first_name,' ',u.last_name) LIKE ?});
                    push(@param, "%${word}%");
                }
                next;
            }

            # handle simple search
            if ($key eq 'simple_search') {
                push(@where, 's.story_id = sc.story_id');
                if ($simple_full_text) {
                    $from{"element as el"} = 1;
                    push(@where, 'el.root_id = s.element_id');
                }
                foreach my $phrase ($pkg->_search_text_to_phrases($value)) {
                    my $numeric = ($phrase =~ /^\d+$/) ? 1 : 0;
                    if (!$numeric) {
                        $phrase =~ s/_/\\_/g;    # escape any literal
                        $phrase =~ s/%/\\%/g;    # SQL wildcard chars
                    }
                    my $where = join(' OR ',
                        ($numeric ? 's.story_id = ?' : ()),
                        's.title LIKE ?',
                        'sc.url LIKE ?');
                    push(@param, ($numeric ? ($phrase) : ()), "%${phrase}%", "%${phrase}%");
                    if ($simple_full_text) {
                        if ($phrase =~ /^\s(.*)\s$/) {

                            # user wants full-word match: replace spaces w/ MySQL word boundaries
                            $where .= ' OR el.data RLIKE CONCAT( "[[:<:]]", ?, "[[:>:]]" )';
                            push(@param, $1);
                        } else {

                            # user wants regular substring match
                            $where .= ' OR el.data LIKE ?';
                            push(@param, "%${phrase}%");
                        }
                    }
                    push(@where, "($where)");
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
                        push @param, $value->[0]->mysql_datetime, $value->[1]->mysql_datetime;
                    } elsif ($value->[0]) {
                        push @where, "$key >= ?";
                        push @param, $value->[0]->mysql_datetime;
                    } elsif ($value->[1]) {
                        push @where, "$key <= ?";
                        push @param, $value->[1]->mysql_datetime;
                    }
                } else {
                    croak(
                        "Bad date argument, must be either an array of two Time::Piece objects or one Time::Piece object."
                    );
                }
                next;
            }

            # handle exclude_story_ids => [1, 2, 3]
            if ($key eq 'exclude_story_ids') {
                my @exclude = grep { $_ } @$value;
                if (@exclude) {
                    push(@where, ('s.story_id != ?') x @exclude);
                    push(@param, @exclude);
                }
                next;
            }

            # handle exclude_story_uuids => [1, 2, 3]
            if ($key eq 'exclude_story_uuids') {
                my @exclude = grep { $_ } @$value;
                if (@exclude) {
                    push(@where, ('s.story_uuid != ?') x @exclude);
                    push(@param, @exclude);
                }
                next;
            }

            # handle published flag
            if ($key eq 'published') {
                my $ps =
                  ($args{published} eq '1')
                  ? 's.published_version > 0'
                  : '(s.published_version IS NULL OR s.published_version = 0)';
                push(@where, $ps);
                next;
            }

            # handle may_see
            if ($key eq 'may_see' && !$ignore_perms) {
                push(@where, 'ucpc.may_see = ?');
                push(@param, 1);
                next;
            }

            # handle may_edit
            if ($key eq 'may_edit' && !$ignore_perms) {
                push(@where, 'ucpc.may_edit = ?');
                push(@param, 1);
                next;
            }

            # handle element_index
            if ($key eq 'element_index') {

                # setup join to element_index
                $from{"element as e"}        = 1;
                $from{"element_index as ei"} = 1;
                push(@where, 's.element_id = e.root_id');
                push(@where, 'e.element_id = ei.element_id');

                # produce where clause
                push(@where, 'e.class = ?', ($like ? 'ei.value LIKE ?' : 'ei.value = ?'));
                push(@param, $value->[0], $value->[1]);
                next;
            }

            # handle full-text search
            if ($key eq 'full_text_string') {
                $from{"element as el"} = 1;
                push(@where, 'el.root_id = s.element_id');
                foreach my $phrase ($pkg->_search_text_to_phrases($value)) {
                    $phrase =~ s/_/\\_/g;
                    $phrase =~ s/%/\\%/g;
                    if ($phrase =~ /^\s(.*)\s$/) {

                        # user wants full-word match: replace spaces w/ MySQL word boundaries
                        push(@where, '(el.data RLIKE CONCAT( "[[:<:]]", ?, "[[:>:]]" ))');
                        push(@param, $1);
                    } else {

                        # user wants regular substring match
                        push(@where, '(el.data LIKE ?)');
                        push(@param, "%${phrase}%");
                    }
                }
                next;
            }

            croak("Unknown find key '$key'");
        }

        # handle ordering by primary URL, which is in story_category
        if ($order_by eq 'url') {
            push(@where, 's.story_id = sc.story_id');
            push(@where, 'sc.ord = 0');
            $order_by = 'sc.url';
        } elsif ($order_by !~ /\w+\./) {
            $order_by = "s." . $order_by;
        }

        # Add user_id into the query
        if(!$ignore_perms) {
            my $user_id = $ENV{REMOTE_USER} || croak("No user_id in REMOTE_USER");
            push(@where, "ucpc.user_id = ?");
            push(@param, $user_id);
        }

        # restrict to visible stories unless show_hidden is passed.
        unless ($show_hidden) {
            push(@where, 's.hidden = 0');
        }

        # include live/retired/trashed
        unless ($args{story_id} or $args{story_uuid}) {
            if ($include_live) {
                push(@where, 's.retired = 0')  unless $include_retired;
                push(@where, 's.trashed  = 0') unless $include_trashed;
            } else {
                if ($include_retired) {
                    if ($include_trashed) {
                        push(@where, 's.retired = 1 AND s.trashed = 1');
                    } else {
                        push(@where, 's.retired = 1 AND s.trashed = 0');
                    }
                } else {
                    push(@where, 's.trashed = 1') if $include_trashed;
                }
            }
        }

        # construct base query
        my $query;
        my $from = " FROM story AS s 
                 LEFT JOIN story_category AS sc
                   ON s.story_id = sc.story_id ";
        if(!$ignore_perms) {
            $from .= " LEFT JOIN user_category_permission_cache as ucpc
                   ON sc.category_id = ucpc.category_id ";
        }

        # join to the story_tag table if needed
        if( $args{tag} ) {
            $from .= ' LEFT JOIN story_tag AS st ON (s.story_id = st.story_id) ';
        }

        my $group_by = 0;

        if ($count) {
            $query = "SELECT COUNT(DISTINCT(s.story_id)) $from";
        } elsif ($ids_only) {
            $query = "SELECT DISTINCT(s.story_id) $from";
        } elsif( $ignore_perms ) {
            $query = "SELECT " . join(', ', map { "s.$_" } STORY_FIELDS) . $from;
        } else {

            # Get user asset permissions -- overrides may_edit if false
            my $may_edit;
            if (pkg('Group')->user_asset_permissions('story') eq "edit") {
                $may_edit = "ucpc.may_edit as may_edit";
            } else {
                $may_edit = $dbh->quote("0") . " as may_edit";
            }

            $query =
                "SELECT "
              . join(', ', map { "s.$_" } STORY_FIELDS)
              . ",ucpc.may_see as may_see, $may_edit"
              . $from;
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
            $query .= " LIMIT $offset, 18446744073709551615";
        }

        debug(__PACKAGE__ . "::find() SQL: " . $query);
        debug(__PACKAGE__ . "::find() SQL ARGS: " . join(', ', map { defined $_ ? $_ : 'undef' } @param));

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

        # we'll fold in user desk permissions after constructing story objects
        my %desk_permissions = pkg('Group')->user_desk_permissions;

        # construct objects from results
        my ($row, @stories, $result);
        while ($row = $sth->fetchrow_arrayref()) {
            my $obj = bless({}, $pkg);
            @{$obj}{(STORY_FIELDS, 'may_see', 'may_edit')} = @$row;

            # objectify dates
            for (qw(cover_date publish_date)) {
                if ($obj->{$_} and $obj->{$_} ne '0000-00-00 00:00:00') {
                    $obj->{$_} = eval {Time::Piece->strptime($obj->{$_}, '%Y-%m-%d %H:%M:%S')};
                } else {
                    $obj->{$_} = undef;
                }
            }

            # load category_ids and urls
            $result = $dbh->selectall_arrayref(
                'SELECT category_id, url '
                  . 'FROM story_category '
                  . 'WHERE story_id = ? ORDER BY ord',
                undef, $obj->{story_id}
            );
            @{$obj}{('category_ids', 'urls')} = ([], []);
            foreach my $row (@$result) {
                push @{$obj->{category_ids}}, $row->[0];
                push @{$obj->{url_cache}},    $row->[1];
            }

            # load contribs
            $result = $dbh->selectall_arrayref(
                'SELECT contrib_id, contrib_type_id FROM story_contrib '
                  . 'WHERE story_id = ? ORDER BY ord',
                undef, $obj->{story_id}
            );
            $obj->{contrib_ids} =
              @$result
              ? [map { {contrib_id => $_->[0], contrib_type_id => $_->[1]} } @$result]
              : [];

            # fold in user desk permissions
            if (my $desk_id = $obj->desk_id) {
                $desk_permissions{$desk_id} eq 'edit' or $obj->{may_edit} = 0;
            }

            push @stories, $obj;
        }

        # finish statement handle
        $sth->finish();

        return @stories;
    }
}

# this private helper method takes a search string and returns
# an array of phrases - e.g. ONE TWO THREE returns (ONE, TWO,
# THREE) whereas "ONE TWO" THREE returns (ONE TWO, THREE)
sub _search_text_to_phrases {
    my ($pkg, $text) = @_;
    return () unless (defined $text);

    # first add any quoted text as multi-word phrase(s)
    my @phrases;
    while ($text =~ s/([\'\"])([^\1]*?)\1//) {
        my $phrase = $2;
        $phrase =~ s/\s+/ /;
        push @phrases, $phrase;
    }

    # then split remaining text into one-word phrases
    push @phrases, (split /\s+/, $text);
    return @phrases;
}

=item C<< Krang::Story->transform_stories(%args) >>

Transform desired stories. This method is useful for performing
bulk transforms of stories. You can do things like add new elements 
or delete existing elements which makes it really handy for doing
element library changes or upgrades.

It takes the following named arguments:

=over

=item * callback

A subroutine that actually performs the translation of the story. It 
receives that story being transformed and a flag indicating whether or
not the story is a live current version (and not a past version).

This subroutine is expected to return the transformed version of the story.

=item * past_versions

A boolean flag indicating whether or not you want to operate on past versions
of stories. If this is false, then you will just be given the current version.

=item * prune_corrupt_versions

If for some reason a past version of a story cannot be thawed out (this can happen
if the element libraries change too drastically) then there's not much that
can be done for that version of the story. If this flag is true, then we will delete
that version of the story completely from the database.

=back

Any other arguments passed in will be sent to the C<find()> method.

    # add a foo element to all stories of the "bar" class
    pkg('Story')->transform_stories(
        class => ['bar'],
        past_versions => 1,
        callback => sub {
            my %args = @_;
            my ( $story, $live ) = @args{ qw( story live ) };
            my $element = $story->element;
            $element->add_child(class => 'foo', value => 'blah, blah');

            return $story;
        },
    );

=cut

sub transform_stories {
    my ($pkg, %args) = @_;
    my $callback = delete $args{callback}
      or croak('You must provide a callback for transform_stories()');
    my $past_versions = delete $args{past_versions};
    my $prune_corrupt = delete $args{prune_corrupt_versions};

    # make find() do all the hard stuff
    my @stories = $pkg->find(%args);
    foreach my $story (@stories) {
        my $story_id = $story->story_id;

        # transform and save the live story
        $story = $callback->(story => $story, live => 1, version => $story->version);
        $story->save(keep_version => 1, no_history => 1, no_verify_checkout => 1, ignore_permissions => 1);

        if ($past_versions) {
            my $dbh = dbh;

            # load each old version, give it to the callback and then replace what's in the db
            foreach my $v (@{$story->all_versions}) {
                next if $v == $story->version;
                my $old_story;
                eval { ($old_story) = $pkg->_load_version($story_id, $v) };

                # if we can't even load, just skip it
                if ($@) {
                    if ($prune_corrupt) {
                        warn "Removing corrupt story $story_id version $v";
                        $dbh->do('DELETE FROM story_version WHERE story_id = ? AND version = ?',
                            undef, $story_id, $v);
                    } else {
                        warn "Can't load version $v of story $story_id: $@\n";
                    }
                    next;
                }
                $old_story = $callback->(story => $old_story, live => 0, version => $v);

                # re-save version
                $dbh->do('REPLACE INTO story_version (story_id, version, data) VALUES (?,?,?)',
                    undef, $story_id, $v, nfreeze($old_story));
            }
        }
    }
}

=item C<< Krang::Story->known_tags() >>

Returns a sorted list of all known tags used on story objects. 

=cut

sub known_tags {
    my $pkg = shift;
    my @tags;
    my $sth = dbh()->prepare_cached('SELECT DISTINCT(tag) FROM story_tag ORDER BY tag');

    $sth->execute();
    while (my $row = $sth->fetchrow_arrayref) {
        push(@tags, $row->[0]);
    }
    return @tags;
}

sub _load_version {
    my ($pkg, $story_id, $version) = @_;
    my $dbh = dbh;

    my ($data) = $dbh->selectrow_array(
        'SELECT data FROM story_version
                                        WHERE story_id = ? AND version = ?',
        undef, $story_id, $version
    );
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

If the story is checked out and thus can't be moved to the desired
desk, throws a C<Krang::Story::CheckedOut> exception.

If the desk has been deleted in the meantime, throws a
C<Krang::Story::NoDesk> exception.

=cut

sub move_to_desk {
    my ($self, $desk_id) = @_;
    my $dbh = dbh();

    croak(__PACKAGE__ . "->move_to_desk requires a desk_id") if not $desk_id;

    my $story_id = $self->story_id;

    # check status
    my ($co) = $dbh->selectrow_array(
        'SELECT checked_out FROM story
           WHERE story_id = ?', undef, $story_id
    );

    Krang::Story::CheckedOut->throw(
        message => "Story is checked out and can't be moved to desk",
        desk_id => $desk_id
    ) if $co;

    Krang::Story::NoDesk->throw(
        message => "Story can't be moved to non existing desk",
        desk_id => $desk_id
    ) unless scalar(pkg('Desk')->find(desk_id => $desk_id));

    $dbh->do(
        'UPDATE story
              SET desk_id = ?, last_desk_id = ?
              WHERE story_id = ?',
        undef, $desk_id, $self->desk_id, $story_id
    );

    # update desk id in our story object
    $self->{last_desk_id} = $self->{desk_id};
    $self->{desk_id}      = $desk_id;

    add_history(
        action  => 'move',
        object  => $self,
        desk_id => $desk_id
    );
}

=item C<< $story->checkout() >>

=item C<< Krang::Story->checkout($story_id) >>

Checkout the story, preventing other users from editing it.  Croaks if
the story is already checked out.

=cut

sub checkout {
    my ($self, $story_id, $args) = @_;
    $args ||= {};
    $self = (pkg('Story')->find(story_id => $story_id))[0]
      unless $self;
    my $dbh     = dbh();
    my $user_id = $ENV{REMOTE_USER};

    unless($args->{ignore_permissions}) {
        # Is user allowed to otherwise edit this object?
        Krang::Story::NoEditAccess->throw(
            message  => "Not allowed to edit story",
            story_id => $self->story_id
        ) unless ($self->may_edit);
    }

    # short circuit checkout
    return
      if $self->{checked_out}
          and $self->{checked_out_by} == $user_id;

    eval {

        # lock story for an atomic test and set on checked_out
        $dbh->do("LOCK TABLES story WRITE");

        # check status
        my ($co, $uid) = $dbh->selectrow_array(
            'SELECT checked_out, checked_out_by FROM story
              WHERE story_id = ?', undef, $self->{story_id}
        );

        Krang::Story::CheckedOut->throw(
            message => "Story $self->{story_id} is already checked out by user '$uid'",
            user_id => $uid,
        ) if ($co and $uid != $user_id);

        # checkout the story
        $dbh->do(
            'UPDATE story
                  SET checked_out = ?, checked_out_by = ?,
                      desk_id     = ?, last_desk_id   = ?
                  WHERE story_id = ?', undef,
            1, $user_id, undef, $self->{desk_id}, $self->{story_id}
        );

        # unlock template table
        $dbh->do("UNLOCK TABLES");
    };

    if (my $e = $@) {
        # unlock the table, so it's not locked forever
        $dbh->do("UNLOCK TABLES");
        croak($e);
    }

    # update some fields
    $self->{checked_out}    = 1;
    $self->{checked_out_by} = $user_id;
    $self->{last_desk_id}   = $self->{desk_id};
    $self->{desk_id}        = undef;

    add_history(
        object => $self,
        action => 'checkout',
    );
}

=item C<< Krang::Story->checkin($story_id) >>

=item C<< $story->checkin() >>

Checkin the story, allow other users to check it out.  This will only
fail if the story is not checked out.

=cut

sub checkin {
    my $self = shift;
    my $story_id;
    if (!ref $self) {
        $story_id = shift;
        ($self) = pkg('Story')->find(story_id => $story_id);
    } else {
        $story_id = $self->{story_id};
    }
    my $args    = shift || {};
    my $dbh     = dbh();
    my $user_id = $ENV{REMOTE_USER};

    # Is user allowed to otherwise edit this object?
    unless($args->{ignore_permissions}) {
        Krang::Story::NoEditAccess->throw(
            message  => "Not allowed to edit story",
            story_id => $self->story_id
        ) unless ($self->may_edit);

    }

    # make sure we're checked out, unless we have may_checkin_all powers
    my %admin_perms = pkg('Group')->user_admin_permissions();
    $self->_verify_checkout() unless $admin_perms{may_checkin_all};

    # checkin the story
    $dbh->do(
        'UPDATE story
              SET checked_out = ?, checked_out_by = ?
              WHERE story_id = ?', undef, 0, 0, $story_id
    );

    # update checkout fields
    $self->{checked_out}    = 0;
    $self->{checked_out_by} = 0;

    add_history(
        object => $self,
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
    $self->{publish_date}      = localtime;

    $self->{desk_id} = undef;

    $self->{checked_out}    = 0;
    $self->{checked_out_by} = 0;

    # update the DB.
    my $dbh = dbh();
    $dbh->do(
        'UPDATE story
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
    $dbh->do(
        'UPDATE story SET preview_version = ? WHERE story_id = ?',
        undef, $self->{preview_version},
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
    my $self     = shift;
    my %arg      = @_;
    my $category = $arg{category} ? $arg{category} : $self->category;

    my $path = $category->site->publish_path;
    my $url  = $self->element->build_url(
        story    => $self,
        category => $category
    );

    # remove the site part
    $url =~ s!^[^/]+/?!!;

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
    my $url  = $self->element->build_url(
        story    => $self,
        category => $category
    );

    # remove the site part
    $url =~ s!^[^/]+/?!!;

    # paste them together
    return canonpath(catdir($path, $url));
}

# make sure the object is checked out, or croak
sub _verify_checkout {
    my $self = shift;

    croak("Story '$self->{story_id}' is not checked out.")
      unless $self->{checked_out};

    croak(
        "Story '$self->{story_id}' is already checked out by another user '$self->{checked_out_by}'"
    ) unless $self->{checked_out_by} == $ENV{REMOTE_USER};
}

=item C<< $story->revert($version) >>

Creates a new version of this story with identical content to the version passed. (Version numbers always increase, never decrease.)
If the new version is successfully written to disk (no duplicate URL errors, etc.), the object itself is returned; if not, an error is returned.

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
        checked_out       => $self->{checked_out},
        published_version => $self->{published_version},
        publish_date      => $self->{publish_date},
        url_cache         => [],
    );
    my ($obj) = $self->_load_version($self->{story_id}, $target);

    # copy in data, preserving contents of %persist
    %$self = (%$obj, %persist);

    # attempt disk-write
    eval { $self->save };
    return $@ if $@;

    add_history(
        object => $self,
        action => 'revert',
    );

    return $self;
}

=item C<< $story->delete() >>

=item C<< Krang::Story->delete($story_id) >>

=item C<< Krang::Story->delete(story_id => $story_id) >>

=item C<< Krang::Story->delete(class => 'article') >>

=item C<< Krang::Story->delete(class => [ qw(article redirect) ]) >>

Deletes the specified story/stories from the database.

This is a permanent operation and requires the admin permission
may_delete.

Throws a Krang::Story::NoDeleteAccess exception if user may not delete
assets. Stories will be checked-out before they are deleted, which
will fail if the story is checked out to another user.

=cut

sub delete {
    my $self = shift;

    my @stories = ();

    if (ref $self) {

        # called as object method
        push @stories, $self;
    } elsif (scalar(@_) == 1) {

        # called as class method with a story id as only parameter
        @stories = pkg('Story')->find(story_id => $_[0]);
        croak(__PACKAGE__ . "::delete() - Unable to load story '$_[0]'.") unless $stories[0];
    } elsif (scalar(@_) % 2 == 0) {
        my %args = @_;
        if ($args{class} and ref $args{class} eq 'ARRAY') {
            @stories = pkg('Story')->find(class => $args{class});
        } elsif ($args{class} and not ref($args{class})) {
            @stories = pkg('Story')->find(class => [$args{class}]);
        } elsif ($args{story_id}) {
            @stories = pkg('Story')->find(story_id => $args{story_id});
            croak(__PACKAGE__ . "::delete() - Unable to load story '$_[0]'.") unless $stories[0];
        } else {
            croak(  __PACKAGE__
                  . "::delete() - Argument 'class' must be a string or an arrayref, "
                  . "but is a "
                  . ref($args{class}));
        }
    } else {
        croak(__PACKAGE__ . "::delete() - Unsupported arguments");
    }

    # delete 'em
    $_->_do_delete() for @stories;
}

# the delete workhorse
sub _do_delete {
    my $self = shift;

    $self->checkout;

    # Is user allowed to delete objects from the trashbin?
    Krang::Story::NoDeleteAccess->throw(
        message  => "Not allowed to delete story",
        story_id => $self->story_id
    ) unless pkg('Group')->user_admin_permissions('admin_delete');

    # unpublish
    pkg('Publisher')->new->unpublish_story(story => $self);

    # first delete history for this object
    pkg('History')->delete(object => $self);

    my $dbh = dbh;
    $dbh->do('DELETE FROM story WHERE story_id = ?',               undef, $self->{story_id});
    $dbh->do('DELETE FROM story_category WHERE story_id = ?',      undef, $self->{story_id});
    $dbh->do('DELETE FROM story_version WHERE story_id = ?',       undef, $self->{story_id});
    $dbh->do('DELETE FROM story_contrib WHERE story_id = ?',       undef, $self->{story_id});
    $dbh->do('DELETE FROM story_category_link WHERE story_id = ?', undef, $self->{story_id});
    $self->element->delete;

    # remove from trash
    pkg('Trash')->remove(object => $self);

    # delete schedules for this story
    $dbh->do('DELETE FROM schedule WHERE object_type = ? and object_id = ?',
        undef, 'story', $self->{story_id});

    # delete alerts for this story
    $dbh->do('DELETE FROM alert WHERE object_type = ? and object_id = ?',
        undef, 'story', $self->{story_id});

    add_history(
        object => $self,
        action => 'delete',
    );

}

=item C<< $copy = $story->clone() >>

=item C<< $copy = $story->clone(category_id => $category_id) >>

Creates a copy of the story object, with most fields identical except
for C<story_id> and C<< element->element_id >> which will both be
C<undef>. Also, the copy gets a new story_uuid.  It will be checked
out by the current user and it will not be saved.

If no category ID is passed in, a raw clone is assumed: In this case,
the title will be set to "Copy of $title" and
$clone->resolve_url_conflict() will be called to provide the clone
with non-conflicting URL(s) derived from the URL(s) of the original.

If a category ID is specified, no further DuplicateURL checks will be
performed, and the clone will live in this category.

=cut

sub clone {
    my ($self, %args) = @_;
    my $copy = bless({%$self}, ref($self));

    # clone the element tree
    $copy->{element} = $self->element->clone();

    # zap ids
    $copy->{story_id} = undef;
    $copy->{element}{element_id} = undef;

    # start at version 0
    $copy->{version} = 0;

    # never been published
    $copy->{publish_date}      = undef;
    $copy->{published_version} = 0;
    $copy->{preview_version}   = 0;

    # get a new UUID
    $copy->{story_uuid} = pkg('UUID')->new;

    # unset retired and trashed flag
    $copy->{retired} = 0;
    $copy->{trashed} = 0;

    # unset (last_)desk_id
    $copy->{desk_id}      = undef;
    $copy->{last_desk_id} = undef;

    # make sure it's checked out
    $copy->{checked_out}    = 1;
    $copy->{checked_out_by} = $ENV{REMOTE_USER};

    # cooked copy or raw clone?
    if ($args{category_id}) {
        $copy->{slug} = $args{slug} if defined($args{slug});
        $copy->categories($args{category_id});
    } else {
        $copy->{title} = localize('Copy of') . ' ' . $copy->{title};
        $copy->resolve_url_conflict(append => 'copy');
    }

    # new story should be editable even if old one wasn't
    $copy->{may_edit} = 1;
    return $copy;
}

=item C<< $story->resolve_url_conflict(append => 'copy') >>

Resolves a URL conflict between $story and another live story.

If the story has a slug, the string specified in C<append> will be
appended to the story's slug.

Otherwise, the story's category_ids, category_cache and url_cache
lists will be cleared.

=cut

sub resolve_url_conflict {
    my ($self, %args) = @_;

    # returns 1 if there is a dup, 0 otherwise
    my $is_dup = sub {
        eval { shift->_verify_unique; };
        return 1 if $@ and ref $@ and $@->isa('Krang::Story::DuplicateURL');
        die($@) if $@;
        return 0;
    };

    # if changing the slug will help, do that until it works
    my @url_attributes = $self->element->class->url_attributes;
    if (grep { $_ eq 'slug' } @url_attributes) {

        # find a slug that works
        my $slug = $self->slug;
        my $x    = 1;
        do {
            $self->slug("${slug}_$args{append}" . ($x > 1 ? $x : ""));
            $x++;
        } while ($is_dup->($self));
    } else {

        # erase category associations
        $self->{category_ids}   = [];
        $self->{category_cache} = [];
        $self->{url_cache}      = [];
    }
}

=item C<< @linked_stories = $story->linked_stories >>

Returns a list of stories linked to from this story.  These will be
Krang::Story objects.  If no stories are linked, returns an empty
list.  This list will not contain any duplicate stories, even if a
story is linked more than once.

=cut

sub linked_stories {
    my ($self, %arg) = @_;
    my $element = $self->element;

    # find StoryLinks and index by id
    my %story_links;
    my $story;
    foreach_element {
        if (    $_->class->isa(pkg('ElementClass::StoryLink'))
            and $story = $_->data)
        {
            $story_links{$story->story_id} = $story;
        } else {
            $_->class->linked_stories(
                element     => $_,
                publisher   => $arg{publisher},
                story_links => \%story_links
            );
        }
    }
    $element;

    return values %story_links;
}

=item C<< @linked_media = $story->linked_media >>

Returns a list of media linked to from this story.  These will be
Krang::Media objects.  If no media are linked, returns an empty list.
This list will not contain any duplicate media, even if a media object
is linked more than once.

=cut

sub linked_media {
    my $self    = shift;
    my $element = $self->element;

    # find StoryLinks and index by id
    my %media_links;
    my $media;
    foreach_element {
        if (    $_->class->isa(pkg('ElementClass::MediaLink'))
            and $media = $_->data)
        {
            $media_links{$media->media_id} = $media;
        }
    }
    $element;

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

=item C<< $story->serialize_xml(writer => $writer, [set => $set, no_elements => 1]) >>

Serialize as XML.  See Krang::DataSet for details.

=cut

sub serialize_xml {
    my ($self, %args) = @_;
    my ($writer, $set, $no_elements) = @args{qw(writer set no_elements)};
    local $_;

    # open up <story> linked to schema/story.xsd
    $writer->startTag(
        'story',
        "xmlns:xsi"                     => "http://www.w3.org/2001/XMLSchema-instance",
        "xsi:noNamespaceSchemaLocation" => 'story.xsd'
    );

    # basic fields
    $writer->dataElement(story_id   => $self->story_id);
    $writer->dataElement(story_uuid => $self->story_uuid);
    $writer->dataElement(class      => $self->class->name);
    $writer->dataElement(title      => $self->title);
    $writer->dataElement(slug       => $self->slug);
    $writer->dataElement(version    => $self->version);
    $writer->dataElement(cover_date => $self->cover_date->datetime);
    $writer->dataElement(notes      => $self->notes);
    $writer->dataElement(retired    => $self->retired);
    $writer->dataElement(trashed    => $self->trashed);

    # tags
    for my $tag ($self->tags) {
        $writer->dataElement(tag => $tag);
    }

    # categories
    for my $category ($self->categories) {
        $writer->dataElement(category_id => $category->category_id);

        $set->add(object => $category, from => $self) if $set;
    }

    # urls
    $writer->dataElement(url => $_) for $self->urls;

    # contributors
    my %contrib_type = pkg('Pref')->get('contrib_type');
    for my $contrib ($self->contribs) {
        $writer->startTag('contrib');
        $writer->dataElement(contrib_id   => $contrib->contrib_id);
        $writer->dataElement(contrib_type => $contrib_type{$contrib->selected_contrib_type()});
        $writer->endTag('contrib');

        $set->add(object => $contrib, from => $self) if $set;
    }

    # schedules
    my @schedules = pkg('Schedule')->find(object_type => 'story', object_id => $self->story_id);
    foreach my $schedule (@schedules) {
        $set->add(object => $schedule, from => $self) if $set;
    }

    # serialize elements
    unless ($no_elements) {
        $self->element->serialize_xml(
            writer => $writer,
            set    => $set,
        );
    }

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
    my $data = pkg('XML')->simple(
        xml           => $xml,
        forcearray    => ['contrib', 'category_id', 'url', 'element', 'data',],
        suppressempty => 1
    );

    # is there an existing object?
    my $story;

    # start with a UUID lookup
    my $match_type;
    if (not $args{no_uuid} and $data->{story_uuid}) {
        ($story) = $pkg->find(
            story_uuid         => $data->{story_uuid},
            show_hidden        => 1,
            ignore_permissions => 1,
        );

        # if not updating this is fatal
        Krang::DataSet::DeserializationFailed->throw(
            message => "A story object with the UUID '$data->{story_uuid}' already"
              . " exists and no_update is set.")
          if $story and $no_update;
    }

    # proceed to URL lookup if no dice
    unless ($story or $args{uuid_only}) {
        ($story) = pkg('Story')->find(
            url                => $data->{url}[0],
            show_hidden        => 1,
            ignore_permissions => 1,
        );

        # if not updating this is fatal
        Krang::DataSet::DeserializationFailed->throw(
            message => "A story object with the url '$data->{url}[0]' already"
              . " exists and no_update is set.")
          if $story and $no_update;
    }

    if ($story) {
        # if primary url of this imported story matches a non-primary
        # url of an existing story, reject
        my ($fail) = $pkg->find(
            non_primary_url     => $data->{url}[0],
            ids_only            => 1,
            ignore_permissions  => 1,
        );
        Krang::DataSet::DeserializationFailed->throw(
            message => "A story object with a non-primary url "
              . "'$data->{url}[0]' already exists.")
          if $fail;

        # check it out to make changes
        $story->checkout(undef, { ignore_permissions => 1 });

        # update slug and title
        $story->slug($data->{slug}   || "");
        $story->title($data->{title} || "");

        # handle the tags
        $story->tags($data->{tag}) if $data->{tag};

        # get category objects for story
        my @category_ids =
          map { $set->map_id(class => pkg('Category'), id => $_) } @{$data->{category_id}};

        # set categories, which might have changed if this was a match by UUID
        $story->categories(\@category_ids, {no_verify_unique => 1, no_verify_reserved => 1});

    } else {

        # check primary URL for conflict - can happen with uuid_only on
        my ($fail) = $pkg->find(
            primary_url        => $data->{url}[0],
            ids_only           => 1,
            ignore_permissions => 1,
        );
        Krang::DataSet::DeserializationFailed->throw(
            message => "A story object with a primary url " . "'$data->{url}[0]' already exists.")
          if $fail;

        # check if any of the secondary urls match existing stories
        # and fail if so
        for (my $count = 1 ; $count < @{$data->{url}} ; $count++) {
            my ($found) = pkg('Story')->find(
                url                => $data->{url}[$count],
                show_hidden        => 1,
                ignore_permissions => 1,
            );
            Krang::DataSet::DeserializationFailed->throw(message =>
                  "A story object with url '$data->{url}[$count]' already exists, which conflicts with one of this story's secondary URLs."
            ) if $found;
        }

        # get category objects for story
        my @categories = map { pkg('Category')->find(category_id => $_) }
          map { $set->map_id(class => pkg('Category'), id => $_) } @{$data->{category_id}};

        # this might have caused this Story to get completed via a
        # circular link, end early if it did
        my ($dup) = pkg('Story')->find(url => $data->{url}, ignore_permissions => 1);
        return $dup if ($dup);

        # create a new story object using categories, slug, title,
        # and class
        $story = pkg('Story')->new(
            categories         => \@categories,
            slug               => $data->{slug} || "",
            title              => $data->{title} || "",
            class              => $data->{class},
            no_verify_unique   => 1,
            no_verify_reserved => 1,
        );

        # handle the tags
        $story->tags($data->{tag}) if $data->{tag};
    }

    # preserve UUID if available
    $story->{story_uuid} = $data->{story_uuid}
      if $data->{story_uuid} and not $args{no_uuid};

    $story->cover_date(Time::Piece->strptime($data->{cover_date}, '%Y-%m-%dT%T'))
      if exists $data->{cover_date};
    $story->notes($data->{notes})
      if exists $data->{notes};

    # save some changes temporarily so we can get a story_id
    $story->save(
        no_verify_unique   => 1,
        no_verify_reserved => 1,
        ignore_permissions => 1,
        skip_categories    => 1,
        skip_save_version  => 1,
    );

    # register id before deserializing elements, since they may
    # contain circular references
    $set->register_id(
        class     => pkg('Story'),
        id        => $data->{story_id},
        import_id => $story->story_id
    );

    # deserialize elements, may contain circular references
    my $element = pkg('Element')->deserialize_xml(
        data      => $data->{element}[0],
        set       => $set,
        no_update => $no_update,
        object    => $story
    );

    # update element
    $story->{element}->delete(skip_delete_hook => 1) if $story->{element};
    $story->{element} = $element;
    $story->{class} = $data->{class};

    # get hash of contrib type names to ids
    my %contrib_types = reverse pkg('Pref')->get('contrib_type');

    # handle contrib association
    if ($data->{contrib}) {
        my @contribs = @{$data->{contrib}};
        my @altered_contribs;
        foreach my $c (@contribs) {
            my $contrib_type_id = $contrib_types{$c->{contrib_type}}
              || Krang::DataSet::DeserializationFailed->throw(
                "Unknown contrib_type '" . $c->{contrib_type} . "'.");

            push(
                @altered_contribs,
                {
                    contrib_id => $set->map_id(class => pkg('Contrib'), id => $c->{contrib_id}),
                    contrib_type_id => $contrib_type_id
                }
            );
        }

        $story->contribs(@altered_contribs);
    }

    # finish the story, not incrementing version
    $story->save(ignore_permissions => 1);
    $story->checkin({ignore_permissions => 1});

    return $story;
}

=item C<< $story->retire() >>

=item C<< Krang::Story->retire(story_id => $story_id) >>

Retire the story, i.e. remove it from its publish/preview location
and don't show it on the Find Story screen.  Throws a
Krang::Story::NoEditAccess exception if user may not edit this
story. Croaks if the story is checked out by another user.

=cut

sub retire {
    my ($self, %args) = @_;
    unless (ref $self) {
        my $story_id = $args{story_id};
        ($self) = pkg('Story')->find(story_id => $story_id);
        croak("Unable to load story '$story_id'.") unless $self;
    }

    # Is user allowed to otherwise edit this object?
    Krang::Story::NoEditAccess->throw(
        message  => "Not allowed to edit story",
        story_id => $self->story_id
    ) unless ($self->may_edit);

    # make sure we are the one
    $self->checkout;

    # run the element class's retire_hook
    my $element = $self->element;
    $element->class->retire_hook(element => $element);

    # unpublish
    pkg('Publisher')->new->unpublish_story(story => $self);

    # retire the story
    my $dbh = dbh();
    $dbh->do(
        "UPDATE story
              SET    retired = 1
              WHERE  story_id = ?", undef,
        $self->{story_id}
    );

    # delete schedules for this story
    $dbh->do('DELETE FROM schedule WHERE object_type = ? and object_id = ?',
        undef, 'story', $self->{story_id});

    # delete any story_category_link entries
    $dbh->do('DELETE FROM story_category_link WHERE story_id = ?', undef, $self->{story_id});

    # living in retire
    $self->{retired} = 1;

    $self->checkin();

    add_history(
        object => $self,
        action => 'retire'
    );
}

=item C<< $story->unretire() >>

=item C<< Krang::Story->unretire(story_id => $story_id) >>

Unretire the story, i.e. show it again on the Find Story screen, but
don't republish it. Throws a Krang::Story::NoEditAccess exception if
user may not edit this story. Throws a Krang::Story::DuplicateURL
exception if a story with the same URL has been created in
Live. Croaks if the story is checked out by another user.

=cut

sub unretire {
    my ($self, %args) = @_;
    unless (ref $self) {
        my $story_id = $args{story_id};
        ($self) = pkg('Story')->find(story_id => $story_id);
        croak("Unable to load story '$story_id'.") unless $self;
    }

    # Is user allowed to otherwise edit this object?
    Krang::Story::NoEditAccess->throw(
        message  => "Not allowed to edit story",
        story_id => $self->story_id
    ) unless ($self->may_edit);

    # make sure we are the one
    $self->checkout;

    # make sure no other story occupies our initial place (URL)
    $self->_verify_unique;

    # make sure it's not now a reserved URL
    $self->_verify_reserved();

    # unretire the story
    my $dbh = dbh();
    $dbh->do('UPDATE story SET retired = 0 WHERE story_id = ?', undef, $self->{story_id});

    # alive again
    $self->{retired} = 0;

    # run the element class's unretire_hook
    my $element = $self->element;
    $element->class->unretire_hook(element => $element);

    # check it back in
    $self->checkin() unless $args{dont_checkin};

    add_history(
        object => $self,
        action => 'unretire',
    );
}

=item C<< $story->trash() >>

=item C<< Krang::Story->trash(story_id => $story_id) >>

Move the story to the trashbin, i.e. remove it from its
publish/preview location and don't show it on the Find Story screen.
Throws a Krang::Story::NoEditAccess exception if user may not edit
this story. Croaks if the story is checked out by another
user.

=cut

sub trash {
    my ($self, %args) = @_;
    my $story_id = $args{story_id};

    unless (ref $self) {
        ($self) = pkg('Story')->find(story_id => $story_id);
        croak("Unable to load story '$story_id'.") unless $self;
    }

    # Is user allowed to otherwise edit this object?
    Krang::Story::NoEditAccess->throw(
        message  => "Not allowed to edit story",
        story_id => $story_id
    ) unless ($self->may_edit);

    # make sure we are the one
    $self->checkout;

    # run the element class's trash_hook
    my $element = $self->element;
    $element->class->trash_hook(element => $element);

    # unpublish
    pkg('Publisher')->new->unpublish_story(story => $self);

    # store in trash
    pkg('Trash')->store(object => $self);

    # update object
    $self->{trashed} = 1;

    # release it
    $self->checkin();

    # delete any story_category_link entries
    dbh()->do('DELETE FROM story_category_link WHERE story_id = ?', undef, $story_id);

    # and log it
    add_history(object => $self, action => 'trash');
}

=item C<< $story->untrash() >>

=item C<< Krang::Story->untrash(story_id => $story_id) >>

Restore the story from the trashbin, i.e. show it again on the Find
Story screen or Retired Stories screens (depending on the location
from where it was deleted).  Throws a Krang::Story::NoRestoreAccess
exception if user may not edit this story. Croaks if the story is
checked out by another user. This method is called by
Krang::Trash->restore().

=cut

sub untrash {
    my ($self, %args) = @_;
    unless (ref $self) {
        my $story_id = $args{story_id};
        ($self) = pkg('Story')->find(story_id => $story_id);
        croak("Unable to load story '$story_id'.") unless $self;
    }

    # Is user allowed to otherwise edit this object?
    Krang::Story::NoRestoreAccess->throw(
        message  => "Not allowed to restore story",
        story_id => $self->story_id
    ) unless ($self->may_edit);

    unless($self->retired) {
        # make sure no other story occupies our initial place (URL)
        $self->_verify_unique;
        # make sure this isn't now a reserved URL
        $self->_verify_reserved();
    }

    # make sure we are the one
    $self->checkout;

    # unset trash flag in story table
    my $dbh = dbh();
    $dbh->do(
        'UPDATE story
              SET trashed = ?
              WHERE story_id = ?', undef,
        0,                         $self->{story_id}
    );

    # remove from trash
    pkg('Trash')->remove(object => $self);

    # maybe in retire, maybe alive again
    $self->{trashed} = 0;

    # run the element class's untrash_hook
    my $element = $self->element;
    $element->class->untrash_hook(element => $element);

    # check back in
    $self->checkin();

    add_history(
        object => $self,
        action => 'untrash',
    );
}

=item C<< $story->wont_publish() >>

Convenience method returning true if story has been retired or
trashed.

=cut

sub wont_publish { return $_[0]->retired || $_[0]->trashed }

=item C<< $story->turn_into_category_index(category => $category) >>

=item C<< $story->turn_into_category_index(category => $category, steal => 1) >>

Convenience method to resolve URL conflicts when creating a $category
whose 'dir' property equals the slug of $story.

Turns the slug-provided $story into a slugless index page of the
specified $category.

Returns undef if user can't check out the story.

When specifiying the flag B<steal>, stories checked out by another
user will be stolen if we have the necessary user admin permission
'may_checkin_all'. Otherwise returns undef.

=cut

sub turn_into_category_index {
    my ($self, %args) = @_;

    # the category whose 'dir' equals the story's slug
    my $category = $args{category};

    # return if we can't edit
    return unless $self->may_edit;

    # handle checked out story
    if ($self->checked_out) {
        if ($self->checked_out_by ne $ENV{REMOTE_USER}) {
            if ($args{steal}) {
                my %admin_perms = pkg('Group')->user_admin_permissions();
                unless ($admin_perms{may_checkin_all}) {
                    return;
                }
            } else {
                return;
            }
            $self->checkin;
            $self->checkout;
        }
    } else {
        $self->checkout;
    }

    # give story temporary slug so we don't throw dupe error during conversion!
    my $slug = $self->slug;
    $self->slug('_TEMP_SLUG_FOR_CONVERSION_');
    $self->save;

    # form story's new cats by appending its slug to existing cats
    my @old_cats = $self->categories;
    my @new_cats;
    foreach my $old_cat (@old_cats) {
        my ($new_cat) = pkg('Category')->find(url => $old_cat->url . $slug);
        unless ($new_cat) {
            if ($category->parent_id eq $old_cat->category_id) {
                $category->save;
                $new_cat = $category;
            } else {
                $new_cat = pkg('Category')->new(
                    dir       => $slug,
                    parent_id => $old_cat->category_id,
                    site_id   => $old_cat->site_id
                );
                $new_cat->save;
            }
        }
        push @new_cats, $new_cat;
    }
    $self->slug('');
    $self->categories(@new_cats);
    $self->save;
    $self->checkin;

    return 1;
}

sub is_category_index {
    my $self = shift;
    return $self->category->url eq $self->url ? 1 : 0;
}

=back

=cut

1;
