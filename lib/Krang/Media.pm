package Krang::Media;
use strict;
use warnings;
use Krang::DB qw(dbh);
use Krang::Conf qw(KrangRoot);
use Krang::Log qw(debug assert ASSERT);
use Krang::Session qw(%session);
use Krang::Contrib;
use Krang::Category;
use Krang::History qw( add_history );
use Carp qw(croak);
use Storable qw(freeze thaw);
use File::Spec::Functions qw(catdir catfile splitpath);
use File::Path;
use File::Copy;
use LWP::MediaTypes qw(guess_media_type);
use Imager;
use File::stat;
use Time::Piece;
use Time::Piece::MySQL;
use File::Temp qw/ tempdir /;

# constants
use constant THUMBNAIL_SIZE => 35;
use constant FIELDS => qw(media_id title category_id media_type_id filename creation_date caption copyright notes url version alt_tag published_version published_date checked_out_by);
use constant IMAGE_TYPES => qw(image/png image/gif image/jpeg image/tiff image/x-bmp);

# setup exceptions
use Exception::Class 
  'Krang::Media::DuplicateURL' => { fields => [ 'media_id' ] };

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
    ($media_obj) = Krang::Media->find( media_id => $media_id );

=head1 DESCRIPTION

This class handles the storage and retrieval of media objects on the
filesystem, as well as media object metadata in the database. Contributors (Krang::Contrib objects) can also be attached to stories.

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
understand is that revert() simply just takes a copy of an older
version and places it into the current in-memory object.

To revert to the contents of version 1, we call the revert() method:

  $media->revert(1)

So now what do we have?  We now have version 1 and 2 in the versioning
table.  We also have version 2 still in the 'media' table from the
last save().  In memory ($media), we now have a copy of version 1 but
with version = 2.

So if we again

  $media->save()

now version = 3 and this is saved in both media and media_version.
Thus, revert() does not give you access to the actual original
version, but instead gives you a copy of it which will create a new
version when saved.

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

=item creation_date

Date the media object was created.  Defaults to current time unless set.

=back

=cut

use Krang::MethodMaker
    new_with_init => 'new',
    new_hash_init => 'hash_init',
    get_set       => [ qw( title alt_tag version checked_out_by published_version caption copyright notes media_type_id category_id filename ) ],
    get => [ qw( media_id creation_date published_date) ];

sub init {
    my $self = shift;
    my %args = @_;

    my $filename = $args{'filename'};

    my $filehandle = delete $args{'filehandle'};
    
    $self->{contrib_ids} = [];
    $self->{version} = 0;  # versions start at 0
    $self->{checked_out_by} = $session{user_id};   
    $self->{creation_date} = localtime unless defined $self->{creation_date};
    
    # finish the object
    $self->hash_init(%args);

    $self->upload_file(filename => $filename, filehandle => $filehandle) if $filehandle;

    return $self;
}

=item $id = $media->media_id()

Returns the unique id assigned the media object.  Will not be populated until $media->save() is called the first time.

=item $media->title()

=item $media->category_id()

=item $media->category()

Returns to category object matching category_id.

=cut

sub category {
    return (Krang::Category->find(category_id => shift->{category_id}))[0];
}

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

Returns 1 if published version > 1.  (Unnecessary convenience method)

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

    my $path = tempdir( DIR => catdir(KrangRoot, 'tmp'));
    my $filepath = catfile($path, $filename);
    open (FILE, ">$filepath") || croak("Unable to open $path for writing media!"); 
   
    my $buffer;
    while (read($filehandle, $buffer, 10240)) { print FILE $buffer }
    close $filehandle;
    close FILE;

    $self->{tempfile} = $filepath;
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

=item $relative_path = $media->file_path(relative => 1) 

Return filesystem path of uploaded media file.  If the relative option
is set to 1 then the path returned is relative to KrangRoot.  Returns
undef before upload_file() on new objects.

=cut

