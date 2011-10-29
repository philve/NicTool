# vim: set expandtab ts=4:
#
# $Id: nt_user.sql 1108 2010-06-22 23:29:36Z matt $
#
#
# NicTool v2.00-rc1 Copyright 2001 Damon Edwards, Abe Shelton & Greg Schueler
# NicTool v2.01 Copyright 2004 The Network People, Inc.
#
# NicTool is free software; you can redistribute it and/or modify it under 
# the terms of the Affero General Public License as published by Affero, 
# Inc.; either version 1 of the License, or any later version.
#
# NicTool is distributed in the hope that it will be useful, but WITHOUT 
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY 
# or FITNESS FOR A PARTICULAR PURPOSE. See the Affero GPL for details.
#
# You should have received a copy of the Affero General Public License
# along with this program; if not, write to Affero Inc., 521 Third St,
# Suite 225, San Francisco, CA 94107, USA
#


DROP TABLE IF EXISTS nt_user;
CREATE TABLE nt_user(
    nt_user_id          INT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
    nt_group_id         INT UNSIGNED NOT NULL,
    first_name          VARCHAR(30),
    last_name           VARCHAR(40),
    username            VARCHAR(50) NOT NULL,
    password            VARCHAR(128) NOT NULL,
    email               VARCHAR(100) NOT NULL,
    deleted             ENUM('0','1') DEFAULT '0' NOT NULL
);
CREATE INDEX nt_user_idx1 on nt_user(username, password);
CREATE INDEX nt_user_idx2 on nt_user(deleted);

DROP TABLE IF EXISTS nt_user_log; 
CREATE TABLE nt_user_log(
    nt_user_log_id      INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    nt_group_id        INT UNSIGNED NOT NULL,
    nt_user_id         INT UNSIGNED NOT NULL,
    action             ENUM('added','modified','deleted','moved') NOT NULL,
    timestamp          INT UNSIGNED NOT NULL,
    modified_user_id   INT UNSIGNED NOT NULL,
    first_name         VARCHAR(30),
    last_name          VARCHAR(40),
    username           VARCHAR(50),
    password           VARCHAR(128),
    email              VARCHAR(100)
);


DROP TABLE IF EXISTS nt_user_session;
CREATE TABLE nt_user_session(
    nt_user_session_id       INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    nt_user_id               INT UNSIGNED NOT NULL,
    nt_user_session	     VARCHAR(100) NOT NULL,
    last_access              INT UNSIGNED NOT NULL
);
CREATE INDEX nt_user_session_idx1 on nt_user_session(nt_user_id, nt_user_session);

DROP TABLE IF EXISTS nt_user_session_log;
CREATE TABLE nt_user_session_log(
    nt_user_session_log_id   INT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
    nt_user_id               INT UNSIGNED NOT NULL,
    action                   ENUM('login','logout','timeout') NOT NULL,
    timestamp                INT UNSIGNED NOT NULL,
    nt_user_session_id       INT UNSIGNED,
    nt_user_session	     VARCHAR(100)
);

DROP TABLE IF EXISTS nt_user_global_log;
CREATE TABLE nt_user_global_log(
    nt_user_global_log_id   INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    nt_user_id              INT UNSIGNED NOT NULL,
    timestamp               INT UNSIGNED NOT NULL,
    action                  ENUM('added','deleted','modified','moved','recovered','delegated','modified delegation','removed delegation') NOT NULL,
    object                  ENUM('zone','group','user','nameserver','zone_record') NOT NULL,
    object_id               INT UNSIGNED NOT NULL,
    target                  ENUM('zone','group','user','nameserver','zone_record') ,
    target_id               INT UNSIGNED ,
    target_name             VARCHAR(255),
    log_entry_id            INT UNSIGNED NOT NULL,
    title                   VARCHAR(255),
    description             VARCHAR(255)
);
CREATE INDEX nt_user_global_log_idx1 on nt_user_global_log(nt_user_id);
