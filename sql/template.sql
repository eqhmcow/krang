DROP TABLE IF EXISTS template;

--
-- Table structure for table 'template'
--

CREATE TABLE template (
        id int(11) NOT NULL auto_increment,
        category_id int(11) NOT NULL,
        checked_out tinyint(1) NOT NULL,
        checked_out_by int(11),
        content longtext,
        creation_date timestamp(14) NOT NULL,
        current_version int(11) NOT NULL,
        deploy_date timestamp(14),
        deployed tinyint(1) NOT NULL,
        description tinytext,
        filename tinytext NOT NULL,
        name tinytext NOT NULL,
        notes text,
        testing int(1) NOT NULL,
        PRIMARY KEY  (id),
        INDEX (category_id),
) TYPE=MyISAM;

--
-- Dumping data for table 'template'
--



DROP TABLE IF EXISTS template_version;

--
-- Table structure for table 'template_version'
--

CREATE TABLE template_version (
        id int(11) NOT NULL auto_increment,
        creation_date timestamp(14) NOT NULL,
        data longtext NOT NULL,
        template_id int(11) NOT NULL,
        version int(11) NOT NULL,
        PRIMARY KEY (id),
        INDEX (template_id),
        INDEX (version)
) TYPE=MyISAM;
