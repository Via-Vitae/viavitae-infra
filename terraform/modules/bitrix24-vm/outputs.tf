output "vm_id" {
  value       = module.vm.vm_id
  description = "Allocated VMID."
}

output "name" {
  value       = module.vm.name
  description = "Host name."
}

output "fqdn" {
  value       = module.vm.fqdn
  description = "Internal fully qualified name."
}

output "public_hostname" {
  value       = var.public_hostname
  description = "Externally visible name, terminated on the dmz VIP."
}

output "ipv4_host" {
  value       = module.vm.ipv4_host
  description = "dmz address. HAProxy forwards to it directly; nothing in prod may."
}

output "port" {
  value       = 443
  description = "HTTPS port served by the vendor stack."
}

output "database_host" {
  value       = var.database_host
  description = "bitrix24-purpose database instance in the dmz."
}

output "egress_allow_list" {
  value       = sort(var.egress_allow_list)
  description = <<-EOT
    Hostnames this VM may reach, implementing rule E6. Sorted so that a diff shows
    an addition rather than a reordering. Reviewed quarterly per ADR-007 condition 2.
  EOT
}

output "approvals" {
  value = {
    legal_review     = var.legal_review_approved
    legal_review_ref = var.legal_review_reference
    dpia_infra_002   = var.dpia_infra_002_approved
    dpia_ref         = var.dpia_reference
  }
  description = "The approval state this VM was created under, as an auditable record in state and in the plan output. INFRA-001 condition C5."
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
