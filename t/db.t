use Test::More tests => 2;
use strict;
use warnings;

use Krang;
use Krang::Conf;
use Krang::DB qw(dbh); 

my $dbh = dbh();
isa_ok($dbh, 'DBI::db', 'DBI handle for "' . Krang::Conf->DBName . '" db');

my $results = $dbh->selectall_arrayref('show tables');
ok($results, 'selected some data');
