package Krang::Media;
use strict;
use warnings;
use Krang::DB qw(dbh);
use Krang::Conf qw(KrangRoot);
use Krang::Session qw(%session);
use Carp qw(croak);
use Storable qw(freeze thaw);
use File::Spec::Functions qw(catdir catfile);
use File::Path;
use File::Copy;
use LWP::MediaTypes qw(guess_media_type);
use Image::Thumbnail;
use File::stat;

# constants
use constant THUMBNAIL_SIZE => 35;
use constant FIELDS => qw(media_id title category_id media_type_id filename creation_date caption copyright notes version uri alt_tag published_version checked_out_by);
use constant IMAGE_TYPES => qw(image/png image/gif image/jpeg image/tiff image/x-bmp);

=head1 NAME

    Krang::Media - Media and media metadata storage and access methods

=head1 SYNOPSIS

    # create new media object
    my $media = Krang::Media->new( title => 'test media', 
                                   caption => 'test caption',
                                   copyright => 'AP 1999', 
                                   media_type_id => $media_type_id, 
                                   category_id => $category_id );

    # add actual media file to media object
    $media->upload_file( filehandle => $filehandle, filename => 'media.jpg' );

    # get MIME type of uploaded file
    $mime_type = $media->mime_type();

    # get path to thumbnail - if image (thumbnail will be created if
    # does not exist)
    $thumbnail_path = $media->thumbnail_path();

    # save the object to the database
    $media->save();

    # mark as checked out by you (your user_id)
    $media->checkout();

    # Now copy current version to versioning table to prepare for edit
    $media->prepare_for_edit();

    # update caption for this media object
    $media->caption('new caption');

    # again, save the object to the database (upping version)
    $media->save(); 

    # get current version number, in this example 2
    $version = $media->version();

    # revert to version 1 
    $media->revert(1);

    # save this in order to keep changes from revert
    $media->save();

    # get id for this object
    my $media_id = $media->media_id();

    # return object by id
    $media_obj = Krang::Media->find( media_id => $media_id );

=head1 DESCRIPTION

This class handles the storage and retrieval of media objects on the
filesystem, as well as media object metadata in the database.

=head2 Media Versioning

Versioning in this system functions perhaps in a non-traditional
way. A quick walk-thru of a media edit and revert may help
understanding:

First, the media object is marked as 'checked out' by the current
user.  After this call, only someone logged in with the same user_id
can edit this media object:

  $media->checkout();

Now, call prepare_for_edit(). This method places a copy of the current version 
of the media object into the 'media_version' table as version 1.

  $media->prepare_for_edit();

Now that the old version of the media object is safe, let's make a
change to the title of this media object:

  $media->title('new title');

Finally, we save the media object:

  $media->save();

After save(), the in-memory object $media will be saved into the
'media' table as version = 2.  So now there are 2 versions,
version 1 in the 'media_version' table and version 2 in the 'media'
table.

Notice that the prepare_for_edit() method works with save to store
versions of media objects.  If you would have called save() B<without>
calling prepare_for_edit() first, you would have effectively lost all
information from version one.

To begin the explaination of 'revert', the most important thing to
understand is that revert() simply just takes a copy of an older
version and places it into the current in-memory object.  So, if we
plan on saving the reverted object as current, we should probably call

  $media->prepare_for_edit()

first, again copying the current object into the versioning table.
Then we call:

  $media->revert(1)

So now what do we have?  We now have version 1 and 2 in the versioning table.  
We also have version 2 still in the 'media' table from the last save().  
In memory ($media), we now have a copy of version 1.  So if we again 

  $media->save()

