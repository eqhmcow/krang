/* my_pref table holds data managed by Krang::MyPref */
DROP TABLE IF EXISTS my_pref;
CREATE TABLE my_pref (
        id      VARCHAR(255) NOT NULL,
        user_id int(10) unsigned NOT NULL,
        value   VARCHAR(255) NOT NULL,
        PRIMARY KEY (user_id, id)	
);
