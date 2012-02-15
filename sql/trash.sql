DROP TABLE IF EXISTS trash;

--
-- Table structure for table 'trash'
--

CREATE TABLE trash (
    object_type  varchar(255)      NOT NULL,
    object_id 	 int(10) unsigned  NOT NULL,
    timestamp    datetime          NOT NULL,
    INDEX (object_type, object_id)
) ENGINE=MyISAM;

