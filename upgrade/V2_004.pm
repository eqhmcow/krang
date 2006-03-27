package V2_004;
use strict;
use warnings;
use Krang::ClassLoader base => 'Upgrade';
use Krang::ClassLoader DB => 'dbh';
 
# add new krang.conf directive, Charset
sub per_installation {
    my $self = shift;

    open(CONF, '<', catfile(KrangRoot, 'conf', 'krang.conf'))
      or die "Unable to open conf/krang.conf: $!";
    my $conf = do { local $/; <CONF> };
    close(CONF);

    # already has a Charset setting?
    return if $conf =~ /^\s*Charset/m;

    # write out conf and add the new Skin line
    open(CONF, '>', catfile(KrangRoot, 'conf', 'krang.conf'))
      or die "Unable to open conf/krang.conf: $!";
    print CONF $conf;
    print CONF <<END;
#
# This variable controls the character-set for Krang's user interface.
# Compliant browsers will use this setting to encode data they send to
# Krang.  NOTE: If your editors use IE 6 on Windows XP and may copy
# non-ASCII data into Krang then you may need to set this to either
# "windows-1252" or "utf-8" to work-around a bug in IE 6.
#
Charset iso-8859-1

END

    close(CONF);
    
}

# nothing yet
sub per_instance {}

1;
