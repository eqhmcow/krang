# count objects in all tables and put results in dbcount.txt
use Krang::ClassFactory qw(pkg);
use Test::More qw(no_plan);

# ignore a few tables which harmlessly grow in certain circumstances
our %IGNORE = map { ($_, 1) } qw( my_pref sessions history );

use strict;
use warnings;
use Krang::ClassLoader 'Script';
use Krang::ClassLoader Conf => qw(KrangRoot);
use File::Spec::Functions qw(catfile);
use Krang::ClassLoader DB => qw(dbh);

open(COUNT, ">", catfile(KrangRoot, "tmp", "dbcount.txt")) or die $!;
my $dbh = dbh;

my $tables = $dbh->selectcol_arrayref('show tables');
@$tables = grep { not exists $IGNORE{$_} } @$tables;
ok(@$tables);

foreach my $table (sort @$tables) {
    my ($count) = $dbh->selectrow_array("select count(*) from $table");
    ok(defined $count);
    print COUNT "$table $count\n";
}

close COUNT;
