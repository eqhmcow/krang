/* user table holds data managed by Krang::User and accessed by
   Krang::CGI::Login */
DROP TABLE IF EXISTS usr;
DROP TABLE IF EXISTS user;
CREATE TABLE user (
        user_id         INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        email           VARCHAR(255),
        first_name	VARCHAR(64),
        last_name	VARCHAR(64),
        login           VARCHAR(255) NOT NULL,
        mobile_phone	VARCHAR(32),
        password        VARCHAR(255) NOT NULL,
        phone		VARCHAR(32),
        KEY (login)
);

/* default account 'admin', password 'shredder' */
INSERT INTO user (email, login, password, first_name, last_name) VALUES
('Joe@Admin.com', 'admin', '36ca9aadabe4e2adcfcc9747dfb0ea10', 'Joe', 'Admin');

DROP TABLE IF EXISTS usr_user_group;
DROP TABLE IF EXISTS user_group_permission;
CREATE TABLE user_group_permission (
        user_id         INT UNSIGNED NOT NULL,
        group_id	INT UNSIGNED NOT NULL,
        permission_type	ENUM('edit','hide','read-only') NOT NULL DEFAULT "edit",
        PRIMARY KEY (user_id, group_id)
);

/* associate 'admin' is in group '1' */
INSERT INTO user_group_permission VALUES (1,1,'edit');
