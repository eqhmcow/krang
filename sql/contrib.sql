DROP TABLE IF EXISTS contrib;

--
-- Table structure for table 'contrib'
--

CREATE TABLE contrib (
    contrib_id int(10) unsigned NOT NULL auto_increment,
    prefix varchar(255) default NULL,
    first varchar(255) default NULL,
    middle varchar(255) default NULL,
    last varchar(255) default NULL,
    suffix varchar(255) default NULL,
    email varchar(255) default NULL,
    phone varchar(255) default NULL,
    bio text,
    url text,
    PRIMARY KEY contrib_id (contrib_id)
) TYPE=MyISAM;

DROP TABLE IF EXISTS contrib_type;

--
-- Table structure for table 'contrib_type'
--

CREATE TABLE contrib_type (
    contrib_type_id int(10) unsigned NOT NULL auto_increment,
    type varchar(255) default NULL,
    PRIMARY KEY contrib_type_id (contrib_type_id)
) TYPE=MyISAM;

DROP TABLE IF EXISTS contrib_contrib_type;

--
-- Table structure for table 'contrib_contrib_type'
--

CREATE TABLE contrib_contrib_type (
    contrib_id int(10) unsigned NOT NULL,
    contrib_type_id int(10) unsigned NOT NULL,
    KEY contrib_id (contrib_id),
    KEY contrib_type_id (contrib_type_id)
) TYPE=MyISAM;

