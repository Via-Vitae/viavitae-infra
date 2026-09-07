# Inputs for modules/proxmox-vm.
#
# Every VM in every environment is created through this module. The reason is not
# tidiness: it is that the invariants that matter — VMID inside its allocated
# block, no password in cloud-init, no balloon device on a database, tagged VLAN,
# EFI disk present exactly when EFI firmware is selected — are enforced here once
# instead of being remembered per call site.

variable "name" {
  type        = string
  description = "VM name, used as the hostname. Must be a valid DNS label because Proxmox writes it into the guest and cloud-init uses it as the hostname."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,62}$", var.name))
    error_message = "name must be a lowercase DNS label of 2-63 characters (^[a-z][a-z0-9-]{1,62}$)."
  }
}

variable "description" {
  type        = string
  description = "Shown in the Proxmox UI. Write what the VM is for and who owns it; an unnamed VM in a cluster of 27 becomes an unowned VM within a year."
}

variable "node_name" {
  type        = string
  description = "Proxmox node that will host this VM. Must be one of the cluster's node names."
}

variable "vm_id" {
  type        = number
  description = "Explicit VMID from this environment's allocated block. Never let Proxmox assign one: an unallocated VMID is invisible to the allocation policy and will eventually collide."
}

variable "vmid_block" {
  type = object({
    start = number
    end   = number
  })
  description = "The allocated VMID block for this environment, read from the global root module's `vmid_blocks` output."
}

variable "pool_id" {
  type        = string
  description = "Proxmox resource pool, from the global root module's `pool_ids` output."
}

variable "template_vm_id" {
  type        = number
  description = "VMID of the cloud-init template to clone. One template per Debian release per environment; the template itself is built by Ansible and is documented in ansible/roles/common/README.md."
}

variable "template_node_name" {
  type        = string
  default     = ""
  description = "Node holding the template. Leave empty to let the provider locate it; set it when templates are not replicated to every node, which is the normal case."
}

variable "clone_retries" {
  type        = number
  default     = 3
  description = "Clone retry count. Cloning a VM on a busy ZFS pool exceeds the default API timeout often enough that a retry is cheaper than a failed apply."
}

variable "cpu_cores" {
  type        = number
  default     = 2
  description = "vCPU cores. Overcommit is 2:1 cluster-wide per docs/capacity-plan.md; a single VM may exceed its host's core count, which is how the plan's headroom calculation stays honest."

  validation {
    condition     = var.cpu_cores >= 1 && var.cpu_cores <= 128
    error_message = "cpu_cores must be between 1 and 128."
  }
}

variable "cpu_sockets" {
  type        = number
  default     = 1
  description = "vCPU sockets. Keep at 1 unless the guest licence is socket-based, which for this estate it never is."
}

variable "cpu_type" {
  type        = string
  default     = "host"
  description = "Emulated CPU model. `host` passes through the physical CPU and is required for live migration between identical hardware; `x86-64-v4` is the portable choice if nodes ever differ."
}

variable "cpu_numa" {
  type        = bool
  default     = false
  description = "Enable NUMA topology. Only useful with cpu affinity pinning, which nothing here uses."
}

variable "memory_dedicated_mb" {
  type        = number
  description = "Committed memory in MiB. Memory is never overcommitted (1:1) per docs/capacity-plan.md, so this number is a real reservation against the 384 GB guest budget."

  validation {
    condition     = var.memory_dedicated_mb >= 512 && var.memory_dedicated_mb <= 262144
    error_message = "memory_dedicated_mb must be between 512 MiB and 256 GiB."
  }
}

variable "memory_ballooning" {
  type        = bool
  default     = false
  description = <<-EOT
    Enable the balloon device. Off by default and it should stay off for
    PostgreSQL, Keycloak and the k3s control plane: the balloon lets the
    hypervisor reclaim memory the guest believes it owns, and the guest kernel's
    OOM killer then chooses the victim. On a database host that victim is
    PostgreSQL. Enable it only for genuinely idle, stateless guests.
  EOT
}

variable "disks" {
  type = list(object({
    interface    = string
    size_gb      = number
    datastore_id = string
    iothread     = bool
    ssd          = bool
    discard      = bool
    backup       = bool
    replicate    = bool
    cache        = string
  }))
  description = <<-EOT
    Attached disks. `backup = false` on a scratch disk keeps it out of vzdump
    archives; `replicate = false` keeps it out of the ZFS replication job, which
    is what a disposable cache disk wants and what a database data disk never
    wants.
  EOT

  validation {
    condition     = length(var.disks) >= 1
    error_message = "At least one disk is required."
  }

  validation {
    condition = alltrue([
      for d in var.disks : contains(["scsi", "virtio", "sata", "ide", "nvme"], d.interface)
    ])
    error_message = "disk.interface must be one of scsi, virtio, sata, ide, nvme."
  }

  validation {
    condition = alltrue([
      for d in var.disks : contains(["none", "directsync", "writethrough", "writeback", "unsafe"], d.cache)
    ])
    error_message = "disk.cache must be one of none, directsync, writethrough, writeback, unsafe. `writeback` on a ZFS zvol is a data-loss setting; `none` is correct for zvols because the pool already caches."
  }

  validation {
    condition = alltrue([
      for d in var.disks : d.size_gb >= 4 && d.size_gb <= 65536
    ])
    error_message = "disk.size_gb must be between 4 GiB and 64 TiB."
  }
}

