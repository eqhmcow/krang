# Test script for Krang::Localization

use Krang::ClassFactory qw (pkg);
use strict;
use warnings;

use Data::Dumper;

use Krang::ClassLoader 'Script';
use Krang::ClassLoader Conf => qw(InstanceElementSet DefaultLanguage AvailableLanguages);
use Krang::ClassLoader Session => qw(%session);
BEGIN { pkg('Session')->create(); }
END   { pkg('Session')->delete(); }

BEGIN {
    my $found;
    foreach my $instance (pkg('Conf')->instances) {
        pkg('Conf')->instance($instance);
        if (InstanceElementSet eq 'TestSet1' || InstanceElementSet eq 'Default') {
            $found = 1;
            last;
        }
    }

    unless ($found) {
        eval "use Test::More skip_all => 'test requires an instance using TestSet1 or Default';";
    } else {
        eval "use Test::More qw(no_plan);";
    }
    die $@ if $@;
}

# test use'ing it
use_ok('Krang::Localization');

# test exported method localize()
our %LANG;
import Krang::Localization qw(%LANG localize);

# test exported method localize() ...
# ... for English
$session{language} = 'en';
is(localize('Workspace'), 'Workspace', "localize('Workspace') for English default");

# ... for other languages
for my $lang ( grep { $_ ne 'en' } AvailableLanguages ) {
    $session{language} = $lang;
    ok(localize('Preferences'), "localize('Workspace') for $LANG{$lang}");
}
