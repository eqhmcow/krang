use Test::More qw(no_plan);
use strict;
use warnings;
use Krang::Script;
use Krang::Site;
use Krang::Category;
use Krang::Story;
use Krang::Conf qw(KrangRoot);
use Krang::Element qw(foreach_element);
use File::Spec::Functions qw(catfile);
BEGIN { use_ok('Krang::DataSet') }

my $DEBUG = 1; # supresses deleting kds files at process end

# create a dataset with a single contributor
my $contrib = Krang::Contrib->new(first  => 'J.',
                                  middle => 'Jonah',
                                  last   => 'Jameson', 
                                  email  => 'jjj@dailybugle.com',
                                  bio    => 'The editor of the Daily Bugle.',
                                 );
$contrib->contrib_type_ids(1,3);
$contrib->save();
END { $contrib->delete() };

my $cset = Krang::DataSet->new();
isa_ok($cset, 'Krang::DataSet');
$cset->add(object => $contrib);

my $jpath = catfile(KrangRoot, 'tmp', 'jjj.kds');
$cset->write(path => $jpath);
ok(-e $jpath and -s $jpath);
END { unlink($jpath) if -e $jpath and not $DEBUG };

# try an import, should work
$cset->import_all();

# try an import with no_update, should fail
eval { $cset->import_all(no_update => 1); };
isa_ok($@, 'Krang::DataSet::ImportRejected');

# make a change and see if it gets overwritten
$contrib->bio('The greatest editor of the Daily Bugle, ever.');
$contrib->save;

my ($loaded_contrib) = Krang::Contrib->find(contrib_id => 
                                            $contrib->contrib_id);
is($loaded_contrib->bio, 'The greatest editor of the Daily Bugle, ever.');

$cset->import_all();

my ($loaded_contrib2) = Krang::Contrib->find(contrib_id => 
                                             $contrib->contrib_id);
is($loaded_contrib2->bio, 'The editor of the Daily Bugle.');

# create a site and category for dummy story
my $site = Krang::Site->new(preview_url  => 'storytest.preview.com',
                            url          => 'storytest.com',
                            publish_path => '/tmp/storytest_publish',
                            preview_path => '/tmp/storytest_preview');
$site->save();
END { $site->delete() }
my ($category) = Krang::Category->find(site_id => $site->site_id());

my $site2 = Krang::Site->new(preview_url  => 'storytest2.preview.com',
                             url          => 'storytest2.com',
                             publish_path => '/tmp/storytest_publish2',
                             preview_path => '/tmp/storytest_preview2');
$site2->save();
END { $site2->delete() }
my ($category2) = Krang::Category->find(site_id => $site2->site_id());

# create a new story
my $story = Krang::Story->new(categories => [$category],
                              title      => "Test",
                              slug       => "test",
                              class      => "article");
$story->save();
END { (Krang::Story->find(url => $story->url))[0]->delete() }

# create a new story, again
my $story2 = Krang::Story->new(categories => [$category],
                               title      => "Test2",
                               slug       => "test2",
                               class      => "article");
$story2->save();
END { (Krang::Story->find(url => $story2->url))[0]->delete() }

# add schedule for story
my $sched =  Krang::Schedule->new(object_type => 'story',
                                object_id   => $story->story_id,
                                action      => 'publish',
                                repeat      => 'hourly',
                                minute      => '0'
                                );

# create a data set containing the story
my $set = Krang::DataSet->new();
isa_ok($set, 'Krang::DataSet');
$set->add(object => $story);
$set->add(object => $story2);

# write it out
my $path = catfile(KrangRoot, 'tmp', 'test.kds');
$set->write(path => $path);
ok(-e $path and -s $path);
END { unlink($path) if -e $path and not $DEBUG };

# try loading it again
my $loaded = Krang::DataSet->new(path => $path);
isa_ok($loaded, 'Krang::DataSet');

# make sure add() matches loaded
my @objects = $loaded->list();
ok(@objects >= 2);
ok(grep { $_->[0] eq 'Krang::Story' and
          $_->[1] eq $story->story_id  } @objects);
ok(grep { $_->[0] eq 'Krang::Story' and
          $_->[1] eq $story2->story_id } @objects);

# try an import
$loaded->import_all();

# try an import with no_update, should fail
eval { $loaded->import_all(no_update => 1); };
isa_ok($@, 'Krang::DataSet::ImportRejected');

# see if it will write again
my $path2 = catfile(KrangRoot, 'tmp', 'test2.kds');
$set->write(path => $path2);
ok(-e $path2 and -s $path2);
END { unlink($path2) if -e $path2 and not $DEBUG };