sub file_path {
    my $self = shift;
    my %args = @_;
    my $root = KrangRoot;
    my $media_id = $self->{media_id};
    my $filename = $self->{filename};
    my $path;

    # if we have a temp file, return it
    if ($self->{tempfile}) {
        $path = $self->{tempfile};
    } elsif ($self->{media_id}) {
        # return path based on media_id if object has been committed to db
        my $instance = Krang::Conf->instance;

        $path = catfile($root,'data','media', $instance, $self->_media_id_path(),$self->{version},$self->{filename});
    }

    # no file_path found
    return unless $path;

    # make path relative if requested
    if ($args{relative}) {
        my $root = KrangRoot;
        $path =~ s/^$root\/?//;
    }

    return $path;
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
    if ($self->file_path()) {
        my $st = stat($self->file_path());
        return $st->size;
    } else {
        return 0;
    }
}

=item $media->save()

Commits media object to the database. Will set media_id to unique id
if not already defined (first save).

If this media object has the same URL as an existing object then
save() will throw a Krang::Media::DuplicateURL exception with a
media_id field indicating the conflicting object.

=cut

sub save {
    my $self = shift;
    my $dbh = dbh;
    my $root = KrangRoot;
    my $media_id;

    $self->{url} = $self->url();

    # check for duplicate url and throw an exception if one found
    my $dup_media_id = $self->duplicate_check();
    Krang::Media::DuplicateURL->throw(message => "duplicate URL",
                                      media_id => $dup_media_id)
        if $dup_media_id;

    # if this is not a new media object
    if (defined $self->{media_id}) {
        $media_id = $self->{media_id}; 

        # get rid of media_id
        my @save_fields = grep {($_ ne 'media_id') && ($_ ne 'creation_date')} FIELDS;

        # update version
        $self->{version} = $self->{version} + 1;
        
        my $sql = 'UPDATE media SET '.join(', ',map { "$_ = ?" } @save_fields).' WHERE media_id = ?';
        $dbh->do($sql, undef, (map { $self->{$_} } @save_fields),$media_id);

	# this file exists, new media was uploaded. copy to new position
	if ($self->{tempfile}) {
	   my $old_path = delete $self->{tempfile};
           my $new_path = $self->file_path;
	   mkpath((splitpath($new_path))[1]);     
	   move($old_path,$new_path) || croak("Cannot move to $new_path");	
	} else {
	    # symbolically link to version dir, since it isnt changing 
            $self->{version}--;
	    my $old_path = $self->file_path;
            $self->{version}++;
	    my $new_path = $self->file_path;
            mkpath((splitpath($new_path))[1]);     
	    link $old_path, $new_path or
              croak("Unable to create link $old_path to $new_path");	
	}
    } else {
        croak('You must upload a file using upload_file() before saving media object!')
          unless $self->{tempfile};

	$self->{version} = 1;
        my $time = localtime();
        $self->{creation_date} = $time->mysql_date();   
     
	$dbh->do('INSERT INTO media ('.join(',', FIELDS).') VALUES (?'.",?" x (scalar FIELDS - 1).")", undef, map { $self->{$_} } FIELDS);

        # make date readable
        $self->{creation_date} = Time::Piece->from_mysql_date( $self->{creation_date} );
	
        $self->{media_id} = $dbh->{mysql_insertid};

        $media_id = $self->{media_id};

	my $old_path = delete $self->{tempfile};
	my $new_path = $self->file_path;
	mkpath((splitpath($new_path))[1]);
	move($old_path,$new_path) || croak("Cannot create $new_path");
    }

    # remove any existing media_contrib relatinships and save any new relationships
    $dbh->do('delete from media_contrib where media_id = ?', undef, $media_id);
    my $count; 
    foreach my $contrib (@{$self->{contrib_ids}}) {
        $dbh->do('insert into media_contrib (media_id, contrib_id, contrib_type_id, ord) values (?,?,?,?)', undef, $media_id, $contrib->{contrib_id}, $contrib->{contrib_type_id}, $count++);
    }


    # save a copy in the version table
    my $serialized; 
    eval { $serialized = freeze($self); };
    croak ("Unable to serialize object: $@") if $@;
    $dbh->do('INSERT into media_version (media_id, version, data) values (?,?,?)', undef, $media_id, $self->{version}, $serialized);


    add_history(    object => $self,
                    action => 'new',
                )
      if $self->{version} == 1;

    add_history(    object => $self,
                    action => 'save',
                );

}

=item @media = Krang::Media->find($param)

Find and return media object(s) with parameters specified. Supported paramter keys:

=over 4

=item *

media_id (can optionally take a list of ids)

=item * 

version - combined with a single C<media_id> (and only C<media_id>), loads a specific version of a media object.  Unlike C<revert()>, this object has C<version> set to the actual version number of the loaded object.

