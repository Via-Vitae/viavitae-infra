# Outputs consumed by the environment root modules through
# `terraform_remote_state`. These are the allocation contract; an environment
# that hard-codes a VMID instead of reading it here has left the allocation
# policy, and the overlap precondition above can no longer see it.

output "pool_ids" {
  value       = { for name, pool in proxmox_virtual_environment_pool.environment : name => pool.pool_id }
  description = "Proxmox resource pool identifier per environment."
}

output "vmid_blocks" {
  value = {
    for name, env in var.environments : name => {
      start = env.vmid_range_start
      end   = env.vmid_range_end
    }
  }
  description = "Inclusive VMID block per environment. Append-only; a block is never reissued and an individual VMID is never reused."
}

output "shared_vmid_block" {
  value = {
    start = var.shared_vmid_range_start
    end   = var.shared_vmid_range_end
  }
  description = "VMID block for shared infrastructure: load balancers, monitoring, identity, databases, CI runners, quorum device."
}

output "restore_vmid_block" {
  value = {
    start = var.restore_vmid_range_start
    end   = var.restore_vmid_range_end
  }
  description = "Sub-block reserved for restore scratch VMs, used by docs/runbooks/backup-restore.md."
}

output "node_names" {
  value       = var.node_names
  description = "Cluster node names available for scheduling, in operator-specified order."
}

output "node_count" {
  value       = length(var.node_names)
  description = <<-EOT
    Number of Proxmox nodes. This is the input that decides whether a k3s control
    plane may be sized at 3: ADR-002 requires 3 distinct nodes before
    `control_plane_count = 3` is permitted, because 3 control-plane VMs on 2
    nodes always loses etcd quorum when one node fails (pigeonhole: at least two
    of the three share a node).
  EOT
}

output "allocation_policy_version" {
  value       = "1.0"
  description = "Version of the allocation policy. Bumped when the meaning of a block changes, so environments can refuse to plan against a policy they were not written for."
}
