### make sure Krang is 8-bit clean, as advertised.  Just tests
### templates at the moment.  Since all of Krang uses the same basic
### SQL and XML techniques, they should all be as 8-bit clean as
### templates.

use Krang::ClassFactory qw(pkg);
use strict;
use warnings;
use Krang::ClassLoader 'Script';
use Krang::ClassLoader 'Template';
use Krang::ClassLoader 'DataSet';
use Krang::ClassLoader Conf => qw(KrangRoot InstanceElementSet);
use Krang::ClassLoader 'Test::Content';
use File::Spec::Functions qw(catfile);

# skip all tests unless a TestSet1-using instance is available
BEGIN {
    my $found;
    foreach my $instance (pkg('Conf')->instances) {
        pkg('Conf')->instance($instance);
        if (InstanceElementSet eq 'TestSet1') {
            eval 'use Test::More qw(no_plan)';
            die $@ if $@;
            $found = 1;
            last;
        }
    }

    eval "use Test::More skip_all => 'test requires a TestSet1 instance';"
      unless $found;
    die $@ if $@;
}

# a bunch of binary data containing all 256 bytes
my $bits = join('', map { chr($_) } 0 .. 255) .
           join('', map { chr($_) } 255 .. 0) .
           join('', map { chr(int(rand(256))) } 0 .. 1024);

# create a new template and try to fill it with 8-bit data
my $template = pkg('Template')->new(filename => 'test' . time . '.tmpl');
isa_ok($template, 'Krang::Template');

$template->content($bits);
is($template->content, $bits);

# database works for 8bit data?
$template->save();
END { $template->delete; }
($template) = pkg('Template')->find(template_id => $template->template_id);
is($template->content, $bits);

# dataset can handle 8bit template data?
my $set = pkg('DataSet')->new();
$set->add(object => $template);
eval { 
    $set->write(path => catfile(KrangRoot, 'tmp', 'eight_bit_test.kds'));
};
ok(not($@), 'writing dataset with eight-bit template');
print STDERR $@ if $@;
ok(-e catfile(KrangRoot, 'tmp', 'eight_bit_test.kds'));

# load it in and see if the same data gets through
$set = pkg('DataSet')->new(path => catfile(KrangRoot, 'tmp', 'eight_bit_test.kds'));
$set->import_all(no_update => 0);
($template) = pkg('Template')->find(template_id => $template->template_id);
is($template->content, $bits);

# try doing the above for a template containing just one of each bit,
# to make sure the binary detector is working
my @templates;
my @bits;
for my $bit (map { chr($_) } (0 .. 255)) {
    my $bits = 'aaaaa' . $bit . 'bbbb';
    print "# Testing bit " . ord($bit) . "\n";

    # create a new template
    my $template = pkg('Template')->new(filename => 'test' . time . ord($bit) . '.tmpl');
    $template->content($bits);

    # database works for 8bit data?
    $template->save();
    ($template) = pkg('Template')->find(template_id => $template->template_id);
    is($template->content, $bits);
    push(@templates, $template);
    push(@bits, $bits);
}

# dataset can handle the 8bit template data?
$set = pkg('DataSet')->new();
$set->add(object => $_) for @templates;
eval { 
    $set->write(path => catfile(KrangRoot, 'tmp', 'eight_bit_test.kds'));
};
ok(not($@), 'writing dataset with eight-bit template');
print STDERR $@ if $@;
ok(-e catfile(KrangRoot, 'tmp', 'eight_bit_test.kds'));

# load it in and see if the same data gets through
$set = pkg('DataSet')->new(path => 
                           catfile(KrangRoot, 'tmp', 'eight_bit_test.kds'));
$set->import_all(no_update => 0);
foreach my $template (@templates) {
    ($template) = pkg('Template')->find(template_id => $template->template_id);
    is($template->content, shift @bits);
    $template->delete;
}

# make a story, with paragraphs containing 8-bit data
my $creator = pkg('Test::Content')->new();
my $site = $creator->create_site(preview_url => 'preview.8bit.com',
                                 publish_url => 'www.8bit.com',
                                 preview_path => '/tmp/8bit-prev',
                                 publish_path => '/tmp/8bit-pub');
my $cat = $creator->create_category(dir    => '8bit');

my $story = pkg('Story')->new(class => 'article',
                              categories => [$cat],
                              slug => '8bits',
                              title => '8 is enough');
my $page = $story->element->child('page');

@bits = ();
for my $bit (map { chr($_) } (0 .. 255)) {
    $page->add_child(class => 'pull_quote',
                     data => ord($bit));
    my $para = $page->add_child(class => 'paragraph',
                                data => $bit);
    is($para->data, $bit, 'BIT: ' . ord($bit) . ' is ok.');
    push(@bits, $bit);
}

# save it and check it
$story->save();
($story) = pkg('Story')->find(story_id => $story->story_id);
my @b = @bits;
foreach my $para ($story->element->match('//paragraph')) {
    my $bit = shift @b;
    is($para->data, $bit, 'BIT: ' . ord($bit) . ' is ok.');
}

# put it in a dataset
$set = pkg('DataSet')->new();
$set->add(object => $story);
eval { 
    $set->write(path => catfile(KrangRoot, 'tmp', 'eight_bit_test2.kds'));
};
ok(not($@), 'writing dataset with eight-bit template');
print STDERR $@ if $@;
ok(-e catfile(KrangRoot, 'tmp', 'eight_bit_test2.kds'));

# load up the dataset and see if the story made it
$set = pkg('DataSet')->new(path => 
                           catfile(KrangRoot, 'tmp', 'eight_bit_test2.kds'));
$set->import_all(no_update => 0);

($story) = pkg('Story')->find(story_id => $story->story_id);
foreach my $para ($story->element->match('//paragraph')) {
    my $bit = shift @bits;
    is($para->data, $bit, 'BIT: ' . ord($bit) . ' is ok.');
}


# clean up

$story->delete;
($cat) = pkg('Category')->find(category_id => $cat->category_id);
$cat->delete;
$creator->cleanup();
