### make sure Krang is 8-bit clean, as advertised.  Just tests
### templates at the moment.  Since all of Krang uses the same basic
### SQL and XML techniques, they should all be as 8-bit clean as
### templates.

use Test::More qw(no_plan);
use strict;
use warnings;
use Krang::Script;
use Krang::Template;
use Krang::DataSet;
use Krang::Conf qw(KrangRoot);
use File::Spec::Functions qw(catfile);

# a bunch of binary data containing all 256 bytes
my $bits = join('', map { chr($_) } 0 .. 255) .
           join('', map { chr($_) } 255 .. 0) .
           join('', map { chr(int(rand(256))) } 0 .. 1024);

# create a new template and try to fill it with 8-bit data
my $template = Krang::Template->new(filename => 'test' . time . '.tmpl');
isa_ok($template, 'Krang::Template');

$template->content($bits);
is($template->content, $bits);

# database works for 8bit data?
$template->save();
END { $template->delete; }
($template) = Krang::Template->find(template_id => $template->template_id);
is($template->content, $bits);

# dataset can handle 8bit template data?
my $set = Krang::DataSet->new();
$set->add(object => $template);
eval { 
    $set->write(path => catfile(KrangRoot, 'tmp', 'eight_bit_test.kds'));
};
ok(not($@), 'writing dataset with eight-bit template');
print STDERR $@ if $@;
ok(-e catfile(KrangRoot, 'tmp', 'eight_bit_test.kds'));

# load it in and see if the same data gets through
$set = Krang::DataSet->new(path => catfile(KrangRoot, 'tmp', 'eight_bit_test.kds'));
$set->import_all(no_update => 0);
($template) = Krang::Template->find(template_id => $template->template_id);
is($template->content, $bits);

# try doing the above for a template containing just one of each bit,
# to make sure the binary detector is working
my @templates;
my @bits;
for my $bit (map { chr($_) } (0 .. 255)) {
    my $bits = 'aaaaa' . $bit . 'bbbb';
    print "# Testing bit " . ord($bit) . "\n";

    # create a new template
    my $template = Krang::Template->new(filename => 'test' . time . ord($bit) . '.tmpl');
    $template->content($bits);

    # database works for 8bit data?
    $template->save();
    ($template) = Krang::Template->find(template_id => $template->template_id);
    is($template->content, $bits);
    push(@templates, $template);
    push(@bits, $bits);
}

# dataset can handle the 8bit template data?
$set = Krang::DataSet->new();
$set->add(object => $_) for @templates;
eval { 
    $set->write(path => catfile(KrangRoot, 'tmp', 'eight_bit_test.kds'));
};
ok(not($@), 'writing dataset with eight-bit template');
print STDERR $@ if $@;
ok(-e catfile(KrangRoot, 'tmp', 'eight_bit_test.kds'));

# load it in and see if the same data gets through
$set = Krang::DataSet->new(path => 
                           catfile(KrangRoot, 'tmp', 'eight_bit_test.kds'));
$set->import_all(no_update => 0);
foreach my $template (@templates) {
    ($template) = Krang::Template->find(template_id => $template->template_id);
    is($template->content, shift @bits);
    $template->delete;
}

# unlink(catfile(KrangRoot, 'tmp', 'eight_bit_test.kds'));
