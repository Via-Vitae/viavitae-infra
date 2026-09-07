# Inputs for the `prod` environment.
#
# This file is the production inventory. Every value in it is either a placement
# decision, a capacity decision or an approval, and all three belong in a plan that
# a human reads before an apply. What is *not* here is any credential: those come
# from the `prod-apply` GitHub Environment, and the `prod-plan` Environment holds
# read-only ones.

variable "environment_name" {
  type        = string
  default     = "prod"
  description = "Environment label, used to look up this environment's VMID block and resource pool."

  validation {
    condition     = var.environment_name == "prod"
    error_message = "This root module provisions production. A copy of this directory that keeps writing to prod's VMID block and pool is the failure this validation exists to prevent."
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
  description = "S3-compatible endpoint of the state bucket. Must match backend.tf."
}

# --- cluster -----------------------------------------------------------------

variable "node_names" {
  type        = list(string)
  description = <<-EOT
    Proxmox nodes available to production, in placement order. This list is the
    input to the ADR-002 quorum gate: with two entries, `control_plane_count` may
    only be 1, because three control-plane VMs on two nodes always lose etcd quorum
    when one node fails.
  EOT

  validation {
    condition     = length(var.node_names) > 0 && length(distinct(var.node_names)) == length(var.node_names)
    error_message = "node_names must be non-empty and free of duplicates."
  }
}

variable "k3s_version" {
  type        = string
  description = "Pinned k3s release, promoted from staging. Changing it is a cluster upgrade and is a `prod` change class in CONTRIBUTING.md, which requires a rollback answer."

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+\\+k3s[0-9]+$", var.k3s_version))
    error_message = "k3s_version must be a fully pinned release such as v1.36.4+k3s1. A channel resolves to whatever is newest at install time."
  }
}

variable "control_plane_count" {
  type        = number
  default     = 1
  description = <<-EOT
    Control-plane VMs. **1 in the two-node pilot.** Raising it to 3 requires a third
    Proxmox node in `node_names`, and modules/k3s-node fails the plan otherwise.
  EOT

  validation {
    condition     = contains([1, 3], var.control_plane_count)
    error_message = "control_plane_count must be 1 or 3. An even number of etcd members has the same quorum as one fewer member and one more failure domain, so 2 buys nothing and costs 4 GiB."
  }
}

variable "api_vip_address" {
  type        = string
  default     = ""
  description = "Kubernetes API VIP held by kube-vip. Required when control_plane_count is 3; forbidden when it is 1, because a VIP in front of a single member is a second thing that can fail without adding anything."
}

variable "worker_count" {
  type        = number
  default     = 4
  description = "Worker VMs. docs/capacity-plan.md puts the RAM ceiling at four workers on the pilot hardware; the fifth is the trigger to order node 3, not a value to raise optimistically."

  validation {
    condition     = var.worker_count >= 1 && var.worker_count <= 20
    error_message = "worker_count must be between 1 and 20, the size of the prod worker VMID range."
  }
}

variable "ha_group_nodes" {
  type        = map(number)
  description = <<-EOT
    HA group membership as node => priority, higher first. These priorities are the
    mechanism behind the N-1 start order in docs/capacity-plan.md; the table in that
    document and these numbers are the same decision written twice, and a change to
    one is a change to the other.
  EOT
}

variable "ha_group_critical_nodes" {
  type        = map(number)
  description = <<-EOT
    A second, restricted HA group holding only the database and the identity
    provider. Two groups rather than one because a single group applies one priority
    order to everything: with one group, either the CRM competes with the database
    for the surviving node's memory, or the priority list has to be re-derived for
    every VM. With two, the critical group is restricted to the node that has room
    and the general group absorbs the rest.
  EOT
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
  description = "Cloud-init template VMID for production."
}

variable "template_node_name" {
  type        = string
  default     = ""
  description = "Node holding the template. Set it when templates are not replicated to every node, which is the normal case."
}

# --- network -----------------------------------------------------------------

variable "vlan_ids" {
  type = object({
    mgmt = number
    prod = number
    dmz  = number
  })
  default = {
    mgmt = 10
    prod = 20
    dmz  = 40
  }
  description = "VLAN tags used by this environment. Production spans three of them because the load balancers are dual-homed and Bitrix24 lives in the dmz."
}

