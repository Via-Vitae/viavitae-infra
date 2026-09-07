# modules/proxmox-vm — the single path to a Proxmox guest.
#
# Clone a cloud-init template, give it a static address and an SSH key, size it,
# tag it, and register it with HA. Nothing else. OS configuration, service
# installation, hardening and patching are Ansible's job; in-cluster workloads
# are Argo CD's job. This module deliberately does not install software, because a
# module that both creates the machine and configures it cannot be re-run without
# either re-creating the machine or silently skipping the configuration.

locals {
  # `protected` is a machine-readable marker, not a comment. Ansible's `common`
  # role sets Proxmox's own protection bit (`qm set --protection 1`) on VMs
  # carrying it, which makes removal and migration fail at the hypervisor too.
  # Two layers, because a Terraform-only guard does nothing to an operator who
  # deletes a VM from the Proxmox UI.
  all_tags = distinct(concat(var.tags, var.protect_deletion ? ["protected"] : []))

  efi_required = var.bios == "ovmf"

  # The primary disk's Proxmox device name, used for the boot order. Index 0 is
  # the boot disk by convention; a module that guessed this would put a data disk
  # first and produce a VM that boots to a UEFI shell with no error.
  boot_device = "${var.disks[0].interface}0"

  # The primary interface first, then any additional ones. Order matters for
  # netplan: the interface carrying the default route must be present, and the
  # validation on var.additional_networks is what guarantees only one does.
  networks = concat(
    [{
      interface    = var.primary_interface
      ipv4_address = var.ipv4_address
      ipv4_gateway = var.ipv4_gateway
      mtu          = 1500
    }],
    [for n in var.additional_networks : {
      interface    = n.interface
      ipv4_address = n.ipv4_address
      ipv4_gateway = n.ipv4_gateway
      mtu          = 1500
    }],
  )

  # The declared key set, written to the guest as a record rather than as
  # configuration. cloud-init already installs these keys into
  # ~${ssh_username}/.ssh/authorized_keys; this file is the *assertion* Ansible
  # checks the live one against.
  #
  # The distinction matters operationally. A key added by hand during a
  # break-glass session is invisible to Terraform, survives every apply, and is
  # exactly the persistence an attacker would choose. With the record on disk,
  # `ansible/roles/common` fails on a live key set that does not equal the
  # declared one — in both directions, so a revoked key that is still installed
  # is caught as well as one that was never declared.
  #
  # Public keys are not credentials. They are already in the cloud-init snippet
  # and in Terraform state by virtue of being installed at all, so writing them
  # again discloses nothing new.
  extra_files_effective = merge(var.extra_files, {
    "/etc/viavitae/ssh-authorized-keys" = join("\n", var.ssh_public_keys)
  })

  user_data = templatefile("${path.module}/cloud-init/user-data.yaml.tftpl", {
    hostname        = var.name
    ssh_username    = var.ssh_username
    ssh_public_keys = var.ssh_public_keys
    dns_domain      = var.dns_domain
    dns_servers     = var.dns_servers
    environment     = var.pool_id
    managed_by      = "terraform:modules/proxmox-vm"
    extra_files     = local.extra_files_effective
  })

  network_config = templatefile("${path.module}/cloud-init/network-config.yaml.tftpl", {
    networks    = local.networks
    dns_domain  = var.dns_domain
    dns_servers = var.dns_servers
  })
}

# --- cloud-init snippets -----------------------------------------------------
#
# Uploaded to a `snippets`-enabled datastore rather than passed inline, because
# the provider takes cloud-init user-data as a file identifier. This path uses the
# provider's SSH transport, which is why `PM_SSH_*` is an apply-time credential
# and is absent from every plan job.

resource "proxmox_virtual_environment_file" "user_data" {
  node_name    = var.node_name
  datastore_id = var.snippets_datastore_id
  content_type = "snippets"
  overwrite    = true

  source_raw {
    data      = local.user_data
    file_name = "${var.name}-${var.vm_id}-user-data.yaml"
  }
}

resource "proxmox_virtual_environment_file" "network_config" {
  node_name    = var.node_name
  datastore_id = var.snippets_datastore_id
  content_type = "snippets"
  overwrite    = true

  source_raw {
    data      = local.network_config
    file_name = "${var.name}-${var.vm_id}-network-config.yaml"
  }
}

# --- the guest ---------------------------------------------------------------

