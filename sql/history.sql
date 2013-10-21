DROP TABLE IF EXISTS history;

--
-- Table structure for table 'history'
--

CREATE TABLE history (
    object_type varchar(255) NOT NULL,
    object_id int(10) unsigned NOT NULL,
    action varchar(255) default NULL,
    version int(10) unsigned default NULL,
    desk_id int(10) unsigned default NULL,
    user_id int(10) unsigned not NULL,
    schedule_id int(10) unsigned NOT NULL,
    timestamp datetime default NULL,
    INDEX (object_type, object_id)
) ENGINE=MyISAM;

