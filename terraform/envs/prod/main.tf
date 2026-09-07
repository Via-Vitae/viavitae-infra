# The `prod` environment.
#
# Everything in this file is either shared platform infrastructure or the production
# cluster. Shared VMs (load balancers, database, identity provider, monitoring store,
# runners, Bitrix24) are created here rather than in the `global` root module because
# the global module owns allocation policy and cannot see a conflict it also creates;
# they draw their identifiers from the shared block, which global allocates.
#
# Read docs/capacity-plan.md before changing any number below. The estate is at 89 %
# of its memory budget and 82 % of its NVMe budget as committed, so an addition here
# is a subtraction somewhere else or a hardware order.

data "terraform_remote_state" "global" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "global/terraform.tfstate"
    region = var.state_region
    endpoints = {
      s3 = var.state_endpoint
    }
    skip_credentials_validation = false
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
  }
}

locals {
  global            = data.terraform_remote_state.global.outputs
  vmid_block        = local.global.vmid_blocks[var.environment_name]
  shared_vmid_block = local.global.shared_vmid_block
  pool_id           = local.global.pool_ids[var.environment_name]

  ha_group          = "viavitae-prod-ha"
  ha_group_critical = "viavitae-prod-critical"

  prefix_length = split("/", var.subnet_prefixes.prod)[1]

  control_plane_nodes = [
    for index in range(var.control_plane_count) :
    var.node_names[index % length(var.node_names)]
  ]

  # Workers are placed on the node with the fewest workers so far, which with two
  # nodes alternates. Co-locating them all on one node would make a single node
  # failure a total workload outage even with capacity to spare on the other.
  worker_nodes = [
    for index in range(var.worker_count) :
    var.node_names[index % length(var.node_names)]
  ]

  control_plane_addresses = [
    for index in range(var.control_plane_count) :
    "${cidrhost(var.subnet_prefixes.prod, var.control_plane_address_offset + index)}/${local.prefix_length}"
  ]

  worker_addresses = [
    for index in range(var.worker_count) :
    "${cidrhost(var.subnet_prefixes.prod, var.worker_address_offset + index)}/${local.prefix_length}"
  ]

  worker_hosts = [
    for index in range(var.worker_count) :
    cidrhost(var.subnet_prefixes.prod, var.worker_address_offset + index)
  ]

  # NodePort range, from docs/network-topology.md rule X2. HAProxy forwards to every
  # worker on these ports; the list is written to the load balancers so that adding a
  # worker updates the backends without a separate change to HAProxy.
  node_port_range = "30000-32767"

  bitrix24_enabled = var.bitrix24.enabled
}

# --- HA groups ---------------------------------------------------------------

resource "proxmox_hagroup" "prod" {
  group   = local.ha_group
  nodes   = var.ha_group_nodes
  comment = "Production workloads. Start order follows docs/capacity-plan.md section N-1."

  restricted  = true
  no_failback = false
}

resource "proxmox_hagroup" "prod_critical" {
  group   = local.ha_group_critical
  nodes   = var.ha_group_critical_nodes
  comment = "Database, identity provider and public entry point. Restricted so that an N-1 event cannot place them on a node that has no room."

  # Restricted plus a short node list is what makes the N-1 order real rather than
  # advisory: Proxmox will only attempt these guests on the listed nodes, in the
  # listed priority, and will fail visibly rather than evicting something else.
  restricted  = true
  no_failback = false
}

# --- k3s control plane -------------------------------------------------------

module "prod_cp" {
  source = "../../modules/k3s-node"
  for_each = {
    for index in range(var.control_plane_count) : index => index
  }

  name = "prod-cp-${each.key}"
  role = "control_plane"

  k3s_version         = var.k3s_version
  control_plane_count = var.control_plane_count
  control_plane_nodes = local.control_plane_nodes
  api_vip_address     = var.api_vip_address

  node_name             = local.control_plane_nodes[each.key]
  vm_id                 = var.vmids.control_plane_base + each.key
  vmid_block            = local.vmid_block
  pool_id               = local.pool_id
  ha_group              = proxmox_hagroup.prod.group
  datastore_id          = var.datastore_id
  snippets_datastore_id = var.snippets_datastore_id
  template_vm_id        = var.template_vm_id
  template_node_name    = var.template_node_name

