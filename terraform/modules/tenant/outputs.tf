# Outputs for modules/tenant.
#
# These are the contract the `clients` ApplicationSet must agree with. If a value
# here and a value in viavitae-clients/clients/<slug>/ disagree, the tenant's
# application cannot reach its own database, and the disagreement is invisible from
# either side.

output "slug" {
  value       = var.slug
  description = "Tenant identifier, and the folder name in viavitae-clients."
}

output "display_name" {
  value       = var.display_name
  description = "Human-readable name."
}

output "reference_id" {
  value       = random_id.tenant_ref.hex
  description = "Stable non-identifying reference for logs, metrics and support tickets."
}

output "schema_name" {
  value       = local.schema_name
  description = "PostgreSQL schema, `t_<slug>`. The application's `search_path`."
}

output "role_name" {
  value       = local.role_name
  description = "PostgreSQL login role, `app_<slug>`. DML only."
}

output "migration_role_name" {
  value       = var.schema_owner_role
  description = "Role that owns the objects and runs migrations. Kept separate so that SQL injection in the application cannot ALTER TABLE, GRANT, or reach another schema."
}

output "namespace" {
  value       = local.namespace
  description = "Kubernetes namespace the ApplicationSet must create. This module does not create it."
}

output "database" {
  value       = var.database
  description = "Database containing the schema."
}

output "hostname" {
  value       = local.hostname
  description = "Public hostname. Derived from the slug and zone unless the tenant brought its own domain."
}

output "hostname_is_wildcard_covered" {
  value       = var.public_hostname == ""
  description = <<-EOT
    True when the hostname is covered by the wildcard certificate and needs no
    certificate action. False means a dedicated Certificate resource is required in
    the tenant's folder, with its own DNS-01 challenge and its own expiry to monitor.
  EOT
}

output "dns_record_fqdn" {
  value       = var.manage_dns ? local.hostname : ""
  description = "The record this module created, or empty when DNS is delegated to the tenant."
}

output "quotas" {
  value = {
    cpu_millicores   = local.cpu_millicores
    memory_mi        = local.memory_mi
    storage_gi       = local.storage_gi
    connection_limit = local.connection_limit
  }
  description = "Effective quotas. The ResourceQuota and LimitRange in the tenant namespace must match these numbers, and the tenant-quota alert fires on them."
}

output "plan" {
  value       = var.plan
  description = "Commercial tier. Feeds tools/cost-estimate.py, which compares the per-tenant infrastructure cost against the €30–50 ceiling."
}

output "lifecycle_state" {
  value       = var.lifecycle_state
  description = "active, suspended or erasure_pending."
}

output "can_login" {
  value       = local.can_login
  description = "Whether the application role can currently authenticate. False is the enforcement behind `suspended`."
}

output "credential_status" {
  value       = "unset — ansible/roles/postgres sets the password from the SOPS-encrypted inventory"
  description = <<-EOT
    Always this string. It exists so that anyone reading a plan output, an issue or
    a state export sees the position explicitly rather than inferring it from the
    absence of a password attribute.
  EOT
}

output "erasure_command" {
  value       = "DROP SCHEMA IF EXISTS ${local.schema_name} CASCADE; DROP ROLE IF EXISTS ${local.role_name};"
  description = <<-EOT
    The exact statements, so that the erasure runbook is executed rather than
    reconstructed. It does not erase backup copies: see
    docs/runbooks/backup-restore.md §Erasure, which states the residual exposure and
    the dates it expires, because a response that claims complete erasure is false.
  EOT
}

output "environment_name" {
  value       = var.environment_name
  description = "Environment this tenant lives in."
}
