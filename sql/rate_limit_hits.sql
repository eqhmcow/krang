DROP TABLE IF EXISTS rate_limit_hits;

--
-- Table structure for table 'desk'
--

CREATE TABLE rate_limit_hits (
   user_id   VARCHAR(255)      NOT NULL,
   action    VARCHAR(255)      NOT NULL,
   timestamp INTEGER UNSIGNED NOT NULL,
   INDEX (user_id(15), action(30), timestamp)
) ENGINE=MyISAM;

