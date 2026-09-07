# Inputs for modules/postgres-vm.
#
# A PostgreSQL host. The module fixes everything that ADR-003 and INFRA-001 make
# non-negotiable — protection, HA, no ballooning, WAL archive destination — and
# leaves only placement and sizing to the caller.

variable "name" {
  type        = string
  description = "Host name, e.g. db-01 or stg-db-0."
}

variable "instance_purpose" {
  type        = string
  description = <<-EOT
    What this instance holds. It is written to /etc/viavitae/pg-purpose and read by
    ansible/roles/postgres, which applies a different tuning and a different
    retention profile per purpose. It is also what makes ADR-007 condition 4
    enforceable: a `bitrix24` purpose may never share an instance with `tenants`.
  EOT

  validation {
    condition     = contains(["tenants", "keycloak", "bitrix24"], var.instance_purpose)
    error_message = "instance_purpose must be tenants, keycloak or bitrix24."
  }
}

variable "is_primary" {
  type        = bool
  default     = true
  description = "Primary or standby. A standby is not backed up by WAL-G (the primary's archive is the backup) but is still covered by vzdump for configuration recovery."
}

variable "standby_of" {
  type        = string
  default     = ""
  description = "For a standby, the address of the primary it replicates from. Required when is_primary is false."
}

variable "wal_g_bucket" {
  type        = string
  default     = ""
  description = <<-EOT
    S3 bucket name for WAL-G continuous archiving. **A name only.** The bucket
    credentials live in the SOPS-encrypted Ansible inventory and are never passed
    to Terraform, because anything given to a provider argument ends up in state,
    in the plan file and in the Proxmox API log.
  EOT

  validation {
    condition     = var.wal_g_bucket == "" || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.wal_g_bucket))
    error_message = "wal_g_bucket must be a valid S3 bucket name."
  }
}

variable "data_disk_size_gb" {
  type        = number
  default     = 500
  description = "PGDATA volume. docs/capacity-plan.md triggers a design change at 500 GB of instance data, so the default is sized exactly to the trigger rather than above it."

  validation {
    condition     = var.data_disk_size_gb >= 100 && var.data_disk_size_gb <= 8192
    error_message = "data_disk_size_gb must be between 100 GiB and 8 TiB."
  }
}

variable "wal_disk_size_gb" {
  type        = number
  default     = 40
  description = "Separate volume for pg_wal. Splitting WAL from data is not a performance luxury here: a WAL disk that fills stops the database cleanly and predictably, while a shared disk that fills takes the whole instance down mid-checkpoint."
}

variable "cpu_cores" {
  type        = number
  default     = 8
  description = "vCPU cores."
}

variable "memory_dedicated_mb" {
  type        = number
  default     = 32768
  description = "Committed memory in MiB. shared_buffers is derived from this by ansible/roles/postgres, so changing it without re-running that role leaves the database sized for a machine it is no longer on."
}

variable "node_name" {
  type        = string
  description = "Proxmox node hosting this VM."
}

variable "vm_id" {
  type        = number
  description = "VMID from the shared block for prod, or the environment block for staging and dev."
}

variable "vmid_block" {
  type = object({
    start = number
    end   = number
  })
  description = "Allocated VMID block."
}

variable "pool_id" {
  type        = string
  description = "Proxmox resource pool."
}

variable "ha_group" {
  type        = string
  description = "HA group. Required — this module has no default, because a database that is not HA-managed does not come back after a node failure until a human arrives."
}

variable "datastore_id" {
  type        = string
  description = "ZFS pool datastore."
}

variable "snippets_datastore_id" {
  type        = string
  description = "Snippets-enabled datastore for cloud-init."
}

variable "template_vm_id" {
  type        = number
  description = "Cloud-init template VMID."
}

variable "template_node_name" {
  type        = string
  default     = ""
  description = "Node holding the template."
}

variable "vlan_id" {
  type        = number
  description = "VLAN. Must be prod (20), staging (30) or dmz (40, only for a bitrix24-purpose instance)."
}

variable "ipv4_address" {
  type        = string
  description = "Static address in CIDR notation."
}

variable "ipv4_gateway" {
  type        = string
  description = "Gateway for that VLAN."
}

variable "dns_domain" {
  type        = string
  default     = "viavitae.internal"
  description = "DNS search domain."
}

variable "dns_servers" {
  type        = list(string)
  description = "Recursive resolvers."
}

variable "ssh_public_keys" {
  type        = list(string)
  description = "SSH public keys for the automation user."
}

variable "environment_name" {
  type        = string
  description = "Environment label, used in tags and in /etc/viavitae/environment."
}

variable "started" {
  type        = bool
  default     = true
  description = "Whether the VM runs after apply."
}
