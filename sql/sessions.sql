/* the sessions table is managed by Krang::Session, using
Apache::Session::MySQL */
DROP TABLE IF EXISTS sessions;
CREATE TABLE sessions (
    id char(32) not null primary key,
    a_session blob,
    last_modified timestamp
 );
