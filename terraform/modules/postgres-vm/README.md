# modules/postgres-vm

A PostgreSQL host. Wraps [`../proxmox-vm`](../proxmox-vm/README.md) with the
sizing, protection and tagging that ADR-003 and INFRA-001 require, and installs
nothing: `ansible/playbooks/postgres.yml` does that, reading the facts this module
writes to `/etc/viavitae/`.

## What is fixed here and why

| Fixed | Value | Reason |
| --- | --- | --- |
| `protect_deletion` | `true`, always | This VM holds every tenant's data. Destroying it because an environment block was commented out during a refactor is the failure mode the flag exists for. |
| `memory_ballooning` | `false`, always | The guest OOM killer picks the largest process. On this host that is PostgreSQL, and `proxmox-vm` fails the plan if the two settings ever disagree. |
| HA group | required, no default | An unmanaged database does not restart after a node failure. Making the argument required means omitting it is a plan error rather than a 03:00 discovery. |
| PGDATA disk `backup` | `false` | The database is recovered from the WAL-G archive, which is transactionally consistent. A `vzdump` copy of a running PGDATA is a last-resort fallback; excluding it halves the backup window for the largest volumes. Replication is still on, so a node failure has a copy. |
| `pg_wal` | separate volume | A WAL disk that fills stops the database cleanly. A shared disk that fills takes the instance down mid-checkpoint. |
| `vlan_id` | 20, 30 or 40 only | A database on the mgmt VLAN would be reachable from the CI runners and would require an exception to the no-route-to-mgmt invariant. |
| Bitrix24 instance | dmz VLAN only, and nothing else may be there | ADR-007 condition 4. Sharing an instance would make a Bitrix24 compromise a tenant breach. |
| Primary `tenants` instance | requires `wal_g_bucket` | Without continuous archiving the RPO is the `vzdump` interval, which contradicts the ≤ 5 min committed in `README.md`. |

## No credential, ever

`wal_g_bucket` is a **bucket name**. The bucket's access key, the replication
password and every application role password live in the SOPS-encrypted Ansible
inventory (`ansible/inventories/<env>/group_vars/*.sops.yml`) and are applied
inside the guest by `ansible/roles/postgres` and `ansible/roles/wal-g`.

Anything passed to a provider argument ends up in Terraform state, in the plan
file attached to the pull request, and in the Proxmox API task log. ADR-003
decision 3 is why the tenant module creates roles without passwords and Ansible
sets them.

## Ansible contract

Files written at first boot, read by `ansible/roles/postgres`:

| Path | Content |
| --- | --- |
| `/etc/viavitae/pg-purpose` | `tenants`, `keycloak` or `bitrix24` |
| `/etc/viavitae/pg-role` | `primary` or `standby` |
| `/etc/viavitae/pg-standby-of` | Primary address, or empty |
| `/etc/viavitae/pg-memory-mb` | Committed memory, from which `shared_buffers` is derived |
| `/etc/viavitae/wal-g-bucket` | Bucket name, or empty. Empty on a `tenants` primary makes the role fail rather than silently skip archiving |
| `/etc/viavitae/environment` | Environment label |

The role **fails** when a file is missing rather than falling back to a default.
A silent default is a second source of truth, and the two disagree on the first
upgrade.

## Example

```hcl
module "db_01" {
  source = "../modules/postgres-vm"

  name              = "db-01"
  instance_purpose  = "tenants"
  is_primary        = true
  wal_g_bucket      = "viavitae-wal-prod"
  data_disk_size_gb = 500

  node_name             = "pve-01"
  vm_id                 = 930
  vmid_block            = data.terraform_remote_state.global.outputs.shared_vmid_block
  pool_id               = data.terraform_remote_state.global.outputs.pool_ids["prod"]
  ha_group              = "viavitae-prod-ha"
  datastore_id          = "local-zfs"
  snippets_datastore_id = "local"
  template_vm_id        = 9000

  vlan_id         = 20
  ipv4_address    = "10.10.20.30/24"
  ipv4_gateway    = "10.10.20.1"
  dns_servers     = ["10.10.10.1", "10.10.10.2"]
  ssh_public_keys = var.ssh_public_keys

  environment_name = "prod"
}
```
