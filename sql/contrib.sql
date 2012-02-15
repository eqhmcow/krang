DROP TABLE IF EXISTS contrib;

--
-- Table structure for table 'contrib'
-- This table stores contributor information.
--

CREATE TABLE contrib (
    contrib_id  int(10) unsigned NOT NULL auto_increment,
    prefix      varchar(255) default NULL,
    first       varchar(255) default NULL,
    middle      varchar(255) default NULL,
    last        varchar(255) default NULL,
    suffix      varchar(255) default NULL,
    email       varchar(255) default NULL,
    phone       varchar(255) default NULL,
    media_id    mediumint unsigned default NULL,
    bio         text,
    url         text,
    PRIMARY KEY contrib_id (contrib_id)
) ENGINE=MyISAM;

DROP TABLE IF EXISTS contrib_type;

--
-- Table structure for table 'contrib_type'
-- This table stores contributor types.  
-- It has a many:many relationship with 'contrib'.
--

CREATE TABLE contrib_type (
    contrib_type_id     SMALLINT unsigned NOT NULL auto_increment,
    type varchar(255)   NOT NULL,
    PRIMARY KEY         contrib_type_id (contrib_type_id)
) ENGINE=MyISAM;

-- Insert base types
INSERT INTO contrib_type (contrib_type_id, type) VALUES (1, 'Writer');
INSERT INTO contrib_type (contrib_type_id, type) VALUES (2, 'Illustrator');
INSERT INTO contrib_type (contrib_type_id, type) VALUES (3, 'Photographer');

DROP TABLE IF EXISTS contrib_contrib_type;

--
-- Table structure for table 'contrib_contrib_type'
-- This is the join table between 'contrib' and 'contrib_type'.
--

CREATE TABLE contrib_contrib_type (
    contrib_id          int(10) unsigned NOT NULL,
    contrib_type_id     int(10) unsigned NOT NULL,
    PRIMARY KEY         (contrib_id, contrib_type_id)
) ENGINE=MyISAM;

