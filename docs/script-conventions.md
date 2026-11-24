# Script conventions

Every script in this repo follows the same shape so it is predictable to run and safe to schedule:

- Header comment: purpose, usage, and exit codes for SQL scripts. Nothing else in the header.
- Thresholds and lab parameters as `DEFINE` variables at the top of SQL scripts, with defaults noted in the comment.
- No hard-coded hostnames, SIDs, service names, credentials, or paths. Examples use placeholders like `$ORACLE_SID`, `<SERVICE_NAME>`, and `<LAB_PASSWORD>`.
- The inventory script is read-only. The setup script is not: it creates a user, an edition, tables, a view, and a package. Its header says so, and nothing here runs against a database you care about. Lab databases only.
- Upgrade scripts are not re-runnable: an edition that already exists fails the script, so the teardown doc drops the child edition first. Comparison scripts are read-only in net effect: probe writes are rolled back before the script moves on.
- SQL scripts are templates for a lab, not turnkey jobs. Read them, replace the placeholders, and check the statements against your lab before running them.
- Exit code 0 on success; non-zero on failure or threshold breach, documented per script.
- Output is plain text, readable in a terminal and greppable in logs.

New scripts should add a usage example to the README.
