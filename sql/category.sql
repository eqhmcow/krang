--
-- Table structure for table 'category'
--

DROP TABLE IF EXISTS category;
CREATE TABLE category (
        category_id	int UNSIGNED NOT NULL AUTO_INCREMENT,
        category_uuid   CHAR(36) NOT NULL,
        element_id      int UNSIGNED,
        dir		varchar(255) NOT NULL,
        parent_id	int UNSIGNED,
        site_id		int UNSIGNED,
        url		varchar(255) NOT NULL,
        PRIMARY KEY (category_id),
        KEY (element_id),
        KEY (dir),
        KEY (parent_id),
        KEY (site_id),
        KEY (url)
) ENGINE=MyISAM;