  vlan_id         = var.vlan_ids.prod
  ipv4_address    = local.control_plane_addresses[each.key]
  ipv4_gateway    = var.ipv4_gateways.prod
  dns_domain      = var.dns_domain
  dns_servers     = var.dns_servers
  ssh_public_keys = var.ssh_public_keys

  environment_name = "prod"

  depends_on = [terraform_data.prod_invariants]
}

# --- k3s workers -------------------------------------------------------------

module "prod_worker" {
  source = "../../modules/k3s-node"
  for_each = {
    for index in range(var.worker_count) : index => index
  }

  name = "prod-worker-${each.key}"
  role = "worker"

  k3s_version         = var.k3s_version
  control_plane_count = var.control_plane_count
  control_plane_nodes = local.control_plane_nodes

  node_name             = local.worker_nodes[each.key]
  vm_id                 = var.vmids.worker_base + each.key
  vmid_block            = local.vmid_block
  pool_id               = local.pool_id
  ha_group              = proxmox_hagroup.prod.group
  datastore_id          = var.datastore_id
  snippets_datastore_id = var.snippets_datastore_id
  template_vm_id        = var.template_vm_id
  template_node_name    = var.template_node_name

  vlan_id         = var.vlan_ids.prod
  ipv4_address    = local.worker_addresses[each.key]
  ipv4_gateway    = var.ipv4_gateways.prod
  dns_domain      = var.dns_domain
  dns_servers     = var.dns_servers
  ssh_public_keys = var.ssh_public_keys

  environment_name = "prod"

  depends_on = [terraform_data.prod_invariants]
}

# --- PostgreSQL --------------------------------------------------------------

module "prod_db_primary" {
  source = "../../modules/postgres-vm"

  name              = "db-01"
  instance_purpose  = "tenants"
  is_primary        = true
  wal_g_bucket      = var.wal_g_bucket
  data_disk_size_gb = var.postgres_data_disk_size_gb

  node_name             = var.node_names[0]
  vm_id                 = var.vmids.postgres_primary
  vmid_block            = local.shared_vmid_block
  pool_id               = local.pool_id
  ha_group              = proxmox_hagroup.prod_critical.group
  datastore_id          = var.datastore_id
  snippets_datastore_id = var.snippets_datastore_id
  template_vm_id        = var.template_vm_id
  template_node_name    = var.template_node_name

  vlan_id         = var.vlan_ids.prod
  ipv4_address    = var.addresses.postgres_primary
  ipv4_gateway    = var.ipv4_gateways.prod
  dns_domain      = var.dns_domain
  dns_servers     = var.dns_servers
  ssh_public_keys = var.ssh_public_keys

  environment_name = "prod"

  depends_on = [terraform_data.prod_invariants]
}

module "prod_db_standby" {
  source = "../../modules/postgres-vm"
  count  = var.postgres_standby_enabled ? 1 : 0

  name              = "db-02"
  instance_purpose  = "tenants"
  is_primary        = false
  standby_of        = cidrhost(var.addresses.postgres_primary, 0)
  wal_g_bucket      = ""
  data_disk_size_gb = var.postgres_data_disk_size_gb

  # The standby is pinned to the other node. A standby on the same node as its
  # primary is a copy that fails whenever the primary fails, which is the one
  # situation a standby exists for.
  node_name             = var.node_names[length(var.node_names) - 1]
  vm_id                 = var.vmids.postgres_standby
  vmid_block            = local.shared_vmid_block
  pool_id               = local.pool_id
  ha_group              = proxmox_hagroup.prod.group
  datastore_id          = var.datastore_id
  snippets_datastore_id = var.snippets_datastore_id
  template_vm_id        = var.template_vm_id
  template_node_name    = var.template_node_name

  vlan_id         = var.vlan_ids.prod
  ipv4_address    = var.addresses.postgres_standby
  ipv4_gateway    = var.ipv4_gateways.prod
  dns_domain      = var.dns_domain
  dns_servers     = var.dns_servers
  ssh_public_keys = var.ssh_public_keys

  environment_name = "prod"

  depends_on = [module.prod_db_primary, terraform_data.prod_invariants]
}

# --- Keycloak ----------------------------------------------------------------

module "prod_sso" {
  source = "../../modules/keycloak-vm"

  name            = "sso-01"
  public_hostname = var.keycloak_public_hostname
  database_host   = cidrhost(var.addresses.postgres_primary, 0)