variable "bridge" {
  type        = string
  default     = "vmbr1"
  description = "VLAN-aware guest bridge. vmbr1 carries every tagged VLAN and has no untagged membership, so a guest that fails to tag gets no connectivity at all."
}

variable "vlan_id" {
  type        = number
  description = "VLAN tag for the guest's primary interface. Required — there is no native VLAN on vmbr1."

  validation {
    condition     = contains([10, 20, 30, 40, 50], var.vlan_id)
    error_message = "vlan_id must be one of the allocated VLANs: 10 mgmt, 20 prod, 30 staging, 40 dmz, 50 dev. An untagged interface (VLAN 1 or absent) is prohibited by docs/network-topology.md."
  }
}

variable "primary_interface" {
  type        = string
  default     = "ens18"
  description = "Guest interface name for the primary NIC. Determined by predictable-NIC naming on the virtio bus, not chosen freely: it must match what the guest will actually call the device, or netplan fails the boot."

  validation {
    condition     = can(regex("^ens[0-9]+$", var.primary_interface))
    error_message = "primary_interface must look like ens18."
  }
}

variable "ipv4_address" {
  type        = string
  description = "Static IPv4 address in CIDR notation, e.g. 10.10.20.30/24, from the allocation table in docs/network-topology.md."

  validation {
    condition     = can(cidrhost(var.ipv4_address, 0))
    error_message = "ipv4_address must be a CIDR address, e.g. 10.10.20.30/24."
  }
}

variable "ipv4_gateway" {
  type        = string
  description = "IPv4 gateway for the VLAN, from docs/network-topology.md."
}

variable "dns_domain" {
  type        = string
  default     = "viavitae.internal"
  description = "DNS search domain written into the guest."
}

variable "dns_servers" {
  type        = list(string)
  description = "Recursive resolvers, reachable from the guest's VLAN. Two minimum: one resolver is a single point of failure for every name lookup on the machine."

  validation {
    condition     = length(var.dns_servers) >= 2
    error_message = "At least two DNS servers are required."
  }
}

variable "ssh_username" {
  type        = string
  default     = "viavitae"
  description = "Administrative user created by cloud-init. Never `root` and never `debian`: a known default username is half of a credential-stuffing attack."
}

variable "ssh_public_keys" {
  type        = list(string)
  description = <<-EOT
    SSH **public** keys only. This module has no way to set a password and that
    is deliberate: a password passed to cloud-init lands in Terraform state in
    plaintext, in the plan file, and in the Proxmox VM configuration. Public keys
    are not secrets, so committing them is safe and auditing them is possible.
  EOT

  validation {
    condition     = length(var.ssh_public_keys) >= 1
    error_message = "At least one SSH public key is required; a VM with no key and no password is unreachable except through the Proxmox console."
  }

  validation {
    condition = alltrue([
      for k in var.ssh_public_keys : can(regex("^(ssh-(rsa|ed25519)|ecdsa-sha2-nistp(256|384|521)) ", k))
    ])
    error_message = "Each entry must be an OpenSSH public key line (ssh-rsa, ssh-ed25519 or ecdsa-sha2-nistp*). A private key here would be committed to state."
  }
}

variable "snippets_datastore_id" {
  type        = string
  description = "Datastore with the `snippets` content type enabled, on the target node. Cloud-init user-data and network-config are uploaded there. Enabling snippets is a manual Proxmox step (Datacenter > Storage > Content) and is a prerequisite recorded in the environment README."
}

variable "cloud_init_datastore_id" {
  type        = string
  default     = "local-zfs"
  description = "Datastore for the cloud-init drive itself."
}

variable "cloud_init_interface" {
  type        = string
  default     = "ide2"
  description = "Hardware interface for the cloud-init drive. Must match what the template expects; a mismatch produces a VM that boots and silently ignores every cloud-init setting."
}

variable "started" {
  type        = bool
  default     = true
  description = "Whether the VM should be running. Set to false to create a machine without booting it, which is how a control-plane node is prepared before Ansible has a k3s token to give it."
}

variable "on_boot" {
  type        = bool
  default     = true
  description = "Start with the host. Must be false for anything in the N-1 priority list in docs/capacity-plan.md that should not compete for RAM during an unattended host reboot."
}

variable "tags" {
  type        = list(string)
  default     = []
  description = "Proxmox tags. Used by the backup role to select what vzdump covers, so a VM with no `backup-daily` or `backup-weekly` tag is not backed up."

  validation {
    condition = alltrue([
      for t in var.tags : can(regex("^[a-z0-9][a-z0-9._-]{0,62}$", t)) && !contains(["terraform"], t)
    ])
    error_message = "Tags must be lowercase alphanumeric with . _ - and must not be the bare word `terraform`: the provider adds that tag itself and a duplicate breaks tag-based backup selection."
  }
}

