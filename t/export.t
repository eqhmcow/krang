use Test::More qw(no_plan);
use strict;
use warnings;
use Krang::Script;
use Krang::Site;
use Krang::Category;
use Krang::Story;
use Krang::Conf qw(KrangRoot);
use IPC::Run qw(run);
use Krang::DataSet;
use File::Spec::Functions qw(catfile);

# create a site and category for dummy story
my $site = Krang::Site->new(preview_url  => 'storytest.preview.com',
                            url          => 'storytest.com',
                            publish_path => '/tmp/storytest_publish',
                            preview_path => '/tmp/storytest_preview');
$site->save();
END { $site->delete() }
my ($category) = Krang::Category->find(site_id => $site->site_id());

# create a new story
my $story = Krang::Story->new(categories => [$category],
                              title      => "Test",
                              slug       => "test",
                              class      => "article");
$story->save();
END { $story->delete() }

# export the story
my $krang_export = catfile(KrangRoot, 'bin', 'krang_export');
my $kds = catfile(KrangRoot, 'tmp', 'export.kds');
my ($in, $out, $err) = ("", "", "");
my @cmd = ($krang_export, '--overwrite', '--output', $kds, '--story_id', $story->story_id);
run(\@cmd, \$in, \$out, \$err);
ok(length($err) == 0);  
like($out, qr/Export completed/);
ok(-s $kds);

# try loading it with Krang::DataSet
my $set = Krang::DataSet->new(path => $kds);
isa_ok($set, 'Krang::DataSet');

# there should be four objects here, the story, the category, and the
# site.
my @obj = $set->list;
is(@obj, 3);
ok(grep { $_->[0] eq 'Krang::Story' and
          $_->[1] eq $story->story_id  } @obj);
ok(grep { $_->[0] eq 'Krang::Category' and
          $_->[1] eq $story->category->category_id  } @obj);
ok(grep { $_->[0] eq 'Krang::Site' and
          $_->[1] eq $story->category->site->site_id  } @obj);

# create a media object
my $media = Krang::Media->new(title => 'test media object', category_id => $category->category_id, media_type_id => 1);
my $filepath = catfile(KrangRoot,'t','media','krang.jpg');
my $fh = new FileHandle $filepath;
$media->upload_file(filename => 'krang.jpg', filehandle => $fh);
$media->save();
END { $media->delete if $media };

# append the media object to the export
($in, $out, $err) = ("", "", "");
@cmd = ($krang_export, '--append', $kds, '--media_id', $media->media_id);
run(\@cmd, \$in, \$out, \$err);
ok(length($err) == 0);  
like($out, qr/Export completed/);
ok(-s $kds);

# try loading it with Krang::DataSet
$set = Krang::DataSet->new(path => $kds);
isa_ok($set, 'Krang::DataSet');

# there should be five objects here, the story, the category, the
# site and the media object
@obj = $set->list;
is(@obj, 4);
ok(grep { $_->[0] eq 'Krang::Story' and
          $_->[1] eq $story->story_id  } @obj);
ok(grep { $_->[0] eq 'Krang::Category' and
          $_->[1] eq $story->category->category_id  } @obj);
ok(grep { $_->[0] eq 'Krang::Site' and
          $_->[1] eq $story->category->site->site_id  } @obj);
ok(grep { $_->[0] eq 'Krang::Media' and
          $_->[1] eq $media->media_id  } @obj);
