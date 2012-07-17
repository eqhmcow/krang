package Krang::Media;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;
use Krang::ClassLoader DB   => qw(dbh);
use Krang::ClassLoader Conf => qw(KrangRoot SavedVersionsPerMedia);
use Krang::ClassLoader Log  => qw(debug info assert ASSERT);
use Krang::ClassLoader 'Contrib';
use Krang::ClassLoader 'Category';
use Krang::ClassLoader Element => qw(foreach_element);
use Krang::ClassLoader 'Group';
use Krang::ClassLoader History => qw( add_history );
use Krang::ClassLoader 'Publisher';
use Krang::ClassLoader 'UUID';
use Krang::ClassLoader 'IO';
use Krang::ClassLoader 'Pref';
use Carp qw(croak);
use Storable qw(nfreeze thaw);
use File::Spec::Functions qw(catdir catfile splitpath canonpath);
use File::Path;
use File::Copy;
use File::Basename qw(fileparse);
use LWP::MediaTypes ();
use Imager;
use File::stat;
use Time::Piece;
use Time::Seconds;
use Time::Piece::MySQL;
use File::Temp qw(tempdir);
use File::Slurp qw(read_file);
use Image::Size;
use FileHandle;

# constants
use constant THUMBNAIL_SIZE     => 35;
use constant MED_THUMBNAIL_SIZE => 200;
use constant FIELDS =>
  qw(media_id media_uuid element_id title category_id media_type_id filename creation_date caption copyright notes url version alt_tag mime_type published published_version preview_version publish_date checked_out_by retired trashed read_only full_text);

# setup exceptions
use Exception::Class (
    'Krang::Media::DuplicateURL'         => {fields => ['media_id']},
    'Krang::Media::NoCategoryEditAccess' => {fields => ['category_id']},
    'Krang::Media::NoEditAccess'         => {fields => ['media_id']},
    'Krang::Media::NoDeleteAccess'       => {fields => ['media_id']},
    'Krang::Media::NoRestoreAccess'      => {fields => ['media_id']},
    'Krang::Media::CheckedOut'           => {fields => ['desk_id', 'user_id']},
);

=head1 NAME

    Krang::Media - Media and media metadata storage and access methods

=head1 SYNOPSIS

    # create new media object
    my $media = pkg('Media')->new(
        title         => 'test media',
        caption       => 'test caption',
        copyright     => 'AP 1999',
        media_type_id => $media_type_id,
        category_id   => $category_id
    );

    # Find permissions for this media (for this user)
    $media->may_see();
    $media->may_edit();

    # add actual media file to media object
    $media->upload_file(filehandle => $filehandle, filename => 'media.jpg');

    # get MIME type of uploaded file
    $mime_type = $media->mime_type();

    # get path to thumbnail - if image (thumbnail will be created if
    # does not exist)
    $thumbnail_path = $media->thumbnail_path();

    # assign 2 contributors to media object, specifying thier contributor type
    $media->contribs(
        {contrib_id => 1,  contrib_type_id => 3},
        {contrib_id => 44, contrib_type_id => 4},
    );

    # get contrib objects attached to this media
    @contribs = $media->contribs();

    # change assignment to include just the first contributor
    $media->contribs($contribs[0]);

    # get the tags for this media
    @tags = $media->tags;

    # change the tags for this media
    $media->tags(['foo', 'bar']);
    $media->tags([]);

    # get media element
    my $element = $media->element();
    $element_id = $media->element_id;    # undef until after save()

    # save the object to the database
    $media->save();

    # mark as checked out by you (your user_id)
    $media->checkout();

    # update caption for this media object
    $media->caption('new caption');

    # again, save the object to the database (upping version)
    $media->save();

    # get current version number, in this example 2
    $version = $media->version();

    # revert to version 1 (creating version 3, identical to 1)
    $media->revert(1);

    # preview media object
    $media->preview;

    # publish media object
    $media->publish;

    # get id for this object
    my $media_id = $media->media_id();

    # return object by id
    ($media_obj) = pkg('Media')->find(media_id => $media_id);

=head1 DESCRIPTION

This class handles the storage and retrieval of media objects on the
filesystem, as well as media object metadata in the database. Contributors
(L<Krang::Contrib> objects) can also be attached to stories.

=head2 Media Versioning

Versioning in this system functions perhaps in a non-traditional
way. A quick walk-thru of a media edit and revert may help
understanding.  We'll assume the existing media object starts with
version = 1.

First, the media object is marked as 'checked out' by the current
user.  After this call, only someone logged in with the same user_id
can edit this media object:

  $media->checkout();

Now that the media object cannot be edited by anyone else, let's make
a change to the title of this media object:

  $media->title('new title');

Finally, we save the media object:

  $media->save();

After save(), the in-memory object $media will be saved into the
'media' table as version = 2, and also saved in media_version for
later use.

To begin the explaination of 'revert', the most important thing to
understand is that revert() simply takes a copy of an older
version and uses it to make a new version.

To revert to the contents of version 1, we call the revert() method:

  $media->revert(1)

So now what do we have?  We now have version 1, 2 and 3 in the versioning
table, and 3 is a copy of 1.

Thus, revert() does not give you access to the actual original
version, but instead gives you a copy of it.

The reason for doing things this way is so you can always get back to
a previous version no matter how many times you've saved and reverted.
This is also how CVS works.

=head1 INTERFACE

=head2 METHODS

=over 

=item $media = Krang::Media->new()

Initialize new media object.  Passing in filehandle and filename upon new is eqivalent of calling new(), then upload_file().

$media->new() supports the following name-value arguments:

=over

=item title, caption, copyright, notes, alt_tag

Fields for storing arbitrary metadata -- B<title> is required.

=item media_type_id

ID for media_type, the media_type this media object is associated with.

=item category_id

ID for category, the category this media object is associated with.

=item checked_out_by

User id of person who has media object checked out, undef if not checked out.

=item published_version

Last published version

=item published

Returns true if the media has been published under its current URL.

=item preview_version

Last preview version

=item filename

The filename of the uploaded media.

=item filehandle

Filehandle for uploaded media.

=item creation_date

Date the media object was created.  Defaults to current time unless set.

=back

=cut

use Krang::ClassLoader MethodMaker => new_with_init => 'new',
  new_hash_init                    => 'hash_init',
  get_set                          => [
    qw(
      title
      alt_tag
      version
      checked_out_by
      published
      published_version
      preview_version
      publish_date
      caption copyright
      notes
      mime_type
      media_type_id
      )
  ],
  get_set_with_notify => [
    {
        method => '_notify',
        attr   => [
            qw(
              filename
              category_id
              )
        ]
    }
  ],
  get => [
    qw(
      media_id
      media_uuid
      creation_date
      may_see
      may_edit
      retired
      trashed
      read_only
      full_text
      )
  ];

sub id_meth   { 'media_id' }
sub uuid_meth { 'media_uuid' }

sub _notify {
    my ($self, $which, $old, $new) = @_;
    return if defined $old and defined $new and $old eq $new;
    return if not defined $old and not defined $new;
    $self->{url_cache} = '';
    $self->{cat_cache} = () if ($which eq 'category_id');

    # clean up the filename if it's changed
    if( $which eq 'filename' ) {
        $self->{filename} = $self->clean_filename($new);
    }
}

sub init {
    my ($self, %args) = @_;
    my $filename   = $self->clean_filename($args{filename});
    my $filehandle = delete $args{filehandle};
    my $tags       = delete $args{tags};

    $self->{contrib_ids}       = [];
    $self->{version}           = 0;                   # versions start at 0
    $self->{published}         = 0;
    $self->{published_version} = 0;
    $self->{preview_version}   = 0;
    $self->{checked_out_by}    = $ENV{REMOTE_USER};
    $self->{creation_date} = localtime unless defined $self->{creation_date};
    $self->{retired}       = 0;
    $self->{trashed}       = 0;
    $self->{read_only}     = 0;

    # Set up temporary permissions
    $self->{may_see}  = 1;
    $self->{may_edit} = 1;

    $self->{media_uuid} = pkg('UUID')->new;

    # initialize the element
    $self->{element} = pkg('Element')->new(
        class  => pkg('ElementClass::Media')->element_class_name,
        object => $self
    );

    # finish the object
    $self->hash_init(%args);

    $self->upload_file(filename => $filename, filehandle => $filehandle) if $filehandle;

    $self->tags($tags);

    return $self;
}

=item $id = $media->media_id()

Returns the unique id assigned the media object.  Will not be populated until $media->save() is called the first time.

=item $media->media_uuid()

Unique ID for media, valid across different machines when the object
is moved via krang_export and krang_import.

=item $media->title()

=item $media->category_id()

=item $media->category()

Returns the category object matching category_id.

=cut

sub category {
    my $self = shift;

    return undef unless $self->{category_id};

    return $self->{cat_cache} if $self->{cat_cache};

    $self->{cat_cache} = (pkg('Category')->find(category_id => $self->{category_id}))[0];

}

=item $media->categories()

Synonym for C<category>.

=cut

sub categories {
    my $self = shift;
    return $self->category(@_);
}

=item $media->filename()

=item $media->caption()

=item $media->copyright()

=item $media->alt_tag()

=item $media->mime_type()

Returns the MIME type of the media file.  This is readonly and undef
until after upload_file() has been called.

=item $media->notes()

=item $media->media_type_id()

Gets/sets the value.

=item $media->checked_out()

Returns 1 if checked out by a user (checked_out_by is set), otherwise
returns 0.

=cut

sub checked_out {
    my $self = shift;
    return 1 if $self->checked_out_by();
    return 0;
}

=item $media->checked_out_by()

Returns id of user who has object checked out, if checked out.

=item $media->published()

Returns true if the media has been published under its current URL.

=item $media->published_version()

Returns version number of published version of this object (if has been published).

=item $media->preview_version()

