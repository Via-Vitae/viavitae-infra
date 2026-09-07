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

output "ipv4_host" {
  value       = module.vm.ipv4_host
  description = "Object store and prober address, referenced by rules X6, X7 and X8."
}

output "s3_endpoint" {
  value       = "https://${module.vm.fqdn}:9000"
  description = <<-EOT
    S3 endpoint consumed by Loki (`monitoring/loki/values.yaml`) and by Prometheus
    remote-write (`monitoring/prometheus/values.yaml`). Credentials are supplied to
    those components from SOPS-encrypted Kubernetes secrets, never from here.
  EOT
}

output "loki_bucket" {
  value       = var.loki_bucket
  description = "Bucket for Loki chunks and index. Personal data, 30-day retention."
}

output "metrics_bucket" {
  value       = var.metrics_bucket
  description = "Bucket for Prometheus long-term blocks."
}

output "uptime_kuma_hostname" {
  value       = var.uptime_kuma_hostname
  description = "Public status page name served by the external prober."
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
