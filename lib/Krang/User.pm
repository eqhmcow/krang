package Krang::User;

=head1 NAME

Krang::User - a means to access information on users

=head1 SYNOPSIS

  use Krang::User;

  # construct object
  my $user = Krang::User->new(email => 'a@b.com',		#optional
			      first_name => 'fname',		#optional
			      group_id => [1, 2, 3],		#optional
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
  my \@group_ids = $user->group_id();
  my $last_name = $user->last_name();
  my $login	= $user->login();
  my $password	= $user->password();
  my $phone	= $user->phone();

  my $id 	= $user->user_id();	# undef until save()

  # setters
  ##########
  $user->first_name( 'first_name' );
  $user->group_id( \@ids );
  $user->last_name('last_name');
  $user->login( 'loginX' );
  $user->mobile_phone( $phone_number );
  $user->password( $password );		# stores MD5 of $SALT and $password
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
    _like => '%fred%' );

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
    $user->{password} eq md5($SALT, $password_string) ? 1 : 0;

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
use Digest::MD5 qw(md5);

# Internal Modules
###################
use Krang;
use Krang::DB qw(dbh);

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

# Lexicals
###########
my %user_args = map {$_ => 1} USER_RW, qw/group_id password/;
my %user_cols = map {$_ => 1} USER_RO, USER_RW, 'password';

# Constructor/Accessor/Mutator setup
use Krang::MethodMaker	new_with_init => 'new',
			new_hash_init => 'hash_init',
			get => [USER_RO],
			get_set => [USER_RW];


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

=item * group_id

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

=item * group_id

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
    for (qw/first_name last_name login password/) {
        croak(__PACKAGE__ . "->init(): Required argument '$_' not present.")
          unless exists $args{$_};
    }

    $self->hash_init(%args);

    # set password and group_ids
    $self->password($args{password});
    $self->{group_id} = [$args{group_id}];

    return $self;
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

    $dbh->do("DELETE FROM user WHERE user_id = ?", undef, ($id));
    $dbh->do("DELETE FROM user_user_group WHERE user_id = ?", undef, ($id));

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
    my ($dbh, $uid, %info, $sth);
    my $query = "SELECT %s_id FROM %s WHERE checked_out_by = ?";

    for (qw/media story template/) {
        $dbh = dbh();
        $sth = $dbh->prepare(sprintf($query, $_, $_));
        $sth->execute(($id));
        $sth->bind_columns(1, \$uid);
        while ($sth->fetch()) {
            push @{$info{$_}}, $uid;
            $dependents++;
        }
        $sth->finish();
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
SELECT login, password, first_name || last_name AS name
FROM user
WHERE login = ? OR password = ? OR name = ?
SQL

    my @params = ($self->{login}, $self->{password},
                  $self->{first_name} . $self->{last_name});

    # alter query if save() has already been called
    if ($id) {
        $query .=  "AND user_id != ?\n";
        push @params, $id;
    }

    my $dbh = dbh();
    my $sth = $dbh->prepare($query);
    $sth->execute(@params);
    my (%info, $row);
    $sth->bind_columns(\(@$row{@{$sth->{NAME_lc}}}));
    while ($sth->fetchrow_arrayref()) {
        for (keys %$row) {
            if ($self->{$_} && $self->{$_} eq $row->{$_}) {
                $info{$row->{user_id}} = $_;
                $duplicates++;
            }
        }
    }
    $sth->finish();

    return ($duplicates, %info);
}


=item * @users = Krang::User->find( %params )

=item * @users = Krang::User->find( user_id => [1, 1, 2, 3, 5] )

=item * @users = Krang::User->find( group_id => [1, 1, 2, 3, 5] )

=item * @user_ids = Krang::User->find( ids_only => 1, %params )

=item * $count = Krang::User->find( count => 1, %params )

