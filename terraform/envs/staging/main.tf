# The `staging` environment: one control plane, one worker, one database, one
# identity provider, and any tenants being rehearsed.
#
# Staging has no Bitrix24 (ADR-007 gates it to prod behind two approvals, and a
# staging copy of a closed-source workload with an outbound flow rehearsed nothing),
# no second database node (a standby in staging would rehearse replication, which is
# a PostgreSQL feature and not a ViaVitae risk), and no load balancer pair (HAProxy
# is shared infrastructure in the prod state).

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
  global     = data.terraform_remote_state.global.outputs
  vmid_block = local.global.vmid_blocks[var.environment_name]
  pool_id    = local.global.pool_ids[var.environment_name]
  ha_group   = "viavitae-staging-ha"

  # Control planes are spread across the declared nodes in order. With one control
  # plane this is simply the first node; the expression is written generally so that
  # raising control_plane_count does not require rewriting the placement.
  control_plane_nodes = [
    for index in range(var.control_plane_count) :
    var.node_names[index % length(var.node_names)]
  ]

  # Worker placement deliberately avoids the control-plane node when there is a
  # choice. Co-locating them means one node failure removes both the cluster's
  # control path and its only capacity.
  worker_nodes = [
    for index in range(var.worker_count) :
    var.node_names[(index + var.control_plane_count) % length(var.node_names)]
  ]

  prefix_length = split("/", var.subnet_prefix)[1]

  # Addresses are derived from the subnet and a documented offset rather than listed
  # per VM, so that raising worker_count allocates the next address instead of
  # leaving a gap someone has to reason about. The offsets themselves come from the
  # allocation table in docs/network-topology.md and are inputs, not guesses.
  control_plane_addresses = [
    for index in range(var.control_plane_count) :
    "${cidrhost(var.subnet_prefix, var.control_plane_address_offset + index)}/${local.prefix_length}"
  ]

  worker_addresses = [
    for index in range(var.worker_count) :
    "${cidrhost(var.subnet_prefix, var.worker_address_offset + index)}/${local.prefix_length}"
  ]
}

resource "proxmox_hagroup" "staging" {
  group   = local.ha_group
  nodes   = var.ha_group_nodes
  comment = "Staging. Lower HA priority than prod by design: an N-1 event evicts staging first, per docs/capacity-plan.md."

  restricted  = true
  no_failback = false
}

# --- control plane -----------------------------------------------------------

module "stg_cp" {
  source = "../../modules/k3s-node"
  for_each = {
    for index in range(var.control_plane_count) : index => index
  }

  name = "stg-cp-${each.key}"
  role = "control_plane"

  k3s_version         = var.k3s_version
  control_plane_count = var.control_plane_count
  control_plane_nodes = local.control_plane_nodes
  api_vip_address     = var.api_vip_address

  node_name             = local.control_plane_nodes[each.key]
  vm_id                 = var.vmids.control_plane_base + each.key
  vmid_block            = local.vmid_block
  pool_id               = local.pool_id
  ha_group              = proxmox_hagroup.staging.group
  datastore_id          = var.datastore_id
  snippets_datastore_id = var.snippets_datastore_id
  template_vm_id        = var.template_vm_id
  template_node_name    = var.template_node_name

  vlan_id         = var.vlan_id
  ipv4_address    = local.control_plane_addresses[each.key]
  ipv4_gateway    = var.ipv4_gateway
  dns_domain      = var.dns_domain
  dns_servers     = var.dns_servers
  ssh_public_keys = var.ssh_public_keys

  environment_name = "staging"

  depends_on = [terraform_data.staging_invariants]
}

# --- workers -----------------------------------------------------------------

module "stg_worker" {
  source = "../../modules/k3s-node"
  for_each = {
    for index in range(var.worker_count) : index => index
  }

  name = "stg-worker-${each.key}"
  role = "worker"

  k3s_version         = var.k3s_version
  control_plane_count = var.control_plane_count
  control_plane_nodes = local.control_plane_nodes

  node_name             = local.worker_nodes[each.key]
  vm_id                 = var.vmids.worker_base + each.key
  vmid_block            = local.vmid_block
  pool_id               = local.pool_id
  ha_group              = proxmox_hagroup.staging.group
  datastore_id          = var.datastore_id
  snippets_datastore_id = var.snippets_datastore_id
  template_vm_id        = var.template_vm_id
  template_node_name    = var.template_node_name

  cpu_cores           = 4
  memory_dedicated_mb = 16384
  disk_size_gb        = 100

  vlan_id         = var.vlan_id
  ipv4_address    = local.worker_addresses[each.key]
  ipv4_gateway    = var.ipv4_gateway
  dns_domain      = var.dns_domain
  dns_servers     = var.dns_servers
  ssh_public_keys = var.ssh_public_keys

  environment_name = "staging"

  depends_on = [terraform_data.staging_invariants]
}

# --- PostgreSQL --------------------------------------------------------------

module "stg_db" {
  source = "../../modules/postgres-vm"

  name             = "stg-db-0"
  instance_purpose = "tenants"
  is_primary       = true
  wal_g_bucket     = var.wal_g_bucket