Returns version number of the last version previewed.

=item $version = $media->version()

Returns the current version number.

=item $creation_date = $media->creation_date()

Returns the initial creation date of the media object.  Not settable here.

=item @contribs = $media->contribs();

=item $media->contribs({ contrib_id => 10, contrib_type_id => 1 }, ...);

=item $media->contribs(@contribs);

Called with no arguments, returns a list of contributor
(Krang::Contrib) objects.  These objects will have
C<selected_contrib_type> set according to their use with this media
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
        if (ref($rec) and ref($rec) eq 'Krang::Contrib') {
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

        } elsif (ref($rec) and ref($rec) eq 'HASH') {
            croak(
                "invalid data passed to contribs: hashes must contain contrib_id and contrib_type_id."
            ) unless $rec->{contrib_id} and $rec->{contrib_type_id};

            push(@contribs, $rec);

        } else {
            croak("invalid data passed to contribs");
        }

        $self->{contrib_ids} = \@contribs;
    }
}

=item $media->clear_contribs()

Removes all contributor associatisons.

=cut

sub clear_contribs { shift->{contrib_ids} = []; }

=item $media->tags()

Get/Set the tags for this media

=cut

sub tags {
    my ($self, $tags) = @_;
    my $dbh = dbh;
    my $id  = $self->media_id;
    if ($tags) {
        die "invalid data passed to tags: must be an array reference"
          unless ref $tags && ref $tags eq 'ARRAY';

        $self->{tags} = $tags;
    } elsif ($self->{tags}) {
        $tags = $self->{tags};
    } else {
        $tags = [];
        my $sth = $dbh->prepare_cached('SELECT tag FROM media_tag WHERE media_id = ? ORDER BY ord');
        $sth->execute($id);
        while (my $row = $sth->fetchrow_arrayref) {
            push(@$tags, $row->[0]);
        }
        $self->{tags} = $tags;
    }
    return @$tags;
}

=item C<< Krang::Media->known_tags() >>

Returns a sorted list of all known tags used on media objects. 

=cut

sub known_tags {
    my $pkg = shift;
    my @tags;
    my $sth = dbh()->prepare_cached('SELECT DISTINCT(tag) FROM media_tag ORDER BY tag');

    $sth->execute();
    while (my $row = $sth->fetchrow_arrayref) {
        push(@tags, $row->[0]);
    }
    return @tags;
}

=item C<< $all_version_numbers = $media->all_versions(); >>

Returns an arrayref containing all the existing version numbers for this media object.

=cut

sub all_versions {
    my $self = shift;
    my $dbh  = dbh;
    return $dbh->selectcol_arrayref('SELECT version FROM media_version WHERE media_id=?',
        undef, $self->media_id);
}

=item C<< $media->prune_versions(number_to_keep => 10); >>

Deletes old versions of this media object. By default prune_versions() keeps
the number of versions specified by SavedVersionsPerMedia in krang.conf;
this can be overridden as above. In either case, it returns the number of 
versions actually deleted.

=cut

sub prune_versions {
    my ($self, %args) = @_;
    my $dbh = dbh;

    # figure out how many versions to keep
    my $number_to_keep = $args{number_to_keep} || SavedVersionsPerMedia;
    return 0 unless $number_to_keep;

    # figure out how many versions can be deleted
    my @all_versions     = @{$self->all_versions};
    my $number_to_delete = @all_versions - $number_to_keep;
    return 0 unless $number_to_delete > 0;

    # delete the oldest ones (which will be first since the list is ascending)
    my @versions_to_delete = splice(@all_versions, 0, $number_to_delete);
    $dbh->do(
        'DELETE FROM media_version WHERE media_id = ? AND version IN ('
          . join(',', ("?") x @versions_to_delete) . ')',
        undef, $self->media_id, @versions_to_delete
    ) unless $args{test_mode};
    return $number_to_delete;
}

=item $media->upload_file(filehandle => $filehandle, filename => $filename)

Stores media file to temporary location on filesystem. Sets $media->filename() also. 

Of if you already have the file in a temporary location in KrangRoot then you can
simply pass the C<filepath> argument instead.

    $media->upload_file(filepath => $path);

=cut

sub upload_file {
    my $self = shift;
    my %args = @_;
    my $root = KrangRoot;
    my ($path, $name, $handle, $tmpdir) = @_;
    if ($path = $args{'filepath'}) {
        ($name, $tmpdir) = fileparse($path);
        $name = $self->clean_filename($name);
    } else {
        $name = $self->clean_filename($args{'filename'})
          || croak(
            'You must pass in a filename in order to upload a file if you are not using filepath');
        $handle = $args{'filehandle'}
          || croak(
            'You must pass in a filehandle in order to upload a file if you are not using filepath'
          );

        $tmpdir = tempdir(DIR => catdir(KrangRoot, 'tmp'));
        $path = catfile($tmpdir, $name);
        open(FILE, ">$path") || croak("Unable to open $path for writing media!");

        my $buffer;
        while (read($handle, $buffer, 10240)) { print FILE $buffer }
        close $handle;
        close FILE;
    }

    $self->{tempfile} = $path;
    $self->{tempdir}  = $tmpdir;

    # blow the URL cache if the filename has changed
    if ($self->filename && $self->filename ne $name) {
        undef $self->{url_cache};
    }
    $self->{filename} = $name;

    # guess the mime_type and media_type
    $self->{mime_type} = $self->guess_mime_type($path);
    $self->{media_type_id} = $self->guess_media_type($path);

    $self->_update_full_text();
}

sub _update_full_text {
    my $self = shift;
    return unless $self->is_text;
    
    my $full_text = read_file($self->file_path);
    $self->{full_text} = $full_text;
}

=item $media->store_temp_file(filename => $filename, content=> $text)

Stores media file to temporary location on filesystem, and sets 
$media->filename(), just like upload_file().  But in this case, the 
filename and its scalar text content are passed, instead of an actual file.

=cut

sub store_temp_file {
    my $self     = shift;
    my %args     = @_;
    my $root     = KrangRoot;
    my $filename = $args{filename}
      || croak('You must pass in a filename in order to save the temp file');
    croak('You cannot use a / in a filename!') if $filename =~ /\//;

    my $content = $args{content};
    $content = '' unless defined $content;

    my $path = tempdir(DIR => catdir(KrangRoot, 'tmp'));
    my $filepath = catfile($path, $filename);

    # text needs to be written out in an encoding aware way
    my $FILE;
    if( $self->is_text ) {
        pkg('IO')->open($FILE, '>', $filepath);
    } else {
        open($FILE, '>', $filepath);
    }
    croak("Unable to open $path for writing media!: $!") unless $FILE;
    print $FILE $content;
    close $FILE;

    $self->{tempfile} = $filepath;
    $self->{tempdir}  = $path;
    $self->{filename} = $filename;

    # blow the URL cache since filename has changed
    undef $self->{url_cache};

    # guess the mime_type
    $self->{mime_type} = $self->guess_mime_type($filepath);
    $self->{media_type_id} = $self->guess_media_type($filepath);

    $self->_update_full_text();

    return $self;
}

=item $file_path = $media->file_path() 

=item $file_path = $media->file_path(version = $version)

=item $relative_path = $media->file_path(relative => 1)

Return filesystem path of uploaded media file.  Given the C<version>
option, returns the filesystem path for this version or undef if this
version does not exist.

If the C<relative> option is set to 1 then the path returned is relative
to KrangRoot.  Returns undef before upload_file() on new objects.

Both options may be combined.

=cut

sub file_path {
    my ($self, %args) = @_;
    my $media_id = $self->{media_id};
    my $filename = $self->{filename};
    my $path;

    # if we have a temp file, return it
    if ($self->{tempfile}) {
        $path = $self->{tempfile};
    } elsif ($self->{media_id}) {

        # return path based on media_id if object has been committed to db
        my $instance = pkg('Conf')->instance;

        my $version = $args{version} ? $args{version} : $self->{version};
        return undef unless $version <= $self->{version};

        $path =
          catfile(KrangRoot, 'data', 'media', $instance, $self->_media_id_path(), $version,
            $self->{filename});
    } else {

        # no file_path found
        return unless $path;
    }

    # make path relative if requested
    return $args{relative} ? $self->_relativize_path($path) : $path;
}

sub _relativize_path {
    my ($self, $path) = @_;
    my $root = KrangRoot;
    $path =~ s/^$root\/?//;
    return $path;
}

sub _media_id_path {
    my $self     = shift;
    my $media_id = $self->{media_id};
    my @media_id_path;

    if ($media_id >= 1000) {
        push(@media_id_path, substr($media_id, 0, 3));
    } else {
        push(@media_id_path, $media_id);
    }
    push(@media_id_path, $media_id);
    return catdir(@media_id_path);
}

=item $file_size = $media->file_size()

Return filesize in bytes.

=cut

sub file_size {
    my $self = shift;
    if ($self->file_path()) {
        my $st = stat($self->file_path());
        return $st->size;
    } else {
        return 0;
    }
}

=item $width = $media->width()

Return width of image in pixels.

=cut

sub width {
    my $self = shift;
    if ($self->file_path()) {
        my ($w, $h) = imgsize($self->file_path());
        return $w;
    } else {
        return;
    }
}

=item $width = $media->height()

Return height of image in pixels.

=cut

sub height {
    my $self = shift;
    if ($self->file_path()) {
        my ($w, $h) = imgsize($self->file_path());
        return $h;
    } else {
        return;
    }
}

=item * C<element> (readonly)

The element for this media object.

=cut

sub element {
    my $self = shift;
    return $self->{element} if $self->{element};
    ($self->{element}) = pkg('Element')->load(
        element_id => $self->{element_id},
        object     => $self
    );

    return $self->{element};
}

=item * C<element_id> (readonly)

The element_id for this media object.

=cut

