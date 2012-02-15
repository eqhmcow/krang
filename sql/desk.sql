DROP TABLE IF EXISTS desk;

--
-- Table structure for table 'desk'
--

CREATE TABLE desk (
    desk_id int(10) unsigned NOT NULL auto_increment,
    name varchar(255), 
    ord int(10) unsigned, 
    PRIMARY KEY (desk_id)
) ENGINE=MyISAM;


--
-- Insert Default Desks
--
INSERT INTO desk VALUES (1, "Edit", 1);
INSERT INTO desk VALUES (2, "Publish", 2);


