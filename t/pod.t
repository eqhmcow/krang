use Krang::ClassFactory qw(pkg);
use Test::Pod qw(no_plan);
use Test::More;

use File::Find qw(find);

# check general pod correctness
find({ wanted => sub { ((/\.pm$/ or /\.pod$/) and not /#/ ) and 
                         pod_file_ok($_, "POD syntax check for $_") },
       no_chdir => 1 },
     'lib/Krang', 'docs');

# check for compliance with coding standards in modules
find({ wanted => 
       sub { 
           return unless /\.pm$/;
           return if /#/; # skip emacs droppings
           open(PM, $_) or die $!;
           my $text = join('', <PM>);
           close PM;

           foreach my $section (qw(NAME SYNOPSIS DESCRIPTION INTERFACE)) {
               ok($text =~ /=head1 $section/, "POD $section check in $_");
           }
       },
       no_chdir => 1 },
     'lib/Krang');