Class method that returns an array of user objects, user ids, or a
count.  Case-insensitive sub-string matching can be performed on any valid
field by passing an argument like: "fieldname_like => '%$string%'" (Note: '%'
characters must surround the sub-string).  The valid search fields are:

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

    # are we looking up group ids as well
    my $groups = exists $args{group_id} ? 1 : 0;

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

    # exclude 'element'
    $fields = $count ? 'count(*)' :
      ($ids_only ? 'user_id' : join(", ", grep {$_ ne 'element'}
                                        keys %user_cols));

    # set up WHERE clause and @params, croak unless the args are in
    # USER_RO or USER_RW
    my @invalid_cols;
    for my $arg (keys %args) {
        # don't use element
        next if $arg eq 'element';

        my $like = 1 if $arg =~ /_like$/;
        ( my $lookup_field = $arg ) =~
          s/^(.+)_like$/($arg eq 'group' ? 'ug' : 'u'). $1/e;

        push @invalid_cols, $arg unless exists $user_cols{$lookup_field};

        if (($arg eq 'user_id' || $arg eq 'group_id') &&
            ref $args{$arg} eq 'ARRAY') {
            my $field = $arg eq 'user_id' ? "u.user_id" : "ug.user_group_id";
            my $tmp = join(" OR ", map {"$field = ?"} @{$args{$arg}});
            $where_clause .= " ($tmp)";
            push @params, @{$args{$arg}};
        } else {
            my $and = defined $where_clause && $where_clause ne '' ?
              ' AND' : '';
            $where_clause .= $like ? "$and $lookup_field LIKE ?" :
              "$and $lookup_field = ?";
            push @params, $args{$arg};
        }
    }

    croak("The following passed search parameters are invalid: '" .
          join("', '", @invalid_cols) . "'") if @invalid_cols;

    # construct base query
    my $query = "SELECT $fields FROM user u";
    $query .= ", user_user_group ug" if $groups;

    # add WHERE and ORDER BY clauses, if any
    $query .= " WHERE $where_clause" if $where_clause;
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
    while ($sth->fetchrow_arrayref()) {
        # if we just want count or ids
        if ($single_column) {
            push @users, $row;
        } else {
            push @users, bless({%$row}, $self);
        }
    }

    # finish statement handle
    $sth->finish();

    # return number of rows if count, otherwise an array of ids or objects
    return $count ? $users[0] : @users;
}


=item * \@group_ids = $user->group_ids()

=item * $user = $user->group_ids( \@group_ids )

Method that returns a list of group ids as getter.  As a setter it accepts a
list of group ids and returns the user object.  The method may croak if it is
unable to lock the user_user_group table on write.

=cut

sub group_ids {
    my $self = shift;
    my $gids = shift || 0;

    if ($gids) {
        my $id = $self->{user_id};
        my $dbh = dbh();
        eval {
            $dbh->do("LOCK TABLES user_user_group WRITE");
            $dbh->do("DELETE FROM user_user_group WHERE user_id = ?",
                     undef, ($id));
            my $sth = $dbh->prepare("INSERT INTO user_user_group VALUES " .
                                    "(?,?)");
            $sth->execute(($id, $_)) for @$gids;
            $dbh->do("UNLOCK TABLES");

            $self->{group_ids} = $gids;
        };

        if (my $err = $@) {
            $dbh->do("UNLOCK TABLES");
            croak($err);
        }
    }

    return $gids ? $self : $self->{group_ids};
}


# Either the fieldname 'login' or this method would have to change, I thought
# the method would be easier...
=item * $true_or_false = Krang::User->logon( $login, $password )

Class method that retrieves the user object associated with $login and compares
the value in the objects 'password' field with md5( $SALT, $password ).

=cut

sub logon {
    my ($self, $login, $password) = @_;
    my $retval = 0;

    my ($user) = Krang::User->find(login => $login);
    return 0 unless $user;

    return md5($SALT, $password) eq $user->{password} ? 1 : 0;
}


=item * $md5_digest = $user->password()

=item * $md5_digest = $user->password( $password )

