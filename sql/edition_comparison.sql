-- ============================================================================
-- edition_comparison.sql
--
-- Purpose:
--   Compare the V1 and V2 editions of the EBR lab side by side, after
--   running sql/ebr_lab_upgrade_v2.sql. It shows the edition chain,
--   which editioned objects exist in each edition, which source lines
--   differ between the two copies of ORDER_API, and then probes the
--   behavior of each edition: the V2 package validates its inputs
--   and offers customer_total_spent, the V1 package does neither, and
--   the CUSTOMER_ORDERS view works from both editions because V2
--   inherits it from V1.
--
-- Usage:
--   Run as a DBA account, for example SYSDBA, after stage 2 is built:
--
--     sqlplus / as sysdba @edition_comparison.sql
--
--   To check a different lab schema or editions, edit the DEFINE
--   lines below.
--
-- Exit code:
--   0 - V2 exists, ORDER_API is editioned in both editions,
--       CUSTOMER_ORDERS is editioned only in V1, the V2-only
--       function is present only in V2 source, and every behavior
--       probe matched its expectation
--   2 - any dictionary check or behavior probe failed
--
-- Notes:
--   Net effect read-only: the probe writes (a negative order in V1,
--   a valid order in V2) are rolled back before the script moves on,
--   and the sequence values they consume leave only harmless gaps.
--   The V1 probe calls customer_total_spent through dynamic SQL, so
--   the expected PLS-00201 is caught at run time instead of failing
--   the script at compile time. Needs Oracle Database 11g Release 2
--   or later. Reviewed; not executed against a live Oracle instance.
-- ============================================================================

SET ECHO OFF
SET FEEDBACK OFF
SET VERIFY OFF
SET PAGESIZE 100
SET LINESIZE 160
SET TRIMSPOOL ON
SET TAB OFF
SET SERVEROUTPUT ON

WHENEVER SQLERROR EXIT 2

-- ----------------------------------------------------------------------------
-- Lab parameters. Edit to match the local lab database.
-- ----------------------------------------------------------------------------
DEFINE lab_schema = LAB_APP
DEFINE lab_password = CHANGEME_LAB_ONLY
DEFINE edition_v1 = V1
DEFINE edition_v2 = V2

PROMPT
PROMPT === 1. Edition chain ===

COLUMN edition_name        FORMAT A20 HEADING 'EDITION'
COLUMN parent_edition_name FORMAT A20 HEADING 'PARENT EDITION'
COLUMN usable              FORMAT A6  HEADING 'USABLE'

SELECT edition_name,
       parent_edition_name,
       usable
  FROM dba_editions
 WHERE edition_name IN ('&edition_v1', '&edition_v2')
 ORDER BY edition_name;

PROMPT
PROMPT === 2. Editioned lab objects, by edition ===
PROMPT (ORDER_API appears in both editions: the V2 copy shadows the
PROMPT  V1 copy. CUSTOMER_ORDERS appears only in V1: V2 sessions
PROMPT  inherit it, so it has no V2 row of its own.)

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
 ORDER BY object_name, edition_name, object_type;

PROMPT
PROMPT === 3. Source lines that differ between the editions ===
PROMPT (DBA_SOURCE_AE shows source across all editions. The new
PROMPT  function and the validation errors exist only in V2 source.)

COLUMN edition_name FORMAT A12 HEADING 'EDITION'
COLUMN line_text    FORMAT A70 HEADING 'SOURCE LINE'

SELECT edition_name,
       TRIM(text) AS line_text
  FROM dba_source_ae
 WHERE owner = '&lab_schema'
   AND name = 'ORDER_API'
   AND (UPPER(text) LIKE '%CUSTOMER_TOTAL_SPENT%'
        OR text LIKE '%-20001%'
        OR text LIKE '%-20002%')
 ORDER BY edition_name, line;

PROMPT
PROMPT === 4. Behaviour probe in V2 ===
PROMPT (V2 rejects a negative amount and an unknown customer, and
PROMPT  customer_total_spent(101) is 339.49 from the seed data. The
PROMPT  valid-order probe is rolled back.)

CONNECT &lab_schema/&lab_password
ALTER SESSION SET EDITION = &edition_v2;

DECLARE
  v_total  NUMBER(12,2);
  v_before NUMBER;
  v_after  NUMBER;
BEGIN
  v_total := order_api.customer_total_spent(101);
  IF v_total <> 339.49 THEN
    RAISE_APPLICATION_ERROR(-20003,
      'V2 customer_total_spent(101) returned ' || TO_CHAR(v_total)
      || ', expected 339.49.');
  END IF;
  DBMS_OUTPUT.PUT_LINE('V2 probe: customer_total_spent(101) = 339.49, as expected.');

  BEGIN
    order_api.place_order(p_customer_id => 101, p_amount => -5.00);
    RAISE_APPLICATION_ERROR(-20004,
      'V2 place_order accepted a negative amount.');
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE <> -20001 THEN
        RAISE;
      END IF;
      DBMS_OUTPUT.PUT_LINE('V2 probe: negative amount rejected with -20001, as expected.');
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
      DBMS_OUTPUT.PUT_LINE('V2 probe: unknown customer rejected with -20002, as expected.');
  END;

  SELECT COUNT(*) INTO v_before FROM orders WHERE customer_id = 102;
  order_api.place_order(p_customer_id => 102, p_amount => 10.00);
  SELECT COUNT(*) INTO v_after FROM orders WHERE customer_id = 102;
  IF v_after <> v_before + 1 THEN
    RAISE_APPLICATION_ERROR(-20006,
      'V2 place_order did not insert the expected row.');
  END IF;
  DBMS_OUTPUT.PUT_LINE('V2 probe: valid order accepted, rolling it back.');
  ROLLBACK;

  SELECT COUNT(*) INTO v_after FROM customer_orders;
  IF v_after <> 3 THEN
    RAISE_APPLICATION_ERROR(-20007,
      'Inherited CUSTOMER_ORDERS view returned an unexpected row count in V2.');
  END IF;
  DBMS_OUTPUT.PUT_LINE('V2 probe: inherited CUSTOMER_ORDERS view returns 3 rows, as expected.');