=item *

title

=item *

title_like - case insensitive match on title. Must include '%' on either end for substring match.

=item *

category_id

=item *

below_category_id - will return media in category and in categories below as well.

=item *

media_type_id

=item * 

contrib_id 

=item *

filename

=item *

filename_like - case insensitive match on filename. Must include '%' on either end for substring match.

=item *

simple_search - Performs a per-word LIKE substring match against title, filename, and url, and an exact match against media_id if value passed in is a number.

=item *

no_attributes - returns objects where the fields caption, copyright, notes, and alt_tag are empty if this is set.

=item *

order_by - field to order search by, defaults to media_id

=item *

order_desc - results will be in ascending order unless this is set to 1 (making them descending).

=item *

limit - limits result to number passed in here, else no limit.

=item *

offset - offset results by this number, else no offset.

=item *

=item * 

url 

=item *

url_like - case insensitive match on url. Must include '%' on either end for substring match.

ids_only - return only media_ids, not objects if this is set true.

=item *

count - return only a count if this is set to true. Cannot be used with ids_only.

=item *

creation_date - Must be passed in as Time::Piece object.  If array of two dates passed in, will use to find media created between those dates.

=back

=cut

sub find {
    my $self = shift;
    my %args = @_;
    my $dbh = dbh;
    my @where;
    my @media_object;

    my %valid_params = ( media_id => 1,
                         version => 1,
                         title => 1,
                         title_like => 1,
                         url => 1,
                         url_like => 1,
                         category_id => 1,
                         below_category_id => 1,
                         media_type_id => 1,
                         contrib_id => 1,
                         filename => 1,
                         filename_like => 1,
                         simple_search => 1,
                         no_attributes => 1,
                         checked_out_by => 1,
                         order_by => 1,
                         order_desc => 1,
                         limit => 1,
                         offset => 1,
                         count => 1,
                         creation_date => 1,
                         ids_only => 1 );
                                                                               
    # check for invalid params and croak if one is found
    foreach my $param (keys %args) {
        croak (__PACKAGE__."->find() - Invalid parameter '$param' called.") if
not $valid_params{$param};
    }

    # set defaults if need be
    my $order_by =  $args{'order_by'} ? $args{'order_by'} : 'media_id';
    my $order_desc = $args{'order_desc'} ? 'desc' : 'asc';
    my $limit = $args{'limit'} ? $args{'limit'} : undef;
    my $offset = $args{'offset'} ? $args{'offset'} : 0;

    # check for invalid argument sets
    croak(__PACKAGE__ . "->find(): 'count' and 'ids_only' were supplied. " .
          "Only one can be present.")
      if $args{count} and $args{ids_only};

    croak(__PACKAGE__ . "->find(): can't use 'version' without 'media_id'.")
      if $args{version} and not $args{media_id};

    if ($args{version}) {
        if (ref $args{media_id} eq 'ARRAY') {
            croak(__PACKAGE__ . "->find(): can't use 'version' with an array of media_ids, must be a single media_id.");
        } else {
            # loading a past version is handled by _load_version()
            return $self->_load_version($args{media_id}, $args{version});
        }
    }

    # set simple keys
    foreach my $key (keys %args) {
	if ( ($key eq 'title') || ($key eq 'category_id') || ($key eq 'media_type_id') || ($key eq 'filename') || ($key eq 'url') || ($key eq 'contrib_id' ) || ($key eq 'checked_out_by')) {
            push @where, $key;
	} 
    }
  
    my $where_string = "";
    $where_string .= join(' and ', map { "$_ = ?" } @where);
    
    # add media_id(s) if needed
    if ($args{media_id}) {
        if (ref $args{media_id} eq 'ARRAY') {
            $where_string .= " and " if $where_string;
            $where_string .= "(" . 
              join(" OR ",  map { " media_id = " . $dbh->quote($_) } 
                   @{$args{media_id} }) .
                     ')';
        } else {
            $where_string .= " and " if $where_string;
            $where_string .= "media_id = ". $dbh->quote($args{media_id});
        }
    }

    # add title_like to where_string if present
    if ($args{'title_like'}) {
        $where_string .= " and " if $where_string;
        $where_string .= "title like ?";
        push @where, 'title_like';
    }

    # add ids of category and cats below if below_category_id is passed in
    if ($args{'below_category_id'}) {
        my $specd_cat = (Krang::Category->find(category_id => $args{below_category_id}))[0];
        my @descendants = $specd_cat->descendants( ids_only => 1 );
        unshift @descendants, $specd_cat->category_id;

        $where_string .= " and " if $where_string;
        $where_string .= "(".
          join(" OR ", map { "category_id = $_" } @descendants) .")";
 
    }

    # add filename_like to where_string if present
    if ($args{'filename_like'}) {
        $where_string .= " and " if $where_string;
        $where_string .= "filename like ?";
        push @where, 'filename_like';
    }

    # add url_like to where_string if present
    if ($args{'url_like'}) {
        $where_string .= " and " if $where_string;
        $where_string .= "url like ?";
        push @where, 'url_like';
    }

    if ($args{'no_attributes'}) {
        $where_string .= " and " if $where_string;
        $where_string .= "((caption = '' or caption is NULL) AND (copyright = '' or copyright is NULL) AND (notes = '' or notes is NULL) AND (alt_tag = '' or alt_tag is NULL))";
    }

    if ($args{'creation_date'}) {
        if (ref($args{'creation_date'}) eq 'ARRAY') {
            $where_string .= " and " if $where_string;
            $where_string .= " creation_date BETWEEN '".$args{'creation_date'}[0]->mysql_datetime."' AND '".$args{'creation_date'}[1]->mysql_datetime."'";
        } else {
            $where_string .= " and " if $where_string;
            $where_string .= " creation_date = '".$args{'creation_date'}->mysql_datetime."'";
        }
    }

    if ($args{'simple_search'}) {
       my @words = split(/\s+/, $args{'simple_search'});
        foreach my $word (@words){
                my $numeric = ($word =~ /^\d+$/) ? 1 : 0;
                my $joined = $numeric ? 'media_id = ?' : '('.join(' OR ', 'title LIKE ?', 'url LIKE ?', 'filename LIKE ?').')';
                $where_string .= " and " if $where_string;
                $where_string .= $joined;
                if ($numeric) {
                    push @where, 'simple_search';
                } else {
                    push @where, ($word, $word, $word);
                    $args{$word} = '%'.$word.'%';
                } 
        } 
    }

    my $select_string;
    if ($args{'count'}) {
        $select_string = 'count(*) as count';
    } elsif ($args{'ids_only'}) {
        $select_string = 'media_id';
    } else {
        my @fields = grep {($_ ne 'media_id')} FIELDS;

        $select_string = 'DISTINCT(media_id), '.join(',', @fields);
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

    debug(__PACKAGE__ . "::find() SQL: " . $sql);
    debug(__PACKAGE__ . "::find() SQL ARGS: " . join(', ', map { defined $args{$_} ? $args{$_} : 'undef' } @where));

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
                next unless defined $obj->{$date_field};
                $obj->{$date_field} = Time::Piece->from_mysql_datetime($obj->{$date_field});
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
    croak ("Unable to deserialize object: $@") if $@;

    # add history now to show which version was reverted to
    add_history(    object => $self,
                    action => 'revert',
                );
    
    my $old_filepath = $self->file_path();
    $self->{version} = $version;
    $self->{checked_out_by} = $checked_out_by;

    # copy old media file into tmp storage
    my $path = tempdir( DIR => catdir(KrangRoot, "tmp") );
    my $filepath = catfile($path, $self->{filename});
    copy($old_filepath,$filepath); 
    $self->{tempfile} = $filepath;
   
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

    eval {
        $self = thaw($data);
    };
    croak ("Unable to deserialize object: $@") if $@;

    my $old_filepath = $self->file_path();

    # copy old media file into tmp storage
    my $path = tempdir( DIR => catdir(KrangRoot, "tmp") );
    my $filepath = catfile($path, $self->{filename});
    copy($old_filepath,$filepath);
    $self->{tempfile} = $filepath;
  
    return $self;
}

=item $thumbnail_path = $media->thumbnail_path();

=item $thumbnail_path = $media->thumbnail_path(relative => 1);

Returns the path to the thumbnail (if media is an image).  Valid image
types are stored in IMAGE_TYPES constant. Will create thumbnail if
first time called.  If relative is set to 1, returns a path relative
to KrangRoot.

Returns undef for media objects that are not images.

=cut

sub thumbnail_path {
    my $self = shift;
    my %args = @_;
    my $root = KrangRoot;
    my $filename = $self->{filename};
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
            # path is the same as the file path with t__ in front of
            # the filename
            my $path = catfile((splitpath($self->file_path(relative => $args{relative})))[1], "t__$filename");
            if (not -f $path) {
                # problems creating thumbnails shouldn't be fatal
                eval {
                    my $img = Imager->new();
                    $img->open(file=>$self->file_path()) || croak $img->errstr();
                    my $thumb = $img->scale(xpixels=>THUMBNAIL_SIZE,ypixels=>THUMBNAIL_SIZE,type=>'min');
                    $thumb->write(file=>$path) || croak $thumb->errstr;
                };
 
                # if it didn't work, log the problem and move on.
                # Thumbnails are optional.
                if ($@) {
                    debug(__PACKAGE__ . " - problem creating thumbnail for $filename : $@");
                    return undef;
                }
            } 

            return $path;
        }
    }
    return undef;
}

