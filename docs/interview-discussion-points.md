# Interview discussion points

The points below are the answers this lab is built to support in a conversation with a senior DBA or hiring manager. They are stated as the lab demonstrates them, not as claims about production experience.

## What EBR is, in one sentence

Edition-Based Redefinition lets you upgrade the database component of an application while it is in use, by keeping more than one version of the application's code in the database at the same time and letting each session see the version that belongs to it.

## Why editions instead of a maintenance window

A normal upgrade replaces code in place, so every session sees the new version at once, including sessions mid-transaction. EBR installs the new version in a new edition while the old version keeps serving, and sessions move when they reconnect. There is no second database to keep in step and no window in which the application must stop for the code change.

## What can and cannot be versioned

Packages, procedures, functions, views, synonyms, triggers, types, and libraries are editionable. Tables are not, and neither are indexes, sequences, constraints, or materialized views. A table exists once and is shared by every edition. That single fact drives the rest of the design: table structure changes go through editioning views, and live data changes go through crossedition triggers.

## How a session picks its edition

Three levels, in precedence order: the edition named on the connection, the user's default edition, and the database default edition. A session can also change its own edition with `ALTER SESSION SET EDITION`. A cutover is therefore a session property, not a database event: nothing is recompiled when sessions move, and the old edition keeps serving until the last session leaves it.

## Inheritance and shadowing

A child edition inherits every editioned object from its parent. An object re-created in the child shadows the parent's copy for sessions in the child, while sessions in the parent keep seeing the parent's copy. An upgrade that touches three packages out of a hundred only re-creates three objects, which is why EBR upgrades stay incremental.

The lab shows both sides at once: the `ORDER_API` package is redefined in `V2`, so it appears in `DBA_OBJECTS_AE` under both editions and each edition runs its own copy, while the `CUSTOMER_ORDERS` view is not redefined in `V2`, so it appears only under `V1` and `V2` sessions inherit it. A session in `V2` calling the new `customer_total_spent` function gets 339.49 for customer 101; the same call in `V1` fails with `PLS-00201`, because the function does not exist there. The validation difference is just as sharp: `V2` rejects a negative amount with `ORA-20001` and an unknown customer with `ORA-20002`, while `V1` accepts the negative amount and reports an unknown customer only through the foreign key.

## Enabling editions is a one-way door

`ALTER USER ... ENABLE EDITIONS` is irreversible, and it should be done before the schema creates the objects it will version. Objects created in `ORA$BASE` are never editioned, even for an editions-enabled owner. A schema also needs the `USE` privilege on every edition its sessions will connect to.

## What EBR does not solve by itself

It versions code, not data and not table structure. Changing a table's columns needs an editioning view. Keeping old-edition and new-edition writes consistent needs crossedition triggers. Moving already-connected sessions needs reconnects, a repointed service, or a logon trigger. Each of those is a later stage of this lab.

## Building a version is not shipping it

Creating `V2` changes nothing for existing sessions. The lab schema default edition stays `V1`, and sessions start in `V1` until the cutover stage changes the default. A session reaches `V2` only by asking for it, with `ALTER SESSION SET EDITION`, and only with the `USE` privilege on `V2`. That separation is what lets a DBA install and test a version before anyone's traffic moves to it, and it is why the cutover is a session-management job rather than a deployment event.

## Licensing

EBR needs no separate license and is available in all Oracle Database editions. That is distinct from features often used alongside it, such as the Diagnostics Pack, Active Data Guard, and Transparent Data Encryption, which do carry their own licensing requirements.
