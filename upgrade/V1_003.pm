package V1_003;
use strict;
use warnings;
use base 'Krang::Upgrade';

use Krang::Conf qw(KrangRoot);
use File::Spec::Functions qw(catfile);
use Krang::DB qw(dbh);

# add new required krang.conf directive, Skin
sub per_installation {
    my $self = shift;

    open(CONF, '<', catfile(KrangRoot, 'conf', 'krang.conf'))
      or die "Unable to open conf/krang.conf: $!";
    my $conf = do { local $/; <CONF> };
    close(CONF);

    # already has a Skin setting?
    return if $conf =~ /^\s*Skin/m;

    # write out conf and add the new Skin line
    open(CONF, '>', catfile(KrangRoot, 'conf', 'krang.conf'))
      or die "Unable to open conf/krang.conf: $!";
    print CONF $conf;
    print CONF <<END;

#
# Select a skin which will determine the look of the UI.  Available
# skins are stored in the skins/ directory.
#
# (This configuration directive was added automatically during an
# upgrade to Krang v1.003.)
#
Skin Default
END

    close(CONF);
    
}


# fix duplicate lists created by a bug in krang_createdb
sub per_instance {
    my $self = shift;
    my $dbh = dbh;

    my $results = $dbh->selectall_arrayref('SELECT list_group_id, name FROM list_group ORDER BY list_group_id');

    my %seen;
    foreach my $row (@$results) {
        my ($id, $name) = @$row;
        next unless $seen{$name}++;
        
        # delete duplicates
        $dbh->do('DELETE FROM list_group WHERE list_group_id = ?', undef, $id);
    }    
}
 

1;
