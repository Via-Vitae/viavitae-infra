# Inputs for modules/monitoring-vm.
#
# This VM is not the monitoring stack. Prometheus, Grafana, Loki and Alertmanager
# run **in the cluster**, deployed by Argo CD from monitoring/*/values.yaml. What
# lives here is the two things that cannot:
#
#   1. The object store those components write to. Loki has no local-disk mode that
#      survives a node failure, and an in-cluster MinIO would store the logs of the
#      cluster inside the cluster it is logging — a failure that destroys the
#      evidence of itself.
#   2. The external prober. A monitor running inside the thing it monitors reports
#      healthy until the moment there is nobody left to report anything.

variable "name" {
  type        = string
  description = "Host name, e.g. mon-01."
}

variable "loki_bucket" {
  type        = string
  description = "Object store bucket for Loki chunks and index. Contents are personal data under INFRA-001 F1 and inherit the 30-day retention."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.loki_bucket))
    error_message = "loki_bucket must be a valid S3 bucket name."
  }
}

variable "metrics_bucket" {
  type        = string
  description = "Object store bucket for Prometheus long-term blocks. Aggregate data; the cardinality budget in docs/capacity-plan.md keeps person-level labels out of it."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.metrics_bucket))
    error_message = "metrics_bucket must be a valid S3 bucket name."
  }
}

variable "uptime_kuma_hostname" {
  type        = string
  description = "Public name of the status page, e.g. status.viavitae.com. Served through HAProxy into the cluster-free prober on this VM."
}

variable "object_store_disk_size_gb" {
  type        = number
  default     = 400
  description = <<-EOT
    Bucket volume. Sized from the retention model rather than from disk price: at
    25 tenants, 90 MB/tenant/day after redaction and 30 days' retention, Loki needs
    roughly 70 GB, and Prometheus long-term blocks need roughly 100 GB at the
    cardinality budget. 400 GB is four times that, which is the headroom the
    `ZFS pool > 75 %` trigger in docs/capacity-plan.md assumes.
  EOT

  validation {
    condition     = var.object_store_disk_size_gb >= 200 && var.object_store_disk_size_gb <= 8192
    error_message = "object_store_disk_size_gb must be between 200 GiB and 8 TiB."
  }
}

variable "cpu_cores" {
  type        = number
  default     = 8
  description = "vCPU cores."
}

variable "memory_dedicated_mb" {
  type        = number
  default     = 24576
  description = "Committed memory. MinIO is not memory-hungry; the allocation is headroom for compaction and for the prober's concurrent checks."
}

variable "node_name" {
  type        = string
  description = "Proxmox node hosting this VM."
}

variable "vm_id" {
  type        = number
  description = "VMID from the shared block."
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
  description = "HA group. Required: priority 7 in the N-1 order, deliberately above `dev` and below the workloads, because an incident without evidence is an incident that will repeat."
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

variable "ipv4_address" {
  type        = string
  description = "Static address in CIDR notation on the prod VLAN, 10.10.20.10 in the allocation table."
}

variable "ipv4_gateway" {
  type        = string
  description = "Gateway for the prod VLAN."
}

variable "dns_domain" {
  type        = string
  default     = "viavitae.internal"
  description = "Internal DNS search domain."
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
  description = "Environment label. One monitoring VM serves all environments; the label identifies the object store, not a per-environment instance."
}

variable "started" {
  type        = bool
  default     = true
  description = "Whether the VM runs after apply."
}
