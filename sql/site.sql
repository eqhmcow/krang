--
-- Table structure for table 'site'
--

DROP TABLE IF EXISTS site;
CREATE TABLE site (
       site_id		int UNSIGNED NOT NULL AUTO_INCREMENT,
       site_uuid        CHAR(36) NOT NULL,
       url		varchar(255) NOT NULL,
       preview_url	varchar(255),
       preview_path	varchar(255),
       publish_path	varchar(255) NOT NULL,
       creation_date    datetime NOT NULL,
       primary key (site_id)
) ENGINE=MyISAM;
