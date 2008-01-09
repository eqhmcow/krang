/* pref table holds data managed by Krang::Preference */
DROP TABLE IF EXISTS pref;
CREATE TABLE pref (
        id      VARCHAR(255) NOT NULL PRIMARY KEY,
        value   VARCHAR(255) NOT NULL
);
INSERT INTO pref (id, value) VALUES ("search_page_size", "20");
INSERT INTO pref (id, value) VALUES ("use_autocomplete", "1");
INSERT INTO pref (id, value) VALUES ("message_timeout", "5");
INSERT INTO pref (id, value) VALUES ("language", "en");
