/* story holds data managed by Krang::Story */
DROP TABLE IF EXISTS story;
CREATE TABLE story (
        story_id            INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        version             SMALLINT UNSIGNED NOT NULL,
        story_uuid          CHAR(36) NOT NULL,
        title               VARCHAR(255) NOT NULL,
        slug                VARCHAR(255) NOT NULL,
        cover_date          DATETIME,
        publish_date        DATETIME,
        published_version   INT UNSIGNED,
        preview_version     INT UNSIGNED,
        notes               TEXT,
        element_id          INT UNSIGNED NOT NULL,
        class               VARCHAR(255) NOT NULL,
        hidden              BOOL NOT NULL DEFAULT 0,
        checked_out         BOOL NOT NULL,
        checked_out_by      INT UNSIGNED NOT NULL,
        desk_id             SMALLINT UNSIGNED,
        last_desk_id        SMALLINT UNSIGNED,
        retired             BOOL NOT NULL DEFAULT 0,
        trashed             BOOL NOT NULL DEFAULT 0,
        INDEX(desk_id),
        INDEX(title),
        INDEX(checked_out),
        INDEX(checked_out_by),
        INDEX(class),
        INDEX(published_version),
        UNIQUE INDEX (story_uuid)
);

/* story_version holds version data managed by Krang::Story */
DROP TABLE IF EXISTS story_version;
CREATE TABLE story_version (
        story_id        INT      UNSIGNED NOT NULL,
        version         SMALLINT UNSIGNED NOT NULL,
        data            MEDIUMBLOB,
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

/* story_category_link holds entries about category-link elements between a story and a category */
DROP TABLE IF EXISTS story_category_link;
CREATE TABLE story_category_link (
        story_category_link_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
        story_id        INT UNSIGNED NOT NULL,
        category_id     INT UNSIGNED NOT NULL,
        publish_if_modified_story_in_cat    BOOL NOT NULL DEFAULT 0,
        publish_if_modified_story_below_cat BOOL NOT NULL DEFAULT 0,
        publish_if_modified_media_in_cat    BOOL NOT NULL DEFAULT 0,
        publish_if_modified_media_below_cat BOOL NOT NULL DEFAULT 0,
        PRIMARY KEY (story_category_link_id),
        UNIQUE KEY (story_id, category_id),
        INDEX (category_id, publish_if_modified_story_in_cat),
        INDEX (category_id, publish_if_modified_story_below_cat),
        INDEX (category_id, publish_if_modified_media_in_cat),
        INDEX (category_id, publish_if_modified_media_below_cat)
);

/* story_tag holds tag information about stories managed by Krang::Story */
DROP TABLE IF EXISTS story_tag;
CREATE TABLE story_tag (
        story_tag_id    INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        story_id        INT UNSIGNED NOT NULL,
        tag             VARCHAR(255) NOT NULL,
        ord             SMALLINT UNSIGNED NOT NULL,
        INDEX(tag),
        INDEX(story_id, ord)
) ENGINE=InnoDB;
