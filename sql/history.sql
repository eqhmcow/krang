DROP TABLE IF EXISTS history;

--
-- Table structure for table 'history'
--

CREATE TABLE history (
    object_type varchar(255) default NULL,
    object_id int(10) unsigned default NULL,
    action varchar(255) default NULL,
    version int(10) unsigned default NULL,
    desk varchar(255) default NULL,
    user_id int(10) unsigned not NULL,
    timestamp datetime default NULL,
    KEY object_type (object_type),
    KEY object_id (object_id)
) TYPE=MyISAM;

