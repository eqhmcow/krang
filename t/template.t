use strict;
use warnings;

use Data::Dumper;
use Krang;
use Test::More qw(no_plan);


BEGIN {use_ok('Krang::Template');}

my $tmpl = Krang::Template->new(category_id => 1,
                                content => '<blink><tmpl_var bob></blink>',
                                element_class => 'Krang::ElementClass::Bob');

isa_ok($tmpl, 'Krang::Template');

# increment version
$tmpl->save();
is($tmpl->version(), 1, 'Version Check');

# write version to version table
$tmpl->prepare_for_edit();

# save description for revert test
my $content = $tmpl->content();

# check Krang::MethodMaker meth...
$tmpl->content('<tmpl_var content>');
my $content2 = $tmpl->content();
is($content2, '<tmpl_var content>', 'Getter/Setter Test');

#$tmpl->content(<<JUNK);
#<html>
#  <head><title>This Is Only A Test!!!</title></head>
#  <body><h1>See the title.</h1></body>
#</html>
#JUNK

# increment version
$tmpl->save();
is($tmpl->version(), 2, 'Version Check 2');

# write version 2 to the version table
$tmpl->prepare_for_edit();

# revert check
$tmpl = $tmpl->revert(1);
is($tmpl->content(), $content, 'Revert Test');

# increment version
$tmpl->save();
is($tmpl->version(), 3, 'Version Check 3');

# verify checkin works
$tmpl->checkin();
is($tmpl->checked_out, '', 'Checkin Test');

my $tmpl2 = Krang::Template->new(category_id => 1,
                                 content => '<html></html>',
                                 filename => 't_w_c.tmpl');

$tmpl2->save();
$tmpl2->prepare_for_edit();

# checkout deploy method
my $dir = File::Spec->catdir($ENV{PWD});
my $path = File::Spec->catfile($dir, 't_w_c.tmpl');
$tmpl2->deploy_to($dir);
ok(-e $path, 'Deploy Test');

# find test
my ($tmpl3) = Krang::Template->find(filename => 'bob.tmpl');
is(ref $tmpl3, 'Krang::Template', 'Find Test');

# clean up the mess
unlink 't_w_c.tmpl';
$tmpl->delete();
$tmpl2->delete();
$tmpl3->delete();
