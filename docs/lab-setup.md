# Lab setup

This lab is built in stages, one per week, and each stage changes one thing. This doc covers the first two stages: building version 1 of the lab, the edition, the schema, and the first editioned objects, then building version 2, a child edition with a redefined package. Later stages build on exactly what is built here, so keep the lab database intact between stages.

## Prerequisites

- Oracle Database 11g Release 2 or later for the setup and upgrade scripts and the comparison script. The inventory script needs 12c Release 1 or later, because it reads `DBA_USERS.DEFAULT_EDITION_NAME`.
- A scratch database you can drop and rebuild, with a `USERS` tablespace and SYSDBA access. The setup script creates a user and an edition. It does not change any database-wide setting.
- SQL*Plus. The scripts are written for it and use its `DEFINE`, `PROMPT`, and exit code conventions.

## Building version 1

Run the setup script as SYSDBA:

```
sqlplus / as sysdba @sql/ebr_lab_setup_v1.sql
```

Before running it, edit the `lab_password` DEFINE at the top of the script. The default is a placeholder, and the script refuses nothing on its own, so treat the password as a lab-only value and never reuse a real credential.

The script does, in order:

1. Creates the `V1` edition as a child of the root edition `ORA$BASE`.
2. Creates the `LAB_APP` schema, grants it the privileges to create tables, sequences, views, procedures, triggers, and synonyms, enables editions for it, sets its default edition to `V1`, and grants it `USE` on the `V1` edition.
3. Connects as `LAB_APP`. The session edition is `V1`, because that is the user default edition.
4. Creates the noneditioned tables `CUSTOMERS` and `ORDERS`, plus the `CUSTOMER_SEQ` and `ORDER_SEQ` sequences. Tables exist once and are visible from every edition.
5. Creates the editioned view `CUSTOMER_ORDERS` and the editioned package `ORDER_API` while the session edition is `V1`, so both are editioned in `V1`.
6. Seeds three fictional customers and three orders, placing the orders through the `V1` package so the package is exercised as part of setup.

## Building version 2

Run the upgrade script as SYSDBA, in the same database:

```
sqlplus / as sysdba @sql/ebr_lab_upgrade_v2.sql
```

Before running it, edit the `lab_password` DEFINE at the top of the script. It must match the value used when stage 1 built the lab, because the script connects as the lab schema. The script does, in order:

1. Creates the `V2` edition as a child of `V1`.
2. Grants the lab schema `USE` on the `V2` edition.
3. Connects as `LAB_APP`, sets the session edition to `V2`, and redefines the `ORDER_API` package there: `place_order` now rejects a zero or negative amount and an unknown customer, and a new function `customer_total_spent` returns a customer's order total. The `CUSTOMER_ORDERS` view is not redefined, so `V2` sessions inherit it from `V1`.
4. Probes the V2 package behavior and rolls the probe writes back, so the seed data is unchanged.
5. Reconnects as SYSDBA and verifies the cross-edition layout: the package appears in both editions and is valid in both, the view appears only in `V1`, and the new function name appears only in `V2` source. It exits 0 when the layout matches the design and 2 when a check fails.

Then compare the two editions side by side:

```
sqlplus / as sysdba @sql/edition_comparison.sql
```

It reports the edition chain, the editioned objects by edition, the source lines that differ, and a behavior probe in each edition: V2 rejects the bad calls and answers the new function, V1 accepts the negative amount and has no such function, and the view returns three rows from both editions. Its probe writes are rolled back too. Re-run the inventory script as well; it still passes, which is the proof that stage 2 left V1 untouched. The full writeup, including the inheritance table and the gotchas, is `docs/multiple-editions-plsql.md`.

The lab schema default edition stays `V1` after this stage. Sessions start in `V1` until the cutover stage changes the default, so building V2 changes nothing for existing sessions.

## Verifying the build

Run the inventory script as a privileged user:

```
sqlplus / as sysdba @sql/edition_inventory.sql
```

It reports the current session edition, the database default edition, every edition in the database, which users are editions-enabled and their default editions, the editioned objects by edition, and the noneditioned objects. It exits 0 when the lab layout matches the design, and 2 when something is missing: the schema not editions-enabled, the `V1` edition absent, or the `V1` view or package not editioned in `V1`.

The check that matters most is the split between the two object lists. `ORDER_API` and `CUSTOMER_ORDERS` should appear in the editioned list with edition name `V1`. `CUSTOMERS`, `ORDERS`, and the two sequences should appear in the noneditioned list with no edition name. That split is the whole point of the first stage: code is versioned, data is shared.

## Trying it by hand

Two quick checks show the edition mechanics working. First, connect as the lab schema twice, once in each of two editions, and compare the current edition:

```sql
-- Session 1
CONNECT lab_app/<LAB_PASSWORD>
SELECT SYS_CONTEXT('USERENV', 'CURRENT_EDITION_NAME') FROM dual;

-- Session 2
CONNECT lab_app/<LAB_PASSWORD>
ALTER SESSION SET EDITION = ora$base;
SELECT SYS_CONTEXT('USERENV', 'CURRENT_EDITION_NAME') FROM dual;
```

The first session reports `V1`, because that is the user default edition. The second reports `ORA$BASE`. A session in `ORA$BASE` cannot see the `V1` package or view, because editioned objects in a child edition are not visible from the parent. A query against `CUSTOMER_ORDERS` from the `ORA$BASE` session fails, while the same query from the `V1` session returns the three seeded orders. The tables, being noneditioned, are visible from both.

After stage 2, try the same comparison between `V1` and `V2`:

```sql
-- Session in V2
CONNECT lab_app/<LAB_PASSWORD>
ALTER SESSION SET EDITION = v2;
SELECT order_api.customer_total_spent(101) FROM dual;

-- Session in V1
CONNECT lab_app/<LAB_PASSWORD>
ALTER SESSION SET EDITION = v1;
SELECT order_api.customer_total_spent(101) FROM dual;
```

The V2 session returns 339.49. The V1 session fails with `PLS-00201`, because the function does not exist in V1. A query against `CUSTOMER_ORDERS` works from both sessions, because V2 inherits the view from V1. To see the validation difference without changing the seed data, place a negative order in each session and roll back afterwards.

## Tearing the lab down

To rebuild from scratch, drop the editions and the user, in that order, as SYSDBA:

```sql
DROP EDITION v2 CASCADE;
DROP EDITION v1 CASCADE;
DROP USER lab_app CASCADE;
```

`DROP EDITION ... CASCADE` drops the editioned objects that exist only in that edition. Drop the child edition first, then the parent, so its editioned objects go with it, then drop the user. Do not run any of these statements against a database that matters.

## What comes next

- Stage 2: a second edition as a child of `V1`, and a changed editioned package, showing inheritance and shadowing. Done: `sql/ebr_lab_upgrade_v2.sql`, `sql/edition_comparison.sql`, `docs/multiple-editions-plsql.md`.
- Stage 3: editioning views, for the day a table has to change shape.
- Stage 4: crossedition triggers and data migration, keeping old and new writes in step.
- Stage 5: cutover and rollback, moving sessions between editions and retiring the old one.
- Then the APEX operations dashboard stages, and the final combined APEX plus EBR zero-downtime upgrade.

Each stage adds its own scripts and docs to this repo, and the inventory script is re-run after each one to show what changed.