variable "subnet_prefixes" {
  type = object({
    mgmt = string
    prod = string
    dmz  = string
  })
  default = {
    mgmt = "10.10.10.0/24"
    prod = "10.10.20.0/24"
    dmz  = "10.10.40.0/24"
  }
  description = "Subnets for those VLANs, from docs/network-topology.md."
}

variable "ipv4_gateways" {
  type = object({
    mgmt = string
    prod = string
    dmz  = string
  })
  default = {
    mgmt = "10.10.10.1"
    prod = "10.10.20.1"
    dmz  = "10.10.40.1"
  }
  description = "Gateways for those VLANs."
}

variable "control_plane_address_offset" {
  type        = number
  default     = 40
  description = "Host offset inside the prod subnet for the first control plane. 10.10.20.40 in the allocation table."
}

variable "worker_address_offset" {
  type        = number
  default     = 50
  description = "Host offset inside the prod subnet for the first worker. 10.10.20.50 in the allocation table."
}

variable "addresses" {
  type = object({
    postgres_primary = string
    postgres_standby = string
    keycloak         = string
    monitoring       = string
    bitrix24         = string
    bitrix24_db      = string
  })
  description = "Static addresses for the shared VMs, in CIDR notation, from the allocation table in docs/network-topology.md."
}

variable "load_balancer_addresses" {
  type = list(object({
    mgmt = string
    dmz  = string
  }))
  description = <<-EOT
    One entry per load-balancer VM, each with its management address on VLAN 10 and
    its data-path address on VLAN 40. Exactly two entries: keepalived needs a pair,
    and a third member would need a different quorum model than the one
    docs/network-topology.md describes.
  EOT

  validation {
    condition     = length(var.load_balancer_addresses) == 2
    error_message = "Exactly two load-balancer VMs. keepalived runs an active/passive pair; a third VM does not add availability, it adds a split-brain candidate."
  }
}

variable "runner_addresses" {
  type        = list(string)
  description = "Management addresses of the CI runner VMs, on VLAN 10. Two entries: one runner is a maintenance window, not an outage, and a fix needed during an incident must not queue behind a runner that is being patched."

  validation {
    condition     = length(var.runner_addresses) >= 1 && length(var.runner_addresses) <= 4
    error_message = "Between one and four runner VMs."
  }
}

variable "dns_domain" {
  type        = string
  default     = "viavitae.internal"
  description = "Internal DNS search domain."
}

variable "dns_servers" {
  type        = list(string)
  description = "Recursive resolvers reachable from every VLAN this environment uses."

  validation {
    condition     = length(var.dns_servers) >= 2
    error_message = "At least two resolvers."
  }
}

variable "ssh_public_keys" {
  type        = list(string)
  description = "SSH public keys for the automation user. Production keys are a smaller set than staging's, and adding one is a change reviewed by security per CODEOWNERS."
}

variable "public_vip" {
  type        = string
  description = "Public virtual IP held by keepalived on the load-balancer pair, e.g. 203.0.113.10. It is an input because it comes from the allocated public block and is also configured on the firewall; Terraform cannot see the firewall, so the two are reconciled in review rather than by code."

  validation {
    condition     = can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", var.public_vip))
    error_message = "public_vip must be a bare IPv4 address, not a CIDR range."
  }
}

variable "public_hostname" {
  type        = string
  description = "Public name the VIP answers for, e.g. lb.viavitae.com. Every tenant CNAME points at this name rather than at the VIP, so moving the platform between addresses is one record instead of one per tenant."
}

# --- VMIDs -------------------------------------------------------------------

variable "vmids" {
  type = object({
    control_plane_base = number
    worker_base        = number
    postgres_primary   = number
    postgres_standby   = number
    keycloak           = number
    monitoring         = number
    bitrix24           = number
    bitrix24_db        = number
    load_balancer_base = number
    runner_base        = number
  })
  description = <<-EOT
    VMID allocations. Control planes and workers come from the prod block
    (1200-1399); everything else comes from the shared block (900-999), because the
    load balancers, the database, the identity provider, the monitoring store, the
    runners and Bitrix24 serve the whole platform rather than one environment.
  EOT
}

# --- database ----------------------------------------------------------------



variable "database_name" {
  type        = string
  default     = "viavitae"
  description = "Database containing the tenant schemas."
}



