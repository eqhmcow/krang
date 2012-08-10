package V3_21;
use strict;
use warnings;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => 'Upgrade';
use Krang::ClassLoader DB   => 'dbh';
use Krang::ClassLoader 'Media';

sub per_instance {
    my ($self, %args) = @_;
    return if $args{no_db};
    my $dbh = dbh();

    # add the story_tag table
    $dbh->do(q/
        CREATE TABLE story_tag (
                story_tag_id    INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
                story_id        INT UNSIGNED NOT NULL,
                tag             VARCHAR(255) NOT NULL,
                ord             SMALLINT UNSIGNED NOT NULL,
                INDEX(tag),
                INDEX(story_id, ord) 
        ) ENGINE=InnoDB
    /);

    # add the media_tag table
    $dbh->do(q/
        CREATE TABLE media_tag (
                media_tag_id    INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
                media_id        INT UNSIGNED NOT NULL,
                tag             VARCHAR(255) NOT NULL,
                ord             SMALLINT UNSIGNED NOT NULL,
                INDEX(tag),
                INDEX(media_id, ord)
        ) ENGINE=InnoDB
    /);
}

sub per_installation {
    my ($self, %args) = @_;

    # nothing to do yet
}

1;
