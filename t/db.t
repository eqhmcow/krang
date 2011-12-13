use Krang::ClassFactory qw(pkg);
use Test::More tests => 6;
use strict;
use warnings;
no warnings 'deprecated';

use Krang::ClassLoader 'Script';
use Krang::ClassLoader 'Conf';
use Krang::ClassLoader DB => qw(dbh forget_dbh);

my $dbh = dbh();
isa_ok($dbh, 'DBI::db', 'DBI handle for "' . pkg('Conf')->InstanceDBName . '" db');

my $results = $dbh->selectall_arrayref('show tables');
ok($results, 'selected some data');

forget_dbh();
my $dbh2 = dbh();
isa_ok($dbh2, 'DBI::db', 'DBI handle for "' . pkg('Conf')->InstanceDBName . '" db');
isnt($dbh, $dbh2);

# Test version control
$dbh = dbh();

# Fail to get dbh if version doesn't match
my ($db_version) = $dbh->selectrow_array("select db_version from db_version");
$dbh->do("update db_version set db_version='9999.9999'");
forget_dbh();
eval { $dbh2 = dbh(); };
like($@, qr/Database <-> Krang version mismatch!/, "dbh() detects version mismatch");

# Try to get dbh in spite of version mismatch (ignore_version=>1)
forget_dbh();
undef($dbh2);
eval { $dbh2 = dbh(ignore_version => 1); };
ok(ref($dbh2), "dbh() respects 'ignore_version' pragma");

# Fix version
$dbh->do("update db_version set db_version=?", undef, $db_version);