# create a media object
my $media = Krang::Media->new(title => 'test media object', category_id => $category->category_id, media_type_id => 1);
my $filepath = catfile(KrangRoot,'t','media','krang.jpg');
my $fh = new FileHandle $filepath;
$media->upload_file(filename => 'krang.jpg', filehandle => $fh);
$media->save();
END { $media->delete if $media };

# add it to the set
$loaded->add(object => $media);

# see if it will write again
my $path3 = catfile(KrangRoot, 'tmp', 'test3.kds');
$loaded->write(path => $path3);
ok(-e $path3 and -s $path3);
END { unlink($path3) if -e $path3 and not $DEBUG };


# create 10 stories
my $count = Krang::Story->find(count => 1);
my $undo = catfile(KrangRoot, 'tmp', 'undo.pl');
system("bin/krang_floodfill --stories 7 --sites 1 --cats 3 --templates 0 --media 5 --users 0 --covers 3 --contribs 10 --undo_script $undo > /dev/null 2>&1");
is(Krang::Story->find(count => 1), $count + 10);

# see if we can serialize them
my @stories = Krang::Story->find(limit    => 10, 
                                 offset   => $count, 
                                 order_by => 'story_id');

# create a data set containing the stories
my $set10 = Krang::DataSet->new();
isa_ok($set10, 'Krang::DataSet');
$set10->add(object => $_) for @stories;

my $path10 = catfile(KrangRoot, 'tmp', '10stories.kds');
$set10->write(path => $path10);
ok(-e $path10 and -s $path10);
END { unlink($path10) if -e $path10 and not $DEBUG };

# delete the floodfilled stories
system("$undo > /dev/null 2>&1");

# load the dataset with an import handler to collect imported objects
my @imported;
my $import10 = Krang::DataSet->new(path => $path10,
                                   import_callback => 
                                   sub { push(@imported, $_[1]) });
isa_ok($import10, 'Krang::DataSet');
$import10->import_all();

# should be 10 stories
is((grep { $_->isa('Krang::Story') } @imported), 10);

# check category content
my %story_cats = map { ($_->url, $_) } map { $_->categories } @stories;
my %import_cats = map { ($_->url, $_) } grep { $_->isa('Krang::Category') } @imported;
foreach my $import_cat (values %import_cats) {
    ok($story_cats{$import_cat->url});
    if ($story_cats{$import_cat->url}->parent) {
        is($story_cats{$import_cat->url}->parent->url,
           $import_cat->parent->url);
    }
}

# check story content
my %imported = map { ($_->url, $_) } 
  grep { $_->isa('Krang::Story') } @imported;
foreach my $story (@stories) {
    my $import = $imported{$story->url};

    # there's a match
    ok($import);

    foreach_element { 
        # check that element content is the same for all paragraphs
        if ($_->name eq 'paragraph') {
            is(($import->element->match($_->xpath))[0]->data(), $_->data);
        }

        # BROKEN: this doesn't work because Krang::Media and
        # Krang::ElementClass may need to do a find() on categories to
        # load its URL.  Since the category object is already deleted
        # the call to url() fails.
        
        # check that story links point to stories with the right URLs
        #if ($_->class->isa('Krang::ElementClass::StoryLink')) {
        #    is(($import->element->match($_->xpath))[0]->data()->url,
        #       $_->data->url);
        #}

        # check that media links point to stories with the right URLs
        #if ($_->class->isa('Krang::ElementClass::MediaLink')) {
        #    is(($import->element->match($_->xpath))[0]->data()->url,
        #       $_->data->url);
        #}
    } $story->element;
}

# cleanup everything in the right order
END { 
    $_->delete for (grep { $_->isa('Krang::Media') } @imported);
    $_->delete for (grep { $_->isa('Krang::Story') } @imported);
    $_->delete 
      for (sort { length($b->url) cmp length($a->url) }
           grep { defined $_->parent_id } 
           grep { $_->isa('Krang::Category') } @imported);
    $_->delete for (grep { $_->isa('Krang::Site') } @imported);
    $_->delete for (grep { $_->isa('Krang::Contrib') } @imported);
};

# try deleting a site a loading it from a data set
my $lsite = Krang::Site->new(preview_url  => 'preview.lazarus.com',
                            url          => 'lazarus.com',
                            publish_path => '/tmp/lazarus',
                            preview_path => '/tmp/lazarus');
$lsite->save();

my $lset = Krang::DataSet->new();
$lset->add(object => $lsite);

# it lives, yes?
my ($found) = Krang::Site->find(url => 'lazarus.com', count => 1);
ok($found);

# this should fail
eval { $lset->import_all(no_update => 1) };
ok($@);

