# ansible/roles/wal-g

Install and configure WAL-G for continuous archiving and point-in-time recovery on a
PostgreSQL primary.

The role is skipped on the standby, which receives WAL via streaming replication and
does not archive.

The WAL-G binary is downloaded from the upstream release and verified against a checksum
in `tools/verify-shas.sh`. The configuration file is written with credentials from
`vault.sops.yml`; the bucket name is not secret, the access key is.

## What the role does not do

- It does not configure base backups. That is the `backup` playbook's job (vzdump for
  the whole VM, WAL-G for the database).
- It does not configure offsite replication. That is `backup/offsite/replication.md`.
- It does not configure backup verification. That is the `backup-check` role.
