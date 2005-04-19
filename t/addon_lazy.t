use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader 'Script';
use Test::More qw(no_plan);
use Krang::ClassLoader 'AddOn';
use Krang::ClassLoader 'Conf';
use File::Spec::Functions qw(catfile);

# make sure LazyLoader isn't installed
my ($lazy) = pkg('AddOn')->find(name => 'LazyLoader');
ok(not $lazy);

# install LazyLoader 1.00
pkg('AddOn')->install(src => 
                      catfile(pkg('Conf')->get('KrangRoot'), 
                              't', 'addons', 'LazyLoader-1.00.tar.gz'));

# worked?
($lazy) = pkg('AddOn')->find(name => 'LazyLoader');
END { $lazy->uninstall }
isa_ok($lazy, 'Krang::AddOn');

# run story.t to see if the story tests still pass with the addon installed
{ 
    local $ENV{SUB_TEST} = 1;
    my $story_t = catfile(pkg('Conf')->get('KrangRoot'), 't', 'story.t');
    do $story_t or die "Unable to run story.t: $! $@";
}
