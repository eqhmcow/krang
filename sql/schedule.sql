/* schedule table is managed by Krang::Schedule */
DROP TABLE IF EXISTS schedule;
CREATE TABLE schedule (
        schedule_id     INT UNSIGNED NOT NULL AUTO_INCREMENT,
        repeat          ENUM('never', 'hourly', 'daily', 'weekly') NOT NULL,
        action          VARCHAR(255) NOT NULL,
        context         TEXT,
        object_type     VARCHAR(255) NOT NULL,
        object_id       INT UNSIGNED NOT NULL,
        last_run        DATETIME,
        next_run        DATETIME NOT NULL,
        day_of_week     INT UNSIGNED,
        hour            INT UNSIGNED,
        minute          INT UNSIGNED,
        PRIMARY KEY (schedule_id),
        INDEX       (object_type, object_id),
        INDEX       (next_run)
);
