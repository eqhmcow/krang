use Test::More tests => 4;
use strict;
use warnings;

use Krang::Script;
use Krang::Conf;
use Krang::DB qw(dbh forget_dbh); 

my $dbh = dbh();
isa_ok($dbh, 'DBI::db', 'DBI handle for "' . Krang::Conf->InstanceDBName . '" db');

my $results = $dbh->selectall_arrayref('show tables');
ok($results, 'selected some data');

forget_dbh();
my $dbh2 = dbh();
isa_ok($dbh2, 'DBI::db', 'DBI handle for "' . Krang::Conf->InstanceDBName . '" db');
isnt($dbh, $dbh2);
