package Krang::Trash;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader DB      => qw(dbh);
use Krang::ClassLoader Log     => qw(debug);
use Krang::ClassLoader History => qw(add_history);
use Krang::ClassLoader Conf    => qw(TrashMaxItems);
use Krang::ClassLoader 'Group';

use Time::Piece;
use Time::Piece::MySQL;
use UNIVERSAL::moniker;
use Carp qw(croak);

use constant TRASH_OBJECT_FIELDS => qw(
  id
  type
  title
  class
  url
  date
  version
  may_see
  may_edit
  linkto
);

# static part of SQL query
our %SQL         = ();
our $NUM_USER_ID = 0;

=head1 NAME

Krang::Trash - data broker for TrashBin CGI

=head1 SYNOPSIS

  use Krang::ClassLoader 'Trash';

  # get a list of objects on the current user's workspace
  @objects = pkg('Trash')->find();

  # get just the first 10, sorting by url:
  @objects = pkg('Trash')->find(limit    => 10,
                                offset   => 0,
                                order_by => 'url');

=head1 DESCRIPTION

This module provides a find() method which returns all objects living
in the trashbin. These are not full-fledged Story/Media/Template
objects, just hashes containing what we need to fill the trashbin's
pager view.

=head1 INTERFACE

=over

=item C<< @objects = Krang::Trash->find() >>

=item C<< $count = Krang::Trash->find(count => 1) >>

Finds stories, media and templates currently living the trashbin.  The
returned array will contain Krang::Story, Krang::Media and
Krang::Template objects slimmed down to Trash objects.  Custom objects
may also be listed (see the class method C<register_find_sql()>).

Since the returned objects do not share single ID-space, the standard
C<ids_only> mode is not supported.

Available search options are:

=over

=item count

Return just a count of the results for this query.

=item limit

Return no more than this many results.

=item offset

Start return results at this offset into the result set.

=item order_by

Output field to sort by.  Defaults to 'type' which sorts stories
first, then media and finally templates.  Other available settings are
'date', 'title', 'url' and 'id'.

=item order_desc

Results will be in sorted in ascending order unless this is set to 1
(making them descending).

=back

=cut

sub find {
    my $pkg  = shift;
    my %args = @_;
    my $dbh  = dbh();

    my $user_id = $ENV{REMOTE_USER};

    croak "Krang::Trash: No user ID found" unless $user_id;

    # get search parameters out of args, leaving just field specifiers
    my $order_by = delete $args{order_by} || 'type';
    my $order_dir = delete $args{order_desc} ? 'DESC' : 'ASC';
    my $limit  = delete $args{limit}  || 0;
    my $offset = delete $args{offset} || 0;
    my $count  = delete $args{count}  || 0;

    # massage order_by clause
    if ($order_by eq 'type') {
        $order_by = " type $order_dir, class ASC, id ASC ";
    } elsif ($order_by eq 'title') {
        $order_by = " title $order_dir, id ASC ";
    } elsif ($order_by eq 'date') {
        $order_by = " date $order_dir, type ASC, id ASC ";
    } else {
        $order_by .= " $order_dir ";
    }

    # build overall SQL query
    my $query       = '';
    my $num_user_id = $NUM_USER_ID;
    my %perms       = pkg('Group')->user_asset_permissions();
    for my $class (keys %SQL) {

        # skip hidden assets
        next if $perms{$class} and $perms{$class} eq 'hide';

        # core assets are all user-sensitive
        $num_user_id++ if $class =~ /story|media|template/;

        # unionize it
        $query .=
          $query
          ? ' UNION ' . $SQL{$class}
          : $SQL{$class};
    }

    # mix in order_by
    $query .= " ORDER BY $order_by " if $order_by and not $count;

    # add LIMIT clause, if any
    if ($limit) {
        $query .= $offset ? " LIMIT $offset, $limit" : " LIMIT $limit";
    } elsif ($offset) {
        $query .= " LIMIT $offset, 18446744073709551615";
    }

    debug(__PACKAGE__ . "::find() SQL: " . $query);

    # execute the search
    my $sth = $dbh->prepare($query);
    $sth->execute(($user_id) x $num_user_id);
    my $results = $sth->fetchall_arrayref;
    $sth->finish;

    # maybe return the count
    return scalar @$results if $count;

    # return a list of hashrefs
    my @objects = ();

    for my $row (@$results) {
        my $obj = {};

        @{$obj}{(TRASH_OBJECT_FIELDS)} = @$row;

        if ($obj->{type} eq 'media') {
            my ($media) = pkg('Media')->find(media_id => $obj->{id});
            $obj->{thumbnail_src} = $media->thumbnail_path(relative => 1);
        }

        # merge in user asset permission
        $obj->{may_edit} = 0 unless $perms{$obj->{type}} eq 'edit';

        push @objects, $obj;
    }

    return @objects;
}

