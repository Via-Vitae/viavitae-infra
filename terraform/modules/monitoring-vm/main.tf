# modules/monitoring-vm — object store for the observability stack, plus the
# external prober.
#
# Installs nothing. ansible/playbooks/… does not cover this VM either: MinIO and
# Uptime Kuma are configured by ansible/roles/monitoring-agent and
# ansible/roles/backup-check from the facts written here. The monitors themselves
# are desired-state in monitoring/uptime-kuma/monitors.yaml and are applied by that
# role, so a monitor is never added by hand on the box.

locals {
  provisioning_files = {
    "/etc/viavitae/minio-loki-bucket"    = "${var.loki_bucket}\n"
    "/etc/viavitae/minio-metrics-bucket" = "${var.metrics_bucket}\n"
    "/etc/viavitae/minio-region"         = "eu-central-1\n"
    "/etc/viavitae/uptime-hostname"      = "${var.uptime_kuma_hostname}\n"
    "/etc/viavitae/environment"          = "${var.environment_name}\n"
    # Retention is a compliance parameter, not a tuning one: INFRA-001 F1 caps log
    # retention at 30 days, and a lifecycle rule that outlives the DPIA is a
    # retention breach nobody decided to make.
    "/etc/viavitae/minio-loki-retention-days" = "30\n"
  }

  tags = ["monitoring", var.environment_name, "object-store", "backup-daily"]
}

module "vm" {
  source = "../proxmox-vm"

  name        = var.name
  description = "Monitoring object store (Loki ${var.loki_bucket}, metrics ${var.metrics_bucket}) and external prober for ${var.environment_name}. Owner: platform. Holds log data — INFRA-001 F1, F2, F14."
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
      # Bucket volume. Excluded from vzdump: the buckets have their own lifecycle
      # and their own offsite replication, and copying 400 GB of chunks into a VM
      # archive every night doubles the backup window to protect data that is
      # already protected twice. Replication stays on, so a node failure has a copy.
      interface    = "scsi"
      size_gb      = var.object_store_disk_size_gb
      datastore_id = var.datastore_id
      iothread     = true
      ssd          = true
      discard      = true
      backup       = false
      replicate    = true
      cache        = "none"
    },
  ]

  bridge          = "vmbr1"
  vlan_id         = 20
  ipv4_address    = var.ipv4_address
  ipv4_gateway    = var.ipv4_gateway
  dns_domain      = var.dns_domain
  dns_servers     = var.dns_servers
  ssh_public_keys = var.ssh_public_keys

  bios                  = "ovmf"
  efi_disk_datastore_id = var.datastore_id

  # Loki chunks contain personal data (INFRA-001 R2), so this is a protected host
  # even though it holds no tenant database.
  protect_deletion = true
  ha_group         = var.ha_group
  on_boot          = true
  started          = var.started

  tags        = local.tags
  extra_files = local.provisioning_files

  depends_on = [terraform_data.monitoring_invariants]
}

resource "terraform_data" "monitoring_invariants" {
  input = {
    loki_bucket    = var.loki_bucket
    metrics_bucket = var.metrics_bucket
    address        = var.ipv4_address
  }

  lifecycle {
    # The object store is on the prod VLAN so that rules X6, X7 and X8 describe a
    # path that exists. On mgmt it would be unreachable from the cluster without an
    # exception to the no-route-to-mgmt invariant.
    precondition {
      condition     = can(regex("^10\\.10\\.20\\.[0-9]{1,3}/24$", var.ipv4_address))
      error_message = "ipv4_address must be inside 10.10.20.0/24 (the prod VLAN), matching the allocation table in docs/network-topology.md."
    }

    # Two buckets, two purposes, two retention rules. A single bucket would make
    # the 30-day log retention apply to metric blocks as well, or force one
    # lifecycle rule to serve two different DPIA positions.
    precondition {
      condition     = var.loki_bucket != var.metrics_bucket
      error_message = "loki_bucket and metrics_bucket must differ. Logs are personal data with a 30-day cap; metric blocks are aggregates with a one-year downsampled retention. One bucket cannot have two retention rules."
    }

    precondition {
      condition     = var.object_store_disk_size_gb >= 200
      error_message = "object_store_disk_size_gb must be at least 200 GiB; below that the 25-tenant retention model in docs/capacity-plan.md does not fit and the ZFS pool crosses its 75 % trigger immediately."
    }
  }
}