we now have a 3rd version - version 1 and 2 in the versioning table,
and version 3 (which is actually just a copy of version 2, since we
didn't change anything) in the 'media' table. Thus, revert() does not
give you access to the actual original version, but instead gives you
a copy of it.  

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

Fields for storing arbitrary metadata

=item media_type_id

ID for media_type, the media_type this media object is associated with.

=item category_id

ID for category, the category this media object is associated with.

=item checked_out_by

User id of person who has media object checked out, undef if not checked out.

=item published_version

Last published version

=item filename

The filename of the uploaded media.

=item filehandle

Filehandle for uploaded media.

=back

=cut

use Krang::MethodMaker
    new_with_init => 'new',
    new_hash_init => 'hash_init',
    get_set       => [ qw( media_id title alt_tag version checked_out_by published_version caption copyright notes media_type_id category_id filename uri ) ];

sub init {
    my $self = shift;
    my %args = @_;

    my $filename = $args{'filename'};

    my $filehandle = delete $args{'filehandle'};

    # finish the object
    $self->hash_init(%args);

    $self->upload_file(filename => $filename, filehandle => $filehandle) if $filehandle;

    return $self;
}

=item $id = $media->media_id()

Returns the unique id assigned the media object.  Will not be populated until $media->save() is called the first time.

=item $media->title()

=item $media->category_id()

=item $media->filename()

=item $media->caption()

=item $media->copyright()

=item $media->alt_tag()

=item $media->notes()

=item $media->media_type_id()

Gets/sets the value.

=item $version = $media->version()

Returns the current version number.

=item $creation_date = $media->creation_date()

Returns the initial creation date of the media object.  Not settable here.

=item $uri = $media->uri()

Returns the path that the media object will preview/publish to. Not settable here.

=item $media->upload_file({filehandle => $filehandle, filename => $filename})

Stores media file to temporary location on filesystem. Sets $media->filename() also. 

=cut

sub upload_file {
    my $self = shift;
    my %args = @_;
    my $root = KrangRoot;
    my $filename = $args{'filename'} || croak('You must pass in a filename in order to upload a file');
    my $filehandle = $args{'filehandle'} || croak('You must pass in a filehandle in order to upload a file');
    croak('You cannot use a / in a filename!') if $filename =~ /\//;

    my $session_id = $session{_session_id}; 
 
    my $path = catdir($root,'tmp','media',$session_id);
    mkpath($path);
    my $filepath = catfile($path, "tempfile");
   
    open (FILE, ">$filepath") || croak("Unable to open $path for writing media!"); 
   
    my $buffer;
    while (read($filehandle, $buffer, 10240)) { print FILE $buffer }
    close $filehandle;
    close FILE;

    $self->{filename} = $filename;
    return $self; 
}

=item $mime_type = $media->mime_type()

Returns MIME type of uploaded file, returns nothing if unknown type or no file uploaded.

=cut

sub mime_type {
    my $self = shift;
    return guess_media_type($self->file_path);
}

=item $file_path = $media->file_path() 

Return filesystem path of uploaded media file.

=cut

sub file_path {
    my $self = shift;
    my $root = KrangRoot; 
    return catfile($root,'data','media',$self->{media_id},$self->{version},$self->{filename});
}

=item $file_size = $media->file_size()

Return filesize in bytes.

=cut

sub file_size {
    my $self = shift;
    my $st = stat($self->file_path());
    return $st->size;
}
 
=item $media->save()

Commits media object to the database. Will set media_id to unique id if not already defined (first save).

=cut

sub save {
    my $self = shift;
    my $dbh = dbh;
    my $root = KrangRoot;
    my $session_id = $session{_session_id} || croak("No session id found"); 

    # if this is not a new media object
    if (defined $self->{media_id}) {
	$self->{version} = ($self->{version} + 1);
	$dbh->do('UPDATE media SET category_id = ?, title = ?, filename = ?, caption = ?, copyright = ?, notes = ?, version = ?, media_type_id = ? WHERE media_id = ?', undef, $self->{category_id}, $self->{title}, $self->{filename}, $self->{caption}, $self->{copyright}, $self->{notes}, $self->{version}, $self->{media_type_id}, $self->{media_id});

	# this file exists, new media was uploaded. copy to new position	
	if (-f catfile($root,'tmp','media',$session_id,'tempfile')) {
	   my $old_path = catfile($root,'tmp','media',$session_id,'tempfile');
           my $new_path = catdir($root,'data','media',$self->{media_id},$self->{version});
	   mkpath($new_path);     
	   $new_path = catfile($new_path,$self->{filename});
	   move($old_path,$new_path) || croak("Cannot move to $new_path");	
	} else {
	    # symbolically link to version dir, since it isnt changing 
	    my $old_path = catdir($root,'data','media',$self->{media_id},($self->{version} - 1));
	    my $new_path = catdir($root,'data','media',$self->{media_id},$self->{version});
	    link $old_path, $new_path || croak("Unable to create link $old_path to $new_path");	
	}
    } else {
	if (not -f catfile($root,'tmp','media',$session_id,'tempfile')) {
            croak('You must upload a file using upload_file() before saving media object!')
	} 
	$self->{version} = 1;
	$dbh->do('INSERT INTO media (category_id, title, filename, caption, copyright, notes, version, media_type_id, creation_date) VALUES (?,?,?,?,?,?,?,?,now())', undef, $self->{category_id}, $self->{title}, $self->{filename}, $self->{caption}, $self->{copyright}, $self->{notes}, $self->{version}, $self->{media_type_id});
	$self->{media_id} = $dbh->{mysql_insertid};

	my $old_path = catfile($root,'tmp','media',$session_id,'tempfile');
	my $new_path = catdir($root,'data','media',$self->{media_id},$self->{version}); 
	mkpath($new_path);
	$new_path = catfile($new_path,$self->{filename});		
	move($old_path,$new_path) || croak("Cannot create $new_path");
    }
}

=item @media = Krang::Media->find($param)

Find and return media object(s) with parameters specified. Supported paramter keys:

=over 4

=item *

media_id

=item *

title

=item *

category_id

=item *

media_type_id

=item *

filename

=item *

creation_date

=item * 

order_by - field to order search by, defaults to media_id

=item *

order_desc - results will be in ascending order unless this is set to 1 (making them descending).

=item *

limit - limits result to number passed in here, else no limit.

=item *

offset - offset results by this number, else no offset.

=item *

only_ids - return only media_ids, not objects if this is set true.

=item *

count - return only a count if this is set to true. Cannot be used with only_ids.

=back

=cut

sub find {
    my $self = shift;
    my %args = @_;
    my $dbh = dbh;
    my @where;
    my @media_object;

    my $order_by =  $args{'order_by'} ? $args{'order_by'} : 'media_id';
    my $order_desc = $args{'order_desc'} ? 'desc' : 'asc';
    my $limit = $args{'limit'} ? $args{'limit'} : undef;
    my $offset = $args{'offset'} ? $args{'offset'} : 0;

    foreach my $key (keys %args) {
	if ( ($key eq 'media_id') || ($key eq 'title') || ($key eq 'category_id') || ($key eq 'media_type_id') || ($key eq 'filename') || ($key eq 'creation_date') ) {
            push @where, $key;
	} 
    }
  
    my $where_string = join ' and ', (map { "$_ = ?" } @where);
    my $select_string;
    if ($args{'count'}) {
        $select_string = 'count(*)';
    } elsif ($args{'only_ids'}) {
        $select_string = 'media_id';
    } else {
        $select_string = join(',', FIELDS);
    }
    
    my $sql = "select $select_string from media where ".$where_string." order by $order_by $order_desc";
   
    # add limit and/or offset if defined 
    if ($limit) {
       $sql .= " limit $offset, $limit";
    } elsif ($offset) {
        $sql .= " limit $offset, -1";
    }

    my $sth = $dbh->prepare($sql);
    $sth->execute(map { $args{$_} } @where) || croak("Unable to execute statement $sql");
    while (my $row = $sth->fetchrow_hashref()) {
        my $obj;
        if ($args{'count'}) {
            return $row->{count};
        } elsif ($args{'only_ids'}) {
            $obj = $row->{media_id};
        } else {    
            $obj = bless {}, $self;
	    foreach my $field (FIELDS) {
	        if ($row->{$field}) {
		    $obj->{$field} = $row->{$field};
	        } 
	    }
        }
	push (@media_object,$obj);
    }
    $sth->finish();	
    return wantarray ? @media_object: \@media_object; 
}

=item $media->revert($version)

Changes media object to copy of the version specified. Does not actually edit the original version, but overwrites in-memory object with version specified.  Thus will not permantly revert until save() after revert().

=cut

sub revert {
    my $self = shift;
    my $dbh = dbh;
    my $version_number = shift;
    my $root = KrangRoot;
    my $session_id = $session{_session_id};

    my $version = $self->{version}; # make sure to preserve this
    my $checked_out_by = $self->{checked_out_by};
     
    croak('Must specify media version number to revert to') if (not $version_number);

    my $sql = 'SELECT data from media_version where media_id = ? AND version = ?';
    my $sth = $dbh->prepare($sql);
    $sth->execute($self->{media_id}, $version_number);

    my $data = $sth->fetchrow_array(); 
    $sth->finish();

    eval {
        %$self = %{thaw($data)};
    };
    craok ("Unable to deserialize object: $@") if $@;

    my $old_filepath = $self->file_path();
    $self->{version} = $version;
    $self->{checked_out_by} = $checked_out_by;

    # copy old media file into tmp storage
    my $path = catdir($root,'tmp','media',$session_id);
    mkpath($path);
    my $filepath = catfile($path, "tempfile");
    copy($old_filepath,$filepath); 
    return $self; 
}

=item $thumbnail_path = $media->thumbnail_path();

Returns the path to the thumbnail (if media is an image).  Valid image types are stored in IMAGE_TYPES constant. Will create thumbnail if first time called.

=cut

sub thumbnail_path {
    my $self = shift;
    my $root = KrangRoot;

    if ($self->filename()) {
        my $mime_type = $self->mime_type();
        my $is_image;

        foreach my $image_type (IMAGE_TYPES) {
            if ($image_type eq $mime_type) {
                $is_image = 1;
                last;
            }
        }
        if ($is_image) {    
            my $path = catfile($root,'data','media',$self->{media_id},$self->{version},"t__".$self->{filename});
            if (not -f $path) {
	        new Image::Thumbnail(
                       module     => 'ImageMagick',
                       size       => THUMBNAIL_SIZE,
                       create     => 1,
                       inputpath  => $self->file_path(),
                       outputpath => $path,
                );
            } 
            return $self->{thumbnail_path} = $path;
        }
    }
}

=item $media->checkout() || Krang::Media->checkout($media_id)

Marks media object as checked out by user_id.

=cut

sub checkout {
    my $self = shift;
    my $media_id = shift;
    my $dbh = dbh;
    my $user_id = $session{user_id};
    
    $media_id = $self->{media_id} if (not $media_id);
    croak("No media_id specified for checkout!") if not $media_id;

    $dbh->do('LOCK tables media WRITE');

    eval {
        my $sth= $dbh->prepare('SELECT checked_out_by FROM media WHERE media_id = ?');
        $sth->execute($media_id);

        my $checkout_id = $sth->fetchrow_array();
        croak("Media asset $media_id already checked out by id $checkout_id!") if ($checkout_id && ($checkout_id ne $user_id));

        $sth->finish();
 
        $dbh->do('update media set checked_out_by = ? where media_id = ?', undef, $user_id, $media_id);
    };

    if ($@) {
        $dbh->do('UNLOCK tables');
        croak("Error in checkout: $@");
    }
    
    $dbh->do('UNLOCK tables');

    $self->{checked_out_by}= $user_id;
}

=item $media->checkin() || Krang::Media->checkin($media_id)

Marks media object as checked in.

=cut

sub checkin {
    my $self = shift;
    my $media_id = shift;
    my $dbh = dbh;
    my $user_id = $session{user_id};
    
    $media_id = $self->{media_id} if (not $media_id);
    croak("No media_id specified for checkin!") if not $media_id;

    $dbh->do('UPDATE media SET checked_out_by = NULL WHERE media_id = ?', undef, $media_id);
    
    $self->{checked_out_by}= $user_id;
}

=item $media->prepare_for_edit() 

Copy current version of media from media table into versioning table.  Will only work for objects that have been save()ed (not new objects).

=cut

sub prepare_for_edit {
    my $self = shift;
    my $dbh = dbh;

    # ASSERT that this is checked out by current user (not someone else)

    my $media_id;
    if ($self->media_id) {
        $media_id = $self->media_id;
    } else {
        croak("No media_id specified for prepare_for_edit!");
    }

    my $serialized; 
    eval {
        $serialized = freeze($self);
    };
    craok ("Unable to serialize object: $@") if $@;

    $dbh->do('INSERT into media_version (media_id, version, data) values (?,?,?)', undef, $media_id, $self->{version}, $serialized);

    return $self;
}

=item $media->delete() || Krang::Media->delete($media_id)

Permenantly delete media object or media object with given id.

=cut

sub delete {
    my $self = shift;
    my $media_id = shift;
    my $dbh = dbh;
    my $root = KrangRoot;

    $media_id = $self->{media_id} if (not $media_id);
  
    $self->checkout($media_id);
     
    croak("No media_id specified for delete!") if not $media_id;

    $dbh->do('DELETE from media where media_id = ?', undef, $media_id); 
    $dbh->do('DELETE from media_version where media_id = ?', undef, $media_id); 

    my $file_dir = catdir($root,'data','media',$media_id);
    rmtree($file_dir) || croak("Cannot delete $file_dir and contents.");
}

=back

=cut

1;
