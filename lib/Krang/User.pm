package Krang::User;

=head1 NAME

Krang::User - a means to access information on users

=head1 SYNOPSIS

  use Krang::ClassLoader 'User';

  # construct object
  my $user = Krang::User->new(email => 'a@b.com',		#optional
			      first_name => 'fname',		#optional
			      group_ids => [1, 2, 3],		#optional
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
  $user->password( $password );		# stores MD5 of $self->SALT, $password
  $user->phone( $phone_number );


  # delete the user from the database
  $user->delete();

  # a hash of search parameters
  my %params =
  ( order_desc => 1,		# result ascend unless this flag is set
    limit => 5,			# return 5 or less user objects
    offset => 1, 	        # start counting result from the
				# second row
    order_by => 'user_id'	# sort on the 'user_id' field
    login_like => '%fred%',	# match rows with 'login's LIKE '%fred'
    phone_like => '718%' );	# match rows with phone#'s LIKE '718%'

  # any valid object field can be appended with '_like' to perform a
  # case-insensitive sub-string match on that field in the database

  # returns an array of user objects matching criteria in %params
  my @users = pkg('User')->find( %params );

=head1 DESCRIPTION

Each user object corresponds to an authorized user of the system.  The degree
of access a user is determined by the groups with which he is associated.

N.B. - Passwords are MD5 digests of $self->SALT and the password string; the
original password string in not retrievable once it is passed but can only be
calculated and compared i.e.:

  my $valid_password =
    $user->{password} eq md5_hex($self->SALT, $password_string) ? 1 : 0;

=cut

#
# Pragmas/Module Dependencies
##############################
# Pragmas
##########
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

# External Modules
###################
use Carp qw(croak);
use Digest::MD5 qw(md5_hex);
use Exception::Class (
    'Krang::User::Duplicate'    => {fields => 'duplicates'},
    'Krang::User::Dependency'   => {fields => 'dependencies'},
    'Krang::User::InvalidGroup' => {fields => 'group_id'},
    'Krang::User::MissingGroup'
);

require Exporter;

# Internal Modules
###################
use Krang::ClassLoader DB   => qw(dbh);
use Krang::ClassLoader Log  => qw/critical debug info/;
use Krang::ClassLoader Conf => qw/PasswordChangeTime PasswordChangeCount/;
use Krang::ClassLoader 'UUID';
use Krang::ClassLoader 'Cache';

#
# Package Variables
####################

# In Krang v3.04 we've converted package constants, lexicals & globals into
# methods so that subclasses need not copy them, and can extend them without
# needing to know what they contain, and so that non-over-ridden methods here
# can see their subclassed values.
#
# This way, for instance, by adding a new field to USER_RW, a subclass
# need not override save(), find() and deserialize_xml() at all.
# They can all see the new field name in their loops, and just work.

# Read-only fields
sub USER_RO {
    return qw(
      user_id
      user_uuid
    );
}

# Read-write fields
sub USER_RW {
    return qw(
      email
      first_name
      last_name
      login
      mobile_phone
      phone
      hidden
      password_changed
      force_pw_change
    );
}

# user_user_group table fields
sub USER_USER_GROUP {
    return qw(
      user_id
      group_id
    );
}

# valid short logins :)
sub SHORT_NAMES {
    return qw(
      adam
      admin
      arobin
      matt
      sam
      krang
    );
}

sub SALT {
    return <<SALT;
Dulce et decorum est pro patria mori
--Horace
SALT
}

sub user_args {
    my $self = shift;
    return map { $_ => 1 } $self->USER_RW(), qw/group_ids password/;
}

sub user_cols {
    my $self = shift;
    return $self->USER_RO(), $self->USER_RW(), 'password';
}

# Constructor/Accessor/Mutator setup
use Krang::ClassLoader MethodMaker => new_with_init => 'new',
  new_hash_init                    => 'hash_init',
  get                              => [USER_RO],
  get_set                          => [USER_RW],
  list                             => 'group_ids';

sub id_meth   { 'user_id' }
sub uuid_meth { 'user_uuid' }

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

=item * user_uuid (read-only)

A unique id of the current object valid between systems when the
object is moved via krang_export/krang_import.

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

    my $encrypted = delete $args{encrypted} || '';

    for my $arg (keys %args) {
        push @bad_args, $arg unless grep $arg eq $_, $self->user_args;
    }
    croak(  __PACKAGE__
          . "->init(): The following constructor args are "
          . "invalid: '"
          . join("', '", @bad_args) . "'")
      if @bad_args;

    # required arg check...
    for (qw/login password/) {
        croak(__PACKAGE__ . "->init(): Required argument '$_' not present.")
          unless exists $args{$_};
    }

    # hidden defaults to 0
    $args{hidden} = 0 unless exists $args{hidden};

    $self->{user_uuid} = pkg('UUID')->new();

    $self->hash_init(%args);

    # set password
    $self->password($args{password}, $encrypted);

    return $self;
}

