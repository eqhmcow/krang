/* schedule table is managed by Krang::Schedule */
DROP TABLE IF EXISTS schedule;
CREATE TABLE schedule (
        schedule_id     INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `repeat`          ENUM('never', 'hourly', 'daily', 'weekly') NOT NULL,
        action          VARCHAR(255) NOT NULL,
        context         TEXT,
        object_type     VARCHAR(255) NOT NULL,
        object_id       INT UNSIGNED NOT NULL,
        initial_date    DATETIME,
        last_run        DATETIME,
        next_run        DATETIME NOT NULL,
        day_of_week     INT UNSIGNED,
        hour            INT UNSIGNED,
        minute          INT UNSIGNED,
        priority        INT UNSIGNED NOT NULL,

        PRIMARY KEY (schedule_id),
        INDEX       (object_type, object_id),
        INDEX       (next_run)
);

/* add default scheduled tasks for tmp cleaning, session expiration
and DB analyze runs */
INSERT INTO schedule 
 (`repeat`, action, object_type, initial_date, last_run, next_run, hour, minute) 
VALUES
 ('daily', 'clean', 'tmp', NOW(), NOW(), NOW(), 3, 0);

INSERT INTO schedule 
 (`repeat`, action, object_type, initial_date, last_run, next_run, hour, minute) 
VALUES
 ('daily', 'clean', 'session', NOW(), NOW(), NOW(), 3, 0);

INSERT INTO schedule 
 (`repeat`, action, object_type, initial_date, last_run, next_run, hour, minute) 
VALUES
 ('daily', 'clean', 'analyze', NOW(), NOW(), NOW(), 3, 0);