=item $media->checkout() || Krang::Media->checkout($media_id)

Marks media object as checked out by user_id.

=cut

sub checkout {
    my $self = shift;
    my $media_id = shift;
    my $dbh = dbh;
    my $user_id = $session{user_id};

    # short circuit checkout on instance method version of call...
    return if $self and
              $self->{checked_out_by} and 
              $self->{checked_out_by} == $user_id;
   
    my $is_object = $media_id ? 0 : 1; 
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

    $self->{checked_out_by} = $user_id if $is_object;

    if ($is_object) {
        add_history(    object => $self,
                        action => 'checkout',
               );
    } else {
        add_history(    object => ((Krang::Media->find(media_id => $media_id))[0]),
                        action => 'checkout',
               );
    }

}

=item $media->checkin() || Krang::Media->checkin($media_id)

Marks media object as checked in.

=cut

sub checkin {
    my $self = shift;
    my $media_id = shift;
    my $dbh = dbh;
    my $user_id = $session{user_id};

    my $is_object = $media_id ? 0 : 1;
    $media_id = $self->{media_id} if (not $media_id);
    croak("No media_id specified for checkin!") if not $media_id;

    $dbh->do('UPDATE media SET checked_out_by = NULL WHERE media_id = ?', undef, $media_id);
    
    $self->{checked_out_by}= $user_id if $is_object;

    if ($is_object) {
        add_history(    object => $self,
                        action => 'checkin',
               );
    } else {
        add_history(    object => ((Krang::Media->find(media_id => $media_id))[0]),
                        action => 'checkin',
               );
    }

}