sub element_id {
    my $self = shift;
    return $self->{element_id};
}

=item $media->save()

=item C<< $media->save(keep_version => 1) >>

Commits media object to the database. Will set media_id to unique id
if not already defined (first save). Increments the version number unless 
called with 'keep_version' set to 1.

If this media object has the same URL as an existing object then
save() will throw a Krang::Media::DuplicateURL exception with a
media_id field indicating the conflicting object.

Users may only save media to categories to which they have edit access.
If the user does not have access to the specified category, save()
will throw a 'Krang::Media::NoCategoryEditAccess' exception.

This method will throw a "Krang::Media::NoEditAccess" exception if a
user does not otherwise have access to edit the media.

=cut

sub save {
    my $self = shift;
    my %args = @_;
    my $dbh  = dbh;
    my $root = KrangRoot;
    my $media_id;

    # Is user allowed to otherwise edit this object?
    Krang::Media::NoEditAccess->throw(
        message  => "Not allowed to edit media",
        media_id => $self->media_id
    ) unless ($self->may_edit);

    # Check permissions: Is user allowed to edit the category?
    my $category_id = $self->{category_id};
    my $category    = $self->category;
    Krang::Media::NoCategoryEditAccess->throw(
        message     => "Not allowed to edit media in category $category_id",
        category_id => $category_id
    ) unless ($category->may_edit);

    $self->{url} = $self->url();

    # check for duplicate url and throw an exception if one found
    $self->duplicate_check();

    # croak if media_type_id not defined
    croak('media_type_id must be set before saving media object!') unless $self->{media_type_id};

    # save element, get id back
    my $element = $self->element;
    $element->save();
    $self->{element_id} = $element->element_id();

    # if this is not a new media object
    if (defined $self->{media_id}) {
        $media_id = $self->{media_id};

        # find last-saved filename (in case we're renaming)
        my ($last_saved_object) = pkg('Media')->find(media_id => $self->media_id);
        my $last_saved_filename = $last_saved_object->filename;

        # get rid of media_id
        my @save_fields = grep { ($_ ne 'media_id') && ($_ ne 'creation_date') } FIELDS;

        # update version
        $self->{version} = $self->{version} + 1 unless $args{keep_version};

        # format publish_date for mysql
        my $old_pub_date = $self->{publish_date} || undef;
        $self->{publish_date} = $self->{publish_date}->mysql_datetime if $self->{publish_date};

        my $sql =
          'UPDATE media SET ' . join(', ', map { "$_ = ?" } @save_fields) . ' WHERE media_id = ?';
        my @data = ();
        for my $field (@save_fields) {
            push(@data, $self->{$field});
        }
        $dbh->do($sql, undef, @data, $media_id);

        # reformat
        $self->{publish_date} = $old_pub_date if $old_pub_date;

        # this file exists, new media was uploaded. copy to new position
        if ($self->{tempfile}) {
            my $old_path = delete $self->{tempfile};
            my $new_path = $self->file_path;
            mkpath((splitpath($new_path))[1]);
            move($old_path, $new_path) || croak("Cannot move to $new_path");
            rmtree(delete $self->{tempdir});
        } elsif (not $args{keep_version}) {

            # there's no new file, so create hard link to old version

            # first find old path by reverting version number & filename and calling file_path()
            my $new_filename = $self->filename;
            $self->{version}--;
            $self->{filename} = $last_saved_filename;
            my $old_path = $self->file_path;

            # next determine new file path
            $self->{version}++;
            $self->{filename} = $new_filename;
            my $new_path = $self->file_path;

            # then create the new path, and link it to the old one
            mkpath((splitpath($new_path))[1]);
            link $old_path, $new_path
              or croak("Unable to create link $old_path to $new_path");

            # if name changed, record that in history table
            # (note that the 'rename' action corresponds to renaming an
            # existing file via a link; uploading (or editing to create)
            # a new file with a new name does not log a 'rename')
            add_history(object => $self, action => 'rename')
              if ($new_filename ne $last_saved_filename);
        }
    } else {
        croak('You must upload a file using upload_file() before saving media object!')
          unless $self->{tempfile};

        $self->{version} = 1;
        my $time = localtime();
        $self->{creation_date} = $time->mysql_datetime();

        $dbh->do(
            'INSERT INTO media ('
              . join(',', FIELDS)
              . ') VALUES (?'
              . ",?" x (scalar FIELDS - 1) . ")",
            undef,
            map { $self->{$_} } FIELDS
        );

        # make date readable
        $self->{creation_date} = $time;

        $self->{media_id} = $dbh->{mysql_insertid};

        $media_id = $self->{media_id};

        my $old_path = delete $self->{tempfile};
        my $new_path = $self->file_path;
        mkpath((splitpath($new_path))[1]);
        move($old_path, $new_path) || croak("Cannot create $new_path");
        rmtree(delete $self->{tempdir});
    }

    # remove any existing media_contrib relatinships and save any new relationships
    $dbh->do('delete from media_contrib where media_id = ?', undef, $media_id);
    my $count;
    foreach my $contrib (@{$self->{contrib_ids}}) {
        $dbh->do(
            'insert into media_contrib (media_id, contrib_id, contrib_type_id, ord) values (?,?,?,?)',
            undef, $media_id, $contrib->{contrib_id}, $contrib->{contrib_type_id}, $count++
        );
    }

    # save a copy in the version table
    my $serialized;
    eval { $serialized = nfreeze($self); };
    croak("Unable to serialize object: $@") if $@;
    $dbh->do('REPLACE INTO media_version (media_id, version, data) values (?,?,?)',
        undef, $media_id, $self->{version}, $serialized);

    # prune previous versions from the version table
    $self->prune_versions();

    # save the tags
    $self->_save_tags();

    add_history(
        object => $self,
        action => 'new',
    ) if $self->{version} == 1;

    add_history(
        object => $self,
        action => 'save',
    );

}

sub _save_tags {
    my $self = shift;
    my $dbh  = dbh();
    my $id   = $self->media_id;

    if (my $tags = $self->{tags}) {
        # clear out any old tags before we insert the new ones
        $dbh->do('DELETE FROM media_tag WHERE media_id = ?', {}, $id);

        my $sth = $dbh->prepare_cached('INSERT INTO media_tag (media_id, tag, ord) VALUES (?,?,?)');
        my $ord = 1;
        foreach my $tag (@$tags) {
            $sth->execute($id, $tag, $ord++);
        }
    }
}

=item @media = Krang::Media->find($param)

Find and return media object(s) with parameters specified. Supported paramter keys:

=over 4

=item * media_id 

(can optionally take a list of ids)

=item * media_uuid

=item * version 

combined with a single C<media_id> (and only C<media_id>), loads a
specific version of a media object.  Unlike C<revert()>, this object
has C<version> set to the actual version number of the loaded object.

=item * title

=item * title_like

case insensitive match on title. Must include '%' on either end for
substring match.

=item * tag

Search for media that have the given tag.

=item * alt_tag

=item * alt_tag_like

case insensitive match on alt_tag. Must include '%' on either end for
substring match.

=item * category_id

=item * below_category_id

will return media in category and in categories below as well.

=item * site_id

returns all media objects associated with a given site.

=item * media_type_id

=item * contrib_id 

=item * filename

=item * filename_like

case insensitive match on filename. Must include '%' on either end for
substring match.

=item * mime_type

=item * published

only returns items that have been published previously.

=item * simple_search

Performs a per-word LIKE substring match against title, filename, and url,
and an exact match against media_id if value passed in is a number.

=item * exclude_media_ids

excludes (an array ref of) IDs from the result set

=item * no_attributes

returns objects where the fields caption, copyright, notes, and alt_tag
are empty if this is set.

=item * order_by

field to order search by, defaults to media_id

=item * order_desc

results will be in ascending order unless this is set to 1 (making
them descending).

=item * limit

limits result to number passed in here, else no limit.

=item * offset

offset results by this number, else no offset.

=item * url

=item * url_like

case insensitive match on url. Must include '%' on either end for
substring match.

=item * full_text

If the media is text-based then we will look at it's contents and
do a full text search for this phrase.

=item * checked_out

Set to 0 to find only non-checked-out media.  Set to 1 to find only
checked out media.  The default, C<undef> returns all media.

=item * checked_out_by

Set to a user_id to find media checked-out by a user.

=item * ids_only

return only media_ids, not objects if this is set true.

=item * count

return only a count if this is set to true. Cannot be used with ids_only.

=item * creation_date

May be either a single date (a L<Time::Piece> object) or an array of
2 dates specifying a range.  In ranges either member may be C<undef>,
specifying no limit in that direction.

=item * include_live

Include live media in the search result. Live media are media that are
neither retired nor have been moved to the trashbin. Set this option to 0,
if find() should not return live media.  The default is 1.

=item * include_retired

Set this option to 1 if you want to include retired media in the search
result. The default is 0.

=item  * include_trashed

Set this option to 1 if you want to include trashed media in the search
result. Trashed media live in the trashbin. The default is 0.

B<NOTE:>When searching for media_id, these three include_* flags are
not taken into account!

=item  * element_index_like - BETA FEATURE: NEEDS MORE TESTING

This find option allows you to search against indexed element data.
For details on element indexing, see L<Krang::ElementClass>.  This
option should be set with an array containing the element name and the
value to match against.  For example, to search for media objects containing
'boston' in their location, assuming location is an indexed element:

    @media = pkg('Media')->find(element_index_like => [location => '%boston%']);

=back

=cut

