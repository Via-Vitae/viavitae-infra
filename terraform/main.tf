# Cluster-wide allocation policy.
#
# This is the `global` root module. It owns exactly two things:
#
#   1. Proxmox resource pools, one per environment, so the UI shows ownership and
#      so a `pool_id` cannot be invented locally by an environment.
#   2. The VMID allocation table, as outputs that every environment root module
#      consumes through `terraform_remote_state`, plus the validation that makes
#      two environments claim the same identifier impossible.
#
# It creates no VMs. A module that creates both the allocation policy and the
# things allocated from it cannot detect a conflict, because the conflict is only
# visible when the two are planned together.

locals {
  # Every allocated block, including the shared block, as start/end pairs.
  all_blocks_raw = concat(
    [for name, env in var.environments : {
      name  = "environment ${name}"
      start = env.vmid_range_start
      end   = env.vmid_range_end
    }],
    [{
      name  = "shared"
      start = var.shared_vmid_range_start
      end   = var.shared_vmid_range_end
    }],
  )

  # `sort` only accepts a list of strings, so the blocks are serialised with
  # zero-padded start and end values, sorted, and parsed back. Padding matters:
  # lexicographically "1000" sorts before "900", which would silently reorder the
  # blocks and make the adjacency test below compare the wrong pairs.
  all_blocks = [
    for entry in sort([
      for block in local.all_blocks_raw :
      format("%07d:%07d:%s", block.start, block.end, block.name)
      ]) : {
      start = tonumber(split(":", entry)[0])
      end   = tonumber(split(":", entry)[1])
      name  = split(":", entry)[2]
    }
  ]

  # Adjacent pairs after sorting by start. Two blocks overlap when the second
  # starts at or before the first ends.
  overlaps = [
    for i in range(length(local.all_blocks) - 1) :
    "${local.all_blocks[i].name} [${local.all_blocks[i].start}-${local.all_blocks[i].end}] overlaps ${local.all_blocks[i + 1].name} [${local.all_blocks[i + 1].start}-${local.all_blocks[i + 1].end}]"
    if local.all_blocks[i + 1].start <= local.all_blocks[i].end
  ]

  # The restore sub-block must sit inside the shared block: restore scratch VMs
  # are shared infrastructure and must not be able to consume an environment ID.
  restore_inside_shared = (
    var.restore_vmid_range_start >= var.shared_vmid_range_start &&
    var.restore_vmid_range_end <= var.shared_vmid_range_end &&
    var.restore_vmid_range_start < var.restore_vmid_range_end
  )
}

resource "proxmox_virtual_environment_pool" "environment" {
  for_each = var.environments

  pool_id = each.value.pool_id
  comment = each.value.pool_comment

  lifecycle {
    precondition {
      condition     = length(local.overlaps) == 0
      error_message = <<-EOT
        VMID blocks overlap: ${join("; ", local.overlaps)}.
        Proxmox VMIDs are cluster-global. Two environments holding the same
        identifier will silently destroy each other's guests, and backups become
        ambiguous because a vzdump archive is named by VMID. Blocks are
        append-only: widen one, never move one.
      EOT
    }

    precondition {
      condition     = local.restore_inside_shared
      error_message = "The restore scratch block (${var.restore_vmid_range_start}-${var.restore_vmid_range_end}) must be a sub-block of the shared block (${var.shared_vmid_range_start}-${var.shared_vmid_range_end})."
    }

    # A pool is referenced by every VM in an environment. Renaming or recreating
    # it orphans those VMs from the UI grouping and breaks the environment's
    # remote-state lookup, so it requires an explicit `terraform state mv` and a
    # pull request that says why. `prevent_destroy` is deliberately not set: the
    # `dev` environment's pool is meant to be destroyable, and a lifecycle flag
    # that has to be edited before a legitimate destroy is a flag that gets
    # edited out and forgotten.
  }
}

# `check` blocks are evaluated on every plan, including plans that do not touch
# the pools above. This is what catches an allocation conflict introduced by a
# change to variables alone, before anything is created.
check "vmid_allocation_is_consistent" {
  assert {
    condition     = length(local.overlaps) == 0
    error_message = "VMID blocks overlap: ${join("; ", local.overlaps)}"
  }

  assert {
    condition     = local.restore_inside_shared
    error_message = "The restore scratch block must be inside the shared block."
  }

  assert {
    condition = alltrue([
      for name in var.node_names : can(regex("^[a-z][a-z0-9-]{0,30}$", name))
    ])
    error_message = "Node names must be lowercase DNS-compatible labels; Proxmox uses them as cluster identity and as part of every API path."
  }
}
