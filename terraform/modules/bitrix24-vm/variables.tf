# Inputs for modules/bitrix24-vm.
#
# This module carries two approval flags that exist for one reason: ADR-007 makes
# Bitrix24 deployment in `prod` conditional on a legal review and on a completed
# DPIA, and a condition that is only written in an ADR is a condition that gets
# forgotten by whoever writes the tfvars.

variable "name" {
  type        = string
  description = "Host name, e.g. crm-01."
}

variable "legal_review_approved" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether Legal has approved the vendor terms, including the data processing
    terms, the support arrangement and any outbound licence-validation flow.
    ADR-007 condition 7. Defaults to false so that the safe state is the default
    and enabling it is a visible, reviewed change.
  EOT
}

variable "dpia_infra_002_approved" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether DPIA INFRA-002 (Bitrix24 on-premises) has been approved by the DPO.
    ADR-007 condition 8 and INFRA-001 condition C5. The record is reserved in
    docs/DPIA-template.md and must exist before a `prod` VM is created, because
    this is closed-source software with an outbound flow that cannot be inspected.
  EOT
}

variable "legal_review_reference" {
  type        = string
  default     = ""
  description = "Issue or document reference for the legal review. Required when legal_review_approved is true: an approval with no reference cannot be audited, and an unauditable approval is an assertion."
}

variable "dpia_reference" {
  type        = string
  default     = ""
  description = "DPIA record reference. Required when dpia_infra_002_approved is true."
}

variable "public_hostname" {
  type        = string
  description = "Externally visible name, e.g. crm.viavitae.com. Terminated on the dmz VIP and forwarded to this VM."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$", var.public_hostname))
    error_message = "public_hostname must be a fully qualified DNS name."
  }
}

variable "database_host" {
  type        = string
  description = "Address of the bitrix24-purpose database instance in the dmz. Never the tenant instance."
}

variable "egress_allow_list" {
  type        = list(string)
  description = <<-EOT
    Hostnames the VM is permitted to reach on the internet, implemented as rule E6
    in docs/network-topology.md. Empty means no internet egress at all, which
    breaks licence validation — so an empty list is a decision, not an omission,
    and the precondition below requires it to be explicit.
  EOT

  validation {
    condition = alltrue([
      for h in var.egress_allow_list : can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$", h))
    ])
    error_message = "Each entry must be a fully qualified hostname. Wildcards are rejected: an allow-list that contains *.vendor.com is an allow-list that contains whatever the vendor's DNS says tomorrow."
  }
}

variable "cpu_cores" {
  type        = number
  default     = 8
  description = "vCPU cores. The vendor's LAMP stack is not small."
}

variable "memory_dedicated_mb" {
  type        = number
  default     = 16384
  description = "Committed memory."
}

variable "disk_size_gb" {
  type        = number
  default     = 200
  description = "Root disk, holding the application and its uploads."
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
  description = <<-EOT
    HA group. Required, but note that in the two-node pilot this VM is priority 10
    in the N-1 start order and will not fit on the surviving node — HA will attempt
    to start it and fail. That is the correct behaviour: the attempt is visible and
    the reason is documented, rather than the VM silently never coming back.
  EOT
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
  description = "Static address in CIDR notation on the dmz VLAN."
}

variable "ipv4_gateway" {
  type        = string
  description = "dmz gateway."
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
  description = "Environment label. `prod` triggers the approval preconditions."
}

variable "started" {
  type        = bool
  default     = true
  description = "Whether the VM runs after apply."
}