Method to get or set the password associated with a user object.  Returns
Digest::MD5->md5( $SALT . $password_string ) as a getter. Stores the same
in the DB as a setter.

=cut

sub password {
    my $self = shift;
    $self->{password} = md5($SALT, $_[0]) if $_[0];
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
        my $info = join("\n\t", map {"id '$_': $info{$_}"} keys %info) . "\n";
        croak(__PACKAGE__ . "->save(): This object duplicates the following " .
              "user objects:\n\t$info");
    }

    my $query;
    my $dbh = dbh();

    # the object has already been saved once if $id
    if ($id) {
        $query = "UPDATE user SET " . join(", ", map {"$_ = ?"} @save_fields) .
          " WHERE user_id = ?";
    } else {
        # build insert query
        $query = "INSERT INTO user (" . join(',', @save_fields) .
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
    $self->group_id($self->{group_id}) if exists $self->{group_id};

    return $self;
}


=back

=head1 TO DO

=head1 SEE ALSO

L<Krang>, L<Krang::DB>

=cut


my $quip = <<END;
Casey At The Bat

It looked extremely rocky for the Mudville nine that day;
The score stood two to four, with but an inning left to play.
So, when Cooney died at second, and Burrows did the same,
A pallor wreathed the features of the patrons of the game.

A straggling few got up to go, leaving there the rest,
With that hope which springs eternal within the human breast.
for they thought: "If only Casey could get a whack at that,"
they'd put even money now, with Casey at the bat.

But Flynn preceded Casey, and likewise so did Blake,
And the former was a pudd'n and the latter was a fake.
So on that stricken multitude a deathlike silence sat;
For there seemed but little chance of Casey's getting to the bat.

But Flynn let drive a "single," to the wonderment of all.
And the much-despised Blakey "tore the cover off the ball."
And when the dust had lifted, and they saw what had occurred,
There was Blakey safe at second, and Flynn a-huggin' third.

Then from the gladdened multitude went up a joyous yell--
It rumbled in the mountaintops, it rattled in the dell;
It struck upon the hillside and rebounded on the flat;
For Casey, mighty Casey was advancing to the bat.

There was ease in Casey's manner as he stepped into his place,
There was pride in Casey's bearing and a smile on Casey's face;
And when responding to the cheers he lightly doffed his hat.
No stranger in the crowd could doubt 'twas Casey at the bat."

Ten thousand eyes were on him as he rubbed his hands with dirt,
Five thousand tongues applauded when he wiped them on his shirt;
Then when the writhing pitcher ground the ball into his hip,
Defiance glanced in Casey's eye, a sneer curled Casey's lip.

And now the leather-covered sphere came hurtling through the air,
And Casey stood a watching it in haughty grandeur there.
Close by the sturdy batsman the ball unheeded sped;
"That ain't my style," said Casey. "Strike one," the umpire said.

From the benches, black with people, there went up a muffled roar,
Like the beating of the storm waves on the stern and distant shore.
"Kill him! kill the umpire!" shouted someone on the stand;
And it's likely they'd have killed him had not Casey raised his hand.

With a smile of Christian charity great Casey's visage shone;
He stilled the rising tumault, he made the game go on;
He signaled to the pitcher, and once more the spheroid flew;
But Casey still ignored it, and the umpire said, "Strike Two."

"Fraud!" cried the maddened thousands, and the echo answered "Fraud!"
But one scornful look from Casey and the audience was awed;
They saw his face grow stern and cold, they saw his muscles strain,
And they knew that Casey wouldn't let the ball go by again.

The sneer is gone from Casey's lips, his teeth are clenched in hate,
He pounds with cruel violence his bat upon the plate;
And now the pitcher holds the ball, and now he lets it go,
And now the air is shattered by the force of Casey's blow.

Oh, somewhere in this favored land the sun is shining bright,
The band is playing somewhere, and somewhere hearts are light;
And somewhere men are laughing, and somewhere children shout,
But there is no joy in Mudville: Mighty Casey has struck out.

-- Ernest Lawrence Thayer
END
