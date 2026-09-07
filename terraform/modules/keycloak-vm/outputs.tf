output "vm_id" {
  value       = module.vm.vm_id
  description = "Allocated VMID."
}

output "name" {
  value       = module.vm.name
  description = "Host name, also the Ansible inventory hostname."
}

output "fqdn" {
  value       = module.vm.fqdn
  description = "Internal fully qualified name."
}

output "public_hostname" {
  value       = var.public_hostname
  description = "Externally visible name. This is the issuer host in every OIDC discovery document, so it is part of the contract with every client, not an internal detail."
}

output "issuer_url" {
  value       = "https://${var.public_hostname}/realms/viavitae"
  description = "OIDC issuer URL clients are configured with. Derived, never hard-coded in a client: a hard-coded issuer in five places is five places to miss during a rename."
}

output "ipv4_host" {
  value       = module.vm.ipv4_host
  description = "Address without prefix length."
}

output "port" {
  value       = 8443
  description = "HTTPS port, as listed in rule X3 of docs/network-topology.md."
}

output "database_host" {
  value       = var.database_host
  description = "keycloak-purpose PostgreSQL instance."
}

output "tags" {
  value       = module.vm.tags
  description = "Effective tags."
}

output "cpu_cores" {
  value       = module.vm.cpu_cores
  description = "Allocated vCPU, summed into the docs/capacity-plan.md budget."
}

output "memory_dedicated_mb" {
  value       = module.vm.memory_dedicated_mb
  description = "Committed memory, summed into the docs/capacity-plan.md budget."
}

output "node_name" {
  value       = module.vm.node_name
  description = "Current Proxmox node."
}
