/* user table holds data managed by Krang::User and accessed by
   Krang::CGI::Login  containing old passwords used by users */
DROP TABLE IF EXISTS old_password;
CREATE TABLE old_password (
        user_id     INT UNSIGNED NOT NULL,
        password    VARCHAR(255) NOT NULL,
        timestamp   TIMESTAMP,
        INDEX (user_id),
        PRIMARY KEY (user_id, password)
);
