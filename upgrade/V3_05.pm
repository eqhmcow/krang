package V3_05;
use strict;
use warnings;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => 'Upgrade';

use Krang::ClassLoader Conf => qw(KrangRoot InstanceElementSet);
use Krang::ClassLoader DB   => 'dbh';
use Krang::ClassLoader 'ElementLibrary';
use Krang::ClassLoader 'ListGroup';

use File::Spec::Functions qw(catfile);

sub per_installation { }

use Cwd qw(cwd);

sub per_instance {
    my ($self, %args) = @_;
    return if $args{no_db};
    my $dbh = dbh();
    my $instance = pkg('Conf')->instance();
    print "\n\nUPGRADING INSTANCE $instance:\n\n";

    # add the new published flag to media
    my @media_columns = @{$dbh->selectcol_arrayref('SHOW columns FROM media')};
    print "Adding 'published' column to media table... ";
    if (grep { $_ eq 'published' } @media_columns) {
        print "already exists (skipping)\n\n";
    } else {
        $dbh->do('ALTER TABLE media ADD published bool NOT NULL DEFAULT 0');
        print "DONE\n\n";
    }

    # add the new 'Image Size' listgroup
    unless (pkg('ListGroup')->find(name => 'Image Size')) {
        if (-e (my $lists_conf = catfile(cwd, 'upgrade', ref($self), 'lists.conf'))) {
            print "Importing new 'Image Size' listgroup...\n\n";
            my $cmd = catfile(KrangRoot, 'bin', 'krang_create_lists');
            $cmd .= " --verbose --input_file $lists_conf";
            local $ENV{KRANG_INSTANCE} = Krang::Conf->instance();
            system($cmd) && die "'$cmd' failed: $?";
        }
    }
}

1;
