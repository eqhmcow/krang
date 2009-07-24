package V3_06;
use strict;
use warnings;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => 'Upgrade';

use Krang::ClassLoader Conf => qw(KrangRoot InstanceElementSet);
use Krang::ClassLoader DB   => 'dbh';
use Krang::ClassLoader 'ElementLibrary';

use File::Spec::Functions qw(catfile);

sub per_installation {
    my $self = shift;

    print "Removing deprecated files... ";

    # replaced Compress-Zlib-1.31.tar.gz with IO-Compress-2.020.tar.gz
    # because Image::Size requires Compress::Zlib >= 2
    $self->remove_files( qw(
      src/Compress-Zlib-1.31.tar.gz
      src/Apache-MOD_PERL/mod_perl-1.30.tar.gz
      src/Compress-Zlib-1.31.tar.gz
      src/DBD-mysql-4.005.tar.gz
      src/DBI-1.58.tar.gz
      src/Image-Size-3.1.1.tar.gz
      src/Pod-Simple-2.05.tar.gz
      src/Storable-2.13.tar.gz
    ));

}

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
