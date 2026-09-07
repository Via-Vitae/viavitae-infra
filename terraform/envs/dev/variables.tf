# Inputs for the `dev` environment.
#
# `dev` is one disposable VM. It has no PostgreSQL VM, no Keycloak VM and no
# monitoring VM of its own: PostgreSQL runs in-cluster as a StatefulSet on
# emptyDir-class storage, and developers authenticate against the staging identity
# provider. That is a deliberate exception to ADR-003's external-database rule and
# it is recorded there, because an exception nobody wrote down becomes the pattern
# somebody copies into staging.

variable "environment_name" {
  type        = string
  default     = "dev"
  description = "Environment label. Fixed by the directory; the default exists so `terraform plan` works without a tfvars file."
}

variable "state_bucket" {
  type        = string
  description = "Bucket holding the global root module's state, read through terraform_remote_state."
}

variable "state_region" {
  type        = string
  default     = "eu-central-1"
  description = "Region of the state bucket."
}

variable "state_endpoint" {
  type        = string
  description = "S3-compatible endpoint of the state bucket. Must match backend.tf; a data source can interpolate variables, a backend block cannot, which is why this value appears twice."
}

variable "node_names" {
  type        = list(string)
  description = "Proxmox nodes available to this environment. `dev` schedules onto whichever node has the most free memory at apply time, so both are listed."

  validation {
    condition     = length(var.node_names) > 0
    error_message = "At least one node is required."
  }
}

variable "k3s_version" {
  type        = string
  description = "Pinned k3s release for this environment. `dev` runs one minor version *behind* staging on purpose: an upgrade that breaks something breaks it here first, and a dev cluster that is always newest tests nothing about the version production will get."

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+\\+k3s[0-9]+$", var.k3s_version))
    error_message = "k3s_version must be a fully pinned release such as v1.36.4+k3s1."
  }
}

variable "control_plane_count" {
  type        = number
  default     = 1
  description = "Always 1 in dev. A disposable single-node cluster is the point."
}

variable "node_vmid" {
  type        = number
  default     = 1000
  description = "VMID of the single dev node, from the dev block in docs/network-topology.md."
}

variable "datastore_id" {
  type        = string
  description = "ZFS pool datastore for VM disks."
}

variable "snippets_datastore_id" {
  type        = string
  description = "Snippets-enabled datastore for cloud-init."
}

variable "template_vm_id" {
  type        = number
  description = "Cloud-init template VMID for this environment."
}

variable "template_node_name" {
  type        = string
  default     = ""
  description = "Node holding the template."
}

variable "vlan_id" {
  type        = number
  default     = 50
  description = "VLAN 50. `dev` has its own VLAN precisely so that a throwaway workload is not in the same broadcast domain as the pre-production copy of the platform."
}

variable "subnet_prefix" {
  type        = string
  default     = "10.10.50.0/24"
  description = "Subnet for this environment's VLAN."
}

variable "ipv4_gateway" {
  type        = string
  default     = "10.10.50.1"
  description = "Gateway for this environment's VLAN."
}

variable "node_ipv4_address" {
  type        = string
  default     = "10.10.50.10/24"
  description = "Address of the single dev node."
}

variable "dns_servers" {
  type        = list(string)
  description = "Recursive resolvers reachable from VLAN 50."

  validation {
    condition     = length(var.dns_servers) >= 2
    error_message = "At least two resolvers."
  }
}

variable "dns_domain" {
  type        = string
  default     = "viavitae.internal"
  description = "Internal DNS search domain."
}

variable "ssh_public_keys" {
  type        = list(string)
  description = "SSH public keys for the automation user and for developers who need console access to a broken dev node."
}

variable "ha_group_nodes" {
  type        = map(number)
  description = <<-EOT
    HA group membership as node => priority. `dev` gets the lowest priority in the
    cluster so that, in an N-1 situation, Proxmox tries to start it last and fails
    for want of memory rather than displacing something that matters. The group
    exists even though dev is disposable: the invariant in modules/k3s-node that a
    control plane must be HA-managed is worth more than the convenience of an
    exception to it.
  EOT
}

variable "cpu_cores" {
  type        = number
  default     = 4
  description = "vCPU for the single node. Higher than the control-plane default because this VM is control plane and worker at once."
}

variable "memory_dedicated_mb" {
  type        = number
  default     = 16384
  description = "Committed memory for the single node."
}

variable "disk_size_gb" {
  type        = number
  default     = 100
  description = "Root disk. Sized for the worker half of the node's job, which is image layers."
}

variable "started" {
  type        = bool
  default     = true
  description = "Whether the node runs after apply. Setting this false is how dev is parked to free RAM for a DR drill."
}
