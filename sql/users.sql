/* users table holds data managed by Krang::User and accessed by
   Krang::CGI::Login */
DROP TABLE IF EXISTS users;
CREATE TABLE users (
        user_id  INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        login     VARCHAR(255),
        password  VARCHAR(255)
);

/* default account 'admin', password 'shredder' */
INSERT INTO users (login, password) VALUES ('admin', MD5('shredder'));
