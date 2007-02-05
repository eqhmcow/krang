package V2_009;
use strict;
use warnings;
use Krang::ClassLoader base => 'Upgrade';
use Krang::ClassLoader DB => 'dbh';
use Krang::Conf qw(KrangRoot);
use File::Spec::Functions qw(catfile);

# Add new krang.conf directive PreviewSSL
sub per_installation {
    my $self = shift;

    open(CONF, '<', catfile(KrangRoot, 'conf', 'krang.conf'))
      or die "Unable to open conf/krang.conf: $!";
    my $conf = do { local $/; <CONF> };
    close(CONF);

    # already has a PreviewSSL setting?
    return if $conf =~ /^\s*PreviewSSL/m;

    # write out conf and add the new line
    open(CONF, '>', catfile(KrangRoot, 'conf', 'krang.conf'))
      or die "Unable to open conf/krang.conf: $!";
    print CONF $conf;
    print CONF <<END;

#
# This variable controls whether Krang uses SSL for links to preview.
# This is independent of EnableSSL, allowing you to run your preview
# server with SSL enabled even if Krang is not using SSL.
#
PreviewSSL 0
END

    close(CONF);

    # previous versions had a bug on stories where checked_out could
    # bet set to checked_out_by instead of the simple boolean if the story
    # was reverted. Fix this so that 'Active Stories' works again
    my $dbh = dbh();
    $dbh->do(qq/
        UPDATE story SET checked_out = 1 WHERE checked_out != 0
    /);
}

# nothing yet
sub per_instance {}

1;