# Default SQL for Krang's core objects
# Order matters since this forms our Trash object fassade
$SQL{story} = <<SQL;
(
SELECT s.story_id    AS id,
       'story'       AS type,
       title,
       class,
       sc.url        AS url,
       s.cover_date  AS date,
       version,
       ucpc.may_see  AS may_see,
       ucpc.may_edit AS may_edit,
       1             AS linkto
 FROM  story AS s
 LEFT JOIN story_category AS sc
        ON s.story_id = sc.story_id
 LEFT JOIN user_category_permission_cache AS ucpc
        ON sc.category_id = ucpc.category_id
 WHERE sc.ord = 0
 AND   ucpc.user_id = ?
 AND   s.trashed = 1
 AND   ucpc.may_see = 1
)
SQL

$SQL{media} = <<SQL;
(
 SELECT media_id      AS id,
        'media'       AS type,
        title         AS title,
        ''            AS class,
        url           AS url,
        creation_date AS date,
        version       AS version,
        ucpc.may_see  AS may_see,
        ucpc.may_edit AS may_edit,
        1             AS linkto
 FROM media AS m
 LEFT JOIN user_category_permission_cache AS ucpc
        ON m.category_id = ucpc.category_id
 WHERE ucpc.user_id = ?
 AND   ucpc.may_see = 1
 AND   m.trashed    = 1
)
SQL

$SQL{template} = <<SQL;
(
 SELECT template_id   AS id,
        'template'    AS type,
        filename      AS title,
        ''            AS class,
        url           AS url,
        creation_date AS date,
        version       AS version,
        ucpc.may_see  AS may_see,
        ucpc.may_edit AS may_edit,
        0             AS linkto
 FROM template AS t
 LEFT JOIN user_category_permission_cache AS ucpc
        ON t.category_id = ucpc.category_id
 WHERE (ucpc.user_id = ? OR t.category_id IS NULL)
 AND   (ucpc.may_see = 1 OR ucpc.may_see IS NULL)
 AND   t.trashed    = 1
)
SQL

=item C<< pkg('Trash')->register_find_sql(object => $moniker, user_sensitive => 0, sql => $sql) >>

This class method allows custom objects other than Krang's core
objects Story, Media and Template to register with the trashbin's
find() method.  It should be called in a BEGIN block!

=back

=head2 ARGUMENTS

=over

=item object

This should be the lowercase moniker of your object's class,
e.g. 'mailing' for Krang::Mailing.

=item sql

This should be the SQL query used to find those objects in the
trashbin.

=item user_sensitive

Set this flag to true if the sql argument includes a placeholder for
the logged in user's ID. Defaults to 0.

=back

=head2 Example: A custom object class named "Krang::Mailing"

