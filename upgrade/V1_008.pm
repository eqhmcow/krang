package V1_008;
use strict;
use warnings;
use base 'Krang::Upgrade';

use Krang::Conf qw(KrangRoot);
use File::Spec::Functions qw(catfile);

# add new required krang.conf directive, EnableBugzilla, defaulting to off
sub per_installation {
    my $self = shift;

    open(CONF, '<', catfile(KrangRoot, 'conf', 'krang.conf'))
      or die "Unable to open conf/krang.conf: $!";
    my $conf = do { local $/; <CONF> };
    close(CONF);

    # already has a Skin setting?
    return if $conf =~ /^\s*EnableBugzilla/m;

    # write out conf and add the new Skin line
    open(CONF, '>', catfile(KrangRoot, 'conf', 'krang.conf'))
      or die "Unable to open conf/krang.conf: $!";
    print CONF $conf;
    print CONF <<END;

#
# EnableBugzilla controls whether Bugzilla is available through the
# Krang UI.
#
# (This configuration directive was added automatically during an
# upgrade to Krang v1.008.)
#
EnableBugzilla 0
END

    close(CONF);
    
}

# nothing yet
sub per_instance {}

1;
