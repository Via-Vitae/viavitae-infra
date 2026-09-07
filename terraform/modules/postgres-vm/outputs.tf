output "vm_id" {
  value       = module.vm.vm_id
  description = "Allocated VMID. This is the number in the vzdump archive names, so a restore is addressed by it."
}

output "name" {
  value       = module.vm.name
  description = "Host name, also the Ansible inventory hostname."
}

output "fqdn" {
  value       = module.vm.fqdn
  description = "Fully qualified name, used in the PostgreSQL TLS certificate SAN."
}

output "ipv4_host" {
  value       = module.vm.ipv4_host
  description = "Address without prefix length. This is what goes into `pg_hba.conf` host lines and into the Kubernetes ExternalName Service that points the cluster at it."
}

output "port" {
  value       = 5432
  description = "PostgreSQL port. Fixed by the module rather than configurable: a non-standard port buys nothing against an attacker who can already reach the VLAN, and it breaks every tool's default."
}

output "instance_purpose" {
  value       = var.instance_purpose
  description = "What the instance holds. Consumed by ansible/roles/postgres to select tuning and retention."
}

output "is_primary" {
  value       = var.is_primary
  description = "Whether this is the primary. The standby's role is to be promoted, and the promotion runbook needs to know which is which without reading Terraform state."
}

output "wal_g_bucket" {
  value       = var.wal_g_bucket
  description = "Bucket name for continuous archiving. A name, not a credential."
}

output "connection_string_without_credentials" {
  value       = "postgresql://${module.vm.ipv4_host}:5432/viavitae?sslmode=require"
  description = <<-EOT
    Connection string with no user and no password, so it can be committed,
    printed in a plan and pasted into an issue. Credentials are injected by the
    application from SOPS-encrypted inventory; a connection string that contains
    them is a secret in every log it passes through.
  EOT
}

output "tags" {
  value       = module.vm.tags
  description = "Effective tags, including `protected` and the backup selection tag."
}

output "cpu_cores" {
  value       = module.vm.cpu_cores
  description = "Allocated vCPU, summed into the docs/capacity-plan.md budget."
}

output "memory_dedicated_mb" {
  value       = module.vm.memory_dedicated_mb
  description = "Committed memory. Summed into the docs/capacity-plan.md budget."
}

output "node_name" {
  value       = module.vm.node_name
  description = "Current Proxmox node. Changes after an HA relocation."
}