sub find {
    my $self = shift;
    my %args = @_;
    my $dbh  = dbh;
    my @where;
    my @media_object;

    my %valid_params = (
        media_id           => 1,
        media_uuid         => 1,
        version            => 1,
        title              => 1,
        title_like         => 1,
        tag                => 1,
        alt_tag            => 1,
        alt_tag_like       => 1,
        url                => 1,
        url_like           => 1,
        category_id        => 1,
        below_category_id  => 1,
        site_id            => 1,
        media_type_id      => 1,
        contrib_id         => 1,
        filename           => 1,
        filename_like      => 1,
        simple_search      => 1,
        no_attributes      => 1,
        order_by           => 1,
        order_desc         => 1,
        published          => 1,
        checked_out        => 1,
        checked_out_by     => 1,
        limit              => 1,
        offset             => 1,
        count              => 1,
        creation_date      => 1,
        ids_only           => 1,
        may_see            => 1,
        may_edit           => 1,
        mime_type          => 1,
        mime_type_like     => 1,
        include_live       => 1,
        include_retired    => 1,
        include_trashed    => 1,
        exclude_media_ids  => 1,
        element_index_like => 1,
        full_text          => 1,
    );

    # check for invalid params and croak if one is found
    foreach my $param (keys %args) {
        croak(__PACKAGE__ . "->find() - Invalid parameter '$param' called.")
          unless ($valid_params{$param});
    }

    # set defaults if need be
    my $order_by   = $args{'order_by'}   ? $args{'order_by'} : 'media_id';
    my $order_desc = $args{'order_desc'} ? 'desc'            : 'asc';
    my $include_retired = delete $args{include_retired} || 0;
    my $include_trashed = delete $args{include_trashed} || 0;
    my $include_live    = delete $args{include_live};
    $include_live = 1 unless defined($include_live);

    # cleanup filename
    $args{filename} = $self->clean_filename($args{filename}) if $args{filename};

    # Put table name "media." in front of each orderby, and $order_desc after
    my @order_bys = split(/\s*\,\s*/, $order_by);
    $order_by = join(", ", (map { "media.$_ $order_desc" } @order_bys));

    my $limit  = $args{'limit'}  ? $args{'limit'}  : undef;
    my $offset = $args{'offset'} ? $args{'offset'} : 0;

    # check for invalid argument sets
    croak(  __PACKAGE__
          . "->find(): 'count' and 'ids_only' were supplied. "
          . "Only one can be present.")
      if $args{count} and $args{ids_only};

    croak(__PACKAGE__ . "->find(): can't use 'version' without 'media_id'.")
      if $args{version} and not $args{media_id};

    if ($args{version}) {
        if (ref $args{media_id} eq 'ARRAY') {
            croak(__PACKAGE__
                  . "->find(): can't use 'version' with an array of media_ids, must be a single media_id."
            );
        } else {

            # loading a past version is handled by _load_version()
            return $self->_load_version($args{media_id}, $args{version});
        }
    }

    # set simple keys
    my @simple_keys = qw( title alt_tag category_id media_type_id filename url
      contrib_id checked_out_by may_see may_edit media_uuid
      mime_type );
    foreach my $key (keys %args) {
        next unless (defined $args{$key} && length $args{$key});
        if (grep { $key eq $_ } @simple_keys) {
            push @where, $key;
        }
    }

    my @where_fields = ();
    foreach my $field (@where) {

        # Pre-pend table name -- either "ucpc" or "media"
        my @ucpc_fields = qw( may_see may_edit );
        my $fqfield = (grep { $field eq $_ } @ucpc_fields) ? "ucpc." : "media.";
        $fqfield .= $field;
        push(@where_fields, $fqfield);
    }

    # Add user_id into the query
    my $user_id = $ENV{REMOTE_USER} || croak("No user_id in REMOTE_USER");
    push(@where_fields, "ucpc.user_id");
    push(@where,        "user_id");
    $args{user_id} = $user_id;

    if( $args{tag} ) {
        push(@where, 'tag');
        push(@where_fields, 'mt.tag');
    }

    # Build query
    my $where_string = "";
    $where_string .= join(' and ', map { "$_ = ?" } @where_fields);

    # add media_id(s) if needed
    if ($args{media_id}) {
        if (ref $args{media_id} eq 'ARRAY') {
            if (scalar(@{$args{media_id}}) > 0) {
                $where_string .= " and " if $where_string;
                $where_string .= "("
                  . join(" OR ", map { " media.media_id = " . $dbh->quote($_) } @{$args{media_id}})
                  . ')';
            }
        } else {
            $where_string .= " and " if $where_string;
            $where_string .= "media.media_id = " . $dbh->quote($args{media_id});
        }
    }

    # add title_like to where_string if present
    if ($args{'title_like'}) {
        $where_string .= " and " if $where_string;
        $where_string .= "media.title like ?";
        push @where, 'title_like';
    }

    # add alt_tag_like to where_string if present
    if ($args{'alt_tag_like'}) {
        $where_string .= " and " if $where_string;
        $where_string .= "media.alt_tag like ?";
        push @where, 'alt_tag_like';
    }

    # add full_text to where_string if present
    if ($args{full_text}) {
        $where_string .= " AND " if $where_string;
        $where_string .= "media.full_text like ?";
        push @where, 'full_text';

        $args{full_text} = '%' . $args{full_text} . '%' unless $args{full_text} =~ /^%.*%$/;
    }

    # add ids of category and cats below if below_category_id is passed in
    if ($args{'below_category_id'}) {
        my $specd_cat = (pkg('Category')->find(category_id => $args{below_category_id}))[0];
        if ($specd_cat) {
            my @descendants = $specd_cat->descendants(ids_only => 1);
            unshift @descendants, $specd_cat->category_id;

            $where_string .= " and " if $where_string;
            $where_string .=
              "(" . join(" OR ", map { "media.category_id = $_" } @descendants) . ")";
        }
    }

    # add join to category table if site_id param is passed in.
    if ($args{site_id}) {
        $where_string .= ' and ' if $where_string;
        $where_string .= "(media.category_id = category.category_id) AND ";
        if (ref $args{site_id} eq 'ARRAY') {
            if (scalar(@{$args{site_id}}) > 0) {
                $where_string .= 'category.site_id IN (' . join(',', @{$args{site_id}}) . ')';
            }
        } else {
            $where_string .= "(category.site_id=?)";
            push @where, 'site_id';
        }
    }

    # add filename_like to where_string if present
    if ($args{'filename_like'}) {
        $where_string .= " and " if $where_string;
        $where_string .= "media.filename like ?";
        push @where, 'filename_like';
    }

    # return only objects that have been published previously
    if ($args{published}) {
        $where_string .= " and " if $where_string;
        $where_string .= "published";
    }

    # add mime_type_like to where_string if present
    if ($args{'mime_type_like'}) {
        $where_string .= " and " if $where_string;
        $where_string .= "media.mime_type like ?";
        push @where, 'mime_type_like';
    }

    # add url_like to where_string if present
    if ($args{'url_like'}) {
        $where_string .= " and " if $where_string;
        $where_string .= "media.url like ?";
        push @where, 'url_like';
    }

    # checked out if checked_out_by is NULL
    if (defined $args{'checked_out'}) {
        $where_string .= " and " if $where_string;
        $args{'checked_out'}
          ? ($where_string .= "media.checked_out_by is not NULL")
          : ($where_string .= "media.checked_out_by is NULL");
    }

    if ($args{'no_attributes'}) {
        $where_string .= " and " if $where_string;
        $where_string .=
          "((media.caption = '' or media.caption is NULL) AND (media.copyright = '' or media.copyright is NULL) AND (media.notes = '' or media.notes is NULL) AND (media.alt_tag = '' or media.alt_tag is NULL))";
    }

    if ($args{'creation_date'}) {
        if (ref($args{'creation_date'}) eq 'ARRAY') {
            $where_string .= " and " if $where_string;
            if ($args{'creation_date'}[0] and $args{'creation_date'}[1]) {
                $where_string .=
                    " media.creation_date BETWEEN '"
                  . $args{'creation_date'}[0]->mysql_datetime
                  . "' AND '"
                  . $args{'creation_date'}[1]->mysql_datetime . "'";
            } elsif ($args{'creation_date'}[0]) {
                $where_string .=
                  " media.creation_date >= '" . $args{'creation_date'}[0]->mysql_datetime . "'";
            } elsif ($args{'creation_date'}[1]) {
                $where_string .=
                  " media.creation_date <= '" . $args{'creation_date'}[1]->mysql_datetime . "'";
            } else {
                croak(
                    "Bad date arguement for creation_date, must be either an array of two Time::Piece objects or one Time::Piece object."
                );
            }
        } else {
            $where_string .= " and " if $where_string;
            $where_string .=
              " media.creation_date = '" . $args{'creation_date'}->mysql_datetime . "'";
        }
    }

    # handle exclude_media_ids => [1, 2, 3]
    if (my $exclude_ids = $args{exclude_media_ids}) {
        if (@$exclude_ids) {
            foreach my $id (@$exclude_ids) {
                $where_string .= " and " if $where_string;
                $where_string .= "media.media_id != $id";
            }
        }
    }

    # ELEMENT_INDEX_LIKE -- BETA FEATURE: NEEDS MORE TESTING
    if ($args{element_index_like}) {
        my $element_index = $args{element_index_like};
        $where_string .= ' and ' if $where_string;
        $where_string .= 'element.class = ? ';
        $where_string .= 'and element_index.value LIKE ?';
        push(@where, $element_index->[0], '%' . $element_index->[1] . '%');
    }

    if ($args{'simple_search'}) {
        my @words = split(/\s+/, $args{'simple_search'});
        foreach my $word (@words) {
            my $numeric = ($word =~ /^\d+$/) ? 1 : 0;
            my $joined =
              $numeric
              ? 'media.media_id = ?'
              : '('
              . join(' OR ', 'media.title LIKE ?', 'media.url LIKE ?', 'media.filename LIKE ?')
              . ')';
            $where_string .= " and " if $where_string;
            $where_string .= $joined;
            if ($numeric) {
                push @where, 'simple_search';
            } else {

                # escape any literal SQL wildcard chars
                $word =~ s/_/\\_/g;
                $word =~ s/%/\\%/g;
                $args{$word} = '%' . $word . '%';
                push @where, ($word, $word, $word);
            }
        }
    }

    # Get user asset permissions -- overrides may_edit if false
    my $media_access = pkg('Group')->user_asset_permissions('media');

    my $select_string;
    my $group_by = 0;
    if ($args{'count'}) {
        $select_string = 'COUNT(distinct media.media_id) AS count';
    } elsif ($args{'ids_only'}) {
        $select_string = 'media.media_id';
    } else {
        my @fields = map { "media.$_" } (grep { ($_ ne 'media_id') } FIELDS);
        push(@fields, "ucpc.may_see AS may_see");

        # Handle asset_media/may_edit
        if ($media_access eq "edit") {
            push(@fields, "ucpc.may_edit AS may_edit");
        } else {
            push(@fields, $dbh->quote("0") . " AS may_edit");
        }

        $select_string = 'media.media_id, ' . join(',', @fields);

        # Set up group by
        $group_by++;
    }

    # include live/retired/trashed
    unless ($args{media_id} or $args{media_uuid}) {
        if ($include_live) {
            unless ($include_retired) {
                $where_string .= ' AND ' if $where_string;
                $where_string .= ' media.retired = 0';
            }
            unless ($include_trashed) {
                $where_string .= ' AND ' if $where_string;
                $where_string .= ' media.trashed  = 0';
            }
        } else {
            if ($include_retired) {
                if ($include_trashed) {
                    $where_string .= ' AND ' if $where_string;
                    $where_string .= ' media.retired = 1 AND media.trashed = 1';
                } else {
                    $where_string .= ' AND ' if $where_string;
                    $where_string .= ' media.retired = 1 AND media.trashed = 0';
                }
            } else {
                if ($include_trashed) {
                    $where_string .= ' AND ' if $where_string;
                    $where_string .= ' media.trashed = 1';
                }
            }
        }
    }

    my $sql = qq/SELECT $select_string FROM media
      LEFT JOIN user_category_permission_cache AS ucpc ON (ucpc.category_id = media.category_id) /;
    $sql .= 'LEFT JOIN media_tag AS mt ON (mt.media_id = media.media_id) ' if $args{tag};
    $sql .= ', element, element_index' if $args{element_index_like};
    $sql .= ", media_contrib"          if $args{'contrib_id'};
    $sql .= ', category'               if $args{site_id};

    $sql .= " WHERE " . $where_string  if $where_string;
    $sql .= " GROUP BY media.media_id" if ($group_by);
    $sql .= " ORDER BY $order_by";

    # add limit and/or offset if defined
    if ($limit) {
        $sql .= " LIMIT $offset, $limit";
    } elsif ($offset) {
        $sql .= " LIMIT $offset, 18446744073709551615";
    }

    debug(__PACKAGE__ . "::find() SQL: " . $sql);
    debug(  __PACKAGE__
          . "::find() SQL ARGS: "
          . join(', ', map { defined $args{$_} ? $args{$_} : 'undef' } @where));

    my $sth = $dbh->prepare($sql);
    $sth->execute(map { $args{$_} } @where) || croak("Unable to execute statement $sql");
    while (my $row = $sth->fetchrow_hashref()) {
        my $obj;
        if ($args{'count'}) {
            return $row->{count};
        } elsif ($args{'ids_only'}) {
            $obj = $row->{media_id};
        } else {
            $obj = bless {%$row}, $self;

            # make dates into Time::Piece objects
            foreach my $date_field (grep { /_date$/ } keys %$obj) {
                next
                  unless ((defined $obj->{$date_field})
                    and ($obj->{$date_field} ne '0000-00-00 00:00:00'));
                $obj->{$date_field} = Time::Piece->from_mysql_datetime($obj->{$date_field});
            }

            # add contrib ids to object
            my $sth2 =
              $dbh->prepare(
                'select contrib_id, contrib_type_id from media_contrib where media_id = ? order by ord'
              );
            $sth2->execute($row->{media_id});
            $obj->{contrib_ids} = [];
            while (my ($contrib_id, $contrib_type_id) = $sth2->fetchrow_array()) {
                push @{$obj->{contrib_ids}},
                  {contrib_id => $contrib_id, contrib_type_id => $contrib_type_id};
            }
        }
        push(@media_object, $obj);
    }
    $sth->finish();
    return @media_object;
}

