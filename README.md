# Oracle Edition-Based Redefinition Lab

An online application upgrade is a database problem before it is a deployment problem. If the database objects change while the application is running, someone has to hold two versions of the truth at once: the old code for the sessions already connected, and the new code for the sessions that arrive after the change. Edition-Based Redefinition is Oracle's answer to that problem, and this lab works through it in small, verifiable steps.

The lab builds a small fictional order system, a customer and order schema with a PL/SQL API, and upgrades it across editions the way a production change would be done: a new edition for the new version, editioned code that differs between editions, editioning views when a table has to change shape, crossedition triggers to keep old and new data in step, and a cutover that moves sessions from one edition to the other without stopping the application.

## Who it is for

Oracle DBAs who own application upgrades and want to understand EBR by doing it, not by reading about it. The material assumes working SQL and PL/SQL and a passing familiarity with schemas and privileges. It does not assume any prior EBR experience; the fundamentals doc starts from the beginning.

## Layout

```
oracle-edition-based-redefinition-lab/
├── sql/    -- SQL*Plus lab scripts (setup, inventory checks)
└── docs/   -- fundamentals, lab setup, interview discussion points
```

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

The SQL in this repo is syntax and logic reviewed against the documented data dictionary and the Oracle Database Development Guide. It has not been executed against a live Oracle instance in this environment, and the headers say so. Sample output in the docs is labeled illustrative lab output, not captured results.

## What this demonstrates

Online upgrade technique at the database layer: editions, editioned versus noneditioned objects, session and default editions, edition inheritance, and the upgrade path from a first edition through editioning views, crossedition triggers, cutover, and rollback. The later stages add the APEX operations dashboard that watches the same objects, and the final stage combines APEX and EBR into one zero-downtime upgrade.

## Background

Recreated from standard DBA practice and the Oracle documentation for a personal lab portfolio, generic examples, not exports from any production environment. That keeps them safe to share and easy to adapt.
