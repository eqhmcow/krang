/* user table holds data managed by Krang::User and accessed by
   Krang::CGI::Login  containing old passwords used by users */
DROP TABLE IF EXISTS old_password;
CREATE TABLE old_password (
        user_id     INT UNSIGNED NOT NULL,
        password    VARCHAR(255) NOT NULL,
        timestamp   TIMESTAMP,
        INDEX (user_id)
);

INSERT INTO old_password (user_id, password) VALUES (1, 'f1a93f635e172bd5be55ae08dd41553a');
