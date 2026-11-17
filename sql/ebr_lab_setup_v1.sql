-- ============================================================================
-- ebr_lab_setup_v1.sql
--
-- Purpose:
--   Builds version 1 of the EBR lab: the V1 edition, an editions-enabled
--   lab schema, and the first version of a small customer and order
--   application. Tables are noneditioned and shared by every edition.
--   The view and the PL/SQL package are editioned in V1, so later
--   stages can redefine them in a child edition without touching V1.
--
-- Usage:
--   Run as a DBA account, for example SYSDBA, in a scratch database:
--
--     sqlplus / as sysdba @ebr_lab_setup_v1.sql
--
--   To change the lab password, edit the DEFINE line below before
--   running the script. Use a lab-only password. Never use a real
--   credential, and never run this script against a database that
--   matters. Re-running the script in the same database fails, because
--   the edition and the user already exist; drop them first
--   (see docs/lab-setup.md) or rebuild the lab database.
--
-- Exit code:
--   0 - edition, user, tables, view, package, and seed data created
--   non-zero - a statement failed (WHENEVER SQLERROR exits immediately)
--
-- Notes:
--   Creates a user and an edition, so it is not read-only. Enabling
--   editions for a user is irreversible. The V1 objects are created
--   while the session edition is V1, which is what makes the view and
--   the package editioned in V1. Objects created in ORA$BASE would not
--   be editioned. Reviewed; not executed against a live Oracle instance.
-- ============================================================================

SET ECHO OFF
SET FEEDBACK ON
SET VERIFY OFF
SET PAGESIZE 100
SET LINESIZE 160
SET TRIMSPOOL ON
SET TAB OFF

WHENEVER SQLERROR EXIT SQL.SQLCODE

-- ----------------------------------------------------------------------------
-- Lab parameters. Edit to match the local lab database.
-- ----------------------------------------------------------------------------
DEFINE lab_schema = LAB_APP
DEFINE lab_password = CHANGEME_LAB_ONLY
DEFINE edition_name = V1

PROMPT
PROMPT === 1. Create the V1 edition ===
PROMPT (V1 is a child of the root edition ORA$BASE.)

CREATE EDITION &edition_name;

PROMPT
PROMPT === 2. Create the lab schema and enable editions ===
PROMPT (Editions are enabled before the schema creates any object,
PROMPT  because an object is editioned only when its owner is
PROMPT  editions-enabled and it is created in a non-ORA$BASE edition.)

CREATE USER &lab_schema IDENTIFIED BY &lab_password
  DEFAULT TABLESPACE users
  QUOTA UNLIMITED ON users;

GRANT CREATE SESSION,
      CREATE TABLE,
      CREATE SEQUENCE,
      CREATE VIEW,
      CREATE PROCEDURE,
      CREATE TRIGGER,
      CREATE SYNONYM
   TO &lab_schema;

ALTER USER &lab_schema ENABLE EDITIONS;
ALTER USER &lab_schema DEFAULT EDITION = &edition_name;
GRANT USE ON EDITION &edition_name TO &lab_schema;

PROMPT
PROMPT === 3. Connect as the lab schema ===
PROMPT (The session edition is the user default edition, V1.)

CONNECT &lab_schema/&lab_password

COLUMN current_edition FORMAT A20 HEADING 'CURRENT EDITION'
SELECT SYS_CONTEXT('USERENV', 'CURRENT_EDITION_NAME') AS current_edition
  FROM dual;

PROMPT
PROMPT === 4. Noneditioned tables ===
PROMPT (Tables exist once and are visible from every edition. The lab
PROMPT  uses sequences for keys so the script stays valid on 11gR2.)

CREATE SEQUENCE customer_seq START WITH 101;
CREATE SEQUENCE order_seq START WITH 1001;

CREATE TABLE customers (
  customer_id   NUMBER PRIMARY KEY,
  customer_name VARCHAR2(100) NOT NULL,
  email         VARCHAR2(200)
);

