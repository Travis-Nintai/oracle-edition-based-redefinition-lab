# Multiple editions and editioned PL/SQL

Stage 1 built version 1 of the lab: one edition, one package, one view. This stage builds version 2, and the point of the stage is the difference between the two editions, not the new code itself. A second edition is where EBR stops being a definition and starts being a technique: two versions of the same package exist in one database, each session sees one of them, and the data underneath is shared.

## Building version 2

Run the upgrade script as SYSDBA, in the scratch database built by stage 1:

```
sqlplus / as sysdba @sql/ebr_lab_upgrade_v2.sql
```

Before running it, edit the `lab_password` DEFINE at the top of the script. It must match the value used when stage 1 built the lab. The script does, in order:

1. Creates the `V2` edition as a child of `V1`.
2. Grants the lab schema `USE` on the `V2` edition.
3. Connects as the lab schema and sets the session edition to `V2` explicitly.
4. Redefines the `ORDER_API` package in `V2`, with validation and a new function.
5. Probes the V2 package behavior, rolling the probe writes back.
6. Reconnects as SYSDBA and verifies the cross-edition layout, exiting 0 when it matches the design and 2 when a check fails.

The lab schema default edition stays `V1`. Nothing in this stage changes it. Sessions keep starting in `V1` until the cutover stage changes the default, which is deliberate: building a version and shipping a version are separate acts, and this stage is only the first one.

## Creating a child edition

```sql
CREATE EDITION v2 AS CHILD OF v1;
```

Three rules from the fundamentals doc decide whether this succeeds. A parent can have at most one child, so `V1` must not already have one. Creating the child needs the `USE` privilege on the parent, which the creator holds by default. And the edition is only a workspace: it holds no data, and creating it copies nothing. `V2` starts empty and sees all of `V1` through inheritance until something is redefined in it.

Re-running the upgrade script fails, because the `V2` edition already exists. To rebuild from the stage 1 state, drop the edition first, as SYSDBA:

```sql
DROP EDITION v2 CASCADE;
```

`DROP EDITION ... CASCADE` drops the editioned objects that exist only in that edition, which here is the V2 copy of the package. `V1` and the shared tables are untouched. Do not run either statement against a database that matters.

## Inheritance and shadowing, shown by the lab

This stage was designed so the two mechanisms are visible in the same dictionary query. Run the inventory script and the comparison script after the upgrade:

```
sqlplus / as sysdba @sql/edition_inventory.sql
sqlplus / as sysdba @sql/edition_comparison.sql
```

The inventory script still passes, because the stage 1 layout is intact: `V1` exists, the schema is editions-enabled, and the `V1` view and package are editioned in `V1`. The comparison script shows what stage 2 added:

| Object | V1 | V2 | What a session sees |
|---|---|---|---|
| `ORDER_API` package and body | Yes | Yes | Its own edition copy. The V2 copy shadows the V1 copy for V2 sessions. |
| `CUSTOMER_ORDERS` view | Yes | No row | V1 sessions see the V1 view. V2 sessions see the same view by inheritance, because a child edition inherits every editioned object it does not redefine. |
| `CUSTOMERS`, `ORDERS`, sequences | Noneditioned | Noneditioned | One copy, shared by every edition. |

The rule to take from the table: an editioned object appears in `DBA_OBJECTS_AE` under the edition where it was created. An object redefined in the child appears under both editions. An object left alone appears only under the parent, and the child sees it anyway. That is why an upgrade that touches three packages out of a hundred only re-creates three objects; everything else is inherited, and the dictionary proves it.

## What changed in V2, and why

The V2 package is a realistic small upgrade, the kind that ships on a normal release: a validation the first version lacked, and one new function the application asked for. Nothing about the tables changed, so no editioning view or crossedition trigger is needed yet. Those come in the next two stages.

### Validation in `place_order`

V1 accepts any amount, including a negative one, and an unknown customer fails only when the foreign key rejects the insert, with `ORA-02291`. V2 checks first:

- An amount of zero or less raises `ORA-20001`, "Order amount must be greater than zero."
- A customer id with no matching row raises `ORA-20002`, "Customer does not exist."

The errors are application errors in the -20000 range, raised with `RAISE_APPLICATION_ERROR`, so the application sees a message it can act on instead of a constraint name. The validation runs before the insert, so a rejected call writes nothing. A DBA reading this change should notice what it does not do: it does not change the table, the sequence, or any existing call that passes valid values. Valid traffic behaves identically in both editions, which is what makes the upgrade safe to ship edition by edition.

### The new function `customer_total_spent`

```sql
FUNCTION customer_total_spent(p_customer_id IN NUMBER) RETURN NUMBER;
```