The SQL select command forms a fassade, mapping asset fields to trash
object fields.  Order matters!  All fields must be present, though
they might contain the empty string (as the 'class' field in the
example below.

Also assumed in the custom objects' database table is the presence of
a boolean column named 'trashed', which is supposed to be set to true
if the object currently lives in the trashbin.

 Class:   Krang::Mailing
 Table:   mailing

 BEGIN {

     pkg('Trash')->register_find_sql(object => 'mailing', user_sensitive => 0, sql => <<SQL);
 SELECT mailing_id   AS id,
        'mailing'    AS type,
        subject      AS title,
        ''           AS class,
        url          AS url,
        mailing_date AS date,
        ''           AS version,
        someperm     AS may_see,
        otherperm    AS may_edit,
        1            AS linkto      # format the URL as a link
 FROM mailing
 WHERE trashed = 1
 SQL

 }

=cut

sub register_find_sql {
    my ($pkg, %args) = @_;

    # got all we need?
    my @missing = grep { $args{$_} ? 0 : $_ } qw(object sql);
    croak(__PACKAGE__ . "::register_find_sql(): Missing argument(s): " . join ', ', @missing)
      if scalar(@missing);

    # store sql
    $SQL{$args{object}} = '(' . $args{sql} . ')';

    # how many user_id placeholders will the query contain?
    $NUM_USER_ID++ if $args{user_sensitive};
}

=over

=item C<< pkg('Trash')->store(object => $story) >>

=item C<< pkg('Trash')->store(object => $media) >>

=item C<< pkg('Trash')->store(object => $template) >>

=item C<< pkg('Trash')->store(object => $other) >>

This method moves the specified object to the trash on the database
level.  It must be called by the object's trash() method.

=cut

sub store {
    my ($self, %args) = @_;

    my ($type, $id) = $self->_type_and_id_from_object(%args);
    my $id_meth = $args{object}->id_meth;
    my $dbh     = dbh();

    # set object's trashed flag
    my $query = <<SQL;
UPDATE $type
SET    trashed  = 1
WHERE  $id_meth = ?
SQL

    debug(__PACKAGE__ . "::store() SQL: " . $query . " ARGS: $id");

    $dbh->do($query, undef, $id);

    # memo in trash table
    $query = <<SQL;
REPLACE INTO trash (object_type, object_id, timestamp)
VALUES (?,?,?)
SQL

    my $t    = localtime();
    my $time = $t->mysql_datetime();

    debug(__PACKAGE__ . "::store() SQL: " . $query . " ARGS: $type, $id, " . $time);

    $dbh->do($query, undef, $type, $id, $time);

    # prune the trash
    $self->prune();

    # inactivate schedules on the trashed object
    pkg('Schedule')->inactivate(object_type => $type, object_id => $id);
}

=item C<< pkg('Trash')->prune() >>

Prune the trash, deleting the oldest entries, leaving TrashMaxItems.

This class method is currently called at the end of each object delete
(i.e. when moving an object into the trash).

=over

=item Potential Security Hole

Users without admin_delete permission may delete assets by creating
bogus objects and pushing them into the trash, thus causing prune() to
permanently delete trashed objects!

=back

=cut

sub prune {
    my ($self) = @_;

    return unless TrashMaxItems;

    my $max = TrashMaxItems;
    my $dbh = dbh();

    # did we reach the limit
    my $query = "SELECT * from trash ORDER BY timestamp ASC LIMIT ?";

    debug(__PACKAGE__ . "::prune() SQL: " . $query . " ARGS: " . ($max + 1));

    my $sth = $dbh->prepare($query);
    $sth->execute($max + 1);
    my $result = $sth->fetchall_arrayref;
    $sth->finish;

    return unless $result;

    return if scalar(@$result) < $max + 1;

    # second item is the oldest we will keep so we have at least one item to delete
    my $datelimit = $result->[1][2];

    # get object_type and object_id of items to be deleted
    $query = "SELECT object_type, object_id from trash WHERE timestamp < ?";

    debug(__PACKAGE__ . "::prune() SQL: " . $query . " ARGS: $datelimit");

    $sth = $dbh->prepare($query);
    $sth->execute($datelimit);
    $result = $sth->fetchall_arrayref;

    return unless $result;

    # delete from object table
    for my $item (@$result) {
        my $type = $item->[0];
        my $id   = $item->[1];
        my $pkg  = pkg(ucfirst($type));

        # potential security hole!
        eval {

            # delete from object table
            my ($object) = $pkg->find($type . '_id' => $id);
            $object->checkin if $object->checked_out;
            local $ENV{REMOTE_USER} = pkg('User')->find(
                login    => 'system',
                ids_only => 1
            );
            $pkg->delete($id);
        };
        debug(__PACKAGE__ . "::prune() - ERROR: " . $@) if $@;
    }
}

=item C<< pkg('Trash')->delete(object => $story) >>

=item C<< pkg('Trash')->delete(object => $media) >>

=item C<< pkg('Trash')->delete(object => $template) >>

=item C<< pkg('Trash')->delete(object => $other) >>

Deletes the specified object from the trashbin, i.e. deletes it
permanently from the database.  The object must implement a method
named C<delete()>.

=cut

sub delete {
    my ($self, %args) = @_;

    $args{object}->delete;
}

=item C<< pkg('Trash')->restore(object => $story) >>

=item C<< pkg('Trash')->restore(object => $media) >>

=item C<< pkg('Trash')->restore(object => $template) >>

=item C<< pkg('Trash')->restore(object => $other) >>

Restores the specified object from the trashbin back to live or to the
retired section (depending from where it has been deleted).  The object must
implement a method named C<untrash()> that does the heavy lifting.

=cut

sub restore {
    my ($self, %args) = @_;

    $args{object}->untrash;

    # activate schedules
    my ($type, $id) = $self->_type_and_id_from_object(%args);
    pkg('Schedule')->activate(object_type => $type, object_id => $id);
}

=item C<< pkg('Trash')->remove(object => $object) >>

This method removes an object from the trash table.  Objects wishing
to implement the trash functionality should call this method in their
C<untrash()> and C<delete()> methods.

=cut

sub remove {
    my $self = shift;
    my ($type, $id) = $self->_type_and_id_from_object(@_);

    my $query = "DELETE FROM trash WHERE object_type = ? AND object_id = ?";

    debug(__PACKAGE__ . "::delete() SQL: $query, ARGS: $type, $id");

    my $dbh = dbh();
    $dbh->do($query, undef, $type, $id);
}

# get object_type and object_id from an object
sub _type_and_id_from_object {
    my ($self, %args) = @_;

    my $object  = $args{object};
    my $id_meth = $object->id_meth;

    return ($object->moniker, $object->$id_meth);
}

1;

=back

=cut

