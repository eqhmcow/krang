package V3_00;
use strict;
use warnings;

use Krang::ClassLoader base => 'Upgrade';

use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader Conf => qw(KrangRoot);
use Krang::ClassLoader DB => qw(dbh);
use Krang::ClassLoader 'ElementLibrary';
use Krang::ClassLoader 'Story';
use Krang::ClassLoader 'Category';

use File::Spec::Functions qw(catfile);


# Add new krang.conf directive PreviewSSL
sub per_installation {
    _update_config();
}


sub per_instance {
    my $self = shift;
    my $dbh = dbh();

    # add the 'use_autocomplete' preference
    $dbh->do('INSERT INTO pref (id, value) VALUES ("use_autocomplete", "1")');
    # add the 'message_timeout' preference
    $dbh->do('INSERT INTO pref (id, value) VALUES ("message_timeout", "5")');
    # change sessions and story_version tables to handle UTF-8
    $dbh->do('ALTER TABLE sessions CHANGE COLUMN a_session a_session BLOB');
    $dbh->do('ALTER TABLE story_version CHANGE COLUMN data data BLOB');
    $dbh->do('ALTER TABLE template_version CHANGE COLUMN data data BLOB');
    $dbh->do('ALTER TABLE media_version CHANGE COLUMN data data BLOB');

    $self->_wipe_slugs_from_cover_stories();

    $self->_fix_slugs_that_duplicate_categories();
}

# add new EnableFTP and Secret directives if they aren't already there
sub _update_config {
    open(CONF, '<', catfile(KrangRoot, 'conf', 'krang.conf'))
      or die "Unable to open conf/krang.conf: $!";
    my $conf = do { local $/; <CONF> };
    close(CONF);

    # write out conf and add the new lines
    open(CONF, '>', catfile(KrangRoot, 'conf', 'krang.conf'))
      or die "Unable to open conf/krang.conf: $!";
    print CONF $conf;
    print CONF "\nEnableFTP 1\n" unless $conf =~ /^\s*EnableFTP/m;

    # create a random secret
    my $secret = _random_secret();
    print CONF "\nSecret '$secret'\n" unless $conf =~ /^\s*Secret/m;
    close(CONF);
}

sub _random_secret {
    my $length = int(rand(10) + 20);
    my $secret = '';
    my @chars = ('a'..'z', 'A'..'Z', 0..9, qw(! @ $ % ^ & - _ = + | ; : . / < > ?));
    $secret .= $chars[int(rand($#chars + 1))] for(0..$length);
    return $secret;
}


# remove slugs from stories that subclass Cover 
# (since slugs will now be optional for all types)
sub _wipe_slugs_from_cover_stories {

    my @types_that_subclass_cover =
	grep { pkg('ElementLibrary')->top_level(name => $_)->isa('Krang::ElementClass::Cover') }
            pkg('ElementLibrary')->top_levels;

    my $dbh = dbh();
    my $sql = qq/update story set slug="" where story.class=?/;
    my $sth = $dbh->prepare($sql);
    
    foreach my $type (@types_that_subclass_cover) {
	print "Cleaning slugs from stories of type '$type'... ";
	$sth->execute($type);
	print "DONE\n";
    }
}


# now that the URLs of categories and stories-with-slugs must be distinct,
# look for duplicates and - when found - resolve them by creating new categories
sub _fix_slugs_that_duplicate_categories {
    print "\nLooking for Stories that must be turned into Covers to avoid URL conflicts: ";

    # grab the ID of every story that conflicts with a category
    my $dbh = dbh();
    my $query = 'select sc.story_id from category c, story_category sc where c.url=concat(sc.url, "/")';
    my $result = $dbh->selectall_arrayref($query, undef);

    if ($result && @$result) {
        print "Found " . @$result . "\n\n";
    
        # Set REMOTE_USER -- needed for API calls
        local($ENV{REMOTE_USER}) = 2; # Magic ID of "system" user
  
        # loop through stories, converting them into category covers
        foreach (@$result) {
            my $story_id = $_->[0];

            # grab story object and - if necessary - check it in
            my ($story) = pkg('Story')->find(story_id => $story_id);

            print "  Converting Story $story_id (".$story->url.") into a Category Cover...\n";

            # Force check-in, if necessary
            if ($story->checked_out) {
                print "    First checking it in: ";
                eval { $story->checkin; };
                if ($@) {
                    print " FAILED (skipping)\n\n";
                }
                print " Done\n";
            }
	    
            # give story temporary slug so we don't throw dupe error during conversion!
            $story->checkout;
            my $slug = $story->slug;
            $story->slug('_TEMP_SLUG_FOR_CONVERSION_'); $story->save;

            # make new categories by appending slug to existing categories
            my @old_cats = $story->categories;
            my @new_cats;
            foreach my $old_cat (@old_cats) {
                my ($new_cat) = pkg('Category')->find(url => $old_cat->url . $slug . '/');
                unless ($new_cat) {
                    print "    Creating new category: ". $old_cat->url . $slug ."/\n";
                    $new_cat = pkg('Category')->new(dir       => $slug,
                                                    parent_id => $old_cat->category_id,
                                                    site_id   => $old_cat->site_id);
                    $new_cat->save;
                } else {
                    print "    Found existing category: ".$new_cat->url."\n";
                }
                push @new_cats, $new_cat;
                print "    Moving story from " . $old_cat->url . " to " . $new_cat->url . "\n";
            }
            print "    Emptying slug.\n";
            $story->slug('');
	    
            # save changes
            $story->categories(@new_cats);
            $story->save; 
            $story->checkin;
        }
    } else {
        print "None found.\n\n";
    }
}

1;