=item * $user_id = Krang::User->check_auth( $login, $password )

Class method that retrieves the user object associated with $login and compares
the value in the objects 'password' field with md5_hex( $self->SALT, $password ).
If it is successful, the 'user_id' is returned, otherwise '0' is returned.

=cut

sub check_auth {
    my ($self, $login, $password) = @_;

    my ($user) = pkg('User')->find(login => $login);
    return 0 unless $user;

    return md5_hex($self->SALT, $password) eq $user->{password} ? $user->{user_id} : 0;
}

=item * $match = $user->check_pass( $password )

=cut

sub check_pass {
    my ($user, $pass) = @_;

    return md5_hex($user->SALT, $pass) eq $user->{password} ? $user->{user_id} : 0;
}

=item * $success = $user->delete()

=item * $success = Krang::user->delete( $user_id )

Instance or class method that deletes the given user object from the database.
It returns '1' following a successful deletion.

N.B. - this call may result in an exception as it precipitates a call to
dependent check.  See $user->dependent_check().

=cut

sub delete {
    my $self = shift;
    my $id   = shift || $self->{user_id};
    my $dbh  = dbh();

    # don't delete if the user has something checked out
    if (ref $self) {
        $self->dependent_check();
    } else {
        $self->dependent_check($id);
    }

    $dbh->do("DELETE FROM user WHERE user_id = ?",                           undef, $id);
    $dbh->do("DELETE FROM user_group_permission WHERE user_id = ?",          undef, $id);
    $dbh->do("DELETE FROM user_category_permission_cache WHERE user_id = ?", undef, $id);
    $dbh->do("DELETE FROM alert WHERE user_id = ?",                          undef, $id);

    # we also need to delete all send schedule entries that might refer to this
    # user in it's context
    my $schedule_class = pkg('Schedule');
    eval "require $schedule_class";
    croak "Could not load $schedule_class: $@" if $@;

    my @scheduled = pkg('Schedule')->find(action => 'send');
    foreach my $schedule (@scheduled) {
        if ($schedule->context) {
            my %context = @{$schedule->context};
            if (exists $context{user_id} and $context{user_id} == $id) {
                $schedule->delete();
            }
        }
    }

    return 1;
}

=item * $user->dependent_check()

This method checks whether an objects are checked out by the current user.  If
this is the case a Krang::User::Dependency exception is thrown.
Krang::User::Dependency exceptions contain a 'dependencies' field that contains
a hash of class names and id of that class that depend on this User object.
One can handle such an exception thusly:

 eval {$user->dependent_check()};
 if ($@ && $@->isa('Krang::User::Dependency')) {
     my %dependencies = $@->dependencies;
     croak("The following objects depend on this user:\n\t" .
	   join("\n\t", map {"$_: " . join(",", @{$dependencies{$_}})}
		keys %dependencies));
 }

=cut

