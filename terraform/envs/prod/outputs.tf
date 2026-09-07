# Outputs for the `prod` environment.
#
# These are the reconciliation surface: tools/preflight.sh compares them against what
# is actually running, and the nightly drift job in deploy.yml compares them against
# state. An output that is not checked is documentation.

output "environment_name" {
  value       = var.environment_name
  description = "Always `prod`."
}

output "ha_groups" {
  value = {
    general  = proxmox_hagroup.prod.group
    critical = proxmox_hagroup.prod_critical.group
  }
  description = "The two HA groups. The critical group holds the database, the identity provider and the load balancers, and is restricted so that an N-1 event cannot place them on a node with no room."
}

output "pool_id" {
  value       = local.pool_id
  description = "Proxmox resource pool."
}

output "vmid_blocks" {
  value = {
    environment = local.vmid_block
    shared      = local.shared_vmid_block
    restore     = local.global.restore_vmid_block
  }
  description = "The blocks this environment draws from, including the restore scratch block it must never allocate into."
}

output "control_plane" {
  value = {
    for key, node in module.prod_cp : key => {
      name    = node.name
      fqdn    = node.fqdn
      ipv4    = node.ipv4_host
      vm_id   = node.vm_id
      node    = node.node_name
      version = node.k3s_version
    }
  }
  description = "Control-plane VMs with the Proxmox node each landed on. If two entries share a node while control_plane_count is 3, the cluster loses quorum on a single node failure."
}

output "workers" {
  value = {
    for key, node in module.prod_worker : key => {
      name  = node.name
      fqdn  = node.fqdn
      ipv4  = node.ipv4_host
      vm_id = node.vm_id
      node  = node.node_name
    }
  }
  description = "Worker VMs. The addresses are HAProxy's backends, so this output and /etc/viavitae/haproxy-backends on the load balancers must agree."
}

output "haproxy_backends" {
  value       = local.worker_hosts
  description = "The backend list written to the load balancers. Kept as an output so a reviewer can see the consequence of changing worker_count without reading the module."
}

output "postgres" {
  value = {
    primary = {
      name         = module.prod_db_primary.name
      ipv4         = module.prod_db_primary.ipv4_host
      port         = module.prod_db_primary.port
      vm_id        = module.prod_db_primary.vm_id
      wal_g_bucket = module.prod_db_primary.wal_g_bucket
      connection   = module.prod_db_primary.connection_string_without_credentials
    }
    standby = var.postgres_standby_enabled ? {
      name  = module.prod_db_standby[0].name
      ipv4  = module.prod_db_standby[0].ipv4_host
      vm_id = module.prod_db_standby[0].vm_id
    } : null
    standby_enabled = var.postgres_standby_enabled
  }
  description = <<-EOT
    Tenant database. `standby_enabled` is false in the pilot, which means recovery is
    from the WAL archive rather than from a replica: RPO ≤ 5 min, RTO 1 h, per
    README.md. Enabling the standby is a node-3 decision, not a preference.
  EOT
}

output "keycloak" {
  value = {
    name       = module.prod_sso.name
    ipv4       = module.prod_sso.ipv4_host
    port       = module.prod_sso.port
    vm_id      = module.prod_sso.vm_id
    issuer_url = module.prod_sso.issuer_url
  }
  description = "Identity provider. The issuer URL is the contract with every client in viavitae-api and viavitae-web."
}

output "monitoring" {
  value = {
    name           = module.prod_monitoring.name
    ipv4           = module.prod_monitoring.ipv4_host
    s3_endpoint    = module.prod_monitoring.s3_endpoint
    loki_bucket    = module.prod_monitoring.loki_bucket
    metrics_bucket = module.prod_monitoring.metrics_bucket
    status_page    = module.prod_monitoring.uptime_kuma_hostname
  }
  description = "Object store and external prober. The monitoring stack itself runs in the cluster."
}

output "load_balancers" {
  value = {
    for key, lb in module.prod_lb : lb.name => {
      ipv4_mgmt = lb.ipv4_host
      vm_id     = lb.vm_id
      node      = lb.node_name
    }
  }
  description = "Load-balancer VMs. The dmz address is not in this output because it is not needed by anything outside the pair and keepalived."
}

