--
-- Table structure for table 'category'
--

DROP TABLE IF EXISTS category;
CREATE TABLE category (
        category_id	int UNSIGNED NOT NULL AUTO_INCREMENT,
        element_id      int UNSIGNED,
        name		varchar(255) NOT NULL,
        parent_id	int UNSIGNED,
        site_id		int UNSIGNED,
        url		text NOT NULL,
        PRIMARY KEY (category_id),
        KEY (element_id),
        KEY (name),
        KEY (parent_id),
        KEY (site_id)
) TYPE=MyISAM;
