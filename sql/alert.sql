DROP TABLE IF EXISTS alert;

--
-- Table structure for table 'alert'
--

CREATE TABLE alert (
    alert_id int(10) unsigned NOT NULL auto_increment,
    user_id int(10) unsigned not NULL,
    action varchar(255) default NULL,
    desk_id int(10) unsigned default NULL,
    category_id int(10) unsigned default NULL,
    PRIMARY KEY (alert_id)
) TYPE=MyISAM;

