package V1_000;
use strict;
use warnings;
use base 'Krang::Upgrade';


use Krang::Conf qw(InstanceDBName DBUser DBPass KrangRoot);
use Krang::DB qw(dbh);

# Nothing to do for this version....
sub per_installation {
    my $self = shift;
}


# add media_id column to the contrib table
sub per_instance {
    my $self = shift;

    my $dbh = dbh();
    my $instance = Krang::Conf->instance();

    # fix broken syndicate/ category created by bug in Krang::Category
    my $result = $dbh->selectall_arrayref('SELECT category_id, url FROM category WHERE url LIKE ?', {}, '%syndicate%');
    foreach my $row (@$result) {
        my ($category_id, $url) = @$row;
        next if $url =~ /news/;
        my $new_url = $url;
        $new_url =~ s!syndicate!news/syndicate!;
        $dbh->do('UPDATE category SET url = ? WHERE category_id = ?', {},
                 $new_url, $category_id);
        
        my $stories = dbh->selectall_arrayref('SELECT story_id, url FROM story_category WHERE category_id = ?', {}, $category_id);
        foreach my $story (@$stories) {
            my ($story_id, $url) = @$story;
            next if $url =~ /news/;
            my $new_url = $url;
            $new_url =~ s!syndicate!news/syndicate!;
            $dbh->do('UPDATE story_category SET url = ? WHERE story_id = ? AND category_id = ?', {},
                     $new_url, $story_id, $category_id);
        }
    }                
}


1;
