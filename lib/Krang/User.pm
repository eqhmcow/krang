package Krang::User;

=head1 NAME

Krang::User - a means to access information on users

=head1 SYNOPSIS

  use Krang::User;

  # construct object
  my $user = Krang::User->new(email => 'a@b.com',		#optional
			      first_name => 'fname',		#optional
			      group_ids => (1, 2, 3),		#optional
			      last_name => 'lname',		#optional
			      login => 'login',			#required
			      mobile_phone => '112-358-1321'	#optional
			      password => 'passwd',		#required
			      phone => '123-456-8901');		#optional

  # saves object to the DB
  $user->save();

  # getters
  ##########
  my $email 	= $user->email();
  my $first_name= $user->first_name();
  my @group_ids = $user->group_ids();	# returns arrayref or array
  my $last_name = $user->last_name();
  my $login	= $user->login();
  my $password	= $user->password();
  my $phone	= $user->phone();

  my $id 	= $user->user_id();	# undef until save()

  # setters
  ##########
  $user->first_name( 'first_name' );
  $user->group_ids( @ids );
  $user->last_name('last_name');
  $user->login( 'loginX' );
  $user->mobile_phone( $phone_number );
  $user->password( $password );		# stores MD5 of $SALT, $password
  $user->phone( $phone_number );


  # delete the user from the database
  $user->delete();

  # a hash of search parameters
  my %params =
  ( order_desc => 'asc',	# sort results in ascending order
    limit => 5,			# return 5 or less user objects
    offset => 1, 	        # start counting result from the
				# second row
    order_by => 'user_id'	# sort on the 'user_id' field
    login_like => '%fred%',	# match rows with 'login's LIKE '%fred'
    phone_like => '718%' );	# match rows with phone#'s LIKE '718%'

  # any valid object field can be appended with '_like' to perform a
  # case-insensitive sub-string match on that field in the database

  # returns an array of user objects matching criteria in %params
  my @users = Krang::User->find( %params );

=head1 DESCRIPTION

Each user object corresponds to an authorized user of the system.  The degree
of access a user is determined by the groups with which he is associated.

N.B. - Passwords are MD5 digests of $SALT and the password string; the
original password string in not retrievable once it is passed but can only be
calculated and compared i.e.:

  my $valid_password =
    $user->{password} eq md5_hex($SALT, $password_string) ? 1 : 0;

=cut


#
# Pragmas/Module Dependencies
##############################
# Pragmas
##########
use strict;
use warnings;

# External Modules
###################
use Carp qw(croak);
use Digest::MD5 qw(md5_hex);
require Exporter;

# Internal Modules
###################
use Krang;
use Krang::DB qw(dbh);
use Krang::Media;
use Krang::Story;
use Krang::Template;

#
# Package Variables
####################
# Constants
############
# Read-only fields
use constant USER_RO => qw(user_id);

# Read-write fields
use constant USER_RW => qw(email
			   first_name
			   last_name
			   login
			   mobile_phone
			   phone);

# user_user_group table fields
use constant USER_USER_GROUP => qw(user_id
			   	   user_group_id);

# Globals
##########
our $SALT = <<SALT;
Dulce et decorum est pro patria mori
--Horace
SALT

our @ISA = qw/Exporter/;
our @EXPORT_OK = ('$SALT');

# Lexicals
###########
my %user_args = map {$_ => 1} USER_RW, qw/group_ids password/;
my %user_cols = map {$_ => 1} USER_RO, USER_RW, 'password';

# Constructor/Accessor/Mutator setup
use Krang::MethodMaker	new_with_init => 'new',
			new_hash_init => 'hash_init',
			get => [USER_RO],
			get_set => [USER_RW],
			list => 'group_ids';


=head1 INTERFACE

=head2 FIELDS

Access to fields for this object is provided my Krang::MethodMaker.  The value
of fields can be obtained and set in the following fashion:

 $value = $user->field_name();
 $user->field_name( $some_value );

The available fields for a user object are:

=over 4

=item * email

=item * first_name

=item * group_ids

All the list utility methods provided by Class::MethodMaker are also available
for this field see L<Class::MethodMaker>

=item * last_name

=item * login

=item * mobile_phone

=item * password

=item * phone

=item * user_id (read-only)

The id of the current object in the database's user table

=back

=head2 METHODS

=over 4

=item * $user = Krang::User->new( %params )

Constructor for the module that relies on Krang::MethodMaker.  Validation of
'%params' is performed in init().  The valid fields for the hash are:

=over 4

=item * email

