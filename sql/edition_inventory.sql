-- ============================================================================
-- edition_inventory.sql
--
-- Purpose:
--   Read-only report of the EBR lab layout: the current session
--   edition, the database default edition, every edition in the
--   database, which users are editions-enabled and their default
--   editions, and which lab objects are editioned in which edition.
--   Use it after running ebr_lab_setup_v1.sql, and again after every
--   later stage, to see exactly what changed between editions.
--
-- Usage:
--   Run as a privileged user, for example SYSDBA:
--
--     sqlplus / as sysdba @edition_inventory.sql
--
--   To check a different lab schema or edition, edit the DEFINE
--   lines below.
--
-- Exit code:
--   0 - lab schema is editions-enabled, the expected edition exists,
--       and the V1 view and package are editioned in that edition
--   2 - any of those checks fails
--
-- Notes:
--   Read-only. Needs Oracle Database 12c Release 1 or later, because
--   it reads DBA_USERS.DEFAULT_EDITION_NAME. DBA_EDITIONS lists every
--   edition; DBA_OBJECTS_AE lists objects across all editions, while
--   DBA_OBJECTS shows only the objects visible in the current edition.
--   Reviewed; not executed against a live Oracle instance.
-- ============================================================================

SET ECHO OFF
SET FEEDBACK OFF
SET VERIFY OFF
SET PAGESIZE 100
SET LINESIZE 160
SET TRIMSPOOL ON
SET TAB OFF

-- ----------------------------------------------------------------------------
-- Lab parameters. Edit to match the local lab database.
-- ----------------------------------------------------------------------------
DEFINE lab_schema = LAB_APP
DEFINE edition_name = V1

PROMPT
PROMPT === 1. Current session edition and database default edition ===

COLUMN current_edition FORMAT A20 HEADING 'CURRENT EDITION'
COLUMN db_default_edition FORMAT A20 HEADING 'DATABASE DEFAULT'

SELECT SYS_CONTEXT('USERENV', 'CURRENT_EDITION_NAME') AS current_edition
  FROM dual;

SELECT property_value AS db_default_edition
  FROM database_properties
 WHERE property_name = 'DEFAULT_EDITION';

PROMPT
PROMPT === 2. Editions in this database ===
PROMPT (Each edition has one parent; ORA$BASE is the root. An edition
PROMPT  can have at most one child, so editions form a single chain.)

COLUMN edition_name        FORMAT A20 HEADING 'EDITION'
COLUMN parent_edition_name FORMAT A20 HEADING 'PARENT EDITION'
COLUMN usable              FORMAT A6  HEADING 'USABLE'

SELECT edition_name,
       parent_edition_name,
       usable
  FROM dba_editions
 ORDER BY edition_name;

PROMPT
PROMPT === 3. Editions-enabled users and their default editions ===

COLUMN username             FORMAT A20 HEADING 'USER'
COLUMN editions_enabled    FORMAT A10 HEADING 'EDITIONS'
COLUMN default_edition_name FORMAT A20 HEADING 'DEFAULT EDITION'

SELECT username,
       editions_enabled,
       default_edition_name
  FROM dba_users
 WHERE editions_enabled = 'Y'
    OR username = '&lab_schema'
 ORDER BY username;

PROMPT
PROMPT === 4. Editioned lab objects, by edition ===
PROMPT (DBA_OBJECTS_AE shows objects across all editions. An editioned
PROMPT  object is identified by owner, name, and edition name.)

COLUMN owner        FORMAT A12 HEADING 'OWNER'
COLUMN object_name  FORMAT A20 HEADING 'OBJECT'
COLUMN object_type  FORMAT A15 HEADING 'TYPE'
COLUMN edition_name FORMAT A12 HEADING 'EDITION'
COLUMN status       FORMAT A8  HEADING 'STATUS'

SELECT owner,
       object_name,
       object_type,
       edition_name,
       status
  FROM dba_objects_ae
 WHERE owner = '&lab_schema'
   AND edition_name IS NOT NULL
 ORDER BY edition_name, object_type, object_name;

PROMPT
PROMPT === 5. Noneditioned lab objects ===
PROMPT (Tables, sequences, and indexes are noneditioned: one copy,
PROMPT  visible from every edition, with a null edition name.)

SELECT owner,
       object_name,
       object_type,
       status
  FROM dba_objects
 WHERE owner = '&lab_schema'
   AND edition_name IS NULL
 ORDER BY object_type, object_name;

PROMPT
PROMPT === Verdict ===

COLUMN exit_code NOPRINT NEW_VALUE v_exit_code
SELECT CASE
         WHEN (SELECT editions_enabled
                 FROM dba_users
                WHERE username = '&lab_schema') <> 'Y' THEN 2
         WHEN NOT EXISTS (SELECT 1
                            FROM dba_editions
                           WHERE edition_name = '&edition_name') THEN 2
         WHEN NOT EXISTS (SELECT 1
                            FROM dba_objects_ae
                           WHERE owner = '&lab_schema'
                             AND object_name = 'ORDER_API'
                             AND object_type = 'PACKAGE'
                             AND edition_name = '&edition_name') THEN 2
         WHEN NOT EXISTS (SELECT 1
                            FROM dba_objects_ae
                           WHERE owner = '&lab_schema'
                             AND object_name = 'CUSTOMER_ORDERS'
                             AND object_type = 'VIEW'
                             AND edition_name = '&edition_name') THEN 2
         WHEN NOT EXISTS (SELECT 1
                            FROM dba_objects
                           WHERE owner = '&lab_schema'
                             AND object_name = 'CUSTOMERS'
                             AND object_type = 'TABLE'
                             AND edition_name IS NULL) THEN 2
         ELSE 0
       END AS exit_code
  FROM dual;

PROMPT
PROMPT Done. Exit code: &v_exit_code (0 = lab layout as expected, 2 = a check failed)
PROMPT A clean report means the edition layout matches the lab design.
PROMPT It does not prove the application behaves the same in each edition.
EXIT &v_exit_code
