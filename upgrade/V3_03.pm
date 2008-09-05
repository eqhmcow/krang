package V3_03;
use strict;
use warnings;
use Krang::ClassLoader base => 'Upgrade';
use Krang::ClassLoader DB => 'dbh';
use Krang::Conf qw(KrangRoot);
use File::Spec::Functions qw(catfile);

sub per_installation {
    my ($self, %args) = @_;
    # remove old files
    $self->remove_files(
        qw(
          src/CGI-Application-Plugin-JSON-0.3.tar.gz
          src/JSON-1.07.tar.gz
          )
    );
}

sub per_instance {
    my ($self, %args) = @_;
    return if $args{no_db};
    my $dbh = dbh();

    # add syntax_highlighting option to preferences
    $dbh->do('INSERT INTO pref (id, value) VALUES ("syntax_highlighting", "1")');
}

1;
