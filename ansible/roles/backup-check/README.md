# ansible/roles/backup-check

Verify backups on every host.

The role checks:
- **Level 1**: The backup job ran recently (within 48 hours).
- **Level 2**: The backup checksum is valid.
- **Level 3**: The backup can be restored to a scratch VM (not implemented in this role;
  that is the DR drill's job, per `docs/runbooks/dr-drill.md`).

The role defaults to level 2 because level 3 requires a scratch VM and is slow.

## What the role does not do

- It does not configure backups. That is the `backup` playbook's job (vzdump for the
  whole VM, WAL-G for the database).
- It does not configure offsite replication. That is `backup/offsite/replication.md`.
- It does not perform DR drills. That is `docs/runbooks/dr-drill.md`.