=item * first_name

=item * group_ids

=item * last_name

=item * login

=item * mobile_phone

=item * password

=item * phone

=back

=cut

# validates arguments passed to new(), see Class::MethodMaker
# the method croaks if we haven't been provied required params or if an
# invalid key is found in the hash passed to new()
sub init {
    my $self = shift;
    my %args = @_;
    my @bad_args;

    for (keys %args) {
        push @bad_args, $_ unless exists $user_args{$_};

    }
    croak(__PACKAGE__ . "->init(): The following constructor args are " .
          "invalid: '" . join("', '", @bad_args) . "'") if @bad_args;

    # required arg check...
    for (qw/login password/) {
        croak(__PACKAGE__ . "->init(): Required argument '$_' not present.")
          unless exists $args{$_};
    }

    $self->hash_init(%args);

    # set password
    $self->password($args{password});

    return $self;
}


=item * $user_id = Krang::User->check_user_pass( $login, $password )

Class method that retrieves the user object associated with $login and compares
the value in the objects 'password' field with md5_hex( $SALT, $password ).
If it is successful, the 'user_id' is returned, otherwise '0' is returned.

=cut

sub check_user_pass {
    my ($self, $login, $password) = @_;

    my ($user) = Krang::User->find(login => $login);
    return 0 unless $user;

    return md5_hex($SALT, $password) eq $user->{password} ?
      $user->{user_id} : 0;
}


=item * $success = $user->delete()

=item * $success = Krang::user->delete( $user_id )

Instance or class method that deletes the given user object from the database.
It returns '1' following a successful deletion.
# TO DO: what should we do if items belong to or are checked out by the current
# user

=cut

sub delete {
    my $self = shift;
    my $id = shift || $self->{user_id};
    my $dbh = dbh();

    # object reference lookup
    my ($dependents, %info) = $self->dependent_check();
    if ($dependents) {
        my $info = join("\n\t",
                        map {"$_: [" . join(",", @{$info{$_}}). "]"}
                        keys %info);
        croak(__PACKAGE__ . "->delete(): The following objects reference " .
              "this class:\n\t$info");
    }

    $dbh->do("DELETE FROM usr WHERE user_id = ?", undef, $id);
    $dbh->do("DELETE FROM usr_user_group WHERE user_id = ?", undef, $id);

    return 1;
}


=item * ($dependents, %info) = $user->dependent_check()

This method returns the number of dependents and a hash of classes and their
respective object ids that reference the current user object.  '0' and undef
will be returned if no references are found.

=cut

sub dependent_check {
    my $self = shift;
    my $id = $self->{user_id};
    my $dependents = 0;
    my ($dbh, %info, $oid, $sth);

    for my $class(qw/media template/) { # no find in Krang::Story yet
        my $module = ucfirst $class;
        no strict 'subs';
        my @objects = "Krang::$module"->find(checked_out_by => $id);
        if (@objects) {
            my $id_field = $class . "_id";
            $dependents += scalar @objects;
            push @{$info{$class}}, map {$_->$id_field} @objects;
        }
    }

    return ($dependents, %info);
}


=item * ($duplicates, %info) = $user->duplicate_check()

This method checks the database to see if any existing site objects possess any
of the same values as the one in memory.  If this is the case, the number of
duplicates and a hash of ids and the duplicated fields is returned; otherwise,
0 and undef are returned.

=cut

sub duplicate_check {
    my $self = shift;
    my $id = $self->{user_id};
    my $duplicates = 0;

    my $query = <<SQL;
SELECT user_id, login, password, first_name, last_name
FROM usr
WHERE login = ? OR password = ? OR (first_name = ? AND last_name = ?)
SQL

    my @params = ($self->{login}, $self->{password},
                  $self->{first_name}, $self->{last_name});

    # alter query if save() has already been called
    if ($id) {
        $query =~ s/login/user_id != ? AND login/;
        push @params, $id;
    }

    my $dbh = dbh();
    my $sth = $dbh->prepare($query);
    $sth->execute(@params);
    my (%info, $row);
    $sth->bind_columns(\(@$row{@{$sth->{NAME_lc}}}));
    while ($sth->fetchrow_arrayref()) {
        for (keys %$row) {
            no warnings;
            if ($self->{$_} eq $row->{$_}) {
                push @{$info{$row->{user_id}}}, $_;
                $duplicates++;
            }
        }
    }
    $sth->finish();

    return ($duplicates, %info);
}


=item * @users = Krang::User->find( %params )

=item * @users = Krang::User->find( user_id => [1, 1, 2, 3, 5] )

