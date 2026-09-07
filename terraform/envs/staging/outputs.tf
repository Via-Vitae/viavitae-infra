# Outputs for the `staging` environment.

output "environment_name" {
  value       = var.environment_name
  description = "Always `staging`."
}

output "ha_group" {
  value       = proxmox_hagroup.staging.group
  description = "HA group. Lower priority than prod's, so an N-1 event evicts staging first."
}

output "pool_id" {
  value       = local.pool_id
  description = "Proxmox resource pool, from the global allocation."
}

output "vmid_block" {
  value       = local.vmid_block
  description = "Allocated VMID block."
}

output "control_plane" {
  value = {
    for key, node in module.stg_cp : key => {
      name    = node.name
      fqdn    = node.fqdn
      ipv4    = node.ipv4_host
      vm_id   = node.vm_id
      node    = node.node_name
      version = node.k3s_version
    }
  }
  description = "Control-plane VMs. One entry per control plane, with the Proxmox node it landed on — which is the input the ADR-002 quorum check reasons about."
}

output "workers" {
  value = {
    for key, node in module.stg_worker : key => {
      name  = node.name
      fqdn  = node.fqdn
      ipv4  = node.ipv4_host
      vm_id = node.vm_id
      node  = node.node_name
    }
  }
  description = "Worker VMs. Consumed by the Ansible inventory generator and by HAProxy's backend list."
}

output "postgres" {
  value = {
    name         = module.stg_db.name
    ipv4         = module.stg_db.ipv4_host
    port         = module.stg_db.port
    vm_id        = module.stg_db.vm_id
    wal_g_bucket = module.stg_db.wal_g_bucket
    connection   = module.stg_db.connection_string_without_credentials
  }
  description = "Tenant database instance. The connection string carries no credentials by construction."
}

output "keycloak" {
  value = {
    name       = module.stg_sso.name
    ipv4       = module.stg_sso.ipv4_host
    port       = module.stg_sso.port
    vm_id      = module.stg_sso.vm_id
    issuer_url = module.stg_sso.issuer_url
  }
  description = "Identity provider. The issuer URL is what every staging client is configured with."
}

output "tenants" {
  value = {
    for slug, tenant in module.tenant : slug => {
      schema    = tenant.schema_name
      role      = tenant.role_name
      namespace = tenant.namespace
      hostname  = tenant.hostname
      quotas    = tenant.quotas
      state     = tenant.lifecycle_state
    }
  }
  description = <<-EOT
    Provisioned tenants. The `clients` ApplicationSet must produce a namespace,
    ResourceQuota and LimitRange matching these values; a mismatch means the tenant's
    application cannot reach its own database, and neither side reports it.
  EOT
}

output "committed_memory_mb" {
  value = (
    sum([for node in module.stg_cp : node.memory_dedicated_mb]) +
    sum([for node in module.stg_worker : node.memory_dedicated_mb]) +
    module.stg_db.memory_dedicated_mb +
    module.stg_sso.memory_dedicated_mb
  )
  description = <<-EOT
    Total memory this environment commits. Compared against the 384 GiB guest budget
    in docs/capacity-plan.md, and the number that decides whether a node failure
    leaves room for anything. Reported as an output so it is visible in every plan
    rather than only in a document somebody has to remember to update.
  EOT
}

output "committed_vcpu" {
  value = (
    sum([for node in module.stg_cp : node.cpu_cores]) +
    sum([for node in module.stg_worker : node.cpu_cores]) +
    module.stg_db.cpu_cores +
    module.stg_sso.cpu_cores
  )
  description = "Total vCPU committed, against the 240 vCPU overcommitted budget."
}
