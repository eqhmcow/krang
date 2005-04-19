# count objects in all tables and compare results to dbcount.txt
# created by aaa_dbcount.t
use Krang::ClassFactory qw(pkg);
use Test::More qw(no_plan);

use strict;
use warnings;
use Krang::ClassLoader 'Script';
use Krang::ClassLoader Conf => qw(KrangRoot);
use File::Spec::Functions qw(catfile);
use Krang::ClassLoader DB => qw(dbh);

open(COUNT, "<", catfile(KrangRoot, "tmp", "dbcount.txt")) or die $!;
my $dbh = dbh;

while (<COUNT>) {
    chomp;
    my ($table, $count1) = split(' ', $_);
    my ($count2) = $dbh->selectrow_array("select count(*) from $table");
    is("$table $count2", "$table $count1", "Row count for '$table'");
}

close COUNT;
