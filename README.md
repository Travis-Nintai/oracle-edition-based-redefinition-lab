# Oracle Edition-Based Redefinition Lab

An online application upgrade is a database problem before it is a deployment problem. If the database objects change while the application is running, someone has to hold two versions of the truth at once: the old code for the sessions already connected, and the new code for the sessions that arrive after the change. Edition-Based Redefinition is Oracle's answer to that problem, and this lab works through it in small, verifiable steps.

The lab builds a small fictional order system, a customer and order schema with a PL/SQL API, and upgrades it across editions the way a production change would be done: a new edition for the new version, editioned code that differs between editions, editioning views when a table has to change shape, crossedition triggers to keep old and new data in step, and a cutover that moves sessions from one edition to the other without stopping the application.

## Who it is for

Oracle DBAs who own application upgrades and want to understand EBR by doing it, not by reading about it. The material assumes working SQL and PL/SQL and a passing familiarity with schemas and privileges. It does not assume any prior EBR experience; the fundamentals doc starts from the beginning.

## Layout

```
oracle-edition-based-redefinition-lab/
├── sql/    -- SQL*Plus lab scripts (setup, upgrade, inventory and comparison checks)
└── docs/   -- fundamentals, lab setup, multiple editions, interview discussion points
```

## Scripts and templates

| File | What it does |
|---|---|
| `sql/ebr_lab_setup_v1.sql` | Builds version 1 of the lab: the V1 edition, the editions-enabled LAB_APP schema, the customers and orders tables, the editioned view and package, and seed data; run as SYSDBA in a scratch database |
| `sql/ebr_lab_upgrade_v2.sql` | Builds version 2: the V2 edition as a child of V1, and a redefined ORDER_API package with input validation and a new customer_total_spent function; V1 is untouched; run as SYSDBA after the V1 setup |
| `sql/edition_inventory.sql` | Read-only edition layout report: session and database default editions, every edition, editions-enabled users, editioned and noneditioned lab objects; exit 2 when the layout does not match the design |
| `sql/edition_comparison.sql` | Read-only in net effect V1 versus V2 comparison: edition chain, editioned objects by edition, differing source lines, and behavior probes in each edition with probe writes rolled back; exit 2 when a check fails |

Build the lab (replace the placeholder lab password in the setup script first):

```
sqlplus / as sysdba @sql/ebr_lab_setup_v1.sql
```

Verify the build:

```
sqlplus / as sysdba @sql/edition_inventory.sql
```

Build version 2, then compare the editions (replace the placeholder lab password in the upgrade script first, with the value used for the V1 setup):

```
sqlplus / as sysdba @sql/ebr_lab_upgrade_v2.sql
sqlplus / as sysdba @sql/edition_comparison.sql
```

## Docs

| Doc | What it covers |
|---|---|
| `docs/ebr-fundamentals.md` | Editions, editioned versus noneditioned objects, session and default editions, edition inheritance, what EBR does not do, versions and licensing |
| `docs/lab-setup.md` | Prerequisites, building and verifying version 1, building version 2, trying the edition mechanics by hand, tearing the lab down, and what the later stages add |
| `docs/multiple-editions-plsql.md` | Creating a child edition, inheritance versus shadowing, what changed in the V2 package and why, comparing the editions, and the gotchas that catch people |
| `docs/interview-discussion-points.md` | The answers this lab is built to support in a conversation with a senior DBA or hiring manager |

Start with `docs/ebr-fundamentals.md` if EBR is new. Start with `docs/lab-setup.md` if you want to build the lab first and read as you go.

## Assumptions

- Oracle Database 11g Release 2 or later for editions and editioned PL/SQL. Editioning views and crossedition triggers, covered in later stages of this lab, need Oracle Database 12c Release 1 or later.
- The lab is built in a scratch database you can drop and rebuild. Nothing here should be run against a database that matters.
- Edition-Based Redefinition needs no separate license and is available in all Oracle Database editions. The lab states the licensing position for each feature it uses, and calls out Diagnostics Pack and similar licensed features separately where they appear in related repos.
- The lab schema, table names, and data are fictional. The database name in examples is ORCLLAB and the host is db.example.local.

## Safety notes

- The setup script creates a database user and an edition. Run it only in a lab database. It creates no production objects and changes no database-wide setting except adding one edition.
- The inventory script is read-only. The setup script is not: it creates a user, an edition, tables, a view, and a package. Read it before running it, and replace the placeholder lab password with a lab-only value.
- Enabling editions for a user is irreversible. Do not enable editions on a schema that already owns application objects unless you have read the fundamentals doc and understand the consequences.
- Never commit credentials, hostnames, or environment-specific connection details alongside these scripts. See `docs/script-conventions.md`.

## Testing

The SQL in this repo is syntax and logic reviewed against the documented data dictionary and the Oracle Database Development Guide. It has not been executed against a live Oracle instance in this environment, and the headers say so. Sample output in the docs is labeled illustrative lab output, not captured results. The comparison script probes both editions and rolls its probe writes back, so the seed data is unchanged after it runs.

## What this demonstrates

Online upgrade technique at the database layer: editions, editioned versus noneditioned objects, session and default editions, edition inheritance and shadowing, and the upgrade path from a first edition through a redefined package, editioning views, crossedition triggers, cutover, and rollback. The V2 stage shows the core of it in one place: the package differs between editions while the view is inherited and the tables are shared. The later stages add the APEX operations dashboard that watches the same objects, and the final stage combines APEX and EBR into one zero-downtime upgrade.

## Background

Recreated from standard DBA practice and the Oracle documentation for a personal lab portfolio, generic examples, not exports from any production environment. That keeps them safe to share and easy to adapt.
