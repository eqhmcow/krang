/* user table holds data managed by Krang::Group */


/* DEPRECATE OLD TABLES */
DROP TABLE IF EXISTS app_class;
DROP TABLE IF EXISTS app_class_group_permission;
DROP TABLE IF EXISTS asset;
DROP TABLE IF EXISTS asset_group_permission;


/* Table for Krang groups */
DROP TABLE IF EXISTS permission_group;  /* "group" is a reserved word. */
CREATE TABLE permission_group (
        group_id            INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        name                VARCHAR(255),
        may_publish         BOOL,
        admin_users         BOOL,
        admin_users_limited BOOL,
        admin_groups        BOOL,
        admin_contribs      BOOL,
        admin_sites         BOOL,
        admin_categories    BOOL,
        admin_jobs          BOOL,
        admin_desks         BOOL,
        admin_prefs         BOOL,
        asset_story         ENUM ("hide", "read-only", "edit") NOT NULL DEFAULT "edit",
        asset_media         ENUM ("hide", "read-only", "edit") NOT NULL DEFAULT "edit",
        asset_template      ENUM ("hide", "read-only", "edit") NOT NULL DEFAULT "edit"
);

/* set up default groups */
INSERT INTO permission_group VALUES (1, 'Admin'  , 1,1,0,1,1,1,1,1,1,1, "edit", "edit", "edit");
INSERT INTO permission_group VALUES (2, 'Editor' , 1,1,1,0,1,0,1,1,0,0, "edit", "edit", "read-only");
INSERT INTO permission_group VALUES (3, 'Default', 0,0,0,0,0,0,0,0,0,0, "read-only", "read-only", "hide");


/* Join table: desk <-> permission_group */
DROP TABLE IF EXISTS desk_group_permission;
CREATE TABLE desk_group_permission (
        desk_id  INT UNSIGNED NOT NULL,
        group_id INT UNSIGNED NOT NULL,
        permission_type ENUM ("hide", "read-only", "edit") NOT NULL DEFAULT "edit",
        PRIMARY KEY (desk_id, group_id)        
);


/* Join table: category <-> permission_group */
DROP TABLE IF EXISTS category_group_permission;
CREATE TABLE category_group_permission (
        category_id INT UNSIGNED NOT NULL,
        group_id    INT UNSIGNED NOT NULL,
        permission_type ENUM ("hide", "read-only", "edit") NOT NULL DEFAULT "edit",
        PRIMARY KEY (category_id, group_id)        
);


/* De-normalized cache of category_group_permission */
/* The purpose of this table is to provide a run-time optimization
   for determining if a particular user (who belongs to N groups)
   is allowed to access a particular category.  This table is 
   "guaranteed" to contain one record for every group/category
   combination.  Unlike category_group_permission which contains
   only records of logical permission assignments, this table 
   will allow calling code to exactly find the permissions for
   a category/group without traversing the tree of categories. */
DROP TABLE IF EXISTS category_group_permission_cache;
CREATE TABLE category_group_permission_cache (
        category_id INT UNSIGNED NOT NULL,
        group_id    INT UNSIGNED NOT NULL,
        may_see     BOOL NOT NULL DEFAULT "0",
        may_edit    BOOL NOT NULL DEFAULT "0",
        PRIMARY KEY (category_id, group_id)        
);
