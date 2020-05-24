/* user table holds data managed by Krang::User and accessed by
   Krang::CGI::Login */
DROP TABLE IF EXISTS user;
CREATE TABLE user (
        user_id          INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        user_uuid        CHAR(36) NOT NULL,
        email            VARCHAR(255),
        first_name	     VARCHAR(64),
        last_name	     VARCHAR(64),
        login            VARCHAR(255) NOT NULL,
        mobile_phone	 VARCHAR(32),
        password         VARCHAR(255) NOT NULL,
        phone		     VARCHAR(32),
        hidden           BOOL NOT NULL DEFAULT 0,
        force_pw_change  BOOL NOT NULL DEFAULT 0,
        password_changed INT UNSIGNED,
        KEY (login),
        INDEX (hidden)
);

/* default account 'admin', password 'whale' */
INSERT INTO user (email, login, password, first_name, last_name, password_changed, user_uuid) VALUES
('Joe@Admin.com', 'admin', 'f1a93f635e172bd5be55ae08dd41553a', 'Joe', 'Admin', UNIX_TIMESTAMP(NOW()), UUID());

/* default account 'system', hidden with no password*/
INSERT INTO user (email, login, password, first_name, last_name, hidden, user_uuid) VALUES
('system@noemail.com', 'system', '*', 'System', 'User', 1, UUID());
