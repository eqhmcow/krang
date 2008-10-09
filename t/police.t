use Krang::ClassFactory qw(pkg);
use Test::More qw(no_plan);
use File::Find qw(find);
use File::Spec::Functions qw(catdir);

use Krang::ClassLoader Conf => (KrangRoot);

# license and registration please

# check for strict and warnings usage in modules
find(
    {
        wanted => sub {
            return unless /\.pm$/;
            return if /#/;    # skip emacs droppings
            open(PM, $_) or die "Unable to open '$_' : $!";
            my ($strict, $warnings);
            while (my $line = <PM>) {
                $strict   = 1 if $line =~ /^\s*use\s+strict\s*;/;
                $warnings = 1 if $line =~ /^\s*use\s+warnings\s*;/;
                last if $strict and $warnings;
            }
            ok($strict,   "$_ 'use strict' test.");
            ok($warnings, "$_ 'use warnings' test.");
        },
        no_chdir => 1
    },
    catdir(KrangRoot, 'lib', 'Krang')
);
