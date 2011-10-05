package Krang::History;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

BEGIN {

    # declare exportable functions
    use Exporter;
    our @ISA       = qw(Exporter);
    our @EXPORT_OK = qw( add_history );
}

use Krang::ClassLoader DB      => qw(dbh);
use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader Log     => qw( info debug );
use Krang::ClassLoader 'Alert';
use Carp qw(croak);
use Time::Piece;
use Time::Piece::MySQL;

=head1 NAME

Krang::History - records historical events for krang objects

=head1 SYNOPSIS

    use Krang::ClassLoader History => qw( add_history );

    # record that a story was created (user_id pulled from session, 
    # object id and type from object passed in)
    add_history(    object => $story, 
                    action => 'new',
               );

    # record that story was saved (user_id pulled from session, 
    # object id, type and version from object passed in)
    add_history(    object => $story, 
                    action => 'save',
               );

    # record that story was checked in to desk 2 (user_id pulled 
    # from session, object id and type from object passed in)
    add_history(    object => $story, 
                    action => 'checkin'
                    desk_id => '2' 
                );

    # record that template was deployed (user_id pulled from session, 
    # object id and type from object passed in)
    add_history(    object => $template,
                    action => 'deploy',
               );
    
    # find and return all events for story 
    # (object id and type from object passed in)
    my @events = pkg('History')->find(  object => $story
                                     );

    # delete all history for media object 
    pkg('History')->delete( object => $media,
                          );

=head1 DESCRIPTION

This class handles the storage and retrieval of historical events in a Krang object's life.  Three interface methods exist- add_history, find, and delete.

=head1 INTERFACE

=head2 METHODS

=over 

=cut

BEGIN {

=item C<< $history->fields() >>

Returns a list of the DB table fields.
Override this method to extend the list

=cut

    sub fields {
        return qw( object_type object_id action version desk_id user_id timestamp );
    }

}

use Krang::ClassLoader MethodMaker => new_with_init => 'new',
  new_hash_init                    => 'hash_init',
  get_set                          => [fields()];

sub init {
    my $self = shift;
    my %args = @_;

    # finish the object
    $self->hash_init(%args);

    return $self;
}

sub _save {
    my $self = shift;
    my $dbh  = dbh;

    # Valid object type?
    my $object_type        = $self->{object_type};
    my @valid_object_types = $self->object_types();
    croak("Invalid object type '$object_type' (expecting: " . join(", ", @valid_object_types) . ")")
      unless (grep { $object_type->isa($_) } @valid_object_types);

    # Valid action?
    my $action        = $self->{action};
    my @valid_actions = $self->actions();
    croak("Invalid action '$action' (expecting: " . join(", ", @valid_actions) . ")")
      unless (grep { $_ eq $action } @valid_actions);

    my $time = localtime();
    $self->{timestamp} = $time->mysql_datetime();

    my @fields = $self->fields();

    $dbh->do(
        'INSERT INTO history ('
          . join(',', @fields)
          . ') VALUES (?'
          . ",?" x (scalar @fields - 1) . ")",
        undef,
        map { $self->{$_} } @fields
    );

}

=item add_history()

This method adds an entry into the database of an action taken on an object.

The valid trackable objects are: Krang::Story, Krang::Media, and Krang::Template. These are passed in as 'object' - 'object_type', and 'object_id' are derived from the object.  The valid actions (specified by 'action') performed on an object are listed in the actions() method at the bottom of this module.

In addition to tracking actions on objects, the user who performed the action is tracked by 'user_id', which is found in the session object.  If the 'action' is  'save' or 'revert', version is also derived from the object. 'desk_id' can be used to track which desk an action was performed on.  A timestamp is added to each history event, and will appear in the field 'timestamp' on objects returned from find. 

=cut

