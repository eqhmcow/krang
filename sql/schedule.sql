/* schedule table is managed by Krang::Schedule */
DROP TABLE IF EXISTS schedule;
CREATE TABLE schedule (
        schedule_id     INT UNSIGNED NOT NULL,
        repeat          ENUM('never', 'hourly', 'daily', 'weekly') NOT NULL,
        action          VARCHAR(255) NOT NULL,
        context         TEXT,
        object_type     VARCHAR(255) NOT NULL,
        object_id       INT UNSIGNED NOT NULL,
        next_run        DATETIME NOT NULL,
        PRIMARY KEY (schedule_id),
        INDEX       (object_type, object_id),
        INDEX       (next_run),
);