output "public_vip" {
  value       = var.public_vip
  description = "Public virtual IP. Reconciled against the firewall configuration by tools/preflight.sh, because Terraform cannot see the firewall and the two must agree."
}

output "public_hostname" {
  value       = var.public_hostname
  description = "Public name every tenant CNAME points at. Changing it is one record instead of one per tenant, which is why tenants point here rather than at the VIP."
}

output "runners" {
  value = {
    for key, runner in module.prod_runner : runner.name => {
      ipv4  = runner.ipv4_host
      vm_id = runner.vm_id
      node  = runner.node_name
    }
  }
  description = "CI runner VMs, on the mgmt VLAN with allow-listed egress per ADR-008."
}

output "bitrix24" {
  value = local.bitrix24_enabled ? {
    name      = module.prod_bitrix24[0].name
    ipv4      = module.prod_bitrix24[0].ipv4_host
    vm_id     = module.prod_bitrix24[0].vm_id
    hostname  = module.prod_bitrix24[0].public_hostname
    egress    = module.prod_bitrix24[0].egress_allow_list
    approvals = module.prod_bitrix24[0].approvals
  } : null
  description = "Bitrix24, or null when disabled. The `approvals` object is the auditable record required by INFRA-001 condition C5."
}

output "tenants" {
  value = {
    for slug, tenant in module.tenant : slug => {
      schema            = tenant.schema_name
      role              = tenant.role_name
      namespace         = tenant.namespace
      hostname          = tenant.hostname
      wildcard_covered  = tenant.hostname_is_wildcard_covered
      quotas            = tenant.quotas
      plan              = tenant.plan
      state             = tenant.lifecycle_state
      can_login         = tenant.can_login
      credential_status = tenant.credential_status
    }
  }
  description = <<-EOT
    Provisioned tenants. The `clients` ApplicationSet must produce a namespace,
    ResourceQuota and LimitRange matching these values, and the tenant-quota alert
    fires on them. `credential_status` is always the same string and exists so that
    nobody has to infer the absence of a password from a missing attribute.
  EOT
}

output "tenant_count" {
  value       = length(var.tenants)
  description = "Number of production tenants. This is the input to every break-even number in docs/capacity-plan.md and to tools/cost-estimate.py."
}

output "committed_memory_mb" {
  value = (
    sum([for node in module.prod_cp : node.memory_dedicated_mb]) +
    sum([for node in module.prod_worker : node.memory_dedicated_mb]) +
    module.prod_db_primary.memory_dedicated_mb +
    (var.postgres_standby_enabled ? module.prod_db_standby[0].memory_dedicated_mb : 0) +
    module.prod_sso.memory_dedicated_mb +
    module.prod_monitoring.memory_dedicated_mb +
    sum([for lb in module.prod_lb : lb.memory_dedicated_mb]) +
    sum([for runner in module.prod_runner : runner.memory_dedicated_mb]) +
    (local.bitrix24_enabled ? module.prod_bitrix24[0].memory_dedicated_mb + module.prod_bitrix24_db[0].memory_dedicated_mb : 0)
  )
  description = <<-EOT
    Total memory this environment commits, in MiB. Against a 384 GiB cluster guest
    budget (two nodes) this is the number that decides whether the next tenant fits,
    and against 192 GiB (one node) it decides what survives an N-1 event. Printed on
    every plan so that a capacity problem is visible in the change that causes it
    rather than in the incident that follows.
  EOT
}

output "committed_vcpu" {
  value = (
    sum([for node in module.prod_cp : node.cpu_cores]) +
    sum([for node in module.prod_worker : node.cpu_cores]) +
    module.prod_db_primary.cpu_cores +
    (var.postgres_standby_enabled ? module.prod_db_standby[0].cpu_cores : 0) +
    module.prod_sso.cpu_cores +
    module.prod_monitoring.cpu_cores +
    sum([for lb in module.prod_lb : lb.cpu_cores]) +
    sum([for runner in module.prod_runner : runner.cpu_cores]) +
    (local.bitrix24_enabled ? module.prod_bitrix24[0].cpu_cores + module.prod_bitrix24_db[0].cpu_cores : 0)
  )
  description = "Total vCPU committed, against a 240 vCPU overcommitted budget."
}

output "k3s_version" {
  value       = var.k3s_version
  description = "The pinned release the cluster runs. A single value, in the plan a reviewer approves."
}
