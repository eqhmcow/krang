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

/* default account 'admin', password 'whale' */
INSERT INTO user (email, login, password, first_name, last_name) VALUES
('Joe@Admin.com', 'admin', 'f1a93f635e172bd5be55ae08dd41553a', 'Joe', 'Admin');

DROP TABLE IF EXISTS usr_user_group;
