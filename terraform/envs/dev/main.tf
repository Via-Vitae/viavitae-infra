# The `dev` environment: one disposable k3s node, nothing else.
#
# What lives here and what does not:
#
#   * One VM, VMID 1000, VLAN 50, which is control plane and worker at once.
#   * PostgreSQL runs in-cluster as a StatefulSet. This is the deliberate exception
#     to ADR-003's external-database rule: a dev database is test fixtures, and a
#     2 vCPU / 8 GiB VM to hold fixtures nobody cares about is 8 GiB the estate does
#     not have. The data is disposable, so losing it with the node is the intended
#     behaviour rather than a failure.
#   * No Keycloak. Developers authenticate against the staging identity provider.
#     A second identity store is a second place for accounts to drift, and a dev
#     Keycloak holding copies of staff accounts is personal data with no purpose.
#   * No monitoring VM. The node ships metrics and logs to the shared monitoring
#     stack on the prod VLAN through rule X8, so that disposing of dev is visible.
#   * No load balancer. `kubectl port-forward`, and the ingress controller's
#     NodePort if a developer needs a real hostname.

data "terraform_remote_state" "global" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "global/terraform.tfstate"
    region = var.state_region
    # Terraform >= 1.6 takes a map of endpoints rather than a single `endpoint`
    # argument; the singular form is deprecated and prints a warning on every plan.
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
  global = data.terraform_remote_state.global.outputs

  # The allocation contract. Nothing in this file hard-codes a VMID range or a pool
  # name: both come from the global root module, which is the only place that can
  # see every environment's block at once and therefore the only place that can
  # detect a collision.
  vmid_block = local.global.vmid_blocks[var.environment_name]
  pool_id    = local.global.pool_ids[var.environment_name]
  ha_group   = "viavitae-${var.environment_name}-ha"

  # Cheapest scheduling: pick the node the operator listed first. `dev` is not
  # worth a placement algorithm, and a deterministic choice makes a plan readable.
  node_name = var.node_names[0]
}

resource "proxmox_hagroup" "dev" {
  group = local.ha_group

  # Lowest priority in the cluster. In an N-1 situation Proxmox attempts to start
  # dev last and fails for want of memory, which is the correct outcome and is what
  # docs/capacity-plan.md §N-1 says should happen.
  nodes = var.ha_group_nodes

  comment = "Disposable dev environment. Lowest HA priority by design; see docs/capacity-plan.md."

  # Restricted: dev may only run on the nodes listed above. An unrestricted group
  # would let Proxmox place a disposable workload on a node reserved for production,
  # which is how a dev cluster ends up competing with tenant databases for ARC.
  restricted  = true
  no_failback = false
}

module "dev_k3s_0" {
  source = "../../modules/k3s-node"

  name = "dev-k3s-0"
  role = "control_plane"

  k3s_version         = var.k3s_version
  control_plane_count = var.control_plane_count
  control_plane_nodes = [local.node_name]

  node_name             = local.node_name
  vm_id                 = var.node_vmid
  vmid_block            = local.vmid_block
  pool_id               = local.pool_id
  ha_group              = proxmox_hagroup.dev.group
  datastore_id          = var.datastore_id
  snippets_datastore_id = var.snippets_datastore_id
  template_vm_id        = var.template_vm_id
  template_node_name    = var.template_node_name

  cpu_cores           = var.cpu_cores
  memory_dedicated_mb = var.memory_dedicated_mb
  disk_size_gb        = var.disk_size_gb

  vlan_id         = var.vlan_id
  ipv4_address    = var.node_ipv4_address
  ipv4_gateway    = var.ipv4_gateway
  dns_domain      = var.dns_domain
  dns_servers     = var.dns_servers
  ssh_public_keys = var.ssh_public_keys

  environment_name = var.environment_name
  started          = var.started

  depends_on = [terraform_data.dev_invariants]
}

resource "terraform_data" "dev_invariants" {
  input = {
    block  = local.vmid_block
    vmid   = var.node_vmid
    vlan   = var.vlan_id
    subnet = var.subnet_prefix
  }

  lifecycle {
    precondition {
      condition     = var.node_vmid >= local.vmid_block.start && var.node_vmid <= local.vmid_block.end
      error_message = "node_vmid ${var.node_vmid} is outside the dev block ${local.vmid_block.start}-${local.vmid_block.end} allocated by the global root module."
    }

    # VLAN 50 and its subnet are a pair. A node tagged 50 with a 10.10.30.0/24
    # address has no gateway and no route, and the failure looks like a broken
    # template rather than a mismatched pair.
    precondition {
      condition     = var.vlan_id == 50 ? can(regex("^10\\.10\\.50\\.[0-9]{1,3}/24$", var.node_ipv4_address)) : false
      error_message = "dev must be on VLAN 50 with an address inside ${var.subnet_prefix}. A disposable workload shares no segment with staging or prod."
    }

    precondition {
      condition     = contains(var.node_names, local.node_name)
      error_message = "The scheduling target must be one of the declared nodes."
    }
  }
}
