package V3_00;
use strict;
use warnings;
use Krang::ClassLoader base => 'Upgrade';
use Krang::ClassLoader DB => 'dbh';
use Krang::Conf qw(KrangRoot);
use File::Spec::Functions qw(catfile);

# Add new krang.conf directive PreviewSSL
sub per_installation {
    _update_config();
}

sub per_instance {
    my $self = shift;
    my $dbh = dbh();

    # add the 'use_autocomplete' preference
    $dbh->do('INSERT INTO pref (id, value) VALUES ("use_autocomplete", "1")');
    # add the 'message_timeout' preference
    $dbh->do('INSERT INTO pref (id, value) VALUES ("message_timeout", "5")');
    # change sessions and story_version tables to handle UTF-8
    $dbh->do('ALTER TABLE sessions CHANGE COLUMN a_session a_session BLOB');
    $dbh->do('ALTER TABLE story_version CHANGE COLUMN data data BLOB');
    $dbh->do('ALTER TABLE template_version CHANGE COLUMN data data BLOB');
    $dbh->do('ALTER TABLE media_version CHANGE COLUMN data data BLOB');

    $self->_wipe_slugs_from_cover_stories();
}

# add new EnableFTP and Secret directives if they aren't already there
sub _update_config {
    open(CONF, '<', catfile(KrangRoot, 'conf', 'krang.conf'))
      or die "Unable to open conf/krang.conf: $!";
    my $conf = do { local $/; <CONF> };
    close(CONF);

    # write out conf and add the new lines
    open(CONF, '>', catfile(KrangRoot, 'conf', 'krang.conf'))
      or die "Unable to open conf/krang.conf: $!";
    print CONF $conf;
    print CONF "\nEnableFTP 1\n" unless $conf =~ /^\s*EnableFTP/m;

    # create a random secret
    my $secret = _random_secret();
    print CONF "\nSecret '$secret'\n" unless $conf =~ /^\s*Secret/m;
    close(CONF);
}

sub _random_secret {
    my $length = int(rand(10) + 20);
    my $secret = '';
    my @chars = ('a'..'z', 'A'..'Z', 0..9, qw(! @ $ % ^ & - _ = + | ; : . / < > ?));
    $secret .= $chars[int(rand($#chars + 1))] for(0..$length);
    return $secret;
}


# remove slugs from stories that subclass Cover 
# (since slugs will now be optional for all types)
sub _wipe_slugs_from_cover_stories {

    my ($self) = @_;

    my @types_that_subclass_cover =
	grep { pkg('ElementLibrary')->top_level(name => $_)->isa('Krang::ElementClass::Cover') }
            pkg('ElementLibrary')->top_levels;

    my $dbh = dbh();
    my $sql = qq/update story set slug="" where story.class=?/;
    my $sth = $dbh->prepare($sql);
    
    foreach my $type (@types_that_subclass_cover) {
	print "Cleaning slugs from stories of type '$type'... ";
	$sth->execute($type);
	print "DONE\n";
    }
}

1;
