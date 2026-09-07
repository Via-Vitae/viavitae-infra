# Inputs for the `staging` environment.
#
# Staging is a scaled copy of prod, not a copy of prod. It exists to answer two
# questions before production does: "does this change work" and "does the recovery
# procedure work". It is the DR drill target, which is why it has a real database
# VM, a real identity provider and a real worker — and why it has no Bitrix24, no
# second database node and one control plane instead of three.

variable "environment_name" {
  type        = string
  default     = "staging"
  description = "Environment label, used to look up this environment's VMID block and resource pool in the global root module's outputs. Fixed by the directory; the default exists so a plan works without a tfvars file."

  validation {
    condition     = var.environment_name == "staging"
    error_message = "This root module provisions the staging environment. Copying the directory to create another environment means changing this validation too, so that the copy cannot silently keep writing to staging's VMID block and pool."
  }
}

# --- state -------------------------------------------------------------------

variable "state_bucket" {
  type        = string
  description = "Bucket holding the global root module's state."
}

variable "state_region" {
  type        = string
  default     = "eu-central-1"
  description = "Region of the state bucket."
}

variable "state_endpoint" {
  type        = string
  description = "S3-compatible endpoint of the state bucket. Must match backend.tf; a data source can interpolate variables, a backend block cannot."
}

# --- cluster -----------------------------------------------------------------

variable "node_names" {
  type        = list(string)
  description = "Proxmox nodes available to staging."

  validation {
    condition     = length(var.node_names) > 0 && length(distinct(var.node_names)) == length(var.node_names)
    error_message = "node_names must be non-empty and free of duplicates."
  }
}

variable "k3s_version" {
  type        = string
  description = "Pinned k3s release. Staging runs the version prod will get next, which is the only reason a staging cluster is worth its RAM."

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+\\+k3s[0-9]+$", var.k3s_version))
    error_message = "k3s_version must be a fully pinned release such as v1.36.4+k3s1."
  }
}

variable "control_plane_count" {
  type        = number
  default     = 1
  description = "One. Staging does not rehearse control-plane HA; the Q3 DR drill rehearses node failure, which is a different thing and does not need three members."
}

variable "api_vip_address" {
  type        = string
  default     = ""
  description = "Kubernetes API VIP. Empty while there is one control plane; required the moment control_plane_count exceeds 1."
}

variable "worker_count" {
  type        = number
  default     = 1
  description = "Worker VMs. One is enough to rehearse a rollout and a pod eviction; two would cost 32 GiB to rehearse nothing extra."

  validation {
    condition     = var.worker_count >= 1 && var.worker_count <= 4
    error_message = "worker_count must be between 1 and 4 in staging."
  }
}

variable "ha_group_nodes" {
  type        = map(number)
  description = "HA group membership as node => priority. Lower than every prod group's priority, so an N-1 event evicts staging before it evicts a tenant workload."
}

# --- storage and template ----------------------------------------------------

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
  description = "Cloud-init template VMID."
}

variable "template_node_name" {
  type        = string
  default     = ""
  description = "Node holding the template."
}

# --- network -----------------------------------------------------------------

variable "vlan_id" {
  type        = number
  default     = 30
  description = "VLAN 30."
}

variable "subnet_prefix" {
  type        = string
  default     = "10.10.30.0/24"
  description = "Subnet for this environment's VLAN."
}

variable "ipv4_gateway" {
  type        = string
  default     = "10.10.30.1"
  description = "Gateway for this environment's VLAN."
}

variable "postgres_address" {
  type        = string
  description = "Static address of the PostgreSQL primary, in CIDR notation, from the allocation table in docs/network-topology.md."

  validation {
    condition     = can(cidrhost(var.postgres_address, 0))
    error_message = "postgres_address must be a CIDR address, e.g. 10.10.30.10/24."
  }
}

variable "keycloak_address" {
  type        = string
  description = "Static address of the Keycloak VM, in CIDR notation, from the allocation table."

  validation {
    condition     = can(cidrhost(var.keycloak_address, 0))
    error_message = "keycloak_address must be a CIDR address, e.g. 10.10.30.20/24."
  }
}

variable "control_plane_address_offset" {
  type        = number
  default     = 30
  description = "Host offset inside the subnet for the first control-plane VM. Sequential VMs take the next offsets. Matches the allocation table, where stg-cp-0 is 10.10.30.30."
}

