package V3_08;
use strict;
use warnings;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => 'Upgrade';
use Krang::ClassLoader Conf => qw(KrangRoot InstanceElementSet);
use Krang::ClassLoader DB   => 'dbh';
use Krang::ClassLoader 'ElementLibrary';
use File::Spec::Functions qw(catfile);
use Cwd qw(cwd);

sub per_instance {
    my ($self, %args) = @_;
    return if $args{no_db};
    my $dbh = dbh();
    $dbh->do('ALTER TABLE group_permission ADD COLUMN may_view_trash BOOL NOT NULL DEFAULT 1 AFTER admin_delete');
}

sub per_installation {
    # nothing yet
}

1;
