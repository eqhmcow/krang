package V1_003;
use strict;
use warnings;
use base 'Krang::Upgrade';

use Krang::Conf qw(KrangRoot);
use File::Spec::Functions qw(catfile);

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
    print $conf;
    print <<END;

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


# nothing to do yet
sub per_instance {}
 
