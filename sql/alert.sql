DROP TABLE IF EXISTS alert;

--
-- Table structure for table 'alert'
--

CREATE TABLE alert (
    alert_id int(10) unsigned not NULL auto_increment,
    user_id int(10) unsigned not NULL,
    action varchar(255) default NULL,
    desk_id int(10) unsigned default NULL,
    category_id int(10) unsigned default NULL,
    object_type varchar(255) default NULL,
    object_id int unsigned default NULL,
    custom_msg_subject VARCHAR(255) default NULL,
    custom_msg_body TEXT default NULL,
    PRIMARY KEY (alert_id),
    KEY `object_type` (`object_type`,`object_id`)
) ENGINE=MyISAM;

