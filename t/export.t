use Krang::ClassFactory qw(pkg);
use strict;
use warnings;
use Krang::ClassLoader 'Script';
use Krang::ClassLoader Conf => qw(InstanceElementSet);

# skip all tests unless a TestSet1-using instance is available
BEGIN {
    my $found;
    foreach my $instance (pkg('Conf')->instances) {
        pkg('Conf')->instance($instance);
        if (InstanceElementSet eq 'TestSet1') {
            $found = 1;
            last;
        }
    }

    unless ($found) {
        eval "use Test::More skip_all => 'test requires a TestSet1 instance';";
    } else {
        eval "use Test::More qw(no_plan);";
    }
    die $@ if $@;
}

use Krang::ClassLoader 'Site';
use Krang::ClassLoader 'Category';
use Krang::ClassLoader 'Story';
use Krang::ClassLoader Conf => qw(KrangRoot);
use IPC::Run qw(run);
use Krang::ClassLoader 'DataSet';
use File::Spec::Functions qw(catfile);

# create a site and category for dummy story
my $site = pkg('Site')->new(preview_url  => 'storytest.preview.com',
                            url          => 'storytest.com',
                            publish_path => '/tmp/storytest_publish',
                            preview_path => '/tmp/storytest_preview');
$site->save();
END { $site->delete() }
my ($category) = pkg('Category')->find(site_id => $site->site_id());

# create a new story
my $story = pkg('Story')->new(categories => [$category],
                              title      => "Test",
                              slug       => "test",
                              class      => "article");
$story->save();

END { $story->delete(); }

# export the story
$ENV{KRANG_INSTANCE} = pkg('Conf')->instance();
my $krang_export = catfile(KrangRoot, 'bin', 'krang_export');
my $kds = catfile(KrangRoot, 'tmp', 'export.kds');
my ($in, $out, $err) = ("", "", "");
my @cmd = ($krang_export, '--overwrite', '--output', $kds, '--story_id', $story->story_id);
run(\@cmd, \$in, \$out, \$err);
ok(length($err) == 0);  
like($out, qr/Export completed/);
ok(-s $kds);

# try loading it with Krang::DataSet
my $set = pkg('DataSet')->new(path => $kds);
isa_ok($set, 'Krang::DataSet');

# there should be four objects here, the story, the category, and the
# site.
my @obj = $set->list;
is(@obj, 3);
ok(grep { $_->[0]->isa('Krang::Story') and
          $_->[1] eq $story->story_id  } @obj);
ok(grep { $_->[0]->isa('Krang::Category') and
          $_->[1] eq $story->category->category_id  } @obj);
ok(grep { $_->[0]->isa('Krang::Site') and
          $_->[1] eq $story->category->site->site_id  } @obj);