CREATE TABLE orders (
  order_id    NUMBER PRIMARY KEY,
  customer_id NUMBER NOT NULL REFERENCES customers(customer_id),
  order_date  DATE NOT NULL,
  amount      NUMBER(10,2) NOT NULL
);

PROMPT
PROMPT === 5. Editioned view and package in V1 ===
PROMPT (Created while the session edition is V1, so both are editioned
PROMPT  in V1 and can be redefined in a child edition later.)

CREATE OR REPLACE VIEW customer_orders AS
SELECT c.customer_id,
       c.customer_name,
       o.order_id,
       o.order_date,
       o.amount
  FROM customers c
  JOIN orders o
    ON o.customer_id = c.customer_id;

CREATE OR REPLACE PACKAGE order_api AS
  PROCEDURE place_order(p_customer_id IN NUMBER, p_amount IN NUMBER);
  FUNCTION order_total(p_order_id IN NUMBER) RETURN NUMBER;
  FUNCTION customer_order_count(p_customer_id IN NUMBER) RETURN NUMBER;
END order_api;
/

CREATE OR REPLACE PACKAGE BODY order_api AS

  PROCEDURE place_order(p_customer_id IN NUMBER, p_amount IN NUMBER) IS
  BEGIN
    INSERT INTO orders (order_id, customer_id, order_date, amount)
    VALUES (order_seq.NEXTVAL, p_customer_id, SYSDATE, p_amount);
  END place_order;

  FUNCTION order_total(p_order_id IN NUMBER) RETURN NUMBER IS
    v_amount NUMBER(10,2);
  BEGIN
    SELECT amount INTO v_amount
      FROM orders
     WHERE order_id = p_order_id;
    RETURN v_amount;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RETURN NULL;
  END order_total;

  FUNCTION customer_order_count(p_customer_id IN NUMBER) RETURN NUMBER IS
    v_count NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_count
      FROM orders
     WHERE customer_id = p_customer_id;
    RETURN v_count;
  END customer_order_count;

END order_api;
/

PROMPT
PROMPT === 6. Seed data through the V1 package ===

INSERT INTO customers (customer_id, customer_name, email)
VALUES (customer_seq.NEXTVAL, 'Acme Supply Co', 'orders@acme.example.local');
INSERT INTO customers (customer_id, customer_name, email)
VALUES (customer_seq.NEXTVAL, 'Riverside Books', 'hello@riverside.example.local');
INSERT INTO customers (customer_id, customer_name, email)
VALUES (customer_seq.NEXTVAL, 'Northgate Hardware', 'sales@northgate.example.local');
COMMIT;

BEGIN
  order_api.place_order(p_customer_id => 101, p_amount => 249.99);
  order_api.place_order(p_customer_id => 101, p_amount => 89.50);
  order_api.place_order(p_customer_id => 102, p_amount => 45.00);
END;
/
COMMIT;

PROMPT
PROMPT === 7. Verify what was created ===
PROMPT (Editioned objects show EDITION_NAME V1. Noneditioned objects
PROMPT  show a null edition name, because they belong to no edition.)

COLUMN object_name  FORMAT A20 HEADING 'OBJECT'
COLUMN object_type  FORMAT A15 HEADING 'TYPE'
COLUMN edition_name FORMAT A12 HEADING 'EDITION'
COLUMN status       FORMAT A8  HEADING 'STATUS'

SELECT object_name,
       object_type,
       edition_name,
       status
  FROM user_objects
 WHERE object_name IN ('CUSTOMERS', 'ORDERS', 'CUSTOMER_SEQ', 'ORDER_SEQ',
                       'CUSTOMER_ORDERS', 'ORDER_API')
 ORDER BY object_type, object_name;

SELECT COUNT(*) AS order_rows FROM orders;
SELECT COUNT(*) AS customer_rows FROM customers;

PROMPT
PROMPT Done. V1 lab is built: edition V1, schema &lab_schema, tables
PROMPT CUSTOMERS and ORDERS, view CUSTOMER_ORDERS, package ORDER_API.
PROMPT Run sql/edition_inventory.sql to inspect the edition layout.
EXIT 0
