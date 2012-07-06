/* user table holds data managed by Krang::Group */


/* DEPRECATE OLD TABLES */
DROP TABLE IF EXISTS permission_group;
DROP TABLE IF EXISTS app_class;
DROP TABLE IF EXISTS app_class_group_permission;
DROP TABLE IF EXISTS asset;
DROP TABLE IF EXISTS asset_group_permission;


/* Table for Krang groups */
DROP TABLE IF EXISTS group_permission;  /* "group" is a reserved word. */
CREATE TABLE group_permission (
        group_id             SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        group_uuid           CHAR(36),
        name                 VARCHAR(255) NOT NULL DEFAULT "",
        may_publish          BOOL NOT NULL DEFAULT 0,
        may_checkin_all      BOOL NOT NULL DEFAULT 0,
        admin_users          BOOL NOT NULL DEFAULT 0,
        admin_users_limited  BOOL NOT NULL DEFAULT 0,
        admin_groups         BOOL NOT NULL DEFAULT 0,
        admin_contribs       BOOL NOT NULL DEFAULT 0,
        admin_sites          BOOL NOT NULL DEFAULT 0,
        admin_categories     BOOL NOT NULL DEFAULT 0,
        admin_categories_ftp BOOL NOT NULL DEFAULT 0,
        admin_jobs           BOOL NOT NULL DEFAULT 0,
        admin_scheduler      BOOL NOT NULL DEFAULT 0,
        admin_desks          BOOL NOT NULL DEFAULT 0,
        admin_lists          BOOL NOT NULL DEFAULT 0,
        admin_delete         BOOL NOT NULL DEFAULT 1,
        may_view_trash       BOOL NOT NULL DEFAULT 0,
        asset_story          ENUM ("hide", "read-only", "edit") NOT NULL DEFAULT "hide",
        asset_media          ENUM ("hide", "read-only", "edit") NOT NULL DEFAULT "hide",
        asset_template       ENUM ("hide", "read-only", "edit") NOT NULL DEFAULT "hide",
        INDEX (group_uuid)
);

/* set up default groups w/ null UUIDs - getting real ones via Krang::UUID 
   would be better, but how? */
INSERT INTO group_permission VALUES (1, NULL, 'Admin'  , 1,1,1,0,1,1,1,1,0,1,1,1,1,1,1, "edit", "edit", "edit");
INSERT INTO group_permission VALUES (2, NULL, 'Editor' , 1,0,1,1,0,1,0,1,0,1,0,0,0,1,1, "edit", "edit", "read-only");
INSERT INTO group_permission VALUES (3, NULL, 'Default', 0,0,0,0,0,0,0,0,0,0,0,0,0,0,1, "read-only", "read-only", "hide");


/* Join table: desk <-> group_permission */
DROP TABLE IF EXISTS desk_group_permission;
CREATE TABLE desk_group_permission (
        desk_id  SMALLINT UNSIGNED NOT NULL,
        group_id SMALLINT UNSIGNED NOT NULL,
        permission_type ENUM ("hide", "read-only", "edit") NOT NULL DEFAULT "edit",
        PRIMARY KEY (desk_id, group_id),
        INDEX (group_id)
);

/* set up default desk permissions */
INSERT INTO desk_group_permission VALUES (1, 1, "edit");
INSERT INTO desk_group_permission VALUES (2, 1, "edit");
INSERT INTO desk_group_permission VALUES (1, 2, "edit");
INSERT INTO desk_group_permission VALUES (2, 2, "edit");
INSERT INTO desk_group_permission VALUES (1, 3, "hide");
INSERT INTO desk_group_permission VALUES (2, 3, "hide");

/* Join table: user <-> group_permission */
DROP TABLE IF EXISTS user_group_permission;
CREATE TABLE user_group_permission (
        user_id         SMALLINT UNSIGNED NOT NULL,
        group_id	SMALLINT UNSIGNED NOT NULL,
        PRIMARY KEY (user_id, group_id),
        INDEX (group_id)
);

/* set default (admin) user permissions for 'admin' and 'system' */
INSERT INTO user_group_permission VALUES (1,1);
INSERT INTO user_group_permission VALUES (2,1);

/* Join table: category <-> group_permission */
DROP TABLE IF EXISTS category_group_permission;
CREATE TABLE category_group_permission (
        category_id SMALLINT UNSIGNED NOT NULL,
        group_id    SMALLINT UNSIGNED NOT NULL,
        permission_type ENUM ("hide", "read-only", "edit") NOT NULL DEFAULT "edit",
        PRIMARY KEY (category_id, group_id),
        INDEX (group_id)
);

DROP TABLE IF EXISTS user_category_permission_cache;
CREATE TABLE user_category_permission_cache (
        category_id SMALLINT UNSIGNED NOT NULL,
        user_id     SMALLINT UNSIGNED NOT NULL,
        may_see     BOOL NOT NULL DEFAULT "0",
        may_edit    BOOL NOT NULL DEFAULT "0",
        PRIMARY KEY (category_id, user_id),
        INDEX (user_id)
);
