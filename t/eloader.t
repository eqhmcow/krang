use Test::More qw(no_plan);
use strict;
use warnings;
use Krang;
use Krang::Conf qw(KrangRoot ElementLibrary);
use Krang::ElementLibrary;
use File::Spec::Functions qw(catfile catdir);
use IPC::Run qw(run);
use Time::HiRes qw(time);
use File::Path qw(rmtree);

my $CLEANUP = 1; # set to 0 to leave sets around to examine

# get a list of source XML files
opendir(TESTS, catdir(KrangRoot, "t", "eloader")) or die $!;
my @xml = grep { /.xml$/ } readdir(TESTS);
closedir TESTS;

# load each test set
foreach my $xml (@xml) {
    my $set = '_' . $xml . '_' . time;
    $set =~ s/\.xml//g;
    $set =~ s/\./_/g;
    print "Loading t/eloader/$xml into $set...\n";
    eload($set, catfile(KrangRoot, "t", "eloader", $xml));

    # created ok?
    ok(-d catdir(ElementLibrary, $set));
    ok(-f catfile(ElementLibrary, $set, 'set.conf'));

    # try loading it
    eval { 
        local $Krang::ElementLibrary::TESTING_SET = $set; 
        Krang::ElementLibrary->load_set(set => $set);
    };
    is($@, '');
    
    rmtree([catdir(ElementLibrary, $set)]) if $CLEANUP;
}

# create a set from an XML file
sub eload {
    my ($set, $xml) = @_;
    
    # setup dummy env vars which aren't used with --xml anyway
    $ENV{BRICOLAGE_USERNAME} = 'dummy';
    $ENV{BRICOLAGE_SERVER}   = 'dummy';
    $ENV{BRICOLAGE_PASSWORD} = 'dummy';

    my @command = (catfile(KrangRoot, "bin", "krang_bric_eloader"),
                   "--set" => $set,
                   "--xml" => $xml,                   
                  );
    my $in;
    run(\@command, \$in, \*STDOUT, \*STDERR) 
      or die "Unable to run ". catfile(KrangRoot, "bin", "krang_bric_eloader");
}

