use strict;
use warnings;
use Krang::Script;
use Krang::Site;
use Krang::Category;
use Krang::Story;
use Krang::Conf qw(InstanceElementSet);
use Krang::ElementLibrary;

# skip all tests unless a PBMM-using instance is available
BEGIN {
    my $found;
    foreach my $instance (Krang::Conf->instances) {
        Krang::Conf->instance($instance);
        if (InstanceElementSet eq 'PBMM') {
            $found = 1;
            last;
        }
    }
                          
    unless ($found) {
        eval "use Test::More skip_all => 'test requires a PBMM instance';";
    } else {
        eval "use Test::More qw(no_plan);";
    }
    die $@ if $@;
}


# PBMM story types must all have the full meta set
my @meta = qw(keywords description technology company_type
              topic geography source);
foreach my $top_name (Krang::ElementLibrary->top_levels) {
    next if $top_name eq 'category';
    my $class = Krang::ElementLibrary->top_level(name => $top_name);
    isa_ok($class, 'Krang::ElementClass::TopLevel');

    foreach my $meta (@meta) {
        ok((grep { $_->name eq "meta_$meta" } $class->children),
           $class->name . " has meta_$meta");
    }
}
