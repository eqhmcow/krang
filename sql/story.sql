/* story holds data managed by Krang::Story */
DROP TABLE IF EXISTS story;
CREATE TABLE story (
        story_id        INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        version         SMALLINT UNSIGNED NOT NULL,

        title           VARCHAR(255) NOT NULL,
        slug            VARCHAR(255) NOT NULL,
        cover_date      DATETIME,
        notes           TEXT,

        element_id      INT UNSIGNED NOT NULL,

        checked_out     BOOL NOT NULL,
        checked_out_by  INT UNSIGNED NOT NULL,

        desk_id         SMALLINT UNSIGNED,

        INDEX(desk_id),
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
        uri             VARCHAR(255) NOT NULL,
        PRIMARY KEY (story_id, category_id, ord)
);

/* story_category holds links between stories and contributors managed
   by Krang::Story */
DROP TABLE IF EXISTS story_contributor;
CREATE TABLE story_contributor (
        story_id        INT UNSIGNED NOT NULL,
        contributor_id  INT UNSIGNED NOT NULL,
        ord             SMALLINT UNSIGNED NOT NULL,
        PRIMARY KEY (story_id, contributor_id, ord)
);

/* story_schedule holds scheduled events for stories, managed by
Krang::Story */
DROP TABLE IF EXISTS story_schedule;
CREATE TABLE story_schedule (
        story_id        INT UNSIGNED NOT NULL,
        ord             SMALLINT UNSIGNED NOT NULL,
        type            ENUM('absolute', 'hourly', 'daily', 'weekly') NOT NULL,
        date            DATETIME NOT NULL,
        action          ENUM('publish', 'expire') NOT NULL,
        version         SMALLINT UNSIGNED,
        PRIMARY KEY (story_id, ord)
);
