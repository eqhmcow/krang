# count objects in all tables and put results in dbcount.txt
use Test::More qw(no_plan);

use strict;
use warnings;
use Krang::Script;
use Krang::Conf qw(KrangRoot);
use File::Spec::Functions qw(catfile);
use Krang::DB qw(dbh);

open(COUNT, ">", catfile(KrangRoot, "tmp", "dbcount.txt")) or die $!;
my $dbh = dbh;

my $tables = $dbh->selectcol_arrayref('show tables');
ok(@$tables);

# make an exception for my_pref, which harmlessly adds a row the first
# time my_pref.t is run.  Maybe fix some day...
@$tables = grep { $_ ne 'my_pref' } @$tables;

foreach my $table (sort @$tables) {
    my ($count) = $dbh->selectrow_array("select count(*) from $table");
    ok(defined $count);
    print COUNT "$table $count\n";
}

close COUNT;