# it dies
$lsite->delete();
($found) = Krang::Site->find(url => 'lazarus.com', count => 1);
ok(not $found);

# the resurection
$lset->import_all();
($found) = Krang::Site->find(url => 'lazarus.com', count => 1);
ok($found);
END { (Krang::Site->find(url => 'lazarus.com'))[0]->delete() };

# try the same with media
$filepath = catfile(KrangRoot,'t','media','krang.jpg');
$fh = new FileHandle $filepath;
my $lmedia = Krang::Media->new(title         => 'test media object', 
                               category_id   => $category->category_id, 
                               media_type_id => 1,
                               filename      => 'lazarus.jpg', 
                               filehandle    => $fh);
$lmedia->save();
$lset->add(object => $lmedia);

# it lives, yes?
($found) = Krang::Media->find(url_like => '%lazarus.jpg', count => 1);
ok($found);

# this should fail
eval { $lset->import_all(no_update => 1) };
ok($@);

# it dies
$lmedia->delete();
($found) = Krang::Media->find(url_like => '%lazarus.jpg', count => 1);
ok(not $found);

# the resurection
$lset->import_all();
($found) = Krang::Media->find(url_like => '%lazarus.jpg', count => 1);
ok($found);
END { (Krang::Media->find(url_like => '%lazarus.jpg'))[0]->delete() }

# try the same with template
my $ltemplate = Krang::Template->new(filename => 'abcd_fake.tmpl',
                                     category_id => $category->category_id,
                                     content => 'this is the content here' );

$ltemplate->save();
$ltemplate->mark_as_deployed();
$lset->add(object => $ltemplate);
                                                                                     
# it lives, yes?
($found) = Krang::Template->find(url => $ltemplate->url, count => 1 );
ok($found);
                                                                                     
# this should fail
eval { $lset->import_all(no_update => 1) };
ok($@);
                                                                                     
# it dies
$ltemplate->delete();
($found) = Krang::Template->find(url => $ltemplate->url, count => 1);
ok(not $found);
                                                                                     
# the resurection
$lset->import_all();
($found) = Krang::Template->find(url => $ltemplate->url, count => 1);
ok($found);
END { (Krang::Template->find(url => $ltemplate->url))[0]->delete() }

# create a story with an element tree and make sure it gets through an
# export/import intact
# create a new story
my $big = Krang::Story->new(categories => [$category],
                            title      => "Big",
                            slug       => "big",
                            class      => "article");
$big->element->child('deck')->data("DECK DECK DECK");
$big->save();

my $bset = Krang::DataSet->new();
$bset->add(object => $big);

ok(Krang::Story->find(url => $big->url));
$big->delete();
ok(not Krang::Story->find(url => $big->url));

$bset->import_all();
($big) = Krang::Story->find(url => $big->url);
ok($big);
END { $big->delete };

is($big->element->child('deck')->data, "DECK DECK DECK");

# create a pair of stories that point to each other in a circle
my $jack = Krang::Story->new(categories => [$category],
                             title      => "Jack",
                             slug       => "jack",
                             class      => "cover");
$jack->save();

# create a pair of stories that point to each other in a circle
my $jill = Krang::Story->new(categories => [$category2],
                             title      => "Jill",
                             slug       => "jill",
                             class      => "cover");
$jill->save();

$jack->element->add_child(class => 'leadin',
                          data  => $jill);
$jill->element->add_child(class => 'leadin',
                          data  => $jack);
$jack->save();
$jill->save();

# serialize them
my $j2set = Krang::DataSet->new();
$j2set->add(object => $jack);
$j2set->add(object => $jill);
isa_ok($j2set, 'Krang::DataSet');

# should be just two stories
is((grep { $_->[0] eq 'Krang::Story' } $j2set->list), 2);

# write it out
my $j2path = catfile(KrangRoot, 'tmp', 'j2.kds');
$j2set->write(path => $j2path);
ok(-e $j2path and -s $j2path);
END { unlink($j2path) if -e $j2path and not $DEBUG };

$jack->delete();
$jill->delete();

# try an import
$j2set->import_all;

# should have them back
my ($imported_jack) = Krang::Story->find(url => $jack->url);
isa_ok($imported_jack, 'Krang::Story');
my ($imported_jill) = Krang::Story->find(url => $jill->url);
isa_ok($imported_jill, 'Krang::Story');

# do they point to each other?
is($imported_jack->element->child('leadin')->data->story_id, 
   $imported_jill->story_id);
is($imported_jill->element->child('leadin')->data->story_id,
   $imported_jack->story_id);

END { $imported_jack->delete();
      $imported_jill->delete(); };
