package Krang::Media;
use strict;
use warnings;
use Krang::DB qw(dbh);
use Krang::Conf qw(KrangRoot);
use Krang::Session qw(%session);
use Krang::Contrib;
use Krang::Category;
use Carp qw(croak);
use Storable qw(freeze thaw);
use File::Spec::Functions qw(catdir catfile);
use File::Path;
use File::Copy;
use LWP::MediaTypes qw(guess_media_type);
use Imager;
use File::stat;
use Time::Piece;
use Time::Piece::MySQL;

# constants
use constant THUMBNAIL_SIZE => 35;
use constant FIELDS => qw(media_id title category_id media_type_id filename creation_date caption copyright notes version url alt_tag published_version checked_out_by);
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

    # assign 2 contributors to media object, specifying thier contributor type
    $media->contribs({contrib_id => 1, contrib_type_id => 3},
                     {contrib_id => 44, contrib_type_id => 4});

    # get contrib objects attached to this media
    @contribs = $media->contribs();

    # change assignment to include just the first contributor
    $media->contribs($contribs[0]);

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
filesystem, as well as media object metadata in the database. Contributors (Krang::Contrib objects) can also be attached to stories.

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
    get_set       => [ qw( title alt_tag version checked_out_by published_version caption copyright notes media_type_id category_id filename url ) ],
    get => [ qw( media_id creation_date) ];