=item * @users = Krang::User->find( group_ids => [1, 1, 2, 3, 5] )

=item * @user_ids = Krang::User->find( ids_only => 1, %params )

=item * $count = Krang::User->find( count => 1, %params )

Class method that returns an array of user objects, user ids, or a
count.  Case-insensitive sub-string matching can be performed on any valid
field by passing an argument like: "fieldname_like => '%$string%'" (Note: '%'
characters must surround the sub-striqng).  The valid search fields are:

=over 4

=item * email

=item * first_name

=item * group_id

=item * last_name

=item * login

=item * mobile_phone

=item * phone

=item * user_id

=back

Additional criteria which affect the search results are:

=over 4

=item * ascend

Result set is sorted in ascending order.

=item * count

If this argument is specified, the method will return a count of the categories
matching the other search criteria provided.

=item * descend

Results set is sorted in descending order only if the 'ascend' option is not
specified.

=item * ids_only

Returns only user ids for the results found in the DB, not objects.

=item * limit

Specify this argument to determine the maximum amount of user objects or
user ids to be returned.

=item * offset

Sets the offset from the first row of the results to return.

=item * order_by

Specify the field by means of which the results will be sorted.  By default
results are sorted with the 'user_id' field.

=back

The method croaks if an invalid search criteria is provided or if both the
'count' and 'ids_only' options are specified.

=cut

