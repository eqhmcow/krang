package V3_20;
use strict;
use warnings;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => 'Upgrade';
use Krang::ClassLoader DB   => 'dbh';
use Krang::ClassLoader 'Media';

sub per_instance {
    my ($self, %args) = @_;
    return if $args{no_db};
    my $dbh = dbh();
    $dbh->do('ALTER TABLE media ADD COLUMN full_text LONGTEXT NULL');

    # look through each media object and fill in the full_text value if it's a text media object
    for my $media (pkg('Media')->find) {
        if( $media->is_text ) {
            $media->_update_full_text();
            $media->save(keep_version => 1);
        }
    }
}

sub per_installation {
    my ($self, %args) = @_;

    # nothing to do yet
}

1;