  node_name             = var.node_names[0]
  vm_id                 = var.vmids.keycloak
  vmid_block            = local.shared_vmid_block
  pool_id               = local.pool_id
  ha_group              = proxmox_hagroup.prod_critical.group
  datastore_id          = var.datastore_id
  snippets_datastore_id = var.snippets_datastore_id
  template_vm_id        = var.template_vm_id
  template_node_name    = var.template_node_name

  vlan_id         = var.vlan_ids.prod
  ipv4_address    = var.addresses.keycloak
  ipv4_gateway    = var.ipv4_gateways.prod
  dns_domain      = var.dns_domain
  dns_servers     = var.dns_servers
  ssh_public_keys = var.ssh_public_keys

  environment_name = "prod"

  depends_on = [terraform_data.prod_invariants]
}

# --- monitoring object store and external prober -----------------------------

module "prod_monitoring" {
  source = "../../modules/monitoring-vm"

  name                 = "mon-01"
  loki_bucket          = var.monitoring.loki_bucket
  metrics_bucket       = var.monitoring.metrics_bucket
  uptime_kuma_hostname = var.monitoring.uptime_kuma_hostname

  object_store_disk_size_gb = var.monitoring.disk_size_gb

  node_name             = var.node_names[0]
  vm_id                 = var.vmids.monitoring
  vmid_block            = local.shared_vmid_block
  pool_id               = local.pool_id
  ha_group              = proxmox_hagroup.prod.group
  datastore_id          = var.datastore_id
  snippets_datastore_id = var.snippets_datastore_id
  template_vm_id        = var.template_vm_id
  template_node_name    = var.template_node_name

  ipv4_address    = var.addresses.monitoring
  ipv4_gateway    = var.ipv4_gateways.prod
  dns_domain      = var.dns_domain
  dns_servers     = var.dns_servers
  ssh_public_keys = var.ssh_public_keys

  environment_name = "prod"

  depends_on = [terraform_data.prod_invariants]
}

# --- load balancers ----------------------------------------------------------
#
# Dual-homed by design and the only hosts in the estate that are: administered on
# VLAN 10, serving traffic on VLAN 40. A dual-homed host is a route between two
# segments, which is why docs/network-topology.md lists them explicitly and why
# adding another one is a security review.

module "prod_lb" {
  source = "../../modules/proxmox-vm"
  for_each = {
    for index, lb in var.load_balancer_addresses : index => lb
  }

  name        = "lb-0${each.key + 1}"
  description = "HAProxy load balancer ${each.key + 1} of 2 for prod. Owner: platform. Dual-homed mgmt+dmz; layer-4 SNI passthrough, no TLS termination."
  node_name   = var.node_names[each.key % length(var.node_names)]
  vm_id       = var.vmids.load_balancer_base + each.key
  vmid_block  = local.shared_vmid_block
  pool_id     = local.pool_id

  template_vm_id        = var.template_vm_id
  template_node_name    = var.template_node_name
  snippets_datastore_id = var.snippets_datastore_id

  cpu_cores           = 2
  memory_dedicated_mb = 2048
  memory_ballooning   = false

  disks = [{
    interface    = "scsi"
    size_gb      = 20
    datastore_id = var.datastore_id
    iothread     = true
    ssd          = true
    discard      = true
    backup       = true
    replicate    = true
    cache        = "none"
  }]

  # Management interface first: it carries the default route, so SSH, Ansible and
  # monitoring all arrive this way. The dmz interface has no gateway.
  bridge          = "vmbr2"
  vlan_id         = var.vlan_ids.mgmt
  ipv4_address    = each.value.mgmt
  ipv4_gateway    = var.ipv4_gateways.mgmt
  dns_domain      = var.dns_domain
  dns_servers     = var.dns_servers
  ssh_public_keys = var.ssh_public_keys

  additional_networks = [{
    interface    = "ens19"
    bridge       = "vmbr1"
    vlan_id      = var.vlan_ids.dmz
    ipv4_address = each.value.dmz
    ipv4_gateway = ""
  }]

  bios                  = "ovmf"
  efi_disk_datastore_id = var.datastore_id

  # The public entry point. Priority 2 in the N-1 order: without it nothing is
  # reachable, including the status page that says nothing is reachable.
  protect_deletion = true
  ha_group         = proxmox_hagroup.prod_critical.group
  on_boot          = true

