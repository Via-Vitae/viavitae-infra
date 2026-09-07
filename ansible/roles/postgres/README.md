# ansible/roles/postgres

Install and configure PostgreSQL 16 on a host declared by `terraform/modules/postgres-vm`.

The role reads `/etc/viavitae/pg-purpose` to determine the instance's purpose (tenants,
bitrix24, or other) and refuses to run if the file is absent. For bitrix24 instances, it
additionally requires ADR-007 conditions 7 and 8 to be met in the inventory.

The provisioner and replication roles are created on first run; their passwords come from
`vault.sops.yml`. Terraform connects as the provisioner role to create tenant schemas and
roles (ADR-003 decision 3).

WAL-G archiving is enabled on the primary when `postgres_walg_enabled` is true; the standby
receives WAL via streaming replication and does not archive.

## What the role does not do

- It does not create tenant schemas or roles. That is Terraform's job (`terraform/modules/tenant`).
- It does not configure backups. That is the `wal-g` role's job.
- It does not tune for a specific workload. The defaults are a starting point; a host with
  more than 16 GB RAM will need tuning beyond what a role can guess.
