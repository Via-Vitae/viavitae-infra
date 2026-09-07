# modules/postgres-vm — a PostgreSQL host as a Proxmox guest.
#
# Installs nothing. Writes the facts Ansible needs into /etc/viavitae/ and enforces
# the invariants that make a database host different from any other VM: protected,
# HA-managed, no ballooning, WAL split from data, and never sharing an instance
# across purposes.

locals {
  provisioning_files = {
    "/etc/viavitae/pg-purpose"    = "${var.instance_purpose}\n"
    "/etc/viavitae/pg-role"       = var.is_primary ? "primary\n" : "standby\n"
    "/etc/viavitae/pg-standby-of" = var.is_primary ? "" : "${var.standby_of}\n"
    "/etc/viavitae/pg-memory-mb"  = "${var.memory_dedicated_mb}\n"
    "/etc/viavitae/environment"   = "${var.environment_name}\n"
    # Empty string is meaningful: it tells the role that continuous archiving is
    # not configured for this instance, which the role must then refuse for a
    # `tenants` purpose rather than silently skipping.
    "/etc/viavitae/wal-g-bucket" = var.wal_g_bucket == "" ? "" : "${var.wal_g_bucket}\n"
  }

  tags = concat(
    ["postgres", var.environment_name, var.instance_purpose],
    # A primary is backed up daily and archived continuously. A standby's data is
    # a copy of the primary's archive, so a daily vzdump of it is a second copy of
    # the same bytes at the cost of a full backup window; weekly is enough to
    # recover configuration and to have something to rebuild from.
    [var.is_primary ? "backup-daily" : "backup-weekly"],
  )
}

module "vm" {
  source = "../proxmox-vm"

  name        = var.name
  description = "PostgreSQL ${var.instance_purpose} ${var.is_primary ? "primary" : "standby"} for ${var.environment_name}. Owner: platform. Holds personal data — see INFRA-001 F7."
  node_name   = var.node_name
  vm_id       = var.vm_id
  vmid_block  = var.vmid_block
  pool_id     = var.pool_id

  template_vm_id        = var.template_vm_id
  template_node_name    = var.template_node_name
  snippets_datastore_id = var.snippets_datastore_id

  cpu_cores           = var.cpu_cores
  memory_dedicated_mb = var.memory_dedicated_mb
  memory_ballooning   = false

  disks = [
    {
      interface    = "scsi"
      size_gb      = 30
      datastore_id = var.datastore_id
      iothread     = true
      ssd          = true
      discard      = true
      backup       = true
      replicate    = true
      cache        = "none"
    },
    {
      # PGDATA. `backup = false` is deliberate and counter-intuitive: the database
      # is recovered by WAL-G from the archive, which is transactionally
      # consistent. A vzdump copy of a running PGDATA is a fallback of last resort,
      # and excluding it from the daily archive halves the backup window for the
      # largest volumes in the estate. It stays in the ZFS replication job, so a
      # node failure still has a copy.
      interface    = "scsi"
      size_gb      = var.data_disk_size_gb
      datastore_id = var.datastore_id
      iothread     = true
      ssd          = true
      discard      = true
      backup       = false
      replicate    = true
      cache        = "none"
    },
    {
      # pg_wal on its own volume, so a WAL surge fills this disk and stops the
      # database cleanly instead of filling a shared disk mid-checkpoint.
      interface    = "scsi"
      size_gb      = var.wal_disk_size_gb
      datastore_id = var.datastore_id
      iothread     = true
      ssd          = true
      discard      = false
      backup       = false
      replicate    = true
      cache        = "none"
    },
  ]

  bridge          = "vmbr1"
  vlan_id         = var.vlan_id
  ipv4_address    = var.ipv4_address
  ipv4_gateway    = var.ipv4_gateway
  dns_domain      = var.dns_domain
  dns_servers     = var.dns_servers
  ssh_public_keys = var.ssh_public_keys

  bios                  = "ovmf"
  efi_disk_datastore_id = var.datastore_id

  # Non-negotiable for this role: this VM holds every tenant's data, including
  # Art. 9 data via the backups described in INFRA-001.
  protect_deletion = true
  ha_group         = var.ha_group
  on_boot          = true
  started          = var.started

  tags        = local.tags
  extra_files = local.provisioning_files

  depends_on = [terraform_data.postgres_invariants]
}

resource "terraform_data" "postgres_invariants" {
  input = {
    purpose    = var.instance_purpose
    primary    = var.is_primary
    standby_of = var.standby_of
    bucket     = var.wal_g_bucket
    vlan       = var.vlan_id
  }

  lifecycle {
    # ADR-007 condition 4: Bitrix24 gets its own instance. Sharing one would put
    # a closed-source vendor workload with an outbound flow we cannot inspect on
    # the same server as every tenant's personal data, and would make a Bitrix24
    # compromise a tenant breach.
    precondition {
      condition     = var.instance_purpose == "bitrix24" ? var.vlan_id == 40 : var.vlan_id != 40
      error_message = "A bitrix24-purpose instance must be on the dmz VLAN (40), and no other purpose may be. See ADR-007 condition 4 and docs/network-topology.md rule X9."
    }

    # A tenants instance without continuous archiving has an RPO of 24 hours, not
    # the 5 minutes promised in README.md and relied on by INFRA-001 F7.
    precondition {
      condition     = var.instance_purpose == "tenants" && var.is_primary ? var.wal_g_bucket != "" : true
      error_message = "A primary `tenants` instance requires wal_g_bucket. Without continuous archiving the RPO is the vzdump interval (24 h), which contradicts the ≤ 5 min RPO committed in README.md and assumed by INFRA-001."
    }

    precondition {
      condition     = var.is_primary ? var.standby_of == "" : var.standby_of != ""
      error_message = "A standby must declare standby_of; a primary must not."
    }

    # Databases belong in prod, staging or dmz. A database on the management VLAN
    # is reachable from the runners, which hold CI credentials, and rule X11 would
    # have to be opened for the cluster to reach it.
    precondition {
      condition     = contains([20, 30, 40], var.vlan_id)
      error_message = "vlan_id must be 20 (prod), 30 (staging) or 40 (dmz). A database on the mgmt VLAN would require an exception to the no-route-to-mgmt invariant."
    }
  }
}