variable "postgres_standby_enabled" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether to create the standby. **False in the pilot**: docs/capacity-plan.md
    shows 340.5 GiB committed against a 384 GiB budget, and a 32 GiB standby is the
    difference between fitting and not fitting. ADR-003 records the consequence —
    recovery is from the WAL archive rather than from a replica — and the trigger for
    enabling it is node 3 arriving, not a preference.
  EOT
}

variable "wal_g_bucket" {
  type        = string
  description = "S3 bucket for continuous archiving. Separate from staging's and from the state bucket."
}

variable "postgres_data_disk_size_gb" {
  type        = number
  default     = 500
  description = "PGDATA volume, sized to the trigger in docs/capacity-plan.md rather than above it."
}

variable "migration_role_name" {
  type        = string
  default     = "migrations"
  description = "Role that owns tenant schema objects and runs migrations, distinct from every tenant's application role."
}

# --- identity ----------------------------------------------------------------

variable "keycloak_public_hostname" {
  type        = string
  description = "Public name of the identity provider, e.g. sso.viavitae.com. Becomes the issuer URL in every client, so changing it is a coordinated change with viavitae-api and viavitae-web."
}

# --- monitoring --------------------------------------------------------------

variable "monitoring" {
  type = object({
    loki_bucket          = string
    metrics_bucket       = string
    uptime_kuma_hostname = string
    disk_size_gb         = number
  })
  description = "Object store buckets and status-page name for the monitoring VM. Two buckets, because logs are personal data with a 30-day cap and metric blocks are aggregates with a one-year downsampled retention."
}

# --- Bitrix24 ----------------------------------------------------------------

variable "bitrix24" {
  type = object({
    enabled                 = bool
    public_hostname         = string
    legal_review_approved   = bool
    legal_review_reference  = string
    dpia_infra_002_approved = bool
    dpia_reference          = string
    egress_allow_list       = list(string)
  })
  description = <<-EOT
    ADR-007 conditions, as data. `enabled` defaults to false and the two approvals
    default to false, so the safe state is the state you get by doing nothing.
    modules/bitrix24-vm fails the plan if `enabled` is true in prod without both
    approvals, and INFRA-001 condition C5 is the reason.
  EOT
}

# --- DNS ---------------------------------------------------------------------

variable "dns_update_server" {
  type        = string
  description = "Authoritative DNS server accepting RFC 2136 updates."
}

variable "dns_update_key_name" {
  type        = string
  description = "TSIG key name, scoped to the tenant hostnames this environment may create."
}

variable "dns_update_key_algorithm" {
  type        = string
  default     = "hmac-sha256"
  description = "TSIG algorithm."

  validation {
    condition     = contains(["hmac-sha256", "hmac-sha512"], var.dns_update_key_algorithm)
    error_message = "Only HMAC-SHA256 and HMAC-SHA512 are accepted. MD5 TSIG can still redirect a hostname, which is the whole thing this key authorises."
  }
}

variable "dns_update_key_secret" {
  type        = string
  sensitive   = true
  description = "TSIG key secret, supplied as TF_VAR_dns_update_key_secret from the prod-apply GitHub Environment."
}

variable "dns_zone" {
  type        = string
  description = "Production authoritative zone, e.g. viavitae.com. with the trailing dot."

  validation {
    condition     = endswith(var.dns_zone, ".")
    error_message = "dns_zone must be fully qualified with a trailing dot, or the provider creates a relative record."
  }
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
    Production tenants. Provisioning one is a `prod` change class in
    CONTRIBUTING.md: it needs the plan attached, a rollback answer, and — because a
    schema is created and a role is granted — the DPIA gate below.
  EOT

  validation {
    condition = alltrue([
      for slug, tenant in var.tenants :
      can(regex("^[a-z][a-z0-9]{1,22}$", slug)) &&
      contains(["community", "essential", "professional"], tenant.plan) &&
      contains(["active", "suspended", "erasure_pending"], tenant.lifecycle_state)
    ])
    error_message = "Each tenant needs a valid slug, a known plan and a known lifecycle_state."
  }
}

variable "dpia_infra_001_signed_off" {
  type        = bool
  default     = false
  description = <<-EOT
    INFRA-001 managing-director signature. Defaults to false, and modules/tenant
    refuses to create a production tenant while it is false. That is INFRA-001
    control M20: the DPIA is a precondition of processing rather than a description
    of it. The signature is genuinely pending — see the sign-off table in
    docs/DPIA-template.md.
  EOT
}
