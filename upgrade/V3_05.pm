package V3_05;
use strict;
use warnings;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => 'Upgrade';
use Krang::ClassLoader DB   => 'dbh';
use Krang::ClassLoader 'ElementLibrary';
use Krang::Conf qw(KrangRoot InstanceElementSet);
use File::Spec::Functions qw(catfile catdir);

sub per_installation { }

sub per_instance {
    my ($self, %args) = @_;
    return if $args{no_db};
    my $dbh = dbh();
    print "\n\nUPGRADING INSTANCE " . uc(InstanceElementSet) . ":\n\n";

    # add the new published flag to media
    my @media_columns = @{$dbh->selectcol_arrayref('SHOW columns FROM media')};
    print "Adding 'published' column to media table... ";
    if (grep { $_ eq 'published' } @media_columns) {
        print "already exists (skipping)\n\n";
    } else {
        $dbh->do('ALTER TABLE media ADD published bool NOT NULL DEFAULT 0');
        print "DONE\n\n";
    }
}

1;