sub init {
    my $self = shift;
    my %args = @_;

    my $filename = $args{'filename'};

    my $filehandle = delete $args{'filehandle'};
    
    $self->{contrib_ids} = [];

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

=item $media->checked_out()

Returns 1 if checked out by a user (checked_out_by is set).  (Unessicary convenience method)

=cut

sub checked_out {
    my $self = shift;
    return 1 if $self->checked_out_by();
}

=item $media->checked_out_by()

Returns id of user who has object checked out, if checked out.

=item $media->published()

Returns 1 if published version > 1.  (Unessicary convenience method)

=cut

sub published {
    my $self = shift;
    return 1 if $self->published_version();
}

=item $media->published_version()

Returns version number of published version of this object (if has been published).

=item $version = $media->version()

Returns the current version number.

=item $creation_date = $media->creation_date()

Returns the initial creation date of the media object.  Not settable here.

=item $url = $media->url()

Returns the path that the media object will preview/publish to. Not settable here.

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
            ($contrib) = Krang::Contrib->find(contrib_id => $id->{contrib_id});
            croak("No contributor found with contrib_id ". $id->{contrib_id})
              unless $contrib;
            $contrib->selected_contrib_type($id->{contrib_type_id});
            push @contribs, $contrib;
        }
        return @contribs; 
    }

    # store list of contributors, passed as either objects or hashes
    foreach my $rec (@_) {
        if (ref($rec) and ref($rec) eq 'Krang::Contrib') {
            croak("invalid data passed to contrib: contributor objects must have contrib_id and selected_contrib_type set.")
              unless $rec->contrib_id and $rec->selected_contrib_type;

            push(@contribs, { contrib_id     => $rec->contrib_id,
                              contrib_type_id=> $rec->selected_contrib_type });

        } elsif (ref($rec) and ref($rec) eq 'HASH') {
            croak("invalid data passed to contribs: hashes must contain contrib_id and contrib_type_id.")
              unless $rec->{contrib_id} and $rec->{contrib_type_id};
            
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
    my $media_id = $self->{media_id};
 
    return catfile($root,'data','media',$self->_media_id_path(),$self->{version},$self->{filename});
}

sub _media_id_path {
    my $self = shift;
    my $media_id = $self->{media_id};
    my @media_id_path;
    
    if ($media_id >= 1000) { 
        push(@media_id_path,substr($media_id, 0, 3)); 
    } else {
        push(@media_id_path,$media_id);
    }
    push(@media_id_path,$media_id);

    return catdir(@media_id_path);
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
    my $media_id;

    # calculate url
    my $url =
      (Krang::Category->find(category_id => $self->{category_id}))[0]->url();
    $self->{url} = _build_url($url, $self->{filename});

    # check for duplicate url
    my $dup_media_id = $self->duplicate_check();
    croak(__PACKAGE__ . "->save(): 'url' field is a duplicate of media " .
          "'$dup_media_id'") if $dup_media_id;

    # if this is not a new media object
    if (defined $self->{media_id}) {
        $media_id = $self->{media_id}; 

        # get rid of media_id
        my @save_fields = FIELDS;
        @save_fields = splice(@save_fields,1); 	

        # update version
        $self->{version} = ($self->{version} + 1);
        
        my $sql = 'UPDATE media SET '.join(', ',map { "$_ = ?" } @save_fields).' WHERE media_id = ?';
	$dbh->do($sql, undef, map { $self->{$_} } @save_fields,$media_id);

	# this file exists, new media was uploaded. copy to new position	
	if (-f catfile($root,'tmp','media',$session_id,'tempfile')) {
	   my $old_path = catfile($root,'tmp','media',$session_id,'tempfile');
           my $new_path = catdir($root,'data','media',$self->_media_id_path,$self->{version});
	   mkpath($new_path);     
	   $new_path = catfile($new_path,$self->{filename});
	   move($old_path,$new_path) || croak("Cannot move to $new_path");	
	} else {
	    # symbolically link to version dir, since it isnt changing 
	    my $old_path = catdir($root,'data','media',$self->_media_id_path,($self->{version} - 1));
	    my $new_path = catdir($root,'data','media',$self->_media_id_path,$self->{version});
	    link $old_path, $new_path || croak("Unable to create link $old_path to $new_path");	
	}
    } else {
	if (not -f catfile($root,'tmp','media',$session_id,'tempfile')) {
            croak('You must upload a file using upload_file() before saving media object!')
	} 
	$self->{version} = 1;
        my $time = localtime();
        $self->{creation_date} = $time->mysql_date();   
     
	$dbh->do('INSERT INTO media ('.join(',', FIELDS).') VALUES (?'.",?" x (scalar FIELDS - 1).")", undef, map { $self->{$_} } FIELDS);

        # make date readable
        $self->{creation_date} = Time::Piece->from_mysql_date( $self->{creation_date} );
	
        $self->{media_id} = $dbh->{mysql_insertid};

        $media_id = $self->{media_id};

	my $old_path = catfile($root,'tmp','media',$session_id,'tempfile');
	my $new_path = catdir($root,'data','media',$self->_media_id_path,$self->{version}); 
	mkpath($new_path);
	$new_path = catfile($new_path,$self->{filename});		
	move($old_path,$new_path) || croak("Cannot create $new_path");
    }

    # remove any existing media_contrib relatinships and save any new relationships
    $dbh->do('delete from media_contrib where media_id = ?', undef, $media_id);
    my $count; 
    foreach my $contrib (@{$self->{contrib_ids}}) {
        $dbh->do('insert into media_contrib (media_id, contrib_id, contrib_type_id, ord) values (?,?,?,?)', undef, $media_id, $contrib->{contrib_id}, $contrib->{contrib_type_id}, $count++);
    }
}

=item @media = Krang::Media->find($param)

Find and return media object(s) with parameters specified. Supported paramter keys:

=over 4

=item *

media_id (can optionally take a list of ids)

=item *

title

=item *

title_like - case insensitive match on title. Must include '%' on either end for substring match.

=item *

category_id

=item *

media_type_id

=item * 

contrib_id 

=item *

filename

=item *

filename_like - case insensitive substring match on filename. Must include '%' on either end for substring match.

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

=item *

creation_date - in 'YYYYMMDD' format.  If array of two dates passed in, will use to find media created between those dates.

=back

=cut

sub find {
    my $self = shift;
    my %args = @_;
    my $dbh = dbh;
    my @where;
    my @media_object;

    # set defaults if need be
    my $order_by =  $args{'order_by'} ? $args{'order_by'} : 'media_id';
    my $order_desc = $args{'order_desc'} ? 'desc' : 'asc';
    my $limit = $args{'limit'} ? $args{'limit'} : undef;
    my $offset = $args{'offset'} ? $args{'offset'} : 0;

    # set simple keys
    foreach my $key (keys %args) {
	if ( ($key eq 'title') || ($key eq 'category_id') || ($key eq 'media_type_id') || ($key eq 'filename') || ($key eq 'creation_date') || ($key eq 'contrib_id' ) ) {
            push @where, $key;
	} 
    }
  
    my $where_string = join ' and ', (map { "$_ = ?" } @where);
    
    # add media_id(s) if needed
    if ($args{media_id}) {
        if (ref $args{media_id} eq 'ARRAY') {
            $where_string ? ($where_string .= " and media_id = ".join( ' or media_id = ', @{$args{media_id}} )) : ($where_string = "media_id = ".join( ' or media_id = ', @{$args{media_id}} ));
        } else {
            $where_string ? ($where_string .= " and media_id = ".$args{media_id}) : ($where_string = "media_id = ".$args{media_id});
        }        
    }

    # add title_like to where_string if present
    if ($args{'title_like'}) {
        $where_string ? ($where_string .= " and title like ?") : ($where_string = " title like ?");
        push @where, 'title_like';
    }

    # add filename_like to where_string if present
    if ($args{'filename_like'}) {
        $where_string ? ($where_string .= " and filename like ?") : ($where_string = " filename like ?");
        push @where, 'filename_like';
    }

    if ($args{'creation_date'}) {
        if (ref($args{'creation_date'}) eq 'ARRAY') {
            $where_string ? ($where_string .= 'AND creation_date BETWEEN '.$args{'creation_date'}[0].' AND '.$args{'creation_date'}[1]) : ($where_string = 'creation_date BETWEEN '.$args{'creation_date'}[0].' AND '.$args{'creation_date'}[1]);
        } else {
            $where_string ? ($where_string .= 'AND creation_date = '.$args{'creation_date'}) : ($where_string = 'creation_date = '.$args{'creation_date'});
        }
    }

    my $select_string;
    if ($args{'count'}) {
        $select_string = 'count(*)';
    } elsif ($args{'only_ids'}) {
        $select_string = 'media_id';
    } else {
        $select_string = join(',', FIELDS);
    }
    
    my $sql = "select $select_string from media";
    $sql .= ", media_contrib" if $args{'contrib_id'};
    $sql .= " where ".$where_string if $where_string;
    $sql .= " order by $order_by $order_desc";
 
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
            # add contrib ids to object
            my $sth2 = $dbh->prepare('select contrib_id, contrib_type_id from media_contrib where media_id = ? order by ord');
            $sth2->execute($row->{media_id});
            $obj->{contrib_ids} = [];
            while (my ($contrib_id, $contrib_type_id) = $sth2->fetchrow_array()) {
                push @{$obj->{contrib_ids}}, {contrib_id => $contrib_id, contrib_type_id => $contrib_type_id};
            }
        }
	push (@media_object,$obj);
    }
    $sth->finish();	
    return @media_object; 
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
            my $path = catfile($root,'data','media',$self->_media_id_path,$self->{version},"t__".$self->{filename});
            if (not -f $path) {
                my $img = Imager->new();
                $img->open(file=>$self->file_path()) || croak $img->errstr();
                my $thumb = $img->scale(xpixels=>THUMBNAIL_SIZE,ypixels=>THUMBNAIL_SIZE,type=>'min');
                $thumb->write(file=>$path) || croak $thumb->errstr;
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

=item $media = $media->update_url( $url );

Method called on object to propagate changes to parent category's 'url'.

=cut

sub update_url {
    my ($self, $url) = @_;
    $self->{url} = _build_url($url, $self->{filename});
    return $self;
}

sub _build_url { (my $url = join('/', @_)) =~ s|/+|/|g; return $url;}

=item $media_id = $media->duplicate_check()

This method checks whether the url of a media object is unique.

=cut

sub duplicate_check {
    my $self = shift;
    my $id = $self->{media_id} || 0;
    my $media_id = 0;

    my $query = <<SQL;
SELECT media_id
FROM media
WHERE url = '$self->{url}'
SQL
    $query .= "AND media_id != $id" if $id;
    my $dbh = dbh();
    my $sth = $dbh->prepare($query);
    $sth->execute();
    $sth->bind_col(1, \$media_id);
    $sth->fetch();
    $sth->finish();

    return $media_id;
}

=item $media->delete() || Krang::Media->delete($media_id)

Permenantly delete media object or media object with given id.

Attempts to checkout the media object, will croak if checked out by another user.

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
    $dbh->do('delete from media_contrib where media_id = ?', undef, $media_id);

    my $file_dir = catdir($root,'data','media',$self->_media_id_path);
    rmtree($file_dir) || croak("Cannot delete $file_dir and contents.");
}

=back

=cut

1;
