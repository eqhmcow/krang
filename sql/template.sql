--
-- Table structure for table 'template'
--

DROP TABLE IF EXISTS template;
CREATE TABLE template (
        template_id 		int(11) UNSIGNED NOT NULL auto_increment,
        template_uuid           CHAR(36) NOT NULL,
        category_id 		int(11) UNSIGNED,
        checked_out 		tinyint(1) UNSIGNED NOT NULL,
        checked_out_by 		int(11) UNSIGNED ,
        content 		mediumtext,
        creation_date 		datetime NOT NULL,
        deploy_date 		datetime,
        deployed 		tinyint(1) UNSIGNED NOT NULL,
        deployed_version 	int(11) UNSIGNED ,
        element_class_name 	varchar(255),
        filename 		tinytext NOT NULL,
        testing 		int(1) UNSIGNED NOT NULL,
        url			text NOT NULL,
        version 		smallint UNSIGNED NOT NULL,
        retired        BOOL NOT NULL DEFAULT 0,
        trashed         BOOL NOT NULL DEFAULT 0,
        read_only       BOOL NOT NULL DEFAULT 0,
        PRIMARY KEY  (template_id),
        INDEX (category_id),
        INDEX (checked_out_by),
        UNIQUE INDEX (template_uuid)
) ENGINE=MyISAM;


--
-- Table structure for table 'template_version'
--

DROP TABLE IF EXISTS template_version;
CREATE TABLE template_version (
        data 		mediumblob NOT NULL,
        template_id 	int(11) UNSIGNED NOT NULL,
        version 	smallint UNSIGNED NOT NULL,
        PRIMARY KEY (version, template_id)
) ENGINE=MyISAM;
