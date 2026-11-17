# Lab setup

This lab is built in stages, one per week, and each stage changes one thing. This doc covers the first stage: building version 1 of the lab, the edition, the schema, and the first editioned objects. Later stages build on exactly what is built here, so keep the lab database intact between stages.

## Prerequisites

- Oracle Database 11g Release 2 or later for the setup script. The inventory script needs 12c Release 1 or later, because it reads `DBA_USERS.DEFAULT_EDITION_NAME`.
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

## Tearing the lab down

To rebuild from scratch, drop the edition and the user, in that order, as SYSDBA:

```sql
DROP EDITION v1 CASCADE;
DROP USER lab_app CASCADE;
```

`DROP EDITION ... CASCADE` drops the editioned objects that exist only in that edition. Drop the edition first so its editioned objects go with it, then drop the user. Do not run either statement against a database that matters.

## What comes next

- Stage 2: a second edition as a child of `V1`, and a changed editioned package, showing inheritance and shadowing.
- Stage 3: editioning views, for the day a table has to change shape.
- Stage 4: crossedition triggers and data migration, keeping old and new writes in step.
- Stage 5: cutover and rollback, moving sessions between editions and retiring the old one.
- Then the APEX operations dashboard stages, and the final combined APEX plus EBR zero-downtime upgrade.

Each stage adds its own scripts and docs to this repo, and the inventory script is re-run after each one to show what changed.
