/* element holds data managed by Krang::Element */
DROP TABLE IF EXISTS element;
CREATE TABLE element (
        element_id  INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        parent_id   INT UNSIGNED,
        root_id     INT UNSIGNED,
        class       VARCHAR(255) NOT NULL,
        ord         SMALLINT UNSIGNED NOT NULL,
        data        MEDIUMTEXT,

        INDEX       (root_id),
        INDEX       (parent_id),
        INDEX       (ord)
);
