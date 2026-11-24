-- ============================================================================
-- ebr_lab_upgrade_v2.sql
--
-- Purpose:
--   Builds version 2 of the EBR lab: a V2 edition as a child of V1, and
--   a redefined ORDER_API package in V2. V1 keeps serving exactly as
--   before. The CUSTOMER_ORDERS view is deliberately not redefined in
--   V2, so it stays inherited from V1; the package is the object that
--   changes in this stage, and the next stage covers views.
--
--   What changes in V2:
--     - place_order rejects a zero or negative amount with error
--       -20001, and rejects an unknown customer with error -20002.
--       In V1 the same calls reach the table unchecked (a negative
--       amount is accepted, an unknown customer fails only on the
--       foreign key with ORA-02291).
--     - A new function, customer_total_spent, returns the total of a
--       customer's orders, or 0 when the customer has no orders.
--       It exists only in V2; V1 sessions cannot call it.
--     - order_total and customer_order_count are unchanged, carried
--       into the V2 package so the package is complete in V2.
--
-- Usage:
--   Run as a DBA account, for example SYSDBA, in the scratch database
--   built by sql/ebr_lab_setup_v1.sql:
--
--     sqlplus / as sysdba @ebr_lab_upgrade_v2.sql
--
--   Edit the DEFINE lines below before running it, especially
--   lab_password, which must match the value used when stage 1 built
--   the lab. Use a lab-only password. Never use a real credential,
--   and never run this script against a database that matters.
--   Re-running the script in the same database fails, because the V2
--   edition already exists; drop it first (see
--   docs/multiple-editions-plsql.md) or rebuild the lab database.
--
-- Exit code:
--   0 - V2 edition created, package redefined in V2, V1 objects
--       untouched, verification checks passed
--   non-zero - a statement failed (WHENEVER SQLERROR exits
--       immediately) or a verification check failed
--
-- Notes:
--   Creates an edition and redefines a package, so it is not
--   read-only. The lab schema default edition stays V1; sessions
--   move to V2 only when they ask for it, and the cutover that
--   changes the default is a later stage. Probe writes in the
--   verification section are rolled back, so the seed data is
--   unchanged. Reviewed; not executed against a live Oracle instance.
-- ============================================================================

SET ECHO OFF
SET FEEDBACK ON
SET VERIFY OFF
SET PAGESIZE 100
SET LINESIZE 160
SET TRIMSPOOL ON
SET TAB OFF
SET SERVEROUTPUT ON

WHENEVER SQLERROR EXIT SQL.SQLCODE

-- ----------------------------------------------------------------------------
-- Lab parameters. Edit to match the lab built by stage 1.
-- ----------------------------------------------------------------------------
DEFINE lab_schema = LAB_APP
DEFINE lab_password = CHANGEME_LAB_ONLY
DEFINE parent_edition = V1
DEFINE edition_name = V2

PROMPT
PROMPT === 1. Create the V2 edition as a child of V1 ===
PROMPT (V1 has no child yet, so this succeeds. A parent can have at
PROMPT  most one child, so a second child of V1 would fail.)

CREATE EDITION &edition_name AS CHILD OF &parent_edition;

PROMPT
PROMPT === 2. Grant the lab schema USE on the V2 edition ===
PROMPT (Without this, a lab session cannot set its edition to V2.)

GRANT USE ON EDITION &edition_name TO &lab_schema;

PROMPT
PROMPT === 3. Connect as the lab schema and set the session edition to V2 ===
PROMPT (The user default edition is still V1. The session edition is
PROMPT  set explicitly, which is what makes the objects created next
PROMPT  editioned in V2 instead of V1.)

CONNECT &lab_schema/&lab_password
ALTER SESSION SET EDITION = &edition_name;

COLUMN current_edition FORMAT A20 HEADING 'CURRENT EDITION'
SELECT SYS_CONTEXT('USERENV', 'CURRENT_EDITION_NAME') AS current_edition
  FROM dual;

PROMPT
PROMPT === 4. Redefine the ORDER_API package in V2 ===
PROMPT (CREATE OR REPLACE in the V2 session creates the V2 copy. The
PROMPT  V1 copy is untouched, and V1 sessions keep seeing it. The
PROMPT  view CUSTOMER_ORDERS is not redefined here, so V2 sessions
PROMPT  inherit the V1 view.)

CREATE OR REPLACE PACKAGE order_api AS
  PROCEDURE place_order(p_customer_id IN NUMBER, p_amount IN NUMBER);
  FUNCTION order_total(p_order_id IN NUMBER) RETURN NUMBER;
  FUNCTION customer_order_count(p_customer_id IN NUMBER) RETURN NUMBER;
  FUNCTION customer_total_spent(p_customer_id IN NUMBER) RETURN NUMBER;
END order_api;
/

CREATE OR REPLACE PACKAGE BODY order_api AS

  PROCEDURE place_order(p_customer_id IN NUMBER, p_amount IN NUMBER) IS
    v_customer_count NUMBER;
  BEGIN
    IF p_amount <= 0 THEN
      RAISE_APPLICATION_ERROR(-20001,
        'Order amount must be greater than zero.');
    END IF;
    SELECT COUNT(*) INTO v_customer_count
      FROM customers
     WHERE customer_id = p_customer_id;
    IF v_customer_count = 0 THEN
      RAISE_APPLICATION_ERROR(-20002, 'Customer does not exist.');
    END IF;
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

  FUNCTION customer_total_spent(p_customer_id IN NUMBER) RETURN NUMBER IS
    v_total NUMBER(12,2);
  BEGIN
    SELECT NVL(SUM(amount), 0) INTO v_total
      FROM orders
     WHERE customer_id = p_customer_id;
    RETURN v_total;
  END customer_total_spent;

