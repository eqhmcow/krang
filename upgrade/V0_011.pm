package V0_011;
use strict;
use warnings;
use base 'Krang::Upgrade';


use Krang::Conf qw(InstanceDBName DBUser DBPass KrangRoot);
use Krang::DB qw(dbh);


# Nothing to do for this version....
sub per_installation {
    my $self = shift;
}


# Create db_version table
sub per_instance {
    my $self = shift;

    my $dbh = dbh();
    my $instance = Krang::Conf->instance();

    #
    # Create db_version table
    #
    my $create_sql = <<EOSQL;
CREATE TABLE db_version (
        db_version VARCHAR(255) NOT NULL
)
EOSQL
    $dbh->do($create_sql);

    # Insert base data
    $dbh->do("INSERT INTO db_version (db_version) VALUES ('0')");


    #
    # Add mime_type column to media table
    #
    $dbh->do("ALTER TABLE media ADD COLUMN mime_type varchar(255)");


    #
    # Add publish tables
    #
    $create_sql = <<EOSQL;
CREATE TABLE publish_story_location (
        story_id       INT UNSIGNED NOT NULL,
        preview        BOOL NOT NULL,
        path           VARCHAR(255) NOT NULL,
        INDEX(story_id, preview)
)
EOSQL
    $dbh->do($create_sql);

    $create_sql = <<EOSQL;
CREATE TABLE publish_media_location (
        media_id       INT UNSIGNED NOT NULL,
        preview        BOOL NOT NULL,
        path           VARCHAR(255) NOT NULL,
        INDEX(media_id, preview)
)
EOSQL
    $dbh->do($create_sql);


    #
    # Add list tables
    #
    $create_sql = <<EOSQL;
CREATE TABLE list_group (
  list_group_id mediumint unsigned NOT NULL auto_increment,
  name varchar(255) NOT NULL,
  description text,
  PRIMARY KEY  (list_group_id,name),
  KEY (name)
) TYPE=MyISAM
EOSQL
    $dbh->do($create_sql);

    $create_sql = <<EOSQL;
CREATE TABLE list (
  list_id mediumint unsigned NOT NULL auto_increment,
  list_group_id mediumint unsigned NOT NULL,
  name varchar(255) NOT NULL,
  parent_list_id mediumint,
  PRIMARY KEY (list_id),
  KEY (name)
) TYPE=MyISAM
EOSQL
    $dbh->do($create_sql);

    $create_sql = <<EOSQL;
CREATE TABLE list_item (
  list_item_id mediumint unsigned NOT NULL auto_increment,
  list_id mediumint unsigned NOT NULL,
  parent_list_item_id  mediumint unsigned,
  data varchar(255) NOT NULL,
  ord smallint NOT NULL,
  PRIMARY KEY (list_item_id) 
) TYPE=MyISAM
EOSQL
    $dbh->do($create_sql);


    #
    # Add element_index table
    #
    $create_sql = <<EOSQL;
CREATE TABLE element_index (
        element_id  INT UNSIGNED NOT NULL,
        value       VARCHAR(255),
        UNIQUE INDEX(element_id),
        INDEX(value)
)
EOSQL
    $dbh->do($create_sql);
}


1;
