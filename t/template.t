use strict;
use warnings;

use Data::Dumper;
use Krang;
use Test::More qw(no_plan);


BEGIN {use_ok('Krang::Template');}

my $tmpl = Krang::Template->new(name => 'test template 1',
                                category_id => 1,
                                description => 'description',
                                notes => 'notes');

isa_ok($tmpl, 'Krang::Template');

# increment version
$tmpl->save();
is($tmpl->version(), 1, 'Version Check');

# write version to version table
$tmpl->prepare_for_edit();

# save description for revert test
my $old_desc = $tmpl->description();

# check Krang::MethodMaker meth...
$tmpl->description('description 2');
my $desc2 = $tmpl->description();
is($desc2, 'description 2', 'Getter/Setter Test');

$tmpl->content(<<JUNK);
<html>
  <head><title>This Is Only A Test!!!</title></head>
  <body><h1>See the title.</h1></body>
</html>
JUNK

# increment version
$tmpl->save();
is($tmpl->version(), 2, 'Version Check 2');

# write version 2 to the version table
$tmpl->prepare_for_edit();

# revert check
$tmpl = $tmpl->revert(1);
is($tmpl->description(), $old_desc, 'Revert Test');

# increment version
$tmpl->save();
is($tmpl->version(), 3, 'Version Check 3');

# verify checkin works
$tmpl->checkin();
is($tmpl->checked_out, '', 'Checkin Test');

my $tmpl2 = Krang::Template->new(name => 'test template 2',
                                 category_id => 1,
                                 content => '<html></html>',
                                 description => 'template w/ content');

$tmpl2->save();
$tmpl2->prepare_for_edit();

# checkout deploy method
$tmpl2->copy_to('test2.tmpl');
ok(-e 'test2.tmpl', 'Deploy Test');

# clean up the mess
unlink 'test2.tmpl';
$tmpl->delete();
$tmpl2->delete();