=item $media = $media->url();

Returns calculated url of media object based on category_id and filename

=cut

sub url {
    my $self= shift;
    
    # calculate url
    my $url =
      (Krang::Category->find(category_id => $self->{category_id}))[0]->url();
    return catdir($url, $self->{filename});
}

=item * preview_url (read-only)

The preview URL for this media object

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

=item $media_id = $media->duplicate_check()

This method checks whether the url of a media object is unique.

=cut

sub duplicate_check {
    my $self = shift;
    my $id = $self->{media_id} || 0;
    my $media_id = 0;

    my $query = 'SELECT media_id FROM media WHERE url = ?';
    $query .= "AND media_id != $id" if $id;
    my $dbh = dbh();
    my $sth = $dbh->prepare($query);
    $sth->execute($self->url);
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

    my $is_object = $media_id ? 0 : 1;

    $media_id = $self->{media_id} if (not $media_id);
  
    $is_object ? $self->checkout() : Krang::Media->checkout($media_id);
     
    croak("No media_id specified for delete!") if not $media_id;

    # first delete history for this object
    if ($is_object) {
        Krang::History->delete(object => $self);
    } else {
        Krang::History->delete( object => ((Krang::Media->find(media_id => $media_id))[0]) );
    }

    my $file_dir = $is_object ? catdir($root,'data','media',Krang::Conf->instance,$self->_media_id_path) : catdir($root,'data','media',Krang::Conf->instance,(Krang::Media->find(media_id => $media_id))[0]->_media_id_path);

    $dbh->do('DELETE from media where media_id = ?', undef, $media_id); 
    $dbh->do('DELETE from media_version where media_id = ?', undef, $media_id); 
    $dbh->do('delete from media_contrib where media_id = ?', undef, $media_id);

    rmtree($file_dir) || croak("Cannot delete $file_dir and contents.");

}

