use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader 'Script';
use Krang::ClassLoader 'Site';
use Krang::ClassLoader 'Template';
use Krang::ClassLoader 'Schedule';
use Krang::ClassLoader 'Alert';
use Krang::ClassLoader DB => qw(dbh);

use Test::More qw(no_plan);
use Carp qw(croak);
use Time::Piece;

BEGIN {
    use_ok(pkg('User'));
}

# Constructor tests
####################
# failures
###########
# invalid field
my $user;
eval {
    $user = pkg('User')->new(login => 'login',
                             password => 'pwd',
                             crunk => 'X');
};
is($@ =~ /constructor args are invalid: 'crunk'/, 1, 'new() - invalid field');

# successes
############
my $admin = pkg('User')->new(login => 'admin',
                             password => 'whale');
$user = pkg('User')->new(login => 'arobin',
                         password => 'gIMp');

# save() tests
###############
# failure 1
eval {$admin->save()};
isa_ok($@, 'Krang::User::Duplicate');
is($@ =~ /This object duplicates/s, 1, 'save() - duplicate check');

# failure 2
$user->group_ids_push('x');
eval {$user->save()};
isa_ok($@, 'Krang::User::InvalidGroup');
is($@ =~ /Invalid group_id in object/s, 1, 'save() - invalid group_id check');

# Check save w/o groups
$user->group_ids_clear();
eval { $user->save() };
isa_ok($@, 'Krang::User::MissingGroup', "Not allowed to save user without groups.  Exception");

# success
$user->group_ids_push(1);
$user->save();
like($user->user_id(), qr/^\d+$/, 'save() - success');
ok($user->user_uuid());

# getters
##########
{
    no strict 'subs';
    is($user->$_, undef, "getter - $_")
      for qw/email first_name last_name mobile_phone phone/;
}
is(scalar(@{$user->group_ids}), 1, 'getter - group_ids()');

# make sure our id_meth and uuid_meth are correct
my $method = $user->id_meth;
is($user->$method, $user->user_id, 'id_meth() is correct');
$method = $user->uuid_meth;
is($user->$method, $user->user_uuid, 'uuid_meth() is correct');

# setters
##########
$user->group_ids(1, 2, 3);
$user->save();
my @gids = $user->group_ids();
for my $i(0..$#gids) {
    is($gids[$i] == $i + 1, 1, "setter - group_ids $i");
}
for (qw/email first_name last_name mobile_phone phone/) {
    no strict 'subs';
    my $val = rand(10);
    $user->$_($val);
    is($user->$_, $val, "setter - $_");
}

# find() tests
###############
($admin) = pkg('User')->find(login => 'system', hidden => 1);
isa_ok($admin, 'Krang::User', 'find() - login');

# make sure email is '' for testing
my $email = $admin->email;
$admin->email(undef);
eval {$admin->save};
croak("Very Bad things: $@") if $@;
my $count = pkg('User')->find(login => 'system', hidden => 1, count => 1);

is($count, 1, 'find - all fields');

my @users = pkg('User')->find(email => undef);
isa_ok($_, 'Krang::User') for @users;
is(scalar @users, 2, 'find - count');

# revert email field
$admin->email($email);
eval {$admin->save};
croak("Very Bad things: $@") if $@;

@users = pkg('User')->find(order_by => 'login');
my @u = sort {$a->{login} cmp $b->{login}} @users;
is($users[0]->login, $u[0]->login, 'find - order_by');

@users = pkg('User')->find(limit => 1);
is(scalar @users, 1, 'find - limit');

@users = pkg('User')->find(group_ids => [1,2,3], login => 'arobin');
isa_ok($_, 'Krang::User') for @users;
is($users[0]->login, 'arobin', 'find - group_ids');
is(scalar @{$users[0]->group_ids()}, 3, 'group_ids - count');

# check_user_pass() tests
##########################
# make sure the admin's username and password are 'admin' and 'whale'
# preserve values for restoration
my ($clogin, $cpass) = map {$admin->$_} qw/login password/;
$admin->login('system');
$admin->password('whale');
eval {$admin->save();};
croak("Won't complete tests bad things have happened: $@") if $@;

is(pkg('User')->check_auth('',''), 0, 'check_auth() - failure 1');
is(pkg('User')->check_auth('system',''), 0, 'check_auth() - failure 2');
ok(pkg('User')->check_auth('system', 'whale'), 'check_auth() - success');

# revert values
$admin->login($clogin);
$admin->{password} = $cpass;
eval {$admin->save();};
croak("Won't complete tests bad things have happened: $@") if $@;


# delete() tests
#################
# create objects to force a delete failure
my $site = pkg('Site')->new(preview_path => 'a',
                            preview_url => 'preview.com',
                            publish_path => 'b',
                            url => 'live.com');
$site->save();
my ($cat) = pkg('Category')->find(site_id => $site->site_id());
my $template = pkg('Template')->new(category_id => $cat->category_id(),
                                    content => 'ima template, baby',
                                    filename => 'tmpl.tmpl');
$template->save();
$template->checkout();

# failure
eval {$admin->delete()};
isa_ok($@, 'Krang::User::Dependency');

# remove cause of failure
$template->delete();

# remove leftover site
$site->delete();

my $old_user = $user; # save this so we can cleanup later
END {
    # clean up the user and any old passwords
    foreach my $u ($user, $old_user, $admin) {
        dbh()->do(
            'DELETE FROM old_password WHERE user_id = ?',
            {},
            $u->user_id
        );
        # success
        is($u->delete(), 1, 'delete()') unless $u->hidden;
    }
}

# if a scheduled send alert refers to a user in it's context stash
# then it should be deleted when the user is deleted
$user = pkg('User')->new(login => 'asdfasdf',
                         password => 'gIMp');
$user->group_ids_push(1);
$user->save();
my $date = localtime();
$date->year($date->year + 1);
my $alert = pkg('Alert')->new(
    user_id => $user->user_id,
    action  => 'move',
);

my $schedule1 = pkg('Schedule')->new(
    object_type => 'alert',
    object_id   => $alert->alert_id,
    action      => 'send',
    repeat      => 'never',
    date        => $date,
    context     => [ user_id => $user->user_id ],
);
isa_ok($schedule1, pkg('Schedule'));
$schedule1->save();
my $schedule2 = pkg('Schedule')->new(
    object_type => 'alert',
    object_id   => $alert->alert_id,
    action      => 'send',
    repeat      => 'never',
    date        => $date,
);
isa_ok($schedule2, pkg('Schedule'));
$schedule2->save();

$user->delete();
my ($schedule) = pkg('Schedule')->find(schedule_id => $schedule1->schedule_id);
ok(! defined $schedule, 'schedule1 was deleted');
($schedule) = pkg('Schedule')->find(schedule_id => $schedule2->schedule_id);
isa_ok($schedule, pkg('Schedule'), 'schedule2 was not deleted');
$schedule->delete();