  node_name             = var.node_names[0]
  vm_id                 = var.vmids.postgres_primary
  vmid_block            = local.vmid_block
  pool_id               = local.pool_id
  ha_group              = proxmox_hagroup.staging.group
  datastore_id          = var.datastore_id
  snippets_datastore_id = var.snippets_datastore_id
  template_vm_id        = var.template_vm_id
  template_node_name    = var.template_node_name

  # Half of prod's database sizing. Staging holds synthetic data, and 32 GiB of
  # committed RAM to hold fixtures is the most expensive fixture storage available.
  cpu_cores           = 2
  memory_dedicated_mb = 8192
  data_disk_size_gb   = 100
  wal_disk_size_gb    = 20

  vlan_id         = var.vlan_id
  ipv4_address    = var.postgres_address
  ipv4_gateway    = var.ipv4_gateway
  dns_domain      = var.dns_domain
  dns_servers     = var.dns_servers
  ssh_public_keys = var.ssh_public_keys

  environment_name = "staging"

  depends_on = [terraform_data.staging_invariants]
}

# --- Keycloak ----------------------------------------------------------------

module "stg_sso" {
  source = "../../modules/keycloak-vm"

  name            = "stg-sso-0"
  public_hostname = "sso.staging.viavitae.com"
  database_host   = cidrhost(var.postgres_address, 0)

  node_name             = var.node_names[0]
  vm_id                 = var.vmids.keycloak
  vmid_block            = local.vmid_block
  pool_id               = local.pool_id
  ha_group              = proxmox_hagroup.staging.group
  datastore_id          = var.datastore_id
  snippets_datastore_id = var.snippets_datastore_id
  template_vm_id        = var.template_vm_id
  template_node_name    = var.template_node_name

  cpu_cores           = 2
  memory_dedicated_mb = 4096
  disk_size_gb        = 40

  vlan_id         = var.vlan_id
  ipv4_address    = var.keycloak_address
  ipv4_gateway    = var.ipv4_gateway
  dns_domain      = var.dns_domain
  dns_servers     = var.dns_servers
  ssh_public_keys = var.ssh_public_keys

  environment_name = "staging"

  depends_on = [terraform_data.staging_invariants]
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
  dns_target = var.dns_target

  environment_name          = "staging"
  dpia_infra_001_signed_off = var.dpia_infra_001_signed_off
}

# --- invariants --------------------------------------------------------------

resource "terraform_data" "staging_invariants" {
  input = {
    block = local.vmid_block
    vmids = var.vmids
    nodes = var.node_names
  }

  lifecycle {
    # Every VMID this environment will allocate, checked against the block before
    # anything is created. Checking each VM individually produces four separate
    # errors for one mistake; checking the highest one produces a plan that says
    # what is actually wrong.
    precondition {
      condition = max(
        var.vmids.control_plane_base + var.control_plane_count - 1,
        var.vmids.worker_base + var.worker_count - 1,
        var.vmids.postgres_primary,
        var.vmids.keycloak,
      ) <= local.vmid_block.end
      error_message = "A VMID exceeds this environment's allocated block, which ends at ${local.vmid_block.end}. Widen the block in the global root module; do not allocate outside it."
    }

    precondition {
      condition = min(
        var.vmids.control_plane_base,
        var.vmids.worker_base,
        var.vmids.postgres_primary,
        var.vmids.keycloak,
      ) >= local.vmid_block.start
      error_message = "A VMID is below this environment's allocated block, which starts at ${local.vmid_block.start}."
    }

    # Ranges must not collide with each other. `worker_base` sits above the control
    # planes with room for growth, and the database and identity provider sit above
    # both, so that raising worker_count consumes free identifiers instead of
    # somebody else's.
    precondition {
      condition = (
        var.vmids.control_plane_base + var.control_plane_count <= var.vmids.worker_base &&
        var.vmids.worker_base + var.worker_count <= var.vmids.postgres_primary &&
        var.vmids.postgres_primary < var.vmids.keycloak
      )
      error_message = "VMID ranges overlap: control planes must fit below worker_base, workers below postgres_primary, and postgres_primary below keycloak."
    }

    precondition {
      condition     = length(var.node_names) >= var.control_plane_count
      error_message = "control_plane_count is ${var.control_plane_count} but only ${length(var.node_names)} nodes are declared. See the ADR-002 quorum rule enforced in modules/k3s-node."
    }

    # Staging must never point at the production zone. A test run that creates a
    # record in the production zone is a production incident caused by a rehearsal.
    precondition {
      condition     = var.dns_zone != "viavitae.com."
      error_message = "dns_zone must not be the production zone. Staging uses a delegated subdomain or its own zone."
    }

    precondition {
      condition     = var.vlan_id == 30
      error_message = "staging is VLAN 30 by definition; docs/network-topology.md allocates no other segment to it."
    }

    # Derived addresses must stay inside the subnet and must not run into the
    # database or Keycloak. Offsets are inputs, so a plausible-looking value can
    # still be wrong, and an address collision between two VMs presents as
    # intermittent ARP flapping rather than as an error.
    precondition {
      condition = (
        var.control_plane_address_offset + var.control_plane_count <= var.worker_address_offset &&
        var.worker_address_offset + var.worker_count <= tonumber(element(split(".", cidrhost(var.postgres_address, 0)), 3))
      )
      error_message = "Address offsets collide: control planes run from ${var.control_plane_address_offset}, workers from ${var.worker_address_offset}, and the database is at ${var.postgres_address}."
    }
  }
}
