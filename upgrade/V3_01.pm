package V3_01;
use strict;
use warnings;
use Krang::ClassLoader base => 'Upgrade';
use Krang::ClassLoader DB => 'dbh';
use Krang::Conf qw(KrangRoot);
use File::Spec::Functions qw(catfile);

# Add new krang.conf directive PreviewSSL
sub per_installation {

}

sub per_instance {
    my ($self, %args) = @_;
    return if $args{no_db};
    my $dbh = dbh();

    # correct size of binary DB columns
    $dbh->do('ALTER TABLE sessions MODIFY COLUMN a_session MEDIUMBLOB');
    $dbh->do('ALTER TABLE story_version MODIFY COLUMN data MEDIUMBLOB');
    $dbh->do('ALTER TABLE media_version MODIFY COLUMN data MEDIUMBLOB');
    $dbh->do('ALTER TABLE template_version MODIFY COLUMN data MEDIUMBLOB');

    # remove deprecated 'priority' field from story table
    $dbh->do('ALTER TABLE story DROP COLUMN priority');
}

1;