=item $media->revert($version)

Changes media object to a copy of the version specified. Does not actually edit the original version, but creates a new version identical to the original.

If the new version is successfully written to disk (no duplicate URL errors, etc.), the object itself is returned; if not, an error is returned.

=cut

sub revert {
    my $self           = shift;
    my $dbh            = dbh;
    my $version_number = shift;
    my $root           = KrangRoot;

    my $version        = $self->{version};          # make sure to preserve this
    my $checked_out_by = $self->{checked_out_by};

    croak('Must specify media version number to revert to') if (not $version_number);

    my $sql = 'SELECT data from media_version where media_id = ? AND version = ?';
    my $sth = $dbh->prepare($sql);
    $sth->execute($self->{media_id}, $version_number);

    my $data = $sth->fetchrow_array();
    $sth->finish();

    eval { %$self = %{thaw($data)}; };
    croak("Unable to deserialize object: $@") if $@;

    my $old_filepath = $self->file_path();
    $self->{version}        = $version;
    $self->{checked_out_by} = $checked_out_by;

    # copy old media file into tmp storage
    my $path = tempdir(DIR => catdir(KrangRoot, "tmp"));
    my $filepath = catfile($path, $self->{filename});
    copy($old_filepath, $filepath);
    $self->{tempfile} = $filepath;
    $self->{tempdir}  = $path;

    # attempt disk-write
    eval { $self->save };
    return $@ if $@;

    add_history(
        object => $self,
        action => 'revert',
    );

    return $self;
}

sub _load_version {
    my ($self, $media_id, $version) = @_;
    my $dbh = dbh;

    my $sql = 'SELECT data from media_version where media_id = ? AND version = ?';
    my $sth = $dbh->prepare($sql);
    $sth->execute($media_id, $version);

    my $data = $sth->fetchrow_array();
    $sth->finish();

    eval { $self = thaw($data); };
    croak("Unable to deserialize object: $@") if $@;

    my $old_filepath = $self->file_path();

    # copy old media file into tmp storage
    my $path = tempdir(DIR => catdir(KrangRoot, "tmp"));
    my $filepath = catfile($path, $self->{filename});
    copy($old_filepath, $filepath);
    $self->{tempfile} = $filepath;
    $self->{tempdir}  = $path;
    return $self;
}

=item $thumbnail_path = $media->thumbnail_path();

=item $thumbnail_path = $media->thumbnail_path(relative => 1);

=item $thumbnail_path = $media->thumbnail_path(medium => 1);

Returns the path to the thumbnail (if media is an image).  Valid image
types are stored in IMAGE_TYPES constant. Will create thumbnail if
first time called.  If C<relative> is set to 1, returns a path relative
to KrangRoot.

If C<medium> is set to true, then it will return the path to the medium
sized thumbnail.

Returns undef if a thumbnail cannot be created.

=cut

sub thumbnail_path {
    my ($self, %args) = @_;
    my $filename = $self->{filename};
    return undef unless $filename;

    # thumbnail path is the same as the file path with t__ or m__ in front of
    # the filename (depending on whether or not it's medium or not)
    my $prefix = $args{medium} ? 'm__' : 't__';
    my $path = catfile((splitpath($self->file_path))[1], $prefix . $filename);

    # all done if it exists
    if( -s $path ) {
        return $args{relative} ? $self->_relativize_path($path) : $path;
    }

    # don't bother with non images
    return undef unless $self->{mime_type} =~ m!^image/!;

    # problems creating thumbnails shouldn't be fatal
    eval {
        my $img = Imager->new();
        $img->open(file => $self->file_path()) or croak $img->errstr();
        my $size = $args{medium} ? MED_THUMBNAIL_SIZE : THUMBNAIL_SIZE;

        # only resize if one side is bigger than the size we're scaling to
        my $thumb;
        if ($img->getwidth > $size || $img->getheight > $size) {
            $thumb = $img->scale(
                xpixels => $size,
                ypixels => $size,
                type    => 'min',
                qtype   => 'mixing',
            );
        } else {
            $thumb = $img;
        }

        # patch to fix a bug in Imager - zero-dimension images cause segfaults.
        if ($thumb->getwidth >= 1 && $thumb->getheight >= 1) {
            $thumb->write(file => $path) or croak $thumb->errstr;
        } else {
            debug(
                sprintf(
                    "%s: thumbnail not written for media_id=%i - dimensions too small",
                    __PACKAGE__, $self->media_id
                )
            );
            return undef;
        }
    };

    # if it didn't work, log the problem and move on. Thumbnails are
    # optional.
    if ($@) {
        debug(__PACKAGE__ . " - problem creating thumbnail for $filename : $@");
        return undef;
    }

    # all done, return the thumbnail path
    return $args{relative} ? $self->_relativize_path($path) : $path;
}

=item $media->checkout() || Krang::Media->checkout($media_id)

Marks media object as checked out by user_id.

Will throw a C<Krang::Media::NoEditAccess> exception if user is not allowed to edit this media.
Will throw a C<Krang::Media::CheckedOut> exception if the media is already checked out.

=cut

