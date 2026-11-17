# Edition-Based Redefinition fundamentals

Edition-Based Redefinition (EBR) lets you upgrade the database component of an application while the application is in use, with little or no downtime. The idea is simple enough to state in one sentence: the database keeps more than one version of the application's code at the same time, and each session sees the version that belongs to it. Old sessions keep running the old code, new sessions pick up the new code, and the data underneath stays shared.

This doc covers the three ideas everything else in the lab rests on: editions, editioned objects, and session editions. Editioning views and crossedition triggers, the two features that handle table structure changes and live data changes, get their own stages later in the lab.

## The problem EBR solves

A normal application upgrade replaces code in place. A package is recompiled, a view is redefined, and every session that uses those objects sees the new version at once, including sessions in the middle of a transaction. That is fine when the application can be stopped, and a risk when it cannot. The usual answers are a maintenance window, or a second database with replication, and both cost something: downtime, or a second environment to keep in step.

EBR offers a third answer inside a single database. The new version of the code is installed in a new edition, in isolation, while the old version keeps serving. Sessions move to the new edition when they reconnect, or when their service is repointed, and the old edition is retired only when nothing uses it anymore. There is no second database and no maintenance window for the code change itself. The data change is a separate question, and that is where editioning views and crossedition triggers come in.

## Editions

An edition is a nonschema object, a named workspace that holds its own copies of editioned objects. Every database has at least one edition, the root edition `ORA$BASE`, which is also the default edition until someone changes it. Editions form a tree: each edition except `ORA$BASE` has exactly one parent, and each edition can have at most one child, so the editions in a database form a single chain from `ORA$BASE` down through the versions you create.

```sql
CREATE EDITION v1;
CREATE EDITION v2 AS CHILD OF v1;
```

Creating an edition needs the `CREATE ANY EDITION` system privilege, which a DBA account holds. Creating a child edition also needs the `USE` privilege on the parent edition; creating an edition grants the creator `USE` on it with grant option, so that part usually takes care of itself.

Two rules about editions matter for everything that follows. First, an edition is not a copy of the database. It holds no data of its own. Noneditioned objects, tables above all, exist once and are visible from every edition. Second, dropping an edition drops every editioned object that exists only in that edition, so an edition is retired deliberately, after checking that no session still uses it.

The database default edition is a database property, readable from `DATABASE_PROPERTIES`:

```sql
SELECT property_value FROM database_properties
 WHERE property_name = 'DEFAULT_EDITION';
```

It starts as `ORA$BASE` and can be changed with `ALTER DATABASE DEFAULT EDITION = <edition>`. Changing it affects only sessions that connect afterwards, which is exactly the property a cutover relies on.

## Editioned and noneditioned objects

Not every object type can be versioned. The editionable types are the code objects: `FUNCTION`, `LIBRARY`, `PACKAGE` and `PACKAGE BODY`, `PROCEDURE`, `SYNONYM`, `TRIGGER`, `TYPE` and `TYPE BODY`, and `VIEW`. Everything else is noneditionable, and the important case is `TABLE`: a table exists once, shared by every edition, and cannot be given a different shape per edition. Indexes, sequences, constraints, and materialized views are noneditioned too. One exception to remember: although `SYNONYM` is an editionable type, a public synonym is a noneditioned object.

Whether an object of an editionable type is actually editioned depends on its owner. An editioned object is an object of an editionable type whose owner is editions-enabled. A schema object of an editionable type owned by a user who is not editions-enabled is potentially editioned: it behaves like an ordinary object until its owner is enabled. A noneditioned object is visible to all editions and has no edition of its own; in the data dictionary its `EDITION_NAME` is null.

Editioned objects are uniquely identified by owner, object name, and edition name. The same package name can therefore exist in `V1` and in `V2` as two different objects, each with its own source, and a session sees only the copy in its own edition.

## Enabling editions for a schema

A schema becomes editions-enabled with one statement:

```sql
ALTER USER lab_app ENABLE EDITIONS;
```

Two things to know before running it. First, enabling editions for a user is irreversible; there is no statement to turn it off again. Second, it should be done before the schema creates the objects it will version. Objects created by an editions-enabled user in an edition other than `ORA$BASE` are editioned in that edition. Objects created in `ORA$BASE` itself are not editioned, even for an editions-enabled owner, because `ORA$BASE` is the shared root every edition inherits from.

