package Krang::Desk;
use strict;
use warnings;

use Carp qw(croak);
use Krang::DB qw(dbh);

=head1 NAME

Krang::Desk - Krang Desk API

=head1 SYNOPSIS

  use Krang::Desk;

  # add a new desk, defaulting to next available slot in order
  my $desk = Krang::Desk->new( name => 'Publish');

=head1 DESCRIPTION

Krang::Desk provides methods to create, delete, and reorder desks.

=head1 INTERFACE

=head2 METHODS

=over

=item new()

Add a new desk.  Takes the following parameters.

=over 4

=item name 

name of desk (required)

=item order

position in order of desks for this desk. defaults to next
available slot in desk order.

=back

=cut

sub new {
    my $class = shift;
    my %args = @_;
    croak(__PACKAGE__."->new - 'name' is a required parameter") if not $args{'name'};

    my $self = bless {}, $class;

    # insert record into db
    $self->_insert(%args);

    return $self;
}

sub _insert {
    my $self = shift;
    my %args = @_;
    my $dbh = dbh();

    # figure out how many desks there currently are
    my $sth = $dbh->prepare('SELECT count(*) from desk');
    $sth->execute();
    my $count;
    $count = $sth->fetchrow_array;
    $sth->finish;

    if ($args{order}) {
        if ($count >= $args{order}) {
            $sth = $dbh->prepare('UPDATE desk set ord = (ord + 1) where ord >= ?');
            $sth->execute($args{order});
            $sth->finish;
        } elsif (($count + 1) < $args{order}) {
            $args{order} = $count + 1;
        }
    } else {
        $args{order} = $count + 1; 
    }
   
    $sth = $dbh->prepare('INSERT INTO desk (name, ord) values (?,?)');
    $sth->execute($args{'name'}, $args{order});
    $sth->finish;

    $self->{desk_id} = $dbh->{mysql_insertid}; 
    $self->{name} = $args{name};
    $self->{order} = $args{order};

}

=item delete()

Delete a desk. Takes a desk_id as argument if called as class method.

=cut

sub delete {
    my $self = shift;
    my $desk_id = shift;
    my $dbh = dbh;

    my $is_object = $desk_id ? 0 : 1;
    $desk_id = $self->{desk_id} if not $desk_id;
    croak(__PACKAGE__."->delete - No desk_id specified.") if not $desk_id; 

    my $order;

    # find order if this is not object
    if ($is_object) {
        $order = $self->{order};
    } else {
        my $sth = $dbh->prepare('SELECT ord from desk where desk_id = ?');
        $sth->execute($desk_id);
        $order = $sth->selectrow_array;
        $sth->finish;
    }
   
    # drop down the order of any desks higher than this one 
    my $sth = $dbh->prepare('UPDATE desk set ord = (ord - 1) where ord > ?');
    $sth->execute($order);
    $sth->finish;

    # fianlly, delete the desk
    $sth = $dbh->prepare('DELETE from desk where desk_id = ?');
    $sth->execute($desk_id);
    $sth->finish;
}

=back

=cut

1;