sub checkout {
    my $self     = shift;
    my $media_id = shift;
    my $dbh      = dbh;
    my $user_id  = $ENV{REMOTE_USER};

    # Load media if media is not already loaded
    unless (ref($self)) {
        croak("No media_id specified") unless ($media_id);
        my ($media) = pkg('Media')->find(media_id => $media_id);
        croak("Can't find media_id '$media_id'") unless ($media and ref($media));

        # We got it.  Save it.
        $self = $media;
    } else {

        # Set $media_id -- we need it later
        $media_id = $self->{media_id};
    }

    # Is user allowed to otherwise edit this object?
    Krang::Media::NoEditAccess->throw(
        message  => "Not allowed to edit media",
        media_id => $self->media_id
    ) unless ($self->may_edit);

    # Short circuit if media is checked out by current user
    return if ($self->{checked_out_by}
        and $self->{checked_out_by} == $user_id);

    eval {
        $dbh->do('LOCK tables media WRITE');
        my $sth = $dbh->prepare('SELECT checked_out_by FROM media WHERE media_id = ?');
        $sth->execute($media_id);

        my $checkout_id = $sth->fetchrow_array();
        if( $checkout_id && ($checkout_id != $user_id)) {
            Krang::Media::CheckedOut->throw(
                message => "Media $self->{media_id} is already checked out by user '$user_id'",
                user_id => $user_id,
            );
        }

        $sth->finish();
        $dbh->do('update media set checked_out_by = ? where media_id = ?', undef, $user_id, $media_id);
        $dbh->do('UNLOCK tables');
    };

    if (my $e = $@) {
        $dbh->do('UNLOCK tables');
        croak($e);
    }

    $dbh->do('UNLOCK tables');

    $self->{checked_out_by} = $user_id;
    add_history(
        object => $self,
        action => 'checkout'
    );
}

=item $media->checkin() || Krang::Media->checkin($media_id)

Marks media object as checked in.

=cut

sub checkin {
    my $self     = shift;
    my $media_id = shift;
    my $dbh      = dbh;
    my $user_id  = $ENV{REMOTE_USER};

    # Load media if media is not already loaded
    unless (ref($self)) {
        croak("No media_id specified") unless ($media_id);
        my ($media) = pkg('Media')->find(media_id => $media_id);
        croak("Can't find media_id '$media_id'") unless ($media and ref($media));

        # We got it.  Save it.
        $self = $media;
    } else {

        # Set $media_id -- we need it later
        $media_id = $self->{media_id};
    }

    # Is user allowed to otherwise edit this object?
    Krang::Media::NoEditAccess->throw(
        message  => "Not allowed to edit media",
        media_id => $self->media_id
    ) unless ($self->may_edit);

    $dbh->do('UPDATE media SET checked_out_by = NULL WHERE media_id = ?', undef, $media_id);

    $self->{checked_out_by} = undef;

    add_history(
        object => $self,
        action => 'checkin'
    );
}

=item C<< $media->mark_as_published() >>

Mark the media object as published.  This will update the C<publish_date> and
C<published_version> attributes, and will also check the media object back
in.

This will also make an entry in the log that the media object has been published.

=cut

sub mark_as_published {
    my $self = shift;

    croak __PACKAGE__ . ": Cannot publish unsaved media object" unless ($self->{media_id});

    $self->{published_version} = $self->{version};
    $self->{publish_date}      = localtime;
    $self->{checked_out_by}    = undef;
    $self->{published}         = 1;

    # update the DB.
    my $dbh = dbh();
    $dbh->do(
        'UPDATE media
              SET checked_out_by = ?,
                  published = 1,
                  published_version = ?,
                  publish_date = ?
              WHERE media_id = ?',

        undef,
        $self->{checked_out_by},
        $self->{published_version},
        $self->{publish_date}->mysql_datetime,
        $self->{media_id}
    );
}

=item C<< $media->mark_as_previewed(unsaved => 1) >>

Mark the media object as previewed.  This will update the
C<preview_version> attribute, setting it equal to C<version>.  This is
used as a sanity check by L<Krang::Publisher> to prevent re-generation
of content.

The argument C<unsaved> defaults to 0.  If true, it indicates that the
media being previewed is in the process of being edited, in which case
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
        'UPDATE media SET preview_version = ? WHERE media_id = ?',
        undef, $self->{preview_version},
        $self->{media_id}
    );

}

=item $media = $media->url();

Returns calculated url of media object based on category_id and filename

=cut

sub url {
    my $self = shift;

    croak "illegal attempt to set readonly attribute 'url'.\n"
      if @_;

    return undef unless ($self->{category_id} and $self->{filename});

    return $self->{url_cache} if $self->{url_cache};

    # else calculate url
    my $category = $self->category;
    croak("Unable to load category $self->{category_id}")
      unless $category;

    my $url = catfile($category->url, $self->{filename});
    $self->{url_cache} = $url;
    return $url;
}

=item * preview_url (read-only)

The preview URL for this media object

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

=item $path = $media->publish_path()

Returns the publish path for the media object, using the site's
publish_path and the media's URL.  This is the filesystem path where
the media object will be published.

=cut

sub publish_path {
    my $self = shift;
    my $path = $self->category->site->publish_path;
    my $url  = $self->url;

    # remove the site part
    $url =~ s![^/]+/!!;

    # paste them together
    return canonpath(catfile($path, $url));
}

=item $path = $media->preview_path()

Returns the preview path for the media object, using the site's
preview_path and the media's URL.  This is the filesystem path where
the media object will be previewed.

=cut

sub preview_path {
    my $self = shift;
    my $path = $self->category->site->preview_path;
    my $url  = $self->preview_url;

    # remove the site part
    $url =~ s![^/]+/!!;

    # paste them together
    return canonpath(catfile($path, $url));
}

=item $media_id = $media->duplicate_check()

This method checks whether the url of a media object is unique.

=cut

sub duplicate_check {
    my ($self, %args) = @_;
    my $id = $self->{media_id} || 0;
    my $media_id = 0;

    my $query = <<SQL;
SELECT media_id
FROM   media
WHERE  url = ?
AND    retired = 0
AND    trashed  = 0
SQL

    $query .= " AND media_id != $id" if $id;

    my $dbh = dbh();
    my $sth = $dbh->prepare($query);
    $sth->execute($self->url);
    $sth->bind_col(1, \$media_id);
    $sth->fetch();
    $sth->finish();

    Krang::Media::DuplicateURL->throw(
        message  => "duplicate URL",
        media_id => $media_id
    ) if $media_id;
}

=item $media->preview

Convenience method to Krang::Publisher, previews media object.

=cut 

sub preview {
    my $self      = shift;
    my $publisher = pkg('Publisher')->new();

    $publisher->preview_media(media => $self);

}

=item $media->publish

Convenience method to Krang::Publisher, publishes media object.

=cut

sub publish {
    my $self      = shift;
    my $publisher = pkg('Publisher')->new();

    $publisher->publish_media(media => $self);
}

=item $media->delete() || Krang::Media->delete($media_id)

Permenantly delete media object or media object with given id.

Attempts to checkout the media object, will croak if checked out by another user.

Will throw "Krang::Media::NoEditAccess" exception if user is not allowed to edit
this media.

=cut

sub delete {
    my $self     = shift;
    my $media_id = shift;

    my $is_object = $media_id ? 0 : 1;

    $self = (pkg('Media')->find(media_id => $media_id))[0] if $media_id;

    croak("No media_id specified for delete!") if not $self->{media_id};

    # Is user allowed to delete objects from the trashbin?
    Krang::Media::NoDeleteAccess->throw(
        message  => "Not allowed to delete media",
        media_id => $self->media_id
    ) unless pkg('Group')->user_admin_permissions('admin_delete');

    my $dbh  = dbh;
    my $root = KrangRoot;

    $self->checkout();

    # unpublish
    pkg('Publisher')->new->unpublish_media(media => $self);

    # and "unpreview", too
    debug __PACKAGE__
      . '->delete(): '
      . "calling \$previewer = pkg('Publisher')->new->_set_preview_mode "
      . "&& \$previewer->unpublish_media(media => $self)";
    my $previewer = pkg('Publisher')->new;
    $previewer->_set_preview_mode();
    $previewer->unpublish_media(media => $self);

    # first delete history for this object
    pkg('History')->delete(object => $self);

    # and delete media element
    $self->element->delete;

    my $file_dir = catdir($root, 'data', 'media', pkg('Conf')->instance, $self->_media_id_path);

    $dbh->do('DELETE from media where media_id = ?',         undef, $self->{media_id});
    $dbh->do('DELETE from media_version where media_id = ?', undef, $self->{media_id});
    $dbh->do('delete from media_contrib where media_id = ?', undef, $self->{media_id});

    rmtree($file_dir) || croak("Cannot delete $file_dir and contents.");

    # delete schedules for this media
    $dbh->do('DELETE FROM schedule WHERE object_type = ? and object_id = ?',
        undef, 'media', $self->{media_id});

    # delete alerts for this media
    $dbh->do('DELETE FROM alert WHERE object_type = ? and object_id = ?',
        undef, 'media', $self->{media_id});

    # remove from trash
    pkg('Trash')->remove(object => $self);

    add_history(
        object => $self,
        action => 'delete',
    );
}

=item * C<< @linked_stories = $media->linked_stories >>

Returns a list of stories linked to from this media object.  These will be
  Krang::Story objects.  If no stories are linked, returns an empty
list.  This list will not contain any duplicate stories, even if a
story is linked more than once.

=cut

sub linked_stories {
    my $self    = shift;
    my $element = $self->element;

    # find StoryLinks and index by id
    my %story_links;
    my $story;
    foreach_element {
        if (    $_->class->isa('Krang::ElementClass::StoryLink')
            and $story = $_->data)
        {
            $story_links{$story->story_id} = $story;
        }
    }
    $element;

    return values %story_links;
}

=item * C<< @linked_media = $media->linked_media >>


Returns a list of media linked to from this media.  These will be
  Krang::Media objects.  If no media are linked, returns an empty list.
This list will not contain any duplicate media, even if a media object
is linked more than once.

=cut

