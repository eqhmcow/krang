package V3_16;
use strict;
use warnings;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => 'Upgrade';
use Krang::ClassLoader DB   => 'dbh';
use Krang::ClassLoader 'Story';

sub per_instance {
    my ($self, %args) = @_;
    return if $args{no_db};
    my $dbh = dbh();
    $dbh->do('ALTER table schedule ENGINE=InnoDB');
    $dbh->do('ALTER table schedule add column daemon_uuid varchar(128) default null');

    $dbh->do('DROP TABLE IF EXISTS story_category_link');
    $dbh->do(q/
        CREATE TABLE story_category_link (
                story_category_link_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                story_id        INT UNSIGNED NOT NULL,
                category_id     INT UNSIGNED NOT NULL,
                publish_if_modified_story_in_cat    BOOL NOT NULL DEFAULT 0,
                publish_if_modified_story_below_cat BOOL NOT NULL DEFAULT 0,
                publish_if_modified_media_in_cat    BOOL NOT NULL DEFAULT 0,
                publish_if_modified_media_below_cat BOOL NOT NULL DEFAULT 0,
                PRIMARY KEY (story_category_link_id),
                UNIQUE KEY (story_id, category_id),
                INDEX (category_id, publish_if_modified_story_in_cat),
                INDEX (category_id, publish_if_modified_story_below_cat),
                INDEX (category_id, publish_if_modified_media_in_cat),
                INDEX (category_id, publish_if_modified_media_below_cat)
        ) 
    /);

    # look through each story and create any story_category_link entries that need to exist
    for my $story (pkg('Story')->find) {
        next if $story->trashed || $story->retired;
        $story->_save_category_links();
    }
}

sub per_installation {
    my ($self, %args) = @_;
    # remove old files
    $self->remove_files(
        qw(
          src/Module-Build-0.30.tar.gz
          src/Params-Validate-0.88.tar.gz
          src/ExtUtils-CBuilder-0.24.tar.gz
          src/Parse-CPAN-Meta-1.40.tar.gz
          )
    );

}

1;