sub add_history {
    my %args   = @_;
    my $object = delete $args{'object'};
    croak("No object specified") unless ($object);

    my $history = pkg('History')->new(%args);

    my $version;
    eval {
        $version = $object->version()
          if ( ($args{action} eq 'save')
            || ($args{action} eq 'revert')
            || ($args{action} eq 'rename'));
    };
    $history->{version} = $version if $version;
    $history->{user_id} = $ENV{REMOTE_USER};

    my $object_type = ref $object;
    $history->{object_type} = $object_type;

    my $object_id_meth = $object->id_meth;
    $history->{object_id} = $object->$object_id_meth;
    $history->_save();

    # log this event
    my $info_string =
        $history->{object_type} . " "
      . $history->{object_id} . " "
      . $history->{action}
      . " by user "
      . $history->{user_id};
    $info_string .= " (version " . $history->{version} . ")" if $history->{version};
    $info_string .= " to desk '" . $history->{desk_id} . "'" if $history->{desk_id};
    info(__PACKAGE__ . " - " . $info_string);

    # check if event should trigger an alert
    pkg('Alert')->check_alert(history => $history, object => $object)
      if ($object->isa('Krang::Story') || $object->isa('Krang::Media'));
}

=item find()

Find and return Krang::History objects with parameters specified. Supported paramter keys:

=over 4

=item *

object - Krang::Story, Krang::Media, or Krang::Template object (required)

=item * 

user_id

=item *

order_by - field to order search by, defaults to timestamp

=item *

order_desc - results will be in ascending order unless this is set to 1 (making them descending).

=item *

limit - limits result to number passed in here, else no limit.

=item *

offset - offset results by this number, else no offset.

=item *

count - return only a count if this is set to true.

=back

=cut

sub find {
    my $self = shift;
    my %args = @_;
    my $dbh  = dbh;

    my $object = delete $args{'object'};
    croak("No object specified") unless ($object);

    my $id_meth = $object->id_meth;
    $args{object_id}   = $object->$id_meth;
    $args{object_type} = ref $object;

    my @where;
    my @history_object;

    # set defaults if need be
    my $order_by   = $args{'order_by'}   ? $args{'order_by'} : 'timestamp';
    my $order_desc = $args{'order_desc'} ? 'desc'            : 'asc';
    my $limit      = $args{'limit'}      ? $args{'limit'}    : undef;
    my $offset     = $args{'offset'}     ? $args{'offset'}   : 0;

    # set simple keys
    foreach my $key (keys %args) {
        if (($key eq 'user_id') || ($key eq 'object_type') || ($key eq 'object_id')) {
            push @where, $key;
        }
    }

    my $where_string = join ' and ', (map { "$_ = ?" } @where);

    my $select_string;
    if ($args{'count'}) {
        $select_string = 'count(*) as count';
    } else {
        $select_string = join(',', $self->fields());
    }

    my $sql = "select $select_string from history";
    $sql .= " where " . $where_string if $where_string;
    $sql .= " order by $order_by $order_desc";

    # add limit and/or offset if defined
    if ($limit) {
        $sql .= " limit $offset, $limit";
    } elsif ($offset) {
        $sql .= " limit $offset, 18446744073709551615";
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
        } else {
            $obj = bless {%$row}, $self;

            # make date readable
            $obj->{timestamp} = Time::Piece->from_mysql_datetime($obj->{timestamp});

            push(@history_object, $obj);
        }
    }
    $sth->finish();
    return @history_object;

}

=item delete()

Deletes all entries from history with object_id and object_type from passed in $object.

=cut

sub delete {
    my $self = shift;
    my %args = @_;
    my $dbh  = dbh;

    my $object      = delete $args{'object'};
    my $id_meth     = $object->id_meth;
    my $object_type = ref $object;
    my $object_id   = $object->$id_meth;

    $dbh->do('DELETE from history where object_id = ? and object_type = ?',
        undef, $object_id, $object_type);

}

=item C<< $history->object_types() >>

Returns a list of asset types.
Override this method to extend the list.

=cut

sub object_types {
    return qw( Krang::Story
      Krang::Media
      Krang::Template
    );
}

=item C<< $history->actions() >>

Returns a list of actions to be logged.
Override this method to extend the list.

=cut

sub actions {
    return qw(
      new
      save
      checkin
      checkout
      steal
      publish
      deploy
      undeploy
      move
      revert
      delete
      rename
      retire
      unretire
      trash
      untrash
      resize
      crop
      rotate
      flip
    );
}

1;

