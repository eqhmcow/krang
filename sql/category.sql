--
-- Table structure for table 'category'
--

DROP TABLE IF EXISTS category;
CREATE TABLE category (
        category_id	int UNSIGNED NOT NULL AUTO_INCREMENT,
        element_id      int UNSIGNED,
        parent_id	int UNSIGNED,
        path		varchar(255) NOT NULL,
        site_id		int UNSIGNED,
        PRIMARY KEY (category_id),
        KEY (element_id),
        KEY (parent_id),
        KEY (site_id)
) TYPE=MyISAM;
