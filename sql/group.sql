/* user table holds data managed by Krang::Group */


/* Table for Krang groups */
DROP TABLE IF EXISTS permission_group;  /* "group" is a reserved word. */
CREATE TABLE permission_group (
        group_id        INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        name            VARCHAR(255),
        may_edit_user   BOOL,
        may_publish     BOOL
);

/* set up default groups */
INSERT INTO permission_group (group_id, name) VALUES (1, 'Global Admin');
INSERT INTO permission_group (group_id, name) VALUES (2, 'Site Admin');
INSERT INTO permission_group (group_id, name) VALUES (3, 'Category Admin');
INSERT INTO permission_group (group_id, name) VALUES (4, 'Default');


/* Join table: category <-> permission_group */
DROP TABLE IF EXISTS category_group_permission;
CREATE TABLE category_group_permission (
        category_id     INT UNSIGNED NOT NULL,
        group_id        INT UNSIGNED NOT NULL,
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
        category_id     INT UNSIGNED NOT NULL,
        group_id        INT UNSIGNED NOT NULL,
        may_see         BOOL NOT NULL DEFAULT "0",
        may_edit        BOOL NOT NULL DEFAULT "0",
        PRIMARY KEY (category_id, group_id)        
);


/* Table for Krang "Application Classes" */
DROP TABLE IF EXISTS app_class;
CREATE TABLE app_class (
        app_class_id    INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        name            VARCHAR(255)
);

/* set up default application classes */
INSERT INTO app_class (app_class_id, name) VALUES (1, 'Story');
INSERT INTO app_class (app_class_id, name) VALUES (2, 'Media');
INSERT INTO app_class (app_class_id, name) VALUES (3, 'Template');
INSERT INTO app_class (app_class_id, name) VALUES (4, 'Admin');


/* Join table: app_class <-> permission_group */
DROP TABLE IF EXISTS app_class_group_permission;
CREATE TABLE app_class_group_permission (
        app_class_id    INT UNSIGNED NOT NULL,
        group_id        INT UNSIGNED NOT NULL,
        permission_type ENUM ("hide", "read-only", "edit") NOT NULL DEFAULT "edit",
        PRIMARY KEY (app_class_id, group_id)        
);


/* Join table: desk <-> permission_group */
DROP TABLE IF EXISTS desk_group_permission;
CREATE TABLE desk_group_permission (
        desk_id         INT UNSIGNED NOT NULL,
        group_id        INT UNSIGNED NOT NULL,
        permission_type ENUM ("hide", "read-only", "edit") NOT NULL DEFAULT "edit",
        PRIMARY KEY (desk_id, group_id)        
);