resource "proxmox_virtual_environment_vm" "this" {
  node_name   = var.node_name
  vm_id       = var.vm_id
  name        = var.name
  description = var.description
  pool_id     = var.pool_id

  tags    = local.all_tags
  started = var.started
  on_boot = var.on_boot

  bios = var.bios

  agent {
    enabled = true
    trim    = true
    type    = "virtio"
  }

  cpu {
    cores   = var.cpu_cores
    sockets = var.cpu_sockets
    type    = var.cpu_type
    numa    = var.cpu_numa
  }

  memory {
    dedicated = var.memory_dedicated_mb
    # `floating` equal to `dedicated` enables the balloon device. Left at 0
    # otherwise, which disables it: ballooning lets the hypervisor take back
    # memory the guest believes it owns, and the guest's OOM killer then picks
    # the victim. On a database host that victim is the database.
    floating = var.memory_ballooning ? var.memory_dedicated_mb : 0
  }

  operating_system {
    type = "l26"
  }

  # A serial console is the only way in when the network configuration this module
  # just wrote is wrong, which is the failure mode cloud-init networking has.
  serial_device {
    device = "socket"
  }

  dynamic "efi_disk" {
    for_each = local.efi_required ? [1] : []
    content {
      datastore_id      = var.efi_disk_datastore_id
      pre_enrolled_keys = false
    }
  }

  clone {
    vm_id        = var.template_vm_id
    node_name    = var.template_node_name == "" ? null : var.template_node_name
    datastore_id = var.disks[0].datastore_id
    retries      = var.clone_retries
  }

  boot_order = [local.boot_device, "net0"]

  dynamic "disk" {
    for_each = var.disks
    content {
      interface    = disk.value.interface
      size         = disk.value.size_gb
      datastore_id = disk.value.datastore_id
      iothread     = disk.value.iothread
      ssd          = disk.value.ssd
      discard      = disk.value.discard
      backup       = disk.value.backup
      replicate    = disk.value.replicate
      cache        = disk.value.cache
    }
  }

  network_device {
    bridge   = var.bridge
    model    = "virtio"
    vlan_id  = var.vlan_id
    firewall = false
    mtu      = 1500
  }

  initialization {
    datastore_id = var.cloud_init_datastore_id
    interface    = var.cloud_init_interface

    # No package upgrade on first boot. Ansible owns patching inside a gated
    # maintenance window, and a first boot that runs `apt upgrade` is a first boot
    # whose duration and outcome are not reproducible.
    upgrade = false

    user_data_file_id    = proxmox_virtual_environment_file.user_data.id
    network_data_file_id = proxmox_virtual_environment_file.network_config.id
  }

  lifecycle {
    # Cloud-init reads its snippets once, on first boot. After that the file
    # identifier is history, and letting the provider track it means a one-line
    # change to user-data.yaml replaces the VM. Ignoring the block is the correct
    # semantics, not a workaround: to re-run cloud-init you rebuild the guest,
    # and that is a deliberate act rather than a side effect of a comment edit.
    ignore_changes = [initialization]

    precondition {
      condition     = var.vm_id >= var.vmid_block.start && var.vm_id <= var.vmid_block.end
      error_message = <<-EOT
        VMID ${var.vm_id} is outside this environment's allocated block
        ${var.vmid_block.start}-${var.vmid_block.end}. VMIDs are cluster-global,
        so an out-of-block identifier will collide with another environment's
        guest. Take the next free identifier inside the block, or widen the block
        in the global root module.
      EOT
    }

    precondition {
      condition     = local.efi_required ? var.efi_disk_datastore_id != "" : true
      error_message = "bios = \"ovmf\" requires efi_disk_datastore_id. Without an EFI variable disk the VM powers on and shows nothing, with no error in the Proxmox task log."
    }

    precondition {
      condition     = var.protect_deletion ? var.memory_ballooning == false : true
      error_message = "memory_ballooning must be false for a VM marked protect_deletion. Those are the database, identity and backup hosts, and ballooning on them converts memory pressure into an OOM kill of the process holding the data."
    }

    precondition {
      condition     = var.protect_deletion ? var.ha_group != null : true
      error_message = "A VM marked protect_deletion must have an ha_group. Protection without HA management means the VM stays down after a node failure until someone notices, which is the opposite of what the protection flag asserts."
    }

    precondition {
      condition     = var.on_boot == true || var.ha_group == null
      error_message = "on_boot = false together with an ha_group is contradictory: HA will start the VM, the host boot will not, and the resulting state depends on which happened last. Choose one."
    }
  }
}

# --- HA membership -----------------------------------------------------------
#
# Registered only when an HA group is given. HA on a two-node cluster requires the
# qdevice described in docs/network-topology.md; without it there is no quorum and
# nothing here will relocate.
#
# The RPO consequence is stated in ADR-002 and is not a module concern: an
# HA-relocated guest boots from the ZFS **replica**, which is asynchronous and up
# to 15 minutes behind. HA gives availability, not durability.

resource "proxmox_haresource" "this" {
  count = var.ha_group != null ? 1 : 0

  resource_id  = "vm:${var.vm_id}"
  group        = var.ha_group
  state        = var.started ? "started" : "stopped"
  max_restart  = var.ha_max_restart
  max_relocate = var.ha_max_relocate
  comment      = "${var.name} (${var.pool_id})"
}