=item C<< $media->serialize_xml(writer => $writer, set => $set) >>

Serialize as XML.  See Krang::DataSet for details.

=cut

sub serialize_xml {
    my ($self, %args) = @_;
    my ($writer, $set) = @args{qw(writer set)};
    local $_;

    # open up <media> linked to schema/media.xsd
    $writer->startTag('media',
                      "xmlns:xsi" => 
                        "http://www.w3.org/2001/XMLSchema-instance",
                      "xsi:noNamespaceSchemaLocation" =>
                        'media.xsd');

    # write media file into data set
    my $path = "media_$self->{media_id}/$self->{filename}";
    $set->add(file => $self->file_path, path => $path, from => $self);

    my %media_type = Krang::Pref->get('media_type');

    # basic fields
    $writer->dataElement(media_id   => $self->{media_id});
    $writer->dataElement(media_type => $media_type{$self->{media_type_id}});
    $writer->dataElement(title      => $self->{title});
    $writer->dataElement(filename   => $self->{filename});
    $writer->dataElement(path       => $path);
    $writer->dataElement(category_id => $self->{category_id});    
    $writer->dataElement(url        => $self->{url});
    $writer->dataElement(caption    => $self->{caption});    
    $writer->dataElement(copyright  => $self->{copyright});    
    $writer->dataElement(alt_tag    => $self->{alt_tag});
    $writer->dataElement(notes      => $self->{notes});
    $writer->dataElement(version           => $self->{version});
    $writer->dataElement(published_version => $self->{published_version})
      if $self->{published_version};
    $writer->dataElement(creation_date => $self->{creation_date}->datetime);
    $writer->dataElement(publish_date  => $self->{publish_date}->datetime)
      if $self->{publish_date};
    
    # add category to set
    $set->add(object => $self->category, from => $self);

    # contributors
    my %contrib_type = Krang::Pref->get('contrib_type');
    for my $contrib ($self->contribs) {
        $writer->startTag('contrib');
        $writer->dataElement(contrib_id => $contrib->contrib_id);
        $writer->dataElement(contrib_type => 
                             $contrib_type{$contrib->selected_contrib_type()});
        $writer->endTag('contrib');

        $set->add(object => $contrib, from => $self);
    }

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
    @complex{qw(media_id filename published_date creation_date checked_out_by
                version published_version category_id)} = ();
    %simple = map { ($_,1) } grep { not exists $complex{$_} } (FIELDS);
    
    # parse it up
    my $data = Krang::XML->simple(xml           => $xml, 
                                  suppressempty => 1);

    # is there an existing object?
    my ($media) = Krang::Media->find(url => $data->{url});
    my $update = 0;
    if ($media) {
        # if not updating this is fatal
        Krang::DataSet::DeserializationFailed->throw(
            message => "A media object with the url '$data->{url}' already ".
                       "exists and no_update is set.")
            if $no_update;

        # update simple fields
        $media->{$_} = $data->{$_} for keys %simple;
        
        # set the update flag
        $update = 1;

    } else {
        # create a new media object with category and simple fields
        $media = Krang::Media->new(category_id => 
                                   $set->map_id(class => "Krang::Category",
                                                id    => $data->{category_id}),
                                   (map { ($_,$data->{$_}) } keys %simple));
    }
        
    # upload the file
    my $path = "media_$data->{media_id}/$data->{filename}";
    my $full_path = $set->map_file(path => $path);
    my $fh = IO::File->new($full_path) or 
      croak("Unable to open $full_path: $!");
    $media->upload_file(filehandle => $fh,
                        filename   => $data->{filename});
    
    # get hash of media type names to ids
    my %media_types = reverse Krang::Pref->get('media_type');
    
    # get ids for media types
    Krang::DataSet::DeserializationFailed->throw(
             "Unknown media_type '$data->{media_type}'.")
        unless $media_types{$data->{media_type}};
    
    # add media type
    $media->media_type_id($media_types{$data->{media_type}});
        
    # save changes
    $media->save();

    # make sure there's a file on the other end
    assert($media->file_path and -e $media->file_path,
           "Media saved successfully") if ASSERT;

    return $media;
}


=back

=cut

1;
