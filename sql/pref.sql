/* pref table holds data managed by Krang::Preference */
DROP TABLE IF EXISTS pref;
CREATE TABLE pref (
        pref_id         INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY
);

DROP TABLE IF EXISTS pref_opt;
CREATE TABLE pref_opt (
        pref_opt_id         INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY
);
