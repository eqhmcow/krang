/* tracks locations of published content, managed by Krang::Publisher */
DROP TABLE IF EXISTS publish_story_location;
CREATE TABLE publish_story_location (
        story_id       INT UNSIGNED NOT NULL,
        preview        BOOL NOT NULL,
        path           VARCHAR(255) NOT NULL,
        INDEX(story_id, preview)
);

DROP TABLE IF EXISTS publish_media_location;
CREATE TABLE publish_media_location (
        media_id       INT UNSIGNED NOT NULL,
        preview        BOOL NOT NULL,
        path           VARCHAR(255) NOT NULL,
        INDEX(media_id, preview)
);

