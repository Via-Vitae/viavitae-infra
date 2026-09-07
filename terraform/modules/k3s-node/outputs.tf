output "vm_id" {
  value       = module.vm.vm_id
  description = "Allocated VMID."
}

output "name" {
  value       = module.vm.name
  description = "Node name, which is also the Kubernetes node name once the kubelet registers."
}

output "fqdn" {
  value       = module.vm.fqdn
  description = "Fully qualified name, used in the kubelet's serving certificate SAN."
}

output "ipv4_host" {
  value       = module.vm.ipv4_host
  description = "Node address. HAProxy forwards the NodePort range to these, and the Ansible inventory is generated from them."
}

output "role" {
  value       = var.role
  description = "control_plane or worker."
}

output "k3s_version" {
  value       = var.k3s_version
  description = <<-EOT
    The pinned release this node was born with, as written to
    /etc/viavitae/k3s-version. After an Ansible-driven upgrade the guest may run a
    newer version than this output claims until the next apply, which is exactly
    the drift the nightly `drift` job in deploy.yml reports.
  EOT
}

output "api_vip_address" {
  value       = var.api_vip_address
  description = "Kubernetes API virtual IP for multi-control-plane clusters; empty for a single control plane."
}

output "environment_name" {
  value       = var.environment_name
  description = "Environment label."
}

output "tags" {
  value       = module.vm.tags
  description = "Effective tags. `backup-daily` on control planes (etcd) and `backup-weekly` on workers, which is what the vzdump schedule selects on."
}

output "protected" {
  value       = module.vm.protected
  description = "True for control-plane VMs, false for workers."
}

output "memory_dedicated_mb" {
  value       = module.vm.memory_dedicated_mb
  description = "Committed memory, summed into the docs/capacity-plan.md budget."
}

output "cpu_cores" {
  value       = module.vm.cpu_cores
  description = "Allocated vCPU."
}

output "node_name" {
  value       = module.vm.node_name
  description = "Proxmox node currently hosting this VM. For control planes this is the input to the ADR-002 quorum check, so a change here is a capacity-plan event, not a routine one."
}