A schema also needs the `USE` privilege on every edition its sessions will connect to:

```sql
GRANT USE ON EDITION v1 TO lab_app;
```

Without it, a session cannot set that edition and the connection fails. The lab grants this as part of setup.

## Session editions and default editions

A session runs in exactly one edition at a time, and that edition decides which copy of every editioned object the session sees. Three levels decide which edition a session starts in, in this order of precedence:

1. The edition named on the connection, for example in the service definition or the connect string.
2. The user's default edition, set with `ALTER USER <user> DEFAULT EDITION = <edition>`.
3. The database default edition, which is `ORA$BASE` unless it has been changed.

A session can also change its own edition after connecting:

```sql
ALTER SESSION SET EDITION = v1;
```

The current edition of a session is readable at any time:

```sql
SELECT SYS_CONTEXT('USERENV', 'CURRENT_EDITION_NAME') FROM dual;
```

The important consequence is that a cutover is a session property, not a database event. Nothing is recompiled and no object is replaced when sessions move. The old edition keeps serving the sessions still in it until the last one leaves, and the new edition serves the sessions that arrive after the change. That is what makes the upgrade online, and it is also why the DBA's job during a cutover is session management: watching which sessions remain in the old edition, and knowing when the old edition can be dropped.

## Edition inheritance

A child edition inherits every editioned object from its parent. An object that is not re-created in the child is the parent's object, unchanged, and a session in the child sees it exactly as a session in the parent does. When an object is re-created in the child, the child's copy shadows the parent's for sessions in the child edition and in any edition below it, while sessions in the parent keep seeing the parent's copy.

This is the mechanism that makes an upgrade incremental. Creating `V2` as a child of `V1` does not copy the schema; it gives you an empty workspace that sees all of `V1` until you change something in it. You then redefine only the objects that change. Everything else is inherited, which is why a version that touches three packages out of a hundred only needs three objects re-created.

Inheritance also explains the one-child rule. If a parent could have two children, the same object could be redefined two different ways under one parent, and the inheritance chain would stop being a chain. The single chain keeps the question "which copy does this session see" unambiguous: walk down from `ORA$BASE` to the session's edition and take the most recent copy of the object.

## What EBR does not do

EBR versions code, not data and not table structure. Three limits follow from that, and each has its own feature later in the lab:

- A table cannot be editioned. If a change alters a table's columns, the table keeps one physical shape, and each edition sees it through an editioning view that projects the columns that edition expects. That is the subject of the third stage of this lab.
- Data written by old-edition sessions and data written by new-edition sessions land in the same table. If the new edition stores something the old edition cannot read, a forward crossedition trigger translates old writes into new columns, and a reverse crossedition trigger does the opposite during a hot rollover. That is the fourth stage.
- Sessions already connected do not move editions on their own. A cutover moves them by reconnecting, by repointing a service, or by a logon trigger, and the old edition stays until the last session leaves. That is the fifth stage.

## Versions and licensing

Editions and editioned objects arrived in Oracle Database 11g Release 2. Editioning views and crossedition triggers arrived in Oracle Database 12c Release 1, so the later stages of this lab need 12c or later. Edition-Based Redefinition needs no separate license and is available in all Oracle Database editions, including Standard Edition. That is worth stating plainly, because several features EBR is often used alongside, such as the Diagnostics Pack for AWR and ASH, Active Data Guard, and Transparent Data Encryption, do carry licensing requirements of their own.

## The lab's versioning story

The lab schema is a small order system: customers, orders, a view of customer orders, and a PL/SQL package that places orders. Version 1 is the application as it ships. Later stages add a second edition with a changed package, then a changed table shape behind an editioning view, then crossedition triggers, and finally a cutover and rollback. Each stage changes one thing, verifies it with the inventory script, and leaves the previous version intact so the difference between editions can be inspected directly.

## References

- Oracle Database Development Guide, "Edition-Based Redefinition" (Oracle documentation)
- Oracle Database SQL Language Reference, `CREATE EDITION` and `ALTER SESSION`
- Oracle Database Reference, `DBA_EDITIONS`, `DBA_OBJECTS_AE`, `DBA_USERS`, `DATABASE_PROPERTIES`
