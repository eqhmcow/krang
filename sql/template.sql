DROP TABLE IF EXISTS template;

--
-- Table structure for table 'template'
--

CREATE TABLE template (
        template_id int(11) NOT NULL auto_increment,
        category_id int(11) NOT NULL,
        checked_out tinyint(1) NOT NULL,
        checked_out_by int(11),
        content longtext,
        creation_date timestamp(14) NOT NULL,
        deploy_date timestamp(14),
        deployed tinyint(1) NOT NULL,
        element_class varchar(255),
        filename tinytext NOT NULL,
        testing int(1) NOT NULL,
        version int(11) NOT NULL,
        PRIMARY KEY  (template_id),
        INDEX (category_id)
) TYPE=MyISAM;

--
-- Dumping data for table 'template'
--



DROP TABLE IF EXISTS template_version;

--
-- Table structure for table 'template_version'
--

CREATE TABLE template_version (
        template_version_id int(11) NOT NULL auto_increment,
        data longtext NOT NULL,
        template_id int(11) NOT NULL,
        version int(11) NOT NULL,
        PRIMARY KEY (template_version_id),
        INDEX (template_id),
        INDEX (version)
) TYPE=MyISAM;