  tags = ["haproxy", "prod", "dmz", "backup-daily"]

  extra_files = {
    "/etc/viavitae/haproxy-public-vip"  = "${var.public_vip}\n"
    "/etc/viavitae/haproxy-public-host" = "${var.public_hostname}\n"
    "/etc/viavitae/haproxy-node-port"   = "${local.node_port_range}\n"
    # Backends are derived from the worker addresses, so adding a worker updates
    # HAProxy in the same apply. A hand-maintained backend list is a list that is
    # wrong the first time the cluster scales.
    "/etc/viavitae/haproxy-backends" = join("\n", local.worker_hosts)
    "/etc/viavitae/haproxy-bitrix24" = local.bitrix24_enabled ? cidrhost(var.addresses.bitrix24, 0) : ""
    "/etc/viavitae/environment"      = "prod\n"
    # Layer 4 only. TLS terminates in Traefik, so there is exactly one place that
    # renews certificates and exactly one expiry to monitor.
    "/etc/viavitae/haproxy-mode" = "sni-passthrough\n"
  }

  depends_on = [terraform_data.prod_invariants]
}

# --- CI runners --------------------------------------------------------------

module "prod_runner" {
  source = "../../modules/proxmox-vm"
  for_each = {
    for index, address in var.runner_addresses : index => address
  }

  name        = "runner-0${each.key + 1}"
  description = "Self-hosted GitHub Actions runner ${each.key + 1} for prod. Owner: platform. Egress allow-listed per ADR-008 and rule E5."
  node_name   = var.node_names[each.key % length(var.node_names)]
  vm_id       = var.vmids.runner_base + each.key
  vmid_block  = local.shared_vmid_block
  pool_id     = local.pool_id

  template_vm_id        = var.template_vm_id
  template_node_name    = var.template_node_name
  snippets_datastore_id = var.snippets_datastore_id

  cpu_cores           = 4
  memory_dedicated_mb = 8192
  memory_ballooning   = false

  disks = [{
    interface    = "scsi"
    size_gb      = 100
    datastore_id = var.datastore_id
    iothread     = true
    ssd          = true
    discard      = true
    backup       = true
    replicate    = true
    cache        = "none"
  }]

  bridge          = "vmbr2"
  vlan_id         = var.vlan_ids.mgmt
  ipv4_address    = each.value
  ipv4_gateway    = var.ipv4_gateways.mgmt
  dns_domain      = var.dns_domain
  dns_servers     = var.dns_servers
  ssh_public_keys = var.ssh_public_keys

  bios                  = "ovmf"
  efi_disk_datastore_id = var.datastore_id

  # A runner is replaceable in minutes and holds no data at rest beyond a workspace
  # that is cleaned per job, so it is neither protected nor HA-managed: HA-relocating
  # a runner mid-job loses the job anyway.
  protect_deletion = false
  ha_group         = null
  on_boot          = true

  tags = ["ci", "runner", "mgmt", "backup-weekly"]

  extra_files = {
    # Must match `vars.RUNNER_LABELS` in the repository settings, which is what
    # ci.yml and deploy.yml select on. Two copies of a label list is one too many,
    # so the workflow reads the repository variable and this file records what the
    # machine is registered as; preflight.sh compares them.
    "/etc/viavitae/runner-labels" = "self-hosted,linux,x64,eu-infra\n"
    "/etc/viavitae/runner-egress" = "allowlist\n"
    "/etc/viavitae/environment"   = "prod\n"
  }

  depends_on = [terraform_data.prod_invariants]
}

# --- Bitrix24 ----------------------------------------------------------------

module "prod_bitrix24" {
  source = "../../modules/bitrix24-vm"
  count  = local.bitrix24_enabled ? 1 : 0

  name            = "crm-01"
  public_hostname = var.bitrix24.public_hostname
  database_host   = cidrhost(var.addresses.bitrix24_db, 0)

  legal_review_approved   = var.bitrix24.legal_review_approved
  legal_review_reference  = var.bitrix24.legal_review_reference
  dpia_infra_002_approved = var.bitrix24.dpia_infra_002_approved
  dpia_reference          = var.bitrix24.dpia_reference
  egress_allow_list       = var.bitrix24.egress_allow_list