END order_api;
/

PROMPT
PROMPT === 5. Verify the V2 package behaves as designed ===
PROMPT (Seed data: customer 101 placed orders of 249.99 and 89.50,
PROMPT  so the V2 total is 339.49. The valid-order probe is rolled
PROMPT  back, so the seed data is unchanged.)

COLUMN v2_total FORMAT 999999990.99 HEADING 'V2 TOTAL FOR 101'

SELECT order_api.customer_total_spent(101) AS v2_total
  FROM dual;

DECLARE
  v_total NUMBER(12,2);
  v_before NUMBER;
  v_after  NUMBER;
BEGIN
  v_total := order_api.customer_total_spent(101);
  IF v_total <> 339.49 THEN
    RAISE_APPLICATION_ERROR(-20003,
      'V2 customer_total_spent returned an unexpected value: '
      || TO_CHAR(v_total));
  END IF;

  BEGIN
    order_api.place_order(p_customer_id => 101, p_amount => -5.00);
    RAISE_APPLICATION_ERROR(-20004,
      'V2 place_order accepted a negative amount.');
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE <> -20001 THEN
        RAISE;
      END IF;
      DBMS_OUTPUT.PUT_LINE(
        'Negative amount rejected in V2 as expected: ' || SQLERRM);
  END;

  BEGIN
    order_api.place_order(p_customer_id => 9999, p_amount => 10.00);
    RAISE_APPLICATION_ERROR(-20005,
      'V2 place_order accepted an unknown customer.');
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE <> -20002 THEN
        RAISE;
      END IF;
      DBMS_OUTPUT.PUT_LINE(
        'Unknown customer rejected in V2 as expected: ' || SQLERRM);
  END;

  SELECT COUNT(*) INTO v_before FROM orders WHERE customer_id = 102;
  order_api.place_order(p_customer_id => 102, p_amount => 10.00);
  SELECT COUNT(*) INTO v_after FROM orders WHERE customer_id = 102;
  IF v_after <> v_before + 1 THEN
    RAISE_APPLICATION_ERROR(-20006,
      'V2 place_order did not insert the expected row.');
  END IF;
  DBMS_OUTPUT.PUT_LINE(
    'Valid order placed in V2 as expected; rolling it back.');
  ROLLBACK;
END;
/

PROMPT
PROMPT === 6. Cross-edition verification ===
PROMPT (ORDER_API now appears in both V1 and V2: the V2 copy shadows
PROMPT  the V1 copy for V2 sessions. CUSTOMER_ORDERS appears only in
PROMPT  V1: V2 sessions inherit it. Both copies of the package must
PROMPT  be VALID.)

CONNECT / AS SYSDBA

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
   AND object_name IN ('ORDER_API', 'CUSTOMER_ORDERS')
 ORDER BY object_name, edition_name, object_type;

PROMPT
PROMPT === Verdict ===

COLUMN exit_code NOPRINT NEW_VALUE v_exit_code
SELECT CASE
         WHEN NOT EXISTS (SELECT 1
                            FROM dba_editions
                           WHERE edition_name = '&edition_name') THEN 2
         WHEN NOT EXISTS (SELECT 1
                            FROM dba_objects_ae
                           WHERE owner = '&lab_schema'
                             AND object_name = 'ORDER_API'
                             AND object_type = 'PACKAGE'
                             AND edition_name = '&edition_name'
                             AND status = 'VALID') THEN 2
         WHEN NOT EXISTS (SELECT 1
                            FROM dba_objects_ae
                           WHERE owner = '&lab_schema'
                             AND object_name = 'ORDER_API'
                             AND object_type = 'PACKAGE BODY'
                             AND edition_name = '&edition_name'
                             AND status = 'VALID') THEN 2
         WHEN NOT EXISTS (SELECT 1
                            FROM dba_objects_ae
                           WHERE owner = '&lab_schema'
                             AND object_name = 'ORDER_API'
                             AND object_type = 'PACKAGE'
                             AND edition_name = '&parent_edition') THEN 2
         WHEN EXISTS (SELECT 1
                        FROM dba_objects_ae
                       WHERE owner = '&lab_schema'
                         AND object_name = 'CUSTOMER_ORDERS'
                         AND object_type = 'VIEW'
                         AND edition_name = '&edition_name') THEN 2
         WHEN NOT EXISTS (SELECT 1
                            FROM dba_source_ae
                           WHERE owner = '&lab_schema'
                             AND name = 'ORDER_API'
                             AND edition_name = '&edition_name'
                             AND UPPER(text) LIKE '%CUSTOMER_TOTAL_SPENT%') THEN 2
         WHEN EXISTS (SELECT 1
                        FROM dba_source_ae
                       WHERE owner = '&lab_schema'
                         AND name = 'ORDER_API'
                         AND edition_name = '&parent_edition'
                         AND UPPER(text) LIKE '%CUSTOMER_TOTAL_SPENT%') THEN 2
         ELSE 0
       END AS exit_code
  FROM dual;

PROMPT
PROMPT Done. Exit code: &v_exit_code (0 = V2 built as designed, 2 = a check failed)
PROMPT V1 is untouched: run sql/edition_inventory.sql to confirm the
PROMPT stage 1 layout still passes, and sql/edition_comparison.sql to
PROMPT compare V1 and V2 behavior side by side.
EXIT &v_exit_code