sub linked_media {
    my $self    = shift;
    my $element = $self->element;

    # find MediaLinks and index by id
    my %media_links;
    my $media;
    foreach_element {
        if (    $_->class->isa('Krang::ElementClass::MediaLink')
            and $media = $_->data)
        {
            $media_links{$media->media_id} = $media;
        }
    }
    $element;
    return values %media_links;
}

=item C<< $media->serialize_xml(writer => $writer, set => $set) >>

Serialize as XML.  See Krang::DataSet for details.

=cut

sub serialize_xml {
    my ($self,   %args) = @_;
    my ($writer, $set)  = @args{qw(writer set)};
    local $_;

    # open up <media> linked to schema/media.xsd
    $writer->startTag(
        'media',
        "xmlns:xsi"                     => "http://www.w3.org/2001/XMLSchema-instance",
        "xsi:noNamespaceSchemaLocation" => 'media.xsd'
    );

    # hash the media_id to a path
    my $media_id = $self->{media_id};
    my $one      = $media_id % 1024;
    my $two      = int($media_id / 1024);
    my $path     = "media_$one/$two/$self->{filename}";

    # write media file into data set
    $set->add(file => $self->file_path, path => $path, from => $self);

    my %media_type = pkg('Pref')->get('media_type');

    # basic fields
    $writer->dataElement(media_id          => $self->{media_id});
    $writer->dataElement(media_uuid        => $self->{media_uuid});
    $writer->dataElement(media_type        => $media_type{$self->{media_type_id}});
    $writer->dataElement(title             => $self->{title});
    $writer->dataElement(filename          => $self->{filename});
    $writer->dataElement(path              => $path);
    $writer->dataElement(category_id       => $self->{category_id});
    $writer->dataElement(url               => $self->{url});
    $writer->dataElement(caption           => $self->{caption});
    $writer->dataElement(copyright         => $self->{copyright});
    $writer->dataElement(alt_tag           => $self->{alt_tag});
    $writer->dataElement(notes             => $self->{notes});
    $writer->dataElement(version           => $self->{version});
    $writer->dataElement(published         => $self->{published});
    $writer->dataElement(published_version => $self->{published_version})
      if $self->{published_version};
    $writer->dataElement(creation_date => $self->{creation_date}->datetime);
    $writer->dataElement(publish_date  => $self->{publish_date}->datetime)
      if $self->{publish_date};
    $writer->dataElement(retired   => $self->retired);
    $writer->dataElement(trashed   => $self->trashed);
    $writer->dataElement(read_only => $self->read_only);

    # tags
    for my $tag ($self->tags) {
        $writer->dataElement(tag => $tag);
    }

    # add category to set
    $set->add(object => $self->category, from => $self);

    # contributors
    my %contrib_type = pkg('Pref')->get('contrib_type');
    for my $contrib ($self->contribs) {
        $writer->startTag('contrib');
        $writer->dataElement(contrib_id   => $contrib->contrib_id);
        $writer->dataElement(contrib_type => $contrib_type{$contrib->selected_contrib_type()});
        $writer->endTag('contrib');

        $set->add(object => $contrib, from => $self);
    }

    # schedules
    foreach
      my $schedule (pkg('Schedule')->find(object_type => 'media', object_id => $self->media_id))
    {
        $set->add(object => $schedule, from => $self);
    }

    # serialize elements
    $self->element->serialize_xml(
        writer => $writer,
        set    => $set
    );

    # all done
    $writer->endTag('media');
}

=item C<< $media = Krang::Media->deserialize_xml(xml => $xml, set => $set, no_update => 0) >>

Deserialize XML.  See Krang::DataSet for details.

If an incoming media has the same URL as an existing media then an
update will occur, unless no_update is set.

Note that the creation_date, version, published_version and
publish_date fields are ignored when importing media.

=cut

sub deserialize_xml {
    my ($pkg, %args) = @_;
    my ($xml, $set, $no_update) = @args{qw(xml set no_update)};

    # divide FIELDS into simple and complex groups
    my (%complex, %simple);
    @complex{
        qw(media_id filename publish_date creation_date checked_out_by element_id
          version url published_version category_id media_uuid trashed retired read_only)
      }
      = ();
    %simple = map { ($_, 1) } grep { not exists $complex{$_} } (FIELDS);

    # parse it up
    my $data = pkg('XML')->simple(
        xml           => $xml,
        forcearray    => ['contrib', 'element', 'data', 'tag'],
        suppressempty => 1
    );

    # is there an existing object?
    my $media;

    # start with UUID lookup
    if (not $args{no_uuid} and $data->{media_uuid}) {
        ($media) = $pkg->find(media_uuid => $data->{media_uuid});

        # if not updating this is fatal
        Krang::DataSet::DeserializationFailed->throw(
            message => "A media object with the UUID '$data->{media_uuid}' already"
              . " exists and no_update is set.")
          if $media and $no_update;
    }

    # proceed to URL lookup if no dice
    unless ($media or $args{uuid_only}) {
        ($media) = pkg('Media')->find(url => $data->{url});

        # if not updating this is fatal
        Krang::DataSet::DeserializationFailed->throw(
            message => "A media object with the url '$data->{url}' already "
              . "exists and no_update is set.")
          if $media and $no_update;
    }

    if ($media) {

        # update simple fields
        $media->{$_} = $data->{$_} for keys %simple;

        # update the category, which can change now with UUID matching
        my $category_id = $set->map_id(
            class => pkg('Category'),
            id    => $data->{category_id}
        );
        $media->category_id($category_id);

        # handle the tags
        $media->tags($data->{tag} || []);

    } else {

        # create a new media object with category and simple fields
        my $category_id = $set->map_id(
            class => pkg('Category'),
            id    => $data->{category_id}
        );
        assert(pkg('Category')->find(category_id => $category_id, count => 1))
          if ASSERT;

        # this might have caused this media to get completed via a
        # circular link, end early if it did
        my ($dup) = pkg('Media')->find(url => $data->{url});
        return $dup if ($dup);

        $media = pkg('Media')->new(
            category_id => $category_id,
            tags        => $data->{tag} || [],
            (map { ($_, $data->{$_}) } keys %simple),
        );
    }

    # preserve UUID if available
    $media->{media_uuid} = $data->{media_uuid}
      if $data->{media_uuid} and not $args{no_uuid};

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

        $media->contribs(@altered_contribs);
    }

    # upload the file
    my $full_path = $set->map_file(
        class => pkg('Media'),
        id    => $data->{media_id}
    );
    croak("Unable to get file path from dataset!") unless $full_path;
    my $fh = IO::File->new($full_path)
      or croak("Unable to open $full_path: $!");
    $media->upload_file(
        filehandle => $fh,
        filename   => $data->{filename}
    );

    # get hash of media type names to ids
    my %media_types = reverse pkg('Pref')->get('media_type');

    # get ids for media types
    Krang::DataSet::DeserializationFailed->throw("Unknown media_type '$data->{media_type}'.")
      unless $media_types{$data->{media_type}};

    # add media type
    $media->media_type_id($media_types{$data->{media_type}});

    # save changes
    $media->save();
    $media->checkin();

    # register this with the dataset to prevent circular reference loops
    $set->register_id(
        class     => pkg('Media'),
        id        => $data->{media_id},
        import_id => $media->media_id,
    );

    # deserialize elements for update
    my $element = pkg('Element')->deserialize_xml(
        data      => $data->{element}[0],
        set       => $set,
        no_update => $no_update,
        object    => $media
    );

    # remove existing element tree
    $media->element->delete(skip_delete_hook => 1) if ($media->element);
    $media->{element}    = $element;
    $media->{element_id} = undef;

    # save again; this time element will be saved and element_id will be set
    $media->save;

    # make sure there's a file on the other end
    assert($media->file_path and -e $media->file_path, "Media saved successfully") if ASSERT;

    return $media;
}

=item C<< $data = Storable::freeze($media) >>

Serialize media.  Krang::Media implements STORABLE_freeze() to
ensure this works correctly.

=cut

sub STORABLE_freeze {
    my ($self, $cloning) = @_;
    return if $cloning;

    # make sure element tree is loaded
    $self->element();

    # avoid serializing category cache since they contain objects not
    # owned by the media
    my $category_cache = delete $self->{cat_cache};

    # serialize data in $self with Storable
    my $data;
    eval { $data = nfreeze({%$self}) };
    croak("Unable to freeze media: $@") if $@;

    # reconnect cache
    $self->{cat_cache} = $category_cache if defined $category_cache;

    return $data;
}

=item C<< $media = Storable::thaw($data) >>

Deserialize frozen media.  Krang::Media implements STORABLE_thaw() to ensure this works correctly.

=cut

sub STORABLE_thaw {
    my ($self, $cloning, $data) = @_;
    local $Krang::Element::THAWING_OBJECT = $self;

    # retrieve object
    eval { %$self = %{thaw($data)} };
    croak("Unable to thaw media: $@") if $@;

    # do we have an element? These were added in 3.04 so older versions before
    # that won't have one, so add it.
    unless($self->{element} ) {
        $self->{element} = pkg('Element')->new(
            class  => pkg('ElementClass::Media')->element_class_name,
            object => $self
        );
    }

    return $self;
}

=item C<< $media->retire() >>

=item C<< Krang::Media->retire(media_id => $media_id) >>

Retire the media, i.e. remove it from its publish/preview location
and don't show it on the Find Media screen.  Throws a
Krang::Media::NoEditAccess exception if user may not retire this
media. Croaks if the media is checked out by another user.

=cut

