package V3_06;
use strict;
use warnings;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => 'Upgrade';

use Krang::ClassLoader Conf => qw(KrangRoot InstanceElementSet);
use Krang::ClassLoader DB   => 'dbh';
use Krang::ClassLoader 'ElementLibrary';

use File::Spec::Functions qw(catfile);

sub per_installation { }

use Cwd qw(cwd);

sub per_instance {
    my ($self, %args) = @_;
    return if $args{no_db};
    my $dbh = dbh();
    my $query = 'SELECT media_type_id FROM media_type WHERE name="Power Point"';
    my $powerpoint = $dbh->selectrow_arrayref($query, undef);
    unless ($powerpoint) {
        $dbh->do('INSERT INTO media_type (name) VALUES ("Power Point")');
    }
}

1;