sub dependent_check {
    my $self       = shift;
    my $id         = shift || $self->{user_id};
    my $dependents = 0;
    my %info;

    for my $class ($self->dependent_class_list) {
        eval "require $class";
        die $@ if $@;

        my @objects = $class->find(checked_out_by => $id);
        if (@objects) {
            my $id_method = $class->id_meth();
            $dependents += scalar @objects;
            push @{$info{$class}}, map { $_->$id_method } @objects;
        }
    }

    Krang::User::Dependency->throw(
        message      => 'Objects depend on this user',
        dependencies => \%info
    ) if $dependents;

    return 0;
}

=item * dependent_class_list

Returns a list of classes to check for potential objects that could
be checked-out by users. This is called by C<dependent_check()> and mainly
exists to be overridden by addons.

Classes in this list must implement the C<find()> and C<id_meth()> methods.

=cut

sub dependent_class_list {
    my $self = shift;
    return (pkg('Media'), pkg('Story'), pkg('Template'));
}

=item * $user->duplicate_check()

This method checks the database to see if any existing site objects possess any
of the same values as the one in memory.  If this is the case, a
Krang::User::Duplicate exception is throw; otherwise, 0 and undef are returned.

Krang::User::Duplicate exception have a 'duplicates' field that contains info
about the object that would be duplicated.  One can handle the exception
thusly:

 eval {$user->duplicate_check()};
 if ($@ && $@->isa('Krang::User::Duplicate')) {
     my %duplicates = $@->duplicates;
     croak("The following objects are duplicated on this object:\n\t" .
	   join("\n\t", map {"$_: " . join(",", @{$duplicates{$_}})}
		keys %duplicates));
 }

=cut

