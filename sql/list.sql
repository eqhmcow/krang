DROP TABLE IF EXISTS list_group;

--
-- Table structure for table 'list_group'
--

CREATE TABLE list_group (
  list_group_id mediumint unsigned NOT NULL auto_increment,
  name varchar(255) NOT NULL,
  description text,
  PRIMARY KEY  (list_group_id),
  KEY (name)
) TYPE=MyISAM;

DROP TABLE IF EXISTS list;

--
-- Table structure for table 'list'
--

CREATE TABLE list (
  list_id mediumint unsigned NOT NULL auto_increment,
  list_group_id mediumint unsigned NOT NULL,
  name varchar(255) NOT NULL,
  parent_list_id mediumint,
  PRIMARY KEY (list_id),
  KEY (name)
) TYPE=MyISAM;

DROP TABLE IF EXISTS list_data;
                                                                                
--
-- Table structure for table 'list_data'
--
                                                                                
CREATE TABLE list_data (
  list_data_id mediumint unsigned NOT NULL auto_increment,
  list_id mediumint unsigned NOT NULL,
  parent_list_data_id  mediumint unsigned,
  data varchar(255) NOT NULL,
  ord smallint NOT NULL,
  PRIMARY KEY (list_data_id) 
) TYPE=MyISAM;


