# modules/k3s-node — a Kubernetes node as a Proxmox guest.
#
# Owns: the role, the pinned k3s version, the sizing defaults, the ADR-002 quorum
# invariant and the tag set that backup selection reads.
# Does not own: installing k3s, joining the cluster, or any in-guest configuration.
# That is ansible/playbooks/k3s-bootstrap.yml and k3s-nodes.yml.

locals {
  is_control_plane = var.role == "control_plane"

  # Role defaults. A control plane is small and latency-sensitive: etcd wants
  # consistent disk latency and very little else. A worker is large because it is
  # the thing that actually runs tenant workloads, and docs/capacity-plan.md sizes
  # the estate from worker RAM.
  cpu_cores           = coalesce(var.cpu_cores, local.is_control_plane ? 2 : 8)
  memory_dedicated_mb = coalesce(var.memory_dedicated_mb, local.is_control_plane ? 4096 : 32768)
  disk_size_gb        = coalesce(var.disk_size_gb, local.is_control_plane ? 60 : 100)

  tags = concat(
    ["k3s", var.environment_name, local.is_control_plane ? "control-plane" : "worker"],
    # Control-plane VMs hold etcd, which is the cluster's only irreplaceable
    # state. Workers hold no persistent tenant data — tenant state lives in
    # PostgreSQL, and pods use emptyDir or PVCs backed by the database — so a
    # worker is rebuilt rather than restored. Daily for etcd, weekly for workers
    # is what that difference is worth in backup window.
    [local.is_control_plane ? "backup-daily" : "backup-weekly"],
  )

  # Files the guest is born with, read by Ansible. Written rather than passed on a
  # command line so that a node rebuilt six months from now gets the same answer,
  # and so the answer is inspectable on the machine during an incident.
  provisioning_files = merge(
    {
      "/etc/viavitae/k3s-version" = "${var.k3s_version}\n"
      "/etc/viavitae/k3s-role"    = "${var.role}\n"
      "/etc/viavitae/environment" = "${var.environment_name}\n"
    },
    # Only meaningful for a multi-control-plane cluster, and kube-vip needs a
    # single agreed address across all members.
    local.is_control_plane && var.api_vip_address != "" ? {
      "/etc/viavitae/k3s-api-vip" = "${var.api_vip_address}\n"
    } : {},
  )
}

module "vm" {
  source = "../proxmox-vm"

  name        = var.name
  description = "k3s ${replace(var.role, "_", "-")} node for ${var.environment_name}. Owner: platform. Version: ${var.k3s_version}."
  node_name   = var.node_name
  vm_id       = var.vm_id
  vmid_block  = var.vmid_block
  pool_id     = var.pool_id

  template_vm_id        = var.template_vm_id
  template_node_name    = var.template_node_name
  snippets_datastore_id = var.snippets_datastore_id

  cpu_cores           = local.cpu_cores
  memory_dedicated_mb = local.memory_dedicated_mb

  # Ballooning off, always. A kubelet that has memory reclaimed under it evicts
  # pods, and an etcd member that is swapped out stops meeting its heartbeat
  # deadline and is removed from the cluster. Both look like an application fault
  # from inside the cluster.
  memory_ballooning = false

  disks = [{
    interface    = "scsi"
    size_gb      = local.disk_size_gb
    datastore_id = var.datastore_id
    iothread     = true
    ssd          = true
    # discard on: k3s image garbage collection deletes layers constantly, and a
    # zvol that never sees the deletion grows forever while reporting free space
    # that the guest believes it has.
    discard   = true
    backup    = true
    replicate = true
    # none: the ZFS pool already caches. writeback on a zvol is a data-loss
    # setting and writethrough costs throughput for no durability gain here.
    cache = "none"
  }]

  bridge          = "vmbr1"
  vlan_id         = var.vlan_id
  ipv4_address    = var.ipv4_address
  ipv4_gateway    = var.ipv4_gateway
  dns_domain      = var.dns_domain
  dns_servers     = var.dns_servers
  ssh_username    = "viavitae"
  ssh_public_keys = var.ssh_public_keys

  bios                  = "ovmf"
  efi_disk_datastore_id = var.datastore_id

  # Control-plane VMs are protected: destroying one destroys an etcd member, and
  # with a single control plane that destroys the cluster. Workers are not: they
  # are rebuilt in minutes from Git and Ansible, and a protection flag on them
  # would make a legitimate scale-down require an override.
  protect_deletion = local.is_control_plane

  ha_group = var.ha_group

  # Start with the host for control planes (they are the cluster) and for workers
  # (nothing runs without them). The N-1 order in docs/capacity-plan.md decides
  # what actually comes up when both cannot.
  on_boot = true
  started = var.started

  tags        = local.tags
  extra_files = local.provisioning_files

  depends_on = [terraform_data.quorum_guard]
}

# The ADR-002 quorum invariant, enforced mechanically.
#
# This lives in a resource rather than in the module call above because Terraform
# does not support `lifecycle` on a module block. `terraform_data` is a built-in
# resource with no provider dependency, so it costs nothing and evaluates before
# anything that depends on it — including the VM.
#
# Three control-plane VMs on two Proxmox nodes always loses etcd quorum when one
# node fails: by the pigeonhole principle at least two of the three share a node,
# so that node's failure removes two of three members, which is more than half.
# The cluster then cannot elect a leader, the API server stops accepting writes,
# and every workload on the surviving node becomes unmanageable — a worse outcome
# than one control plane, which at least restarts under Proxmox HA.
resource "terraform_data" "quorum_guard" {
  input = {
    control_plane_count = var.control_plane_count
    control_plane_nodes = var.control_plane_nodes
    role                = var.role
    node_name           = var.node_name
    api_vip_address     = var.api_vip_address
    ha_group            = var.ha_group
  }

  lifecycle {
    precondition {
      condition = var.control_plane_count == 3 ? (
        length(var.control_plane_nodes) == 3 &&
        length(distinct(var.control_plane_nodes)) == 3
      ) : true
      error_message = <<-EOT
        control_plane_count is 3 but the placement ${jsonencode(var.control_plane_nodes)}
        does not put each control plane on a distinct Proxmox node. With fewer than
        three distinct nodes, one node failure removes a majority of etcd members and
        the cluster loses quorum — see ADR-002 condition 1. Either rack the third
        node, or set control_plane_count to 1 and rely on Proxmox HA.
      EOT
    }

    precondition {
      condition     = local.is_control_plane ? contains(var.control_plane_nodes, var.node_name) : true
      error_message = "This control-plane VM is placed on ${var.node_name}, which is not in control_plane_nodes (${jsonencode(var.control_plane_nodes)}). The quorum check is meaningless unless the declared list matches reality."
    }

    precondition {
      condition     = length(var.control_plane_nodes) == var.control_plane_count
      error_message = "control_plane_nodes has ${length(var.control_plane_nodes)} entries but control_plane_count is ${var.control_plane_count}. They describe the same cluster and must agree."
    }

    precondition {
      condition     = var.control_plane_count > 1 ? var.api_vip_address != "" : true
      error_message = "A multi-control-plane cluster requires api_vip_address. Without it every kubeconfig and every worker points at one member, and losing that member loses the control path even though quorum survives."
    }

    precondition {
      condition     = local.is_control_plane ? var.ha_group != null : true
      error_message = "A control-plane VM must have an ha_group. In the two-node pilot there is exactly one control plane, and HA is the only mechanism that restarts it after a node failure."
    }
  }
}
