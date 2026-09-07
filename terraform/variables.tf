# Inputs for the `global` root module: cluster-wide allocation policy.
#
# Nothing in this module creates a workload. It creates the resource pools that
# environments attach to, and it is the single place where VMID blocks are
# assigned, so that two environments cannot claim the same identifier even when
# their states are applied concurrently by different people.

variable "environments" {
  type = map(object({
    # Inclusive VMID block for this environment. Blocks must not overlap and must
    # not touch the shared block. Enforced by validation, not by review.
    vmid_range_start = number
    vmid_range_end   = number

    # Proxmox resource pool identifier, e.g. "viavitae-prod".
    pool_id = string

    # Human-readable comment shown in the Proxmox UI.
    pool_comment = string

    # Environments marked disposable are allowed to be destroyed by automation
    # without a plan review. Only `dev` may set this to true.
    disposable = bool
  }))

  description = <<-EOT
    Per-environment VMID allocation and resource pool. The VMID block is the
    primary key of the allocation policy: it is append-only, a block is never
    reissued to a different environment, and an individual VMID inside a block is
    never reused after destruction (docs/network-topology.md, "Addressing and
    VMID allocation").
  EOT

  validation {
    condition = alltrue([
      for name, env in var.environments :
      env.vmid_range_start >= 100 && env.vmid_range_end <= 999999 &&
      env.vmid_range_start < env.vmid_range_end &&
      # Every block needs room for at least one node, one worker and one database.
      (env.vmid_range_end - env.vmid_range_start) >= 10
    ])
    error_message = "Each environment needs a VMID block of at least 10 identifiers, within Proxmox's 100-999999 range, with start < end."
  }

  validation {
    condition = alltrue([
      for name, env in var.environments :
      can(regex("^viavitae-[a-z][a-z0-9-]{1,30}$", env.pool_id))
    ])
    error_message = "pool_id must match ^viavitae-[a-z][a-z0-9-]{1,30}$ so pools are recognisable in the Proxmox UI and cannot collide with manually created pools."
  }

  validation {
    condition = alltrue([
      for name, env in var.environments : env.disposable == true ? name == "dev" : true
    ])
    error_message = "Only the `dev` environment may be marked disposable. A disposable flag on staging or prod would let automation destroy it without a reviewed plan."
  }
}

variable "shared_vmid_range_start" {
  type        = number
  default     = 900
  description = "Start of the VMID block reserved for shared infrastructure (load balancers, monitoring, identity, databases, CI runners, quorum device)."
}

variable "shared_vmid_range_end" {
  type        = number
  default     = 999
  description = "End of the shared VMID block, inclusive."
}

variable "restore_vmid_range_start" {
  type        = number
  default     = 950
  description = "Start of the sub-block reserved for restore scratch VMs. Reserving it stops a restore from consuming an allocation that an environment later wants."
}

variable "restore_vmid_range_end" {
  type        = number
  default     = 959
  description = "End of the restore scratch sub-block, inclusive."
}

variable "node_names" {
  type        = list(string)
  description = "Proxmox cluster node names, in the order used for scheduling. Read from the cluster by the operator and committed; a node that is not in this list cannot host anything Terraform manages."

  validation {
    condition     = length(var.node_names) > 0 && length(distinct(var.node_names)) == length(var.node_names)
    error_message = "node_names must be non-empty and free of duplicates."
  }
}

# There is deliberately no `resource_pool_default` variable. An implicit default
# pool is where unowned VMs accumulate, and an unowned VM is a VM nobody patches,
# nobody backs up and nobody can explain. Every VM belongs to an environment pool
# created above; a VM that belongs nowhere should not exist.
