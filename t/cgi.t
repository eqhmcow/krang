use Test::More qw(no_plan);
use File::Find qw(find);

# a list of CGI modules without a suitable default mode (one that
# requires no parameters)
our %BAD_DEFAULT = map { ($_,1) } 
  (qw( Krang::CGI::History
       Krang::CGI::ElementEditor ));


# Arrange for CGI output to come back via return, but NOT go to STDOUT
$ENV{CGI_APP_RETURN_ONLY} = 1;


# Check all Krang CGI-App modules
find({ wanted => 
       sub { 
           return unless /^lib\/(Krang\/CGI\/.*)\.pm$/;
           return if /#/; # skip emacs droppings

           my $app_package = join('::', (split(/\//, $1)));
           check_cgiapp($app_package);
       },
       no_chdir => 1 },
     'lib/Krang/CGI/');


# A Krang CGI-App module is deemed to be OK if:
#    1. Compiles OK
#    2. Instantiates as a sub-class of Krang::CGI
#    3. Runs with default (start) mode
#    4. Output starts "Content-Type:"
sub check_cgiapp {
    my $app_package = shift;

    # Can we load the module?
    require_ok($app_package);

    # Is this a Krang::CGI?
    my $app = 0;
    eval ( $app = $app_package->new() );
    isa_ok($app, 'Krang::CGI');

    # skip modules without a suitable default mode
    next if $BAD_DEFAULT{$app_package};

    # Can we run the default mode?
    my $output = '';
    eval { $output = $app->run() };
    ok(not($@), "\$$app_package->run()");

    # Does our output start "Content-Type:"?
    like($output,  qr/^Content\-Type\:/, "Testing output of $app_package->run().");
}
