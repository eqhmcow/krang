/* managed by Krang::DB to verify consistency at run-time */
DROP TABLE IF EXISTS db_version;
CREATE TABLE db_version (
        db_version VARCHAR(255) NOT NULL
);
INSERT INTO db_version (db_version) VALUES ("0");