It returns the sum of a customer's order amounts, or 0 when the customer has no orders. For the seed data, customer 101 totals 339.49, from orders of 249.99 and 89.50. The function exists only in V2. A V1 session that calls it gets `PLS-00201`, identifier must be declared, because in V1 the function does not exist at all. That is the sharpest demonstration in this stage that editions version code: the same schema, the same package name, and one edition has a function the other has never heard of.

Note the deliberate ambiguity in the return value: 0 means either a customer with no orders or a customer that does not exist. The function reports spend, not existence, and the doc states that plainly so nobody reads more into a 0 than it carries. The customer-existence check belongs in `place_order`, where an unknown customer is an error, not in a reporting function.

### What did not change

`order_total` and `customer_order_count` are identical in both editions. They are carried into the V2 package in full, because a package is replaced as a unit: redefining it means supplying the whole spec and body, not a patch. The view is untouched, the tables are untouched, and the seed data is untouched. The upgrade script proves the last point by rolling back its probe writes and the comparison script proves it by counting the rows afterwards: three customers, three orders.

## Comparing the editions

`sql/edition_comparison.sql` is the stage 2 check, and it is the script to reach for whenever a later stage needs to show what differs between two editions. It runs as SYSDBA and its net effect is read-only: every probe write is rolled back. It reports, in order:

1. The edition chain, from `DBA_EDITIONS`.
2. Every editioned lab object by edition, from `DBA_OBJECTS_AE`. This is the inheritance table above, as query output.
3. The source lines that differ, from `DBA_SOURCE_AE`: the new function name and the two error numbers, each labelled with its edition. `DBA_SOURCE_AE` is the across-all-editions source view; the session-scoped `DBA_SOURCE` would show only the current edition.
4. A behavior probe in V2: the new function returns 339.49, a negative amount is rejected with -20001, an unknown customer with -20002, a valid order is accepted and rolled back, and the inherited view returns three rows.
5. A behavior probe in V1: a negative amount is accepted and rolled back, the new function is not callable, and the view returns three rows.
6. A row count confirming the seed data is unchanged, then a verdict that exits 0 when the layout matches the design and 2 when a check fails.

Two details of the probes are worth knowing. The V1 call to the V2-only function goes through dynamic SQL (`EXECUTE IMMEDIATE` with an `OUT` bind), because a direct call would fail the script at compile time with `PLS-00201` instead of at run time, where the exception handler can catch it and report it. And the probe orders consume sequence values that a rollback does not return; sequence gaps after a probe are normal and harmless.

## Gotchas

- **Creating objects in the wrong edition.** The classic EBR mistake is forgetting which edition the session is in. Always check `SYS_CONTEXT('USERENV', 'CURRENT_EDITION_NAME')` before creating or replacing an editioned object, and confirm it again in the verification output. The upgrade script prints the current edition after setting it, and the verification section shows which edition each object belongs to.
- **The `USE` privilege.** A session cannot set its edition to `V2` without `USE` on `V2`. The grant is part of the upgrade script, and the error without it is a plain privilege error at `ALTER SESSION`, not a helpful hint about editions. If a session cannot switch editions, check the grant first.
- **Default edition versus session edition.** The user default edition is `V1` and the database default edition is `ORA$BASE`. Setting a session edition changes one session; it changes no default and affects no other session. Confusing the two is how a DBA ships a version to everyone by accident, or tests a version while believing it is live.
- **Package state does not cross editions.** Sessions already running in `V1` keep the `V1` package, with its state, while `V2` is built. Creating `V2` objects invalidates nothing in `V1`. That is the property the whole technique rests on, and it is also why the DBA's job at cutover is session management, not recompilation.
- **A package is replaced whole.** There is no partial redefinition. The V2 spec and body carry the unchanged functions along with the new one, and a function left out of the V2 spec would simply not exist in V2.
- **The one-child rule.** `V1` can have only one child, so there is exactly one `V2`. A second line of development from `V1` would need its own chain, and that is a design conversation, not a script change.

## Versions and licensing

Editions and editioned PL/SQL need Oracle Database 11g Release 2 or later, and everything in this stage stays inside that baseline. The comparison script reads `DBA_SOURCE_AE`, which has existed since 11g Release 2. Edition-Based Redefinition needs no separate license and is available in all Oracle Database editions.

## What comes next

- Stage 3: editioning views, for the day a table has to change shape. The `CUSTOMER_ORDERS` view, inherited untouched in this stage, is where that change will land.
- Stage 4: crossedition triggers and data migration, keeping old and new writes in step.
- Stage 5: cutover and rollback, moving sessions between editions and retiring the old one.
- Then the APEX operations dashboard stages, and the final combined APEX plus EBR zero-downtime upgrade.

## References

- Oracle Database Development Guide, "Edition-Based Redefinition" (Oracle documentation)
- Oracle Database Reference, `DBA_OBJECTS_AE`, `DBA_SOURCE_AE`, `DBA_EDITIONS`
- Oracle Database PL/SQL Language Reference, `RAISE_APPLICATION_ERROR`
