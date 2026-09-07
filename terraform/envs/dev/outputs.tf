# Outputs for the `dev` environment.
#
# Consumed by tools/preflight.sh, by the Ansible inventory generator and by whoever
# is trying to reach a dev cluster that has just been rebuilt.

output "environment_name" {
  value       = var.environment_name
  description = "Always `dev`."
}

output "node_name" {
  value       = module.dev_k3s_0.name
  description = "Hostname of the single node, which is also the Kubernetes node name."
}

output "node_fqdn" {
  value       = module.dev_k3s_0.fqdn
  description = "Fully qualified node name."
}

output "node_ipv4" {
  value       = module.dev_k3s_0.ipv4_host
  description = "Node address. `kubectl` access is via port-forward from a workstation on the mgmt VLAN; there is no route to VLAN 50 from anywhere else (rule X12)."
}

output "vm_id" {
  value       = module.dev_k3s_0.vm_id
  description = "VMID."
}

output "k3s_version" {
  value       = module.dev_k3s_0.k3s_version
  description = "Pinned k3s release. One minor version behind staging by design."
}

output "ha_group" {
  value       = proxmox_hagroup.dev.group
  description = "HA group, lowest priority in the cluster and restricted to the declared nodes."
}

output "pool_id" {
  value       = local.pool_id
  description = "Proxmox resource pool, from the global allocation."
}

output "vmid_block" {
  value       = local.vmid_block
  description = "Allocated VMID block for this environment."
}

output "kubeconfig_note" {
  value       = "ssh viavitae@${module.dev_k3s_0.ipv4_host} 'sudo cat /etc/rancher/k3s/k3s.yaml' — the admin kubeconfig is on the node and is never copied into Terraform state, CI logs or a pull request."
  description = "How to reach the cluster. Written as an output so that the answer is one command away rather than one search away."
}

output "disposal_note" {
  value       = "Destroying this environment is expected and safe. It holds no personal data, no tenant data and nothing that is not reproducible from Git within 20 minutes."
  description = "The one output that exists to stop someone hesitating at 02:00."
}
