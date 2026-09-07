# Inputs for modules/keycloak-vm.

variable "name" {
  type        = string
  description = "Host name, e.g. sso-01 or stg-sso-0."
}

variable "public_hostname" {
  type        = string
  description = <<-EOT
    Externally visible name, e.g. sso.viavitae.com. Keycloak derives its issuer
    URL, its redirect URI allow-list and its cookie domain from this, so it must be
    the name a browser actually uses. Getting it wrong produces a login that
    authenticates and then fails on redirect, with no error in either log.
  EOT

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$", var.public_hostname))
    error_message = "public_hostname must be a fully qualified DNS name."
  }
}

variable "database_host" {
  type        = string
  description = "Address of the keycloak-purpose PostgreSQL instance. Keycloak shares no instance with tenant data: an identity store that can be reached by a tenant query is a privilege boundary that does not exist."
}

variable "cpu_cores" {
  type        = number
  default     = 4
  description = "vCPU cores."
}

variable "memory_dedicated_mb" {
  type        = number
  default     = 8192
  description = "Committed memory. Keycloak runs on the JVM and its heap is derived from this by ansible/roles/keycloak; changing one without the other produces a container that is OOM-killed or a heap that wastes the allocation."
}

variable "disk_size_gb" {
  type        = number
  default     = 60
  description = "Root disk. Keycloak itself is stateless; its state is the database."
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
  description = "HA group. Required: without authentication no administrator can log in to fix anything, including an outage of authentication."
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
  description = "VLAN. Must be prod (20) or staging (30)."
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
  description = "Environment label."
}

variable "started" {
  type        = bool
  default     = true
  description = "Whether the VM runs after apply."
}