sub retire {
    my ($self, %args) = @_;
    unless (ref $self) {
        my $media_id = $args{media_id};
        ($self) = pkg('Media')->find(media_id => $media_id);
        croak("Unable to load media '$media_id'.") unless $self;
    }

    # Is user allowed to otherwise edit this object?
    Krang::Media::NoEditAccess->throw(
        message  => "Not allowed to edit media",
        media_id => $self->media_id
    ) unless ($self->may_edit);

    # make sure we are the one
    $self->checkout;

    # run the element class's retire_hook
    my $element = $self->element;
    $element->class->retire_hook(element => $element);

    # unpublish
    pkg('Publisher')->new->unpublish_media(media => $self);

    # retire the media
    my $dbh = dbh();
    $dbh->do(
        "UPDATE media
              SET    retired = 1
              WHERE  media_id = ?", undef,
        $self->{media_id}
    );

    # delete schedules for this media
    $dbh->do('DELETE FROM schedule WHERE object_type = ? and object_id = ?',
        undef, 'media', $self->{media_id});

    # living in retire
    $self->{retired} = 1;

    $self->checkin();

    add_history(
        object => $self,
        action => 'retire'
    );
}

=item C<< $media->unretire() >>

=item C<< Krang::Media->unretire(media_id => $media_id) >>

Unretire the media, i.e. show it again on the Find Media screen, but
don't republish it. Throws a Krang::Media::NoEditAccess exception if
user may not unretire this media. Throws a Krang::Media::DuplicateURL
exception if a media with the same URL has been created in Live.
Croaks if the media is checked out by another user.

=cut

sub unretire {
    my ($self, %args) = @_;
    unless (ref $self) {
        my $media_id = $args{media_id};
        ($self) = pkg('Media')->find(media_id => $media_id);
        croak("Unable to load media '$media_id'.") unless $self;
    }

    # Is user allowed to edit this object?
    Krang::Media::NoEditAccess->throw(
        message  => "Not allowed to edit media",
        media_id => $self->media_id
    ) unless ($self->may_edit);

    # make sure no other media occupies our initial place (URL)
    $self->duplicate_check();

    # make sure we are the one
    $self->checkout;

    # alive again
    $self->{retired} = 0;

    # unretire the media
    my $dbh = dbh();
    $dbh->do(
        'UPDATE media
              SET    retired = 0
              WHERE  media_id = ?', undef,
        $self->{media_id}
    );

    add_history(
        object => $self,
        action => 'unretire',
    );

    # check it back in
    $self->checkin();
}

=item C<< $media->trash() >>

=item C<< Krang::Media->trash(media_id => $media_id) >>

Move the media to the trashbin, i.e. remove it from its
publish/preview location and don't show it on the Find Media screen.
Throws a Krang::Media::NoEditAccess exception if user may not edit
this media. Croaks if the media is checked out by another
user.

=cut

sub trash {
    my ($self, %args) = @_;
    unless (ref $self) {
        my $media_id = $args{media_id};
        ($self) = pkg('Media')->find(media_id => $media_id);
        croak("Unable to load media '$media_id'.") unless $self;
    }

    # Is user allowed to otherwise edit this object?
    Krang::Media::NoEditAccess->throw(
        message  => "Not allowed to edit media",
        media_id => $self->media_id
    ) unless ($self->may_edit);

    # make sure we are the one
    $self->checkout;

    # run the element class's trash_hook
    my $element = $self->element;
    $element->class->trash_hook(element => $element);

    # unpublish
    pkg('Publisher')->new->unpublish_media(media => $self);

    # store in trash
    pkg('Trash')->store(object => $self);

    # update object
    $self->{trashed} = 1;

    # release it
    $self->checkin();

    # and log it
    add_history(object => $self, action => 'trash');
}

=item C<< $media->untrash() >>

=item C<< Krang::Media->untrash(media_id => $media_id) >>

Restore the media from the trashbin, i.e. show it again on the Find
Media screen or Retired Media screens (depending on the location from
where it was deleted).  Throws a Krang::Media::NoRestoreAccess
exception if user may not edit this media. Croaks if the media is
checked out by another user. This method is called by
Krang::Trash->restore().

=cut

sub untrash {
    my ($self, %args) = @_;
    unless (ref $self) {
        my $media_id = $args{media_id};
        ($self) = pkg('Media')->find(media_id => $media_id);
        croak("Unable to load media '$media_id'.") unless $self;
    }

    # Is user allowed to otherwise edit this object?
    Krang::Media::NoRestoreAccess->throw(
        message  => "Not allowed to restore media",
        media_id => $self->media_id
    ) unless $self->may_edit;

    # make sure no other media occupies our initial place (URL)
    $self->duplicate_check() unless $self->retired;

    # make sure we are the one
    $self->checkout;

    # unset trashed flag in media table
    my $dbh = dbh();
    $dbh->do(
        'UPDATE media
              SET trashed = ?
              WHERE media_id = ?', undef,
        0,                         $self->{media_id}
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

=item C<< $media->wont_publish() >>

Convenience method returning true if media has been retired or
trashed.

=cut

sub wont_publish { return $_[0]->retired || $_[0]->trashed }

=item C<< $media->clone(category_id => $category_id) >>

Copy $media to the category having the specified category_id.  Returns
an unsaved and checked_out copy with the media file already uploaded.

=cut

sub clone {
    my ($self, %args) = @_;

    croak("No Category ID specified where to copy the media to")
      unless $args{category_id};

    my $copy = bless({%$self} => ref($self));

    # clone the element tree
    $copy->{element} = $self->element->clone();
    $copy->{element}{element_id} = undef;    # this will be set on save()

    # redefine
    $copy->{media_id}          = undef;
    $copy->{media_uuid}        = pkg('UUID')->new;
    $copy->{category_id}       = $args{category_id};
    $copy->{version}           = 0;
    $copy->{creation_date}     = undef;
    $copy->{preview_version}   = 0;
    $copy->{published}         = 0;
    $copy->{published_version} = 0;
    $copy->{publish_date}      = undef;
    $copy->{retired}           = 0;
    $copy->{trashed}           = 0;
    $copy->{url_cache}         = undef;
    $copy->{cat_cache}         = undef;
    $copy->{checked_out}       = 1;
    $copy->{checked_out_by}    = $ENV{REMOTE_USER};

    # upload file
    my $filepath   = $self->file_path;
    my $filehandle = new FileHandle $filepath;

    croak("Cant get a filehandle on '$filepath' to copy Media " . $self->media_id)
      unless $filehandle;

    $copy->upload_file(filename => $self->filename, filehandle => $filehandle);

    # set URL
    $copy->{url} = $copy->url;

    return $copy;
}

=item C<< $media->is_text() >>

Returns true if this media object appears to be text (HTML, JS, CSS, etc);

=cut

sub is_text {
    my $self = shift;
    my $filename = $self->filename;
    my $mime_type = $self->mime_type;

    # we need a filename and a mime type
    return 0 unless $filename;
    return 0 unless $mime_type;

    if( $mime_type =~ /^text\// ) {
        return 1;
    } elsif( $mime_type eq 'application/javascript' ) {
        return 1;
    } elsif( $mime_type eq 'application/json' ) {
        return 1;
    } elsif( $filename =~ /\.ssi$/ ) {
        return 1;
    }
    return 0;
}

=item C<< $media->is_image() >>

Returns true if this media object appears to be an image.

=cut

sub is_image {
    my $self = shift;
    return $self->filename && $self->mime_type && $self->mime_type =~ /^image\//;
}

=item C<< Krang::Media->guess_media_type($filename) >>

Returns a C<media_type_id> based on a good guess from the filename.

=cut

my %EXTENSION_TYPES = (
    jpg   => 'Image',
    jpeg  => 'Image',
    png   => 'Image',
    gif   => 'Image',
    tiff  => 'Image',
    tif   => 'Image',
    bmp   => 'Image',
    text  => 'Text',
    txt   => 'Text',
    html  => 'HTML',
    htm   => 'HTML',
    pdf   => 'PDF',
    xls   => 'Excel',
    csv   => 'Excel',
    tsv   => 'Excel',
    ods   => 'Excel',
    sxc   => 'Excel',
    xlsx  => 'Excel',
    doc   => 'Word',
    sxw   => 'Word',
    odt   => 'Word',
    docx  => 'Word',
    mpe   => 'Video',
    mpg   => 'Video',
    mpeg  => 'Video',
    avi   => 'Video',
    divx  => 'Video',
    f4v   => 'Video',
    flv   => 'Video',
    ogm   => 'Video',
    wmv   => 'Video',
    mp3   => 'Audio',
    ogg   => 'Audio',
    flacc => 'Audio',
    wav   => 'Audio',
    fla   => 'Flash',
    swf   => 'Flash',
    js    => 'JavaScript',
    css   => 'Stylesheet',
    ssi   => 'Include',
    ppt   => 'Power Point',
    sxi   => 'Power Point',
    odp   => 'Power Point',
);

sub guess_media_type {
    my ($pkg, $filename) = @_;
    my %media_types = pkg('Pref')->get('media_type');

    # guess the media type based on the file's extension
    $filename =~ /\.(\w+)$/;
    my $type_id = $EXTENSION_TYPES{lc $1} || 'Text';
    foreach my $k (keys %media_types) {
        if( $type_id eq $media_types{$k} ) {
            $type_id = $k;
            last;
        }
    }

    return $type_id;
}

=item C<< Krang::Media->guess_mime_type($filename) >>

Returns a C<mime_type> based on a good guess from the filename.

=cut

sub guess_mime_type {
    my ($pkg, $filename) = @_;
    return LWP::MediaTypes::guess_media_type($filename);
}

=item C<< Krang::Media->clean_filename($filename) >>

Cleans up the filename just like Krang::Media does internally
before saving filename changes. This method let's perform those
same cleanups in case you need to work with the file prior
to creating a media object.

=cut

sub clean_filename {
    my ($pkg, $filename) = @_;
    return $filename unless $filename;
    $filename =~ s/[^\w\s\.\-]//g;     # clean invalid chars
    $filename =~ s/(^\s+|\s+$)+//g;    # trim leading and trailing whitespace
    $filename =~ s/[\s\_]+/_/g;        # use underscores btw words
    return $filename;
}

=back

=cut

1;