sub duplicate_check {
    my $self  = shift;
    my $id    = $self->{user_id};
    my $query = <<SQL;
SELECT user_id, login
FROM user
WHERE login = ?
SQL
    my @params = map { $self->{$_} } qw/login/;

    # alter query if save() has already been called
    if ($id) {
        $query =~ s/WHERE /WHERE user_id != ? AND (/;
        $query .= ")";
        unshift @params, $id;
    }

    my $dbh = dbh();
    my $sth = $dbh->prepare($query);
    $sth->execute(@params);

    my (%info, $row);
    my $duplicates = 0;

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

    Krang::User::Duplicate->throw(
        message    => 'This object duplicates one or ' . 'more User objects',
        duplicates => \%info
    ) if $duplicates;

    return $duplicates;
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

=item * login

=item * email

=item * first_name

=item * group_id

=item * last_name

=item * login

=item * mobile_phone

=item * phone

=item * user_id

=item * user_uuid

=item * simple_search

Searches first_name, last_name and login for matching LIKE strings

=back

Additional criteria which affect the search results are:

=over 4

=item * ascend

Result set is sorted in ascending order.

=item * count

If this argument is specified, the method will return a count of the categories
matching the other search criteria provided.

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

=item * order_desc

Set this flag to '1' to sort results relative to the 'order_by' field in
descending order, by default results sort in ascending order

=back

The method croaks if an invalid search criteria is provided or if both the
'count' and 'ids_only' options are specified.

=cut

sub find {
    my $self = shift;
    my %args = @_;
    my ($fields, @params);
    my @lookup_cols  = $self->user_cols;
    my $where_clause = '';
    push @lookup_cols, 'group_ids';

    # check the cache if we're looking for a single user
    my $cache_worthy = (keys(%args) == 1 and exists $args{user_id}) ? 1 : 0;
    if ($cache_worthy) {
        my $user = pkg('Cache')->get('Krang::User' => $args{user_id});
        return ($user) if $user;
    }

    # are we looking up group ids as well
    my $groups = exists $args{group_ids} ? 1 : 0;

    # grab ascend/descending, limit, and offset args
    my $ascend = delete $args{order_desc} ? 'DESC' : 'ASC';
    my $limit    = delete $args{limit}    || '';
    my $offset   = delete $args{offset}   || '';
    my $order_by = delete $args{order_by} || 'user_id';
    $order_by = ($order_by eq 'group_id' ? "ug." : "u.") . $order_by;

    # set search fields
    my $count    = delete $args{count}    || '';
    my $ids_only = delete $args{ids_only} || '';

    # set bool to determine whether to use $row or %row for binding below
    my $single_column = $ids_only || $count ? 1 : 0;

    croak(  __PACKAGE__
          . "->find(): 'count' and 'ids_only' were supplied. "
          . "Only one can be present.")
      if ($count && $ids_only);

    # build list of fields to select
    if ($count) {
        $fields = 'count(*)';
    } elsif ($ids_only) {
        $fields = 'u.user_id';
    } else {
        $fields = join(", ", map { "u.$_" } $self->user_cols);
    }

    # set up WHERE clause and @params, croak unless the args are in
    # USER_RO or USER_RW
    my @invalid_cols;
    for my $arg (keys %args) {

        # don't use element
        next if $arg eq 'password';

        my $like = 1 if $arg =~ /_like$/;
        (my $lookup_field = $arg) =~ s/^(.+)_like$/($arg eq 'group' ? 'ug' : 'u'). $1/e;

        push @invalid_cols, $arg
          unless $arg eq 'simple_search'
              or grep $lookup_field eq $_, @lookup_cols;

        my $and = defined $where_clause && $where_clause ne '' ? ' AND' : '';

        if (($arg eq 'user_id' || $arg eq 'group_ids')
            && ref $args{$arg} eq 'ARRAY')
        {
            my $field = $arg eq 'user_id' ? "u.user_id" : "ug.group_id";
            my $tmp = join(" OR ", map { "$field = ?" } @{$args{$arg}});
            $where_clause .= "$and ($tmp)";
            push @params, @{$args{$arg}};
        } elsif ($arg eq 'simple_search') {
            my @words = split(/\s+/, $args{$arg});
            for (@words) {
                $where_clause .= ($where_clause ? " AND " : '')
                  . "concat(u.first_name, ' ', u.last_name, ' ', u.login) LIKE ?";
                push @params, "%" . $_ . "%";
            }
        } else {

            # prepend 'u' or 'ug'
            $lookup_field = ($arg eq 'group_id' ? "ug." : "u.") . $lookup_field;
            if (not defined $args{$arg}) {
                $where_clause .= "$and $lookup_field IS NULL";
            } else {
                $where_clause .=
                  $like
                  ? "$and $lookup_field LIKE ?"
                  : "$and $lookup_field = ?";
                push @params, $args{$arg};
            }
        }
    }

    croak(
        "The following passed search parameters are invalid: '" . join("', '", @invalid_cols) . "'")
      if @invalid_cols;

    # revise $from and/or $where_clause
    my $from = "user u";
    if ($groups) {
        $from .= ", user_group_permission ug";
        $where_clause = "u.user_id = ug.user_id AND " . $where_clause;
    }

    # setup base query
    # distinct so we don't return duplicates which is a definite possiblity
    # with multiple 'group_ids'
    my $query = "SELECT distinct $fields FROM $from";

    # add WHERE and ORDER BY clauses, if any
    $query .= " WHERE $where_clause"        if $where_clause;
    $query .= " ORDER BY $order_by $ascend" if $order_by;

    # add LIMIT clause, if any
    if ($limit) {
        $query .= $offset ? " LIMIT $offset, $limit" : " LIMIT $limit";
    } elsif ($offset) {
        $query .= " LIMIT $offset, 18446744073709551615";
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
        $sth->bind_columns(\(@$row{@{$sth->{NAME_lc}}}));
    }

    # construct user objects from results
    my $id = 0;
    while ($sth->fetch()) {

        # if we just want count or ids
        if ($single_column) {
            push @users, $row;
        } else {
            push @users, bless({%$row}, $self);
        }
    }

    # associate group_ids with user objects
    unless ($count or $ids_only) {
        my %user_hash = map { $_->{user_id} => $_ } @users;
        _add_group_ids(\%user_hash, $dbh);
    }

    # set in the cache if this was a simple find
    pkg('Cache')->set('Krang::User' => $args{user_id} => $users[0])
      if $cache_worthy and $users[0];

    # return number of rows if count, otherwise an array of ids or objects
    return $count ? $users[0] : @users;
}

=item * $md5_digest = $user->password()

=item * $md5_digest = $user->password( $password )

=item * $md5_digest = Krang::User->password( $password )

=item * $md5_digest = Krang::User->password( $password, 1 )

Method to get or set the password associated with a user object.  Returns
Digest::MD5->md5( $self->SALT . $password_string ) as a getter. Stores the same
in the DB as a setter. As a class method it returns an md5 digest of its
argument. If a true argument is passed in after the first 'password' arg,
the password is not encrypted (assumed to be already).

=cut

sub password {
    my $self = shift;
    return $self->{password} unless @_;
    my $pass = $_[1] ? $_[0] : md5_hex($self->SALT, $_[0]);
    if ((ref $self) && $pass) {

        # record that this password was updated
        my $old_pw = $self->{password};
        $self->{password} = $pass;
        $self->password_changed(scalar time);
        $self->force_pw_change(0);

        # store the old one in the old_passwords table if this is an
        # actual user with an old pw and not a temp user stored in the
        # session while being created by the UI
        if (PasswordChangeCount && $old_pw && $self->user_id) {

            # get all of our old password and remove the oldest ones
            # if we have too many
            my $sth =
              dbh()
              ->prepare_cached(
                'SELECT password FROM old_password WHERE user_id = ? ORDER BY timestamp DESC');
            $sth->execute($self->user_id);
            my $old_pws = $sth->fetchall_arrayref();
            if (scalar @$old_pws > (PasswordChangeCount - 1)) {

                # delete any we don't want
                foreach my $i ((PasswordChangeCount - 2) .. $#$old_pws) {
                    dbh->do(
                        'DELETE FROM old_password WHERE user_id = ? AND password = ?',
                        undef, $self->user_id, $old_pws->[0]->[0],
                    );
                }
            }

            # remember the latest old one
            $sth = dbh->prepare_cached('INSERT INTO old_password (user_id, password) VALUES (?,?)');
            $sth->execute($self->user_id, $old_pw);
        }
    }
    return $pass;
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

    my %args = @_;
    my $update_cache = exists $args{update_cache} ? $args{update_cache} : 1;

    my $id = $self->{user_id} || 0;
    my @save_fields = grep { $_ ne 'user_id' } $self->user_cols;

    # saving with the cache on is verboten
    if (pkg('Cache')->active()) {
        croak(  "Cannot save users while cache is on!  This cache was started at "
              . join(', ', @{pkg('Cache')->stack(-1)})
              . ".");
    }

    # check for duplicates
    $self->duplicate_check();

    # validate group ids, throws InvalidGroup exception if we've got a
    # non-extant group in the 'group_ids' field
    $self->_validate_group_ids();

    my $query;
    my $dbh = dbh();

    # the object has already been saved once if $id
    if ($id) {
        $query =
          "UPDATE user SET " . join(", ", map { "$_ = ?" } @save_fields) . " WHERE user_id = ?";
    } else {

        # build insert query
        $query =
            "INSERT INTO user ("
          . join(',', @save_fields)
          . ") VALUES (?"
          . ", ?" x (scalar @save_fields - 1) . ")";
    }

    # bind parameters
    my @params = map { $self->{$_} } @save_fields;

    # need user_id for updates
    push @params, $id if $id;

    # croak if no rows are affected
    croak(  __PACKAGE__
          . "->save(): Unable to save user object "
          . ($id ? "id '$id' " : '')
          . "to the DB.")
      unless $dbh->do($query, undef, @params);

    $self->{user_id} = $dbh->{mysql_insertid} unless $id;
    $id = $self->{user_id};

    # remove and add group associations
    eval {
        $dbh->do("LOCK TABLES user_group_permission WRITE");
        $dbh->do("DELETE FROM user_group_permission WHERE user_id = ?", undef, ($id));

        # associate user with groups, if any
        foreach my $gid (@{$self->{group_ids}}) {
            $dbh->do(qq/ INSERT INTO user_group_permission (user_id,group_id) VALUES (?,?) /,
                undef, $id, $gid);
        }

        $dbh->do("UNLOCK TABLES");
    };

    if (my $err = $@) {
        $dbh->do("UNLOCK TABLES");
        croak($err);
    }

    # lazy load Group so using User won't load element
    # sets, which is sometimes bad
    eval "require " . pkg('Group') or die $@;

    # Update user permissions cache, unless the caller asked us not to...
    debug "skipping pkg(Group)->add_user_permissions()\n" unless $update_cache;
    pkg('Group')->add_user_permissions($self) if $update_cache;

    return $self;
}

# looks up associate group_ids with the given User object
sub _add_group_ids {
    my ($users_href, $dbh) = @_;
    my $query = <<SQL;
SELECT group_id FROM user_group_permission
WHERE user_id = ?
SQL
    my $sth = $dbh->prepare($query);

    while (my ($id, $obj) = each %$users_href) {
        my $gid;
        $sth->execute($id);
        $sth->bind_col(1, \$gid);
        push @{$obj->{group_ids}}, $gid while $sth->fetch();
    }
}

# validate 'group_ids' field
# returns either an exception or a hash of group_ids and permission_types
sub _validate_group_ids {
    my $self = shift;
    my (@bad_groups, %types);

    my $rgroup_ids = $self->{group_ids};

    # Throw exception if no groups
    Krang::User::MissingGroup->throw(message => 'No groups specified for this user')
      unless (defined($rgroup_ids) and @$rgroup_ids);

    foreach my $group_id (@$rgroup_ids) {

        # lazy load Group so using User won't load element
        # sets, which is sometimes bad
        eval "require " . pkg('Group') or die $@;
        my ($found_group) = pkg('Group')->find(group_id => $group_id, count => 1);
        push(@bad_groups, $group_id) unless ($found_group);
    }

    # Throw exception if bad groups
    Krang::User::InvalidGroup->throw(
        message  => 'Invalid group_id in object',
        group_id => \@bad_groups
    ) if @bad_groups;
}

=item * $user->serialize_xml(writer => $writer, set => $set)

Serialize as XML.  See Krang::DataSet for details.

=cut

sub serialize_xml {
    my ($self,   %args) = @_;
    my ($writer, $set)  = @args{qw(writer set)};
    local $_;

    # open up <template> linked to schema/template.xsd
    $writer->startTag(
        'user',
        "xmlns:xsi"                     => "http://www.w3.org/2001/XMLSchema-instance",
        "xsi:noNamespaceSchemaLocation" => 'user.xsd'
    );

    $writer->dataElement(user_id   => $self->{user_id});
    $writer->dataElement(user_uuid => $self->{user_uuid})
      if $self->{user_uuid};
    $writer->dataElement(login        => $self->{login});
    $writer->dataElement(password     => $self->{password});
    $writer->dataElement(first_name   => $self->{first_name});
    $writer->dataElement(last_name    => $self->{last_name});
    $writer->dataElement(email        => $self->{email});
    $writer->dataElement(phone        => $self->{phone});
    $writer->dataElement(mobile_phone => $self->{mobile_phone});
    $writer->dataElement(hidden       => $self->{hidden});

    # lazy load Group so using User won't load element
    # sets, which is sometimes bad
    eval "require " . pkg('Group') or die $@;

    my $group_ids = $self->{group_ids};
    foreach my $group_id (@$group_ids) {
        $writer->dataElement(group_id => $group_id);
        $set->add(object => (pkg('Group')->find(group_id => $group_id))[0], from => $self);
    }

    # get alerts for this user
    my @alerts = pkg('Alert')->find(user_id => $self->{user_id});
    foreach my $alert (@alerts) {
        $set->add(object => $alert, from => $self);
    }

    # all done
    $writer->endTag('user');
}

=item * C<< $user = Krang::User->deserialize_xml(xml => $xml, set => $set, no_update => 0) >>

Deserialize XML.  See Krang::DataSet for details.

If an incoming user has the same login as an existing user then an
update will occur, unless no_update is set.

=cut

sub deserialize_xml {
    my ($pkg, %args) = @_;
    my ($xml, $set, $no_update) = @args{qw(xml set no_update)};

    my %fields = map { ($_, 1) } USER_RW;

    # parse it up
    my $data = pkg('XML')->simple(
        xml           => $xml,
        suppressempty => 1,
        forcearray    => ['group_id']
    );

    # is there an existing object?
    my $user;

    # start with UUID lookup
    if (not $args{no_uuid} and $data->{user_uuid}) {
        ($user) = $pkg->find(user_uuid => $data->{user_uuid});

        # if not updating this is fatal
        Krang::DataSet::DeserializationFailed->throw(
            message => "A user object with the UUID '$data->{user_uuid}' already"
              . " exists and no_update is set.")
          if $user and $no_update;
    }

    # proceed to login lookup if no dice
    unless ($user or $args{uuid_only}) {
        ($user) = pkg('User')->find(login => $data->{login});

        # if not updating this is fatal
        Krang::DataSet::DeserializationFailed->throw(
            message => "A user object with the login '$data->{login}' already "
              . "exists and no_update is set.")
          if $user and $no_update;
    }

    if ($user) {
        debug(__PACKAGE__ . "->deserialize_xml : found user");

        # update simple fields
        $user->{$_} = $data->{$_} for keys %fields;
        $user->password($data->{password}, 1);
    } else {
        $user = pkg('User')->new(
            password  => $data->{password},
            encrypted => 1,
            (map { ($_, $data->{$_}) } keys %fields)
        );
    }

    # preserve UUID if available
    $user->{user_uuid} = $data->{user_uuid}
      if $data->{user_uuid} and not $args{no_uuid};

    my @group_ids = @{$data->{group_id}};
    my @new_group_ids;
    foreach my $g (@group_ids) {
        push(@new_group_ids, $set->map_id(class => pkg('Group'), id => $g));
    }
    $user->group_ids(@new_group_ids);

    $user->save;
}

=item * C<< $user->may_delete_user($other_user_obj) >>

=item * C<< $user->may_delete_user($other_user_id) >>

Convenience method accepting a Krang::User object or a user
id. Returns true if the calling user may delete the given user, false
otherwise. This method may be used in Krang::CGI::User to prevent CGI
param tampering.

=cut

sub may_delete_user {
    my ($self, $user) = @_;

    # we are fine if we have global user admin perms
    return 1 unless pkg('Group')->user_admin_permissions('admin_users_limited');

    # make sure we have a Krang::User object
    ($user) = pkg('User')->find(user_id => $user)
      unless ref($user) && $user->isa('Krang::User');

    # get our groups...
    my %curr_user_group_id = map { $_ => 1 } $self->group_ids;
    my %curr_user_group_for =
      map { $_ => pkg('Group')->find(group_id => $_) } keys %curr_user_group_id;

    # ... and the targeted user's groups
    my @target_user_group_ids = $user->group_ids;

    # verify if we may manage any group the targeted user is in
    for my $gid (@target_user_group_ids) {
        return unless $curr_user_group_id{$gid};

        return 1 if $curr_user_group_for{$gid}->admin_users_limited;
    }

    return;
}

=item * C<< $current_user = pkg('User')->current_user_group_ids >>

=item * C<< $current_user = $other_user->current_user_group_ids >>

Convenience method returning the group_ids for the logged in user.

=cut

sub current_user_group_ids {
    my $user_id = $ENV{REMOTE_USER}
      || croak("No user_id in session");
    return (pkg('User')->find(user_id => $user_id))[0]->group_ids;
}

=item * C<< $user->display_name >>

Show's a user friendly display name for this person. This consists
of their first and last name (if they have it) else falling back to
their username.

=cut

sub display_name {
    my $self = shift;
    my $first = $self->first_name;
    my $last = $self->last_name;
    if( $first && $last ) {
        return "$first $last";
    } elsif( $first ) {
        return $first;
    } elsif( $last ) {
        return $last;
    } else {
        return $self->login;
    }
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