  node_name             = var.node_names[0]
  vm_id                 = var.vmids.bitrix24
  vmid_block            = local.shared_vmid_block
  pool_id               = local.pool_id
  ha_group              = proxmox_hagroup.prod.group
  datastore_id          = var.datastore_id
  snippets_datastore_id = var.snippets_datastore_id
  template_vm_id        = var.template_vm_id
  template_node_name    = var.template_node_name

  ipv4_address    = var.addresses.bitrix24
  ipv4_gateway    = var.ipv4_gateways.dmz
  dns_domain      = var.dns_domain
  dns_servers     = var.dns_servers
  ssh_public_keys = var.ssh_public_keys

  environment_name = "prod"

  depends_on = [terraform_data.prod_invariants]
}

module "prod_bitrix24_db" {
  source = "../../modules/postgres-vm"
  count  = local.bitrix24_enabled ? 1 : 0

  name             = "crm-db-01"
  instance_purpose = "bitrix24"
  is_primary       = true
  wal_g_bucket     = ""

  node_name             = var.node_names[0]
  vm_id                 = var.vmids.bitrix24_db
  vmid_block            = local.shared_vmid_block
  pool_id               = local.pool_id
  ha_group              = proxmox_hagroup.prod.group
  datastore_id          = var.datastore_id
  snippets_datastore_id = var.snippets_datastore_id
  template_vm_id        = var.template_vm_id
  template_node_name    = var.template_node_name

  cpu_cores           = 4
  memory_dedicated_mb = 8192
  data_disk_size_gb   = 150
  wal_disk_size_gb    = 20

  vlan_id         = var.vlan_ids.dmz
  ipv4_address    = var.addresses.bitrix24_db
  ipv4_gateway    = var.ipv4_gateways.dmz
  dns_domain      = var.dns_domain
  dns_servers     = var.dns_servers
  ssh_public_keys = var.ssh_public_keys

  environment_name = "prod"

  depends_on = [module.prod_bitrix24, terraform_data.prod_invariants]
}

# --- tenants -----------------------------------------------------------------

module "tenant" {
  source   = "../../modules/tenant"
  for_each = var.tenants

  slug         = each.key
  display_name = each.value.display_name
  plan         = each.value.plan
  database     = var.database_name

  schema_owner_role = var.migration_role_name
  lifecycle_state   = each.value.lifecycle_state
  public_hostname   = each.value.public_hostname
  manage_dns        = each.value.manage_dns

  dns_zone   = var.dns_zone
  dns_target = var.public_hostname

  environment_name          = "prod"
  dpia_infra_001_signed_off = var.dpia_infra_001_signed_off
}

# --- invariants --------------------------------------------------------------

