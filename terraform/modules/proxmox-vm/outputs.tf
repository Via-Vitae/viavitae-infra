# Outputs for modules/proxmox-vm.
#
# These are consumed by the environment root modules and by the service modules
# that wrap this one. Note what is *not* here: no credential of any kind, because
# this module never receives one.

output "vm_id" {
  value       = proxmox_virtual_environment_vm.this.vm_id
  description = "Allocated VMID. Used to name vzdump archives, to address the guest in Ansible inventories and to identify HA resources."
}

output "name" {
  value       = proxmox_virtual_environment_vm.this.name
  description = "VM name, which is also the guest hostname."
}

output "fqdn" {
  value       = "${var.name}.${var.dns_domain}"
  description = "Fully qualified name written into the guest by cloud-init and used in TLS SANs."
}

output "node_name" {
  value       = proxmox_virtual_environment_vm.this.node_name
  description = "Node currently hosting the guest. Changes after an HA relocation, which is why it is an output and not an echo of the input."
}

output "ipv4_address" {
  value       = var.ipv4_address
  description = "Configured address in CIDR notation. This is the address the allocation table promised, not the address the guest reported."
}

output "ipv4_host" {
  value       = cidrhost(var.ipv4_address, 0)
  description = "Configured address without the prefix length, for use in Ansible inventory hostnames and firewall rules."
}

output "reported_ipv4_addresses" {
  value       = proxmox_virtual_environment_vm.this.ipv4_addresses
  description = <<-EOT
    Addresses reported by the QEMU guest agent, per interface. Empty until the
    agent starts and reports. When this disagrees with `ipv4_address`, the guest
    did not apply its cloud-init network configuration, and the disagreement is
    the diagnostic: it distinguishes "wrong config" from "no config".
  EOT
}

output "vlan_id" {
  value       = var.vlan_id
  description = "VLAN tag on the guest's primary interface."
}

output "tags" {
  value       = local.all_tags
  description = "Effective tags, including `protected` when deletion protection is on. Ansible's backup role selects vzdump targets by tag, so this output is what a backup schedule is really reading."
}

output "protected" {
  value       = var.protect_deletion
  description = "Whether the VM carries the `protected` marker. Ansible's common role sets Proxmox's protection bit from it."
}

output "ha_registered" {
  value       = var.ha_group != null
  description = "Whether the VM is managed by Proxmox HA. A VM that is in the N-1 priority list of docs/capacity-plan.md and reports false here will not come back after a node failure."
}

output "ha_group" {
  value       = var.ha_group
  description = "HA group the VM belongs to, or null."
}

output "memory_dedicated_mb" {
  value       = var.memory_dedicated_mb
  description = "Committed memory in MiB. Summed across an environment this is the number compared against the 384 GB guest budget in docs/capacity-plan.md."
}

output "cpu_cores" {
  value       = var.cpu_cores
  description = "Allocated vCPU cores."
}

output "user_data_file_id" {
  value       = proxmox_virtual_environment_file.user_data.id
  description = "Identifier of the uploaded cloud-init user-data snippet, for locating it on the node when first boot misbehaves."
}

output "network_config_file_id" {
  value       = proxmox_virtual_environment_file.network_config.id
  description = "Identifier of the uploaded cloud-init network-config snippet."
}