variable "worker_address_offset" {
  type        = number
  default     = 40
  description = "Host offset inside the subnet for the first worker VM. Matches the allocation table, where stg-worker-0 is 10.10.30.40."
}

variable "dns_domain" {
  type        = string
  default     = "viavitae.internal"
  description = "Internal DNS search domain."
}

variable "dns_servers" {
  type        = list(string)
  description = "Recursive resolvers reachable from VLAN 30."

  validation {
    condition     = length(var.dns_servers) >= 2
    error_message = "At least two resolvers."
  }
}

variable "ssh_public_keys" {
  type        = list(string)
  description = "SSH public keys for the automation user."
}

# --- VMIDs -------------------------------------------------------------------

variable "vmids" {
  type = object({
    control_plane_base = number
    worker_base        = number
    postgres_primary   = number
    keycloak           = number
  })
  description = "Starting VMIDs, allocated inside this environment's block. Control planes and workers are numbered sequentially from their bases, so raising worker_count consumes the next identifier and never reuses one."
}

# --- database ----------------------------------------------------------------



variable "database_name" {
  type        = string
  default     = "viavitae"
  description = "Database containing the tenant schemas."
}



variable "wal_g_bucket" {
  type        = string
  description = "S3 bucket for continuous archiving in staging. A separate bucket from prod: a staging restore that reads prod's archive is a staging restore that can overwrite prod's recovery point."
}

variable "migration_role_name" {
  type        = string
  default     = "migrations"
  description = "Role that owns tenant schema objects and runs migrations. Distinct from every tenant's application role, so DDL and DML cannot be confused by an injection."
}

# --- DNS ---------------------------------------------------------------------

variable "dns_update_server" {
  type        = string
  description = "Authoritative DNS server accepting RFC 2136 updates."
}

variable "dns_update_key_name" {
  type        = string
  description = "TSIG key name. Scoped to the staging hostnames; a key that can update the whole zone is a key that can redirect production."
}

variable "dns_update_key_algorithm" {
  type        = string
  default     = "hmac-sha256"
  description = "TSIG algorithm."

  validation {
    condition     = contains(["hmac-sha256", "hmac-sha512"], var.dns_update_key_algorithm)
    error_message = "Only HMAC-SHA256 and HMAC-SHA512 are accepted. MD5 TSIG is still supported by many servers and is not acceptable for a key that can redirect a hostname."
  }
}

variable "dns_update_key_secret" {
  type        = string
  sensitive   = true
  description = "TSIG key secret, supplied as TF_VAR_dns_update_key_secret from the GitHub Environment."
}

variable "dns_zone" {
  type        = string
  description = "Authoritative zone for staging hostnames. Staging uses its own zone or a delegated subdomain, never the production zone: a staging record created in the production zone by a test run is a production incident."

  validation {
    condition     = endswith(var.dns_zone, ".")
    error_message = "dns_zone must be fully qualified with a trailing dot."
  }
}

variable "dns_target" {
  type        = string
  description = "CNAME target for tenant hostnames in this environment."
}

# --- tenants -----------------------------------------------------------------

variable "tenants" {
  type = map(object({
    display_name    = string
    plan            = string
    lifecycle_state = optional(string, "active")
    public_hostname = optional(string, "")
    manage_dns      = optional(bool, true)
  }))
  default     = {}
  description = <<-EOT
    Tenants to provision in staging. Empty by default, and staging tenants should be
    synthetic: a real tenant's data in staging is a second copy of personal data in
    a second place, with a second retention obligation and a weaker access model.
    Where a real tenant must be rehearsed, the drill uses a restored copy on a
    scratch VM per docs/runbooks/dr-drill.md, not a standing staging tenant.
  EOT

  validation {
    condition = alltrue([
      for slug, tenant in var.tenants :
      can(regex("^[a-z][a-z0-9]{1,22}$", slug))
    ])
    error_message = "Every tenant key must be a valid slug: 2-23 characters, lowercase letters and digits, starting with a letter."
  }
}

variable "dpia_infra_001_signed_off" {
  type        = bool
  default     = false
  description = "INFRA-001 managing-director signature. Required for prod tenants; recorded here so that staging can rehearse the check failing."
}
