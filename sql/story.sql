/* story holds data managed by Krang::Story */
DROP TABLE IF EXISTS story;
CREATE TABLE story (
        story_id        INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        version         SMALLINT UNSIGNED NOT NULL,

        title           VARCHAR(255) NOT NULL,
        slug            VARCHAR(255) NOT NULL,
        cover_date      DATETIME,
        publish_date    DATETIME,
        published_version INT UNSIGNED,
        notes           TEXT,
        priority        TINYINT UNSIGNED NOT NULL DEFAULT 2,
        
        element_id      INT UNSIGNED NOT NULL,
        class           VARCHAR(255) NOT NULL,

        checked_out     BOOL NOT NULL,
        checked_out_by  INT UNSIGNED NOT NULL,

        desk_id         SMALLINT UNSIGNED,

        INDEX(desk_id),
        INDEX(title),
        INDEX(checked_out),
        INDEX(checked_out_by)
);

/* story_version holds version data managed by Krang::Story */
DROP TABLE IF EXISTS story_version;
CREATE TABLE story_version (
        story_id        INT      UNSIGNED NOT NULL,
        version         SMALLINT UNSIGNED NOT NULL,
        data            LONGTEXT,
        PRIMARY KEY (story_id, version)
);

/* story_category holds links between stories and categories managed
   by Krang::Story */
DROP TABLE IF EXISTS story_category;
CREATE TABLE story_category (
        story_id        INT UNSIGNED NOT NULL,
        category_id     INT UNSIGNED NOT NULL,
        ord             SMALLINT UNSIGNED NOT NULL,
        url             VARCHAR(255) NOT NULL,
        PRIMARY KEY (story_id, category_id),
        INDEX (category_id),
        INDEX (url),
        INDEX (ord)
);

/* story_contrib holds links between stories and contributors managed
   by Krang::Story */
DROP TABLE IF EXISTS story_contrib;
CREATE TABLE story_contrib (
        story_id        INT UNSIGNED NOT NULL,
        contrib_id      INT UNSIGNED NOT NULL,
        contrib_type_id INT UNSIGNED NOT NULL,
        ord             SMALLINT UNSIGNED NOT NULL,
        PRIMARY KEY (story_id, contrib_id, contrib_type_id),
        INDEX (ord)
);
