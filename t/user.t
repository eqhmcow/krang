use strict;
use warnings;

use Krang::Script;
use Krang::Site;
use Krang::Template;

use Test::More qw(no_plan);

BEGIN {
    use_ok('Krang::User');
}

# Constructor tests
####################
# failures
###########
# invalid field
my $user;
eval {
    $user = Krang::User->new(login => 'login',
                             password => 'pwd',
                             crunk => 'X');
};
is($@ =~ /constructor args are invalid: 'crunk'/, 1, 'new() - invalid field');

# successes
############
my $admin = Krang::User->new(login => 'admin',
                             password => 'shredder');
$user = Krang::User->new(login => 'arobin',
                         password => 'gIMp');

# save() tests
###############
# failure
eval {$admin->save()};
is($@ =~ /user objects.*login.*password/s, 1, 'save() - duplicate check');

# success
$user->save();
is($user->user_id() =~ /^\d+$/, 1, 'save() - success');

# getters
##########
{
    no strict 'subs';
    is($user->$_, undef, "getter - $_")
      for qw/email first_name last_name mobile_phone phone/;
}
is(scalar @{$user->group_ids} <= 0, 1, 'getter - group_ids()');

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
($admin) = Krang::User->find(login => 'admin');
isa_ok($admin, 'Krang::User', 'find() - login');

my $count = Krang::User->find(email => undef,
                              first_name => 'Joe',
                              last_name => 'Admin',
                              login => 'admin',
                              mobile_phone => undef,
                              phone => undef);
is($count, 1, 'find - all fields');

my @users = Krang::User->find(email => undef);
isa_ok($_, 'Krang::User') for @users;
is(scalar @users, 2, 'find - count');

@users = Krang::User->find(order_by => 'login');
is($users[0]->login, 'admin', 'find - order_by');

@users = Krang::User->find(limit => 1);
is(scalar @users, 1, 'find - limit');

@users = Krang::User->find(offset => 1);
is($users[0]->login, 'arobin', 'find - offset');

@users = Krang::User->find(group_ids => [1,2,3]);
isa_ok($_, 'Krang::User') for @users;
is(scalar @users, 1, 'find - group_ids');
is(scalar @{$users[0]->group_ids()}, 3, 'group_ids - count');

# check_user_pass() tests
##########################
is(Krang::User->check_auth('',''), 0, 'check_auth() - failure 1');
is(Krang::User->check_auth('admin',''), 0, 'check_auth() - failure 2');
is(Krang::User->check_auth('admin', 'shredder'), 1, 'check_auth() - success');

# delete() tests
#################
# create objects to force a delete failure
my $site = Krang::Site->new(preview_path => 'a',
                            preview_url => 'preview.com',
                            publish_path => 'b',
                            url => 'live.com');
$site->save();
my ($cat) = Krang::Category->find(site_id => $site->site_id());
my $template = Krang::Template->new(category_id => $cat->category_id(),
                                    content => 'ima template, baby',
                                    filename => 'tmpl.tmpl');
$template->save();
$template->checkout();

# failure
eval {$admin->delete()};
is($@ =~ /reference this class:.*template/is, 1, 'delete() failure');

# remove cause of failure
$template->delete();

# success
is($user->delete(), 1, 'delete()');

# remove leftover site
$site->delete();

__END__