variable "bios" {
  type        = string
  default     = "ovmf"
  description = "Firmware. `ovmf` (UEFI) for anything cloned from a UEFI template; `seabios` for legacy. Getting this wrong produces an unbootable VM with no error message."

  validation {
    condition     = contains(["ovmf", "seabios"], var.bios)
    error_message = "bios must be ovmf or seabios."
  }
}

variable "efi_disk_datastore_id" {
  type        = string
  default     = ""
  description = "Datastore for the EFI variable disk. Required when bios is ovmf; the precondition below fails the plan rather than producing an unbootable VM."
}

variable "ha_group" {
  type        = string
  default     = null
  description = <<-EOT
    Proxmox HA group to register this VM with. Null disables HA management
    entirely, which is correct for `dev` and for restore scratch VMs, and wrong
    for anything in the N-1 priority list. The group is created by the environment
    root module; this module only registers membership.
  EOT
}

variable "ha_max_restart" {
  type        = number
  default     = 3
  description = "Restart attempts before HA gives up. A service that crash-loops three times is not going to succeed on the fourth, and continuing to restart it hides the real fault behind a green HA status."
}

variable "ha_max_relocate" {
  type        = number
  default     = 2
  description = "Relocation attempts. With two nodes, 2 means one move and one retry; more than that just moves the same problem back and forth."
}

variable "extra_files" {
  type        = map(string)
  default     = {}
  description = <<-EOT
    Additional files cloud-init writes on first boot, as path => content. This is
    how a role-specific fact declared in Terraform reaches the guest without
    Terraform installing anything: `k3s-node` writes the pinned k3s version here
    and Ansible reads it back, so the version is declared in exactly one place and
    installed by exactly one tool.

    Restricted to /etc/viavitae/ on purpose. cloud-init write_files runs as root
    and can write anywhere on the guest, so an unrestricted map here would be a
    remote-write primitive available to anyone who can edit a tfvars file — which
    is a wider audience than anyone who can SSH to the node.
  EOT

  validation {
    condition = alltrue([
      for path, content in var.extra_files :
      can(regex("^/etc/viavitae/[a-z0-9][a-z0-9._-]{0,63}$", path))
    ])
    error_message = "extra_files keys must be absolute paths directly inside /etc/viavitae/, named with lowercase alphanumerics and . _ - only. Subdirectories, .. and any other location are rejected."
  }

  validation {
    condition = alltrue([
      for path, content in var.extra_files :
      !can(regex("(?i)(password|passwd|secret|token|api_?key|private key|BEGIN [A-Z ]*PRIVATE)", content))
    ])
    error_message = "extra_files must not contain credentials. Anything written here is uploaded as a Proxmox snippet, stored in Terraform state, and readable by anyone with node SSH or API access."
  }

  validation {
    # Reserved because the module writes it from var.ssh_public_keys. A caller that
    # set it would be silently overridden by the merge in main.tf, and a silently
    # ignored variable is one that gets trusted.
    condition     = !contains(keys(var.extra_files), "/etc/viavitae/ssh-authorized-keys")
    error_message = "/etc/viavitae/ssh-authorized-keys is written by this module from var.ssh_public_keys. Set the keys there instead."
  }
}

variable "additional_networks" {
  type = list(object({
    # Guest interface name, e.g. ens19. Must not equal the primary interface name.
    interface    = string
    bridge       = string
    vlan_id      = number
    ipv4_address = string
    # Must be empty. Only one interface may carry a default route: two of them make
    # the guest's routing table order-dependent, and the failure looks like
    # intermittent packet loss rather than a configuration error.
    ipv4_gateway = string
  }))
  default     = []
  description = <<-EOT
    Extra interfaces, for the one legitimate dual-homed role in this estate: the
    HAProxy load balancers, administered on `mgmt` and serving traffic on `dmz`.
    A dual-homed host is a route between two segments, so every entry is a
    firewall decision and not just a NIC — docs/network-topology.md records the
    hosts that may have one, and adding to that list needs a security review.
  EOT

  validation {
    condition = alltrue([
      for n in var.additional_networks :
      contains([10, 20, 30, 40, 50], n.vlan_id) &&
      n.ipv4_gateway == "" &&
      can(cidrhost(n.ipv4_address, 0)) &&
      can(regex("^ens[0-9]+$", n.interface))
    ])
    error_message = "Each additional network needs a valid CIDR address, an allocated VLAN, an ens<N> interface name and an empty ipv4_gateway. Only the primary interface may carry a default route."
  }
}

variable "protect_deletion" {
  type        = bool
  default     = false
  description = <<-EOT
    Set true for VMs whose loss is a data-loss event: PostgreSQL, Keycloak and
    the backup appliance. It makes `terraform destroy` fail loudly instead of
    quietly deleting a database because an environment block was commented out
    during a refactor.
  EOT
}
