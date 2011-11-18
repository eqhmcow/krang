DROP TABLE IF EXISTS media;

--
-- Table structure for table 'media'
--

CREATE TABLE media (
    media_id                mediumint unsigned NOT NULL auto_increment,
    media_uuid              CHAR(36) NOT NULL,
    element_id              int unsigned NOT NULL,
    category_id             mediumint unsigned NOT NULL,
    title                   varchar(255) NOT NULL,
    filename                varchar(255) NOT NULL,
    caption                 text,
    copyright               text,
    notes                   text,
    url                     varchar(255) NOT NULL,
    alt_tag                 varchar(255) default NULL,
    mime_type               varchar(255),
    version                 SMALLINT unsigned NOT NULL,
    creation_date           datetime NOT NULL,
    last_modified_date      datetime,
    media_type_id           mediumint unsigned default NULL,
    preview_version         INT UNSIGNED,
    published_version       mediumint unsigned default NULL,
    publish_date            datetime default NULL,
    checked_out_by          smallint unsigned default NULL,
    retired                 bool NOT NULL DEFAULT 0,
    trashed                 bool NOT NULL DEFAULT 0,
    published               bool NOT NULL DEFAULT 0,
    read_only               bool NOT NULL DEFAULT 0,
    PRIMARY KEY (media_id),
    KEY (category_id), KEY (media_type_id),
    KEY (url), KEY (title),
    KEY (checked_out_by), UNIQUE KEY (media_uuid)
) TYPE=MyISAM;

DROP TABLE IF EXISTS media_version;

--
-- Table structure for table 'media_version'
--

CREATE TABLE media_version (
    media_id        mediumint unsigned NOT NULL,
    version         SMALLINT unsigned NOT NULL,
    data            mediumblob NOT NULL,
    PRIMARY KEY (media_id, version),
    KEY (media_id),
    KEY (version)
) TYPE=MyISAM;

DROP TABLE IF EXISTS media_type;

--
-- Table structure for table 'media_type'
--

CREATE TABLE media_type (
    media_type_id   smallint unsigned NOT NULL auto_increment,
    name            varchar(255) NOT NULL,
    PRIMARY KEY (media_type_id)
) TYPE=MyISAM;

-- Default data for media_type

insert into media_type (name) values ('Image');           
insert into media_type (name) values ('Text');
insert into media_type (name) values ('HTML');
insert into media_type (name) values ('PDF');
insert into media_type (name) values ('Excel');
insert into media_type (name) values ('Word');
insert into media_type (name) values ('Video');
insert into media_type (name) values ('Audio');
insert into media_type (name) values ('Flash');
insert into media_type (name) values ('JavaScript'); 
insert into media_type (name) values ('Stylesheet'); 
insert into media_type (name) values ('Include'); 
insert into media_type (name) values ('Power Point'); 

--
-- Table structure for table 'media_contrib'
--

DROP TABLE IF EXISTS media_contrib;
CREATE TABLE media_contrib (
    media_id        mediumint UNSIGNED NOT NULL,
    contrib_id      mediumint UNSIGNED NOT NULL,
    contrib_type_id smallint UNSIGNED NOT NULL,
    ord             smallint UNSIGNED NOT NULL,
    PRIMARY KEY (media_id, contrib_id, ord),
    KEY (media_id),
    KEY (contrib_id)
);
