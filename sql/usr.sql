/* user table holds data managed by Krang::User and accessed by
   Krang::CGI::Login */
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS usr;
CREATE TABLE usr (
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
INSERT INTO usr (login, password) VALUES ('admin',
'36ca9aadabe4e2adcfcc9747dfb0ea10');

DROP TABLE IF EXISTS usr_user_group;
CREATE TABLE usr_user_group (
        user_id         INT UNSIGNED NOT NULL,
        user_group_id   INT UNSIGNED NOT NULL,
        PRIMARY KEY (user_id, user_group_id)        
);