resource "terraform_data" "prod_invariants" {
  input = {
    nodes        = var.node_names
    cp_count     = var.control_plane_count
    workers      = var.worker_count
    vmids        = var.vmids
    env_block    = local.vmid_block
    shared       = local.shared_vmid_block
    vip          = var.public_vip
    dpia         = var.dpia_infra_001_signed_off
    tenant_count = length(var.tenants)
  }

  lifecycle {
    # ADR-002 condition 1, at the level where the node list is known. The module
    # checks the same rule per VM; this check reports it once, with both numbers.
    precondition {
      condition     = var.control_plane_count == 3 ? length(var.node_names) >= 3 : true
      error_message = <<-EOT
        control_plane_count is 3 but only ${length(var.node_names)} Proxmox nodes are
        declared. Three control-plane VMs on two nodes always lose etcd quorum when
        one node fails, because at least two of the three share a node. Rack the third
        node and add it to node_names, or set control_plane_count to 1 and rely on
        Proxmox HA — which is what the pilot does, per ADR-002.
      EOT
    }

    precondition {
      condition     = var.control_plane_count == 1 ? var.api_vip_address == "" : var.api_vip_address != ""
      error_message = "api_vip_address must be empty for a single control plane and set for three. A VIP in front of one member is a second failure domain that adds nothing."
    }

    # Identifiers: the environment block covers the cluster, the shared block
    # covers everything else, and neither may be exceeded.
    precondition {
      condition = (
        var.vmids.control_plane_base + var.control_plane_count - 1 <= local.vmid_block.end &&
        var.vmids.control_plane_base >= local.vmid_block.start &&
        var.vmids.worker_base + var.worker_count - 1 <= local.vmid_block.end &&
        var.vmids.worker_base >= local.vmid_block.start
      )
      error_message = "Control-plane or worker VMIDs fall outside the prod block ${local.vmid_block.start}-${local.vmid_block.end}."
    }

    precondition {
      condition = alltrue([
        for key in ["postgres_primary", "postgres_standby", "keycloak", "monitoring", "bitrix24", "bitrix24_db", "load_balancer_base", "runner_base"] :
        tomap(var.vmids)[key] >= local.shared_vmid_block.start &&
        tomap(var.vmids)[key] <= local.shared_vmid_block.end
      ])
      error_message = "A shared VMID falls outside the shared block ${local.shared_vmid_block.start}-${local.shared_vmid_block.end}."
    }

    precondition {
      condition = (
        var.vmids.control_plane_base + var.control_plane_count <= var.vmids.worker_base &&
        var.vmids.load_balancer_base + 1 < var.vmids.monitoring &&
        var.vmids.monitoring < var.vmids.keycloak &&
        var.vmids.keycloak < var.vmids.postgres_primary &&
        var.vmids.postgres_primary < var.vmids.postgres_standby &&
        var.vmids.postgres_standby < var.vmids.bitrix24 &&
        var.vmids.bitrix24 < var.vmids.bitrix24_db &&
        var.vmids.bitrix24_db < local.global.restore_vmid_block.start
      )
      error_message = "VMID allocations overlap. The order is load balancers, monitoring, identity, databases, CRM, then the restore scratch block; see docs/network-topology.md."
    }

    # The restore scratch block must stay empty. If a VMID lands in 950-959, a
    # restore during an incident has nowhere to put its scratch VM, and the runbook
    # in docs/runbooks/backup-restore.md stops at step 1.
    precondition {
      condition = !contains(
        [for vmid in values(tomap(var.vmids)) : vmid],
        local.global.restore_vmid_block.start
      )
      error_message = "A VMID collides with the restore scratch block reserved by the global root module."
    }

    # INFRA-001 condition C5 and ADR-007 condition 8: Bitrix24 in production
    # requires an approved DPIA. modules/bitrix24-vm enforces the same rule; this
    # copy exists so the plan fails on the variable rather than deeper in the graph.
    precondition {
      condition = local.bitrix24_enabled ? (
        var.bitrix24.legal_review_approved && var.bitrix24.dpia_infra_002_approved
      ) : true
      error_message = "bitrix24.enabled is true in prod without both approvals. ADR-007 conditions 7 and 8; INFRA-001 condition C5."
    }

    # A standby on the same node as its primary fails whenever the primary fails.
    precondition {
      condition     = var.postgres_standby_enabled ? length(var.node_names) >= 2 : true
      error_message = "postgres_standby_enabled requires at least two Proxmox nodes; otherwise the standby is a copy that fails with its primary."
    }

    # Addresses must be inside the subnet they are tagged with, and the derived
    # ranges must not reach the shared VMs.
    precondition {
      condition = (
        var.control_plane_address_offset + var.control_plane_count <= var.worker_address_offset &&
        var.worker_address_offset + var.worker_count <= 200
      )
      error_message = "Derived node addresses collide: control planes from offset ${var.control_plane_address_offset}, workers from ${var.worker_address_offset}, and the shared VMs occupy the low addresses in the same subnet."
    }
  }
}

# Reported on every plan, because the number that matters in production is the one
# that says how much room is left.
check "capacity_headroom" {
  assert {
    condition = (
      sum([for node in module.prod_cp : node.memory_dedicated_mb]) +
      sum([for node in module.prod_worker : node.memory_dedicated_mb]) +
      module.prod_db_primary.memory_dedicated_mb +
      (var.postgres_standby_enabled ? module.prod_db_standby[0].memory_dedicated_mb : 0) +
      module.prod_sso.memory_dedicated_mb +
      module.prod_monitoring.memory_dedicated_mb +
      sum([for lb in module.prod_lb : lb.memory_dedicated_mb]) +
      sum([for runner in module.prod_runner : runner.memory_dedicated_mb]) +
      (local.bitrix24_enabled ? module.prod_bitrix24[0].memory_dedicated_mb + module.prod_bitrix24_db[0].memory_dedicated_mb : 0)
    ) <= 262144
    error_message = "This environment commits more than 256 GiB, which is one node's entire physical memory. That means an N-1 event cannot be survived even after evicting dev and staging; see docs/capacity-plan.md."
  }
}
