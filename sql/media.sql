DROP TABLE IF EXISTS media;

--
-- Table structure for table 'media'
--

CREATE TABLE media (
  media_id int(10) unsigned NOT NULL auto_increment,
  category_id int(10) unsigned default NULL,
  title varchar(255) default NULL,
  filename varchar(255) default NULL,
  caption text,
  copyright text,
  notes text,
  uri varchar(255) default NULL,
  alt_tag varchar(255) default NULL,
  version SMALLINT unsigned default NULL,
  creation_date date default NULL,
  media_type_id int(10) unsigned default NULL,
  published_version int(10) unsigned default NULL,
  checked_out_by int(10) unsigned default NULL,
  PRIMARY KEY  (media_id),
  KEY category_id (category_id),
  KEY media_type_id (media_type_id)
) TYPE=MyISAM;

DROP TABLE IF EXISTS media_version;

--
-- Table structure for table 'media_version'
--

CREATE TABLE media_version (
  media_id int(10) unsigned NOT NULL,
  version SMALLINT unsigned NOT NULL,
  data longtext,
  PRIMARY KEY (media_id, version)
) TYPE=MyISAM;

DROP TABLE IF EXISTS media_type;

--
-- Table structure for table 'media_type'
--

CREATE TABLE media_type (
  media_type_id int(10) unsigned NOT NULL auto_increment,
  name varchar(255) default NULL,
  PRIMARY KEY  (media_type_id)
) TYPE=MyISAM;