sub find {
    my $self = shift;
    my %args = @_;
    my ($fields, @params, $where_clause);
    my %lookup_cols = %user_cols;
    $lookup_cols{group_ids} = 1;

    # are we looking up group ids as well
    my $groups = exists $args{group_ids} ? 1 : 0;

    # grab ascend/descending, limit, and offset args
    my $ascend = uc(delete $args{order_desc}) || ''; # its prettier w/uc() :)
    my $limit = delete $args{limit} || '';
    my $offset = delete $args{offset} || '';
    my $order_by = delete $args{order_by} || 'user_id';

    # set search fields
    my $count = delete $args{count} || '';
    my $ids_only = delete $args{ids_only} || '';

    # set bool to determine whether to use $row or %row for binding below
    my $single_column = $ids_only || $count ? 1 : 0;

    croak(__PACKAGE__ . "->find(): 'count' and 'ids_only' were supplied. " .
          "Only one can be present.") if ($count && $ids_only);

    # build list of fields to select
    if ($count) {
        $fields = 'count(*)';
    } elsif ($ids_only) {
        $fields = 'u.user_id';
    } else {
        $fields = join(", ", map {"u.$_"} keys %user_cols);
        $fields .= ", ug.user_group_id" if $groups;
    }

    # set up WHERE clause and @params, croak unless the args are in
    # USER_RO or USER_RW
    my @invalid_cols;
    for my $arg (keys %args) {
        # don't use element
        next if $arg eq 'password';

        my $like = 1 if $arg =~ /_like$/;
        ( my $lookup_field = $arg ) =~
          s/^(.+)_like$/($arg eq 'group' ? 'ug' : 'u'). $1/e;

        push @invalid_cols, $arg unless exists $lookup_cols{$lookup_field};

        if (($arg eq 'user_id' || $arg eq 'group_ids') &&
            ref $args{$arg} eq 'ARRAY') {
            my $field = $arg eq 'user_id' ? "u.user_id" : "ug.user_group_id";
            my $tmp = join(" OR ", map {"$field = ?"} @{$args{$arg}});
            $where_clause .= " ($tmp)";
            push @params, @{$args{$arg}};
        } else {
            my $and = defined $where_clause && $where_clause ne '' ?
              ' AND' : '';
            if ($args{$arg} eq '') {
                $where_clause .= "$and $lookup_field IS NULL";
            } else {
                $where_clause .= $like ? "$and $lookup_field LIKE ?" :
                  "$and $lookup_field = ?";
                push @params, $args{$arg};
            }
        }
    }

    croak("The following passed search parameters are invalid: '" .
          join("', '", @invalid_cols) . "'") if @invalid_cols;

    # construct base query
    my $query = "SELECT $fields FROM usr u";
    $query .= ", usr_user_group ug" if $groups;

    # add WHERE and ORDER BY clauses, if any
    if ($where_clause) {
        $query .= " WHERE " . ($groups ? "u.user_id = ug.user_id AND" : "")
          . "$where_clause";
    }
    $query .= " ORDER BY $order_by $ascend" if $order_by;

    # add LIMIT clause, if any
    if ($limit) {
        $query .= $offset ? " LIMIT $offset, $limit" : " LIMIT $limit";
    } elsif ($offset) {
        $query .= " LIMIT $offset, -1";
    }

    my $dbh = dbh();
    my $sth = $dbh->prepare($query);
    $sth->execute(@params);

    # holders for query results and new objects
    my ($row, @users);

    # bind fetch calls to $row or %$row
    # a possibly insane micro-optimization :)
    if ($single_column) {
        $sth->bind_col(1, \$row);
    } else {
        $sth->bind_columns(\( @$row{@{$sth->{NAME_lc}}} ));
    }

    # construct user objects from results
    my $id = 0;
    while ($sth->fetch()) {
        # if we just want count or ids
        if ($single_column) {
            push @users, $row;
        } else {
            if ($groups) {
                if ($id != $row->{user_id}) {
                    my %$hashref = map {$_ => $row->{$_}}
                      grep {$_ ne 'user_group_id'} keys %$row;
                    push @users, bless($hashref, $self);
                }
                push @{$users[$#users]->{group_ids}}, $row->{user_group_id};

                $id = $row->{user_id}
                  if ($id != $row->{user_id} || !defined $id);
            } else {
            push @users, bless({%$row}, $self);
            }

        }
    }

    # return number of rows if count, otherwise an array of ids or objects
    return $count ? $users[0] : @users;
}


=item * $md5_digest = $user->password()

=item * $md5_digest = $user->password( $password )

Method to get or set the password associated with a user object.  Returns
Digest::MD5->md5( $SALT . $password_string ) as a getter. Stores the same
in the DB as a setter.

=cut

sub password {
    my $self = shift;
    $self->{password} = md5_hex($SALT, $_[0]) if $_[0];
    return $self->{password};
}


=item * $user = $user->save()

Saves the contents of the user object in memory to the database.  'user_id'
will be defined if the call is successful.

The method croaks if the save would result in a duplicate object (i.e.
if any field value required to be unique is not found to be so).  It also
croaks if its database query affects no rows in the database.

=cut

sub save {
    my $self = shift;
    my $id = $self->{user_id} || 0;
    my @save_fields = grep {$_ ne 'user_id'} keys %user_cols;

    # check for duplicates
    my ($duplicates, %info) = $self->duplicate_check();
    if ($duplicates) {
        my $info = join("\n\t",
                        map {"id '$_': " .
                               join(", ", sort @{$info{$_}})}
                        keys %info) . "\n";
        croak(__PACKAGE__ . "->save(): This object duplicates the following " .
              "user objects:\n\t$info");
    }

    my $query;
    my $dbh = dbh();

    # the object has already been saved once if $id
    if ($id) {
        $query = "UPDATE usr SET " . join(", ", map {"$_ = ?"} @save_fields) .
          " WHERE user_id = ?";
    } else {
        # build insert query
        $query = "INSERT INTO usr (" . join(',', @save_fields) .
          ") VALUES (?" . ", ?" x (scalar @save_fields - 1) . ")";
    }

    # bind parameters
    my @params = map {$self->{$_}} @save_fields;

    # need user_id for updates
    push @params, $id if $id;

    # croak if no rows are affected
    croak(__PACKAGE__ . "->save(): Unable to save user object " .
          ($id ? "id '$id' " : '') . "to the DB.")
      unless $dbh->do($query, undef, @params);

    $self->{user_id} = $dbh->{mysql_insertid} unless $id;

    # associate user with groups if any
    if (exists $self->{group_ids}) {
        eval {
            $dbh->do("LOCK TABLES usr_user_group WRITE");
            $dbh->do("DELETE FROM usr_user_group WHERE user_id = ?",
                     undef, ($id));
            my $sth = $dbh->prepare("INSERT INTO usr_user_group VALUES " .
                                    "(?,?)");
            $sth->execute(($id, $_)) for @{$self->{group_ids}};
            $dbh->do("UNLOCK TABLES");
        };

        if (my $err = $@) {
            $dbh->do("UNLOCK TABLES");
            croak($err);
        }
    }

    return $self;
}


=back

=head1 TO DO

=head1 SEE ALSO

L<Krang>, L<Krang::DB>

=cut


my $quip = <<END;
Epitaph on a tyrant

Perfection, of a kind, was what he was after
And the poetry he invented was easy to understand;
He knew human folly like the back of his hand,
And was greatly interested in armies and fleets;
When he laughed, respectable senators burst with laughter,
And when he cried the little children died in the streets.

-- W. H. Auden
END