END;
/

PROMPT
PROMPT === 5. Behaviour probe in V1 ===
PROMPT (V1 accepts a negative amount, because it has no validation,
PROMPT  and it has no customer_total_spent to call. The probe order
PROMPT  is rolled back.)

ALTER SESSION SET EDITION = &edition_v1;

DECLARE
  v_total      NUMBER(12,2);
  v_before     NUMBER;
  v_after      NUMBER;
  v_seen_error BOOLEAN := FALSE;
  v_err        VARCHAR2(4000);
BEGIN
  SELECT COUNT(*) INTO v_before
    FROM orders
   WHERE customer_id = 101 AND amount < 0;
  order_api.place_order(p_customer_id => 101, p_amount => -5.00);
  SELECT COUNT(*) INTO v_after
    FROM orders
   WHERE customer_id = 101 AND amount < 0;
  IF v_after <> v_before + 1 THEN
    RAISE_APPLICATION_ERROR(-20008,
      'V1 place_order did not accept the negative amount.');
  END IF;
  DBMS_OUTPUT.PUT_LINE('V1 probe: negative amount accepted, as expected in V1; rolling it back.');
  ROLLBACK;

  BEGIN
    EXECUTE IMMEDIATE
      'BEGIN :r := order_api.customer_total_spent(101); END;'
      USING OUT v_total;
  EXCEPTION
    WHEN OTHERS THEN
      v_seen_error := TRUE;
      v_err := SQLERRM;
  END;
  IF NOT v_seen_error THEN
    RAISE_APPLICATION_ERROR(-20009,
      'customer_total_spent unexpectedly callable in V1.');
  END IF;
  DBMS_OUTPUT.PUT_LINE('V1 probe: customer_total_spent not available, as expected: ' || v_err);

  SELECT COUNT(*) INTO v_after FROM customer_orders;
  IF v_after <> 3 THEN
    RAISE_APPLICATION_ERROR(-20010,
      'CUSTOMER_ORDERS view returned an unexpected row count in V1.');
  END IF;
  DBMS_OUTPUT.PUT_LINE('V1 probe: CUSTOMER_ORDERS view returns 3 rows, as expected.');
END;
/

PROMPT
PROMPT === 6. Seed data is unchanged ===

CONNECT / AS SYSDBA

COLUMN order_rows    FORMAT 999999 HEADING 'ORDERS'
COLUMN customer_rows FORMAT 999999 HEADING 'CUSTOMERS'

SELECT COUNT(*) AS order_rows FROM &lab_schema..orders;
SELECT COUNT(*) AS customer_rows FROM &lab_schema..customers;

PROMPT
PROMPT === Verdict ===

COLUMN exit_code NOPRINT NEW_VALUE v_exit_code
SELECT CASE
         WHEN NOT EXISTS (SELECT 1
                            FROM dba_editions
                           WHERE edition_name = '&edition_v2') THEN 2
         WHEN NOT EXISTS (SELECT 1
                            FROM dba_objects_ae
                           WHERE owner = '&lab_schema'
                             AND object_name = 'ORDER_API'
                             AND object_type = 'PACKAGE'
                             AND edition_name = '&edition_v1') THEN 2
         WHEN NOT EXISTS (SELECT 1
                            FROM dba_objects_ae
                           WHERE owner = '&lab_schema'
                             AND object_name = 'ORDER_API'
                             AND object_type = 'PACKAGE'
                             AND edition_name = '&edition_v2') THEN 2
         WHEN NOT EXISTS (SELECT 1
                            FROM dba_objects_ae
                           WHERE owner = '&lab_schema'
                             AND object_name = 'CUSTOMER_ORDERS'
                             AND object_type = 'VIEW'
                             AND edition_name = '&edition_v1') THEN 2
         WHEN EXISTS (SELECT 1
                        FROM dba_objects_ae
                       WHERE owner = '&lab_schema'
                         AND object_name = 'CUSTOMER_ORDERS'
                         AND object_type = 'VIEW'
                         AND edition_name = '&edition_v2') THEN 2
         WHEN NOT EXISTS (SELECT 1
                            FROM dba_source_ae
                           WHERE owner = '&lab_schema'
                             AND name = 'ORDER_API'
                             AND edition_name = '&edition_v2'
                             AND UPPER(text) LIKE '%CUSTOMER_TOTAL_SPENT%') THEN 2
         WHEN EXISTS (SELECT 1
                        FROM dba_source_ae
                       WHERE owner = '&lab_schema'
                         AND name = 'ORDER_API'
                         AND edition_name = '&edition_v1'
                         AND UPPER(text) LIKE '%CUSTOMER_TOTAL_SPENT%') THEN 2
         ELSE 0
       END AS exit_code
  FROM dual;

PROMPT
PROMPT Done. Exit code: &v_exit_code (0 = V1 and V2 compare as designed, 2 = a check failed)
PROMPT A clean report means V2 shadows V1 only where it redefines
PROMPT the package, and inherits everything else from V1.
EXIT &v_exit_code
