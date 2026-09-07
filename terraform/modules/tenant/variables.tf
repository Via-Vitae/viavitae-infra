# Inputs for modules/tenant.
#
# One tenant = one PostgreSQL schema, one login role, one DNS record, one namespace
# name and one quota set. The module creates the first three, because those are the
# three things Git cannot do. The namespace, its quota and the workload are created
# by the `clients` ApplicationSet from `viavitae-clients/clients/<slug>/`, and this
# module outputs the values that generator needs in order to agree with the database.

variable "slug" {
  type        = string
  description = <<-EOT
    Tenant identifier. It becomes the schema name (`t_<slug>`), the role name
    (`app_<slug>`), the namespace name (`tenant-<slug>`), the public hostname
    (`<slug>.viavitae.com`) and the folder name in viavitae-clients. It is therefore
    effectively permanent: changing it is a migration, not a rename.
  EOT

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,22}$", var.slug))
    error_message = "slug must be 2-23 characters, lowercase letters and digits, starting with a letter. No hyphens: the slug is concatenated into identifiers that have their own character rules, and a hyphen in one place is an invalid identifier in another."
  }

  validation {
    condition = !contains([
      "public", "admin", "administrator", "root", "postgres", "postgresql", "api",
      "app", "web", "demos", "demo", "tenant", "tenants", "monitoring", "ingress",
      "argocd", "kube", "kubernetes", "system", "default", "information", "schema",
      "platform", "viavitae", "test", "testing", "staging", "dev", "prod", "all",
    ], var.slug)
    error_message = "This slug is reserved. It collides with a namespace, a Kubernetes system name, a PostgreSQL system schema, an environment name or the platform's own identity — and the collision would be invisible until something tried to address both."
  }
}

variable "display_name" {
  type        = string
  description = "Human-readable tenant name. Recorded in this module's outputs and in the tenant's folder in viavitae-clients; the database catalogue holds the owner role, which is named after the slug."

  validation {
    condition     = length(var.display_name) >= 2 && length(var.display_name) <= 120
    error_message = "display_name must be between 2 and 120 characters."
  }
}

variable "plan" {
  type        = string
  default     = "essential"
  description = <<-EOT
    Commercial tier. It sets the quota ceilings, and the quotas in
    docs/capacity-plan.md and the margin model in tools/cost-estimate.py are derived
    from the same three names. Adding a tier means changing all three.
  EOT

  validation {
    condition     = contains(["community", "essential", "professional"], var.plan)
    error_message = "plan must be community, essential or professional."
  }
}

variable "quota_cpu_millicores" {
  type        = number
  default     = null
  description = "Override the plan's CPU quota. Must not exceed the plan ceiling: a tenant above its tier's ceiling is being sold the wrong tier, and the capacity model no longer describes reality."
}

variable "quota_memory_mi" {
  type        = number
  default     = null
  description = "Override the plan's memory quota in MiB."
}

variable "quota_storage_gi" {
  type        = number
  default     = null
  description = "Override the plan's storage quota in GiB."
}

variable "connection_limit" {
  type        = number
  default     = null
  description = <<-EOT
    Override the plan's PostgreSQL connection limit for this tenant's role. Set at
    all because pgbouncer in transaction mode does not make the limit unnecessary:
    the pooler caps concurrent server connections, but a tenant that opens 500
    client connections still consumes 500 pooler slots and starves everyone else.
  EOT
}

variable "lifecycle_state" {
  type        = string
  default     = "active"
  description = <<-EOT
    `active`, `suspended` or `erasure_pending`. Suspension sets NOLOGIN on the
    tenant's role, which is a real revocation rather than a label: the application
    stops immediately, at the database, without a deployment. `erasure_pending`
    additionally revokes grants, and the runbook in
    docs/runbooks/backup-restore.md §Erasure takes it from there.
  EOT

  validation {
    condition     = contains(["active", "suspended", "erasure_pending"], var.lifecycle_state)
    error_message = "lifecycle_state must be active, suspended or erasure_pending."
  }
}

variable "database" {
  type        = string
  default     = "viavitae"
  description = "Database containing the tenant schemas. One database, many schemas — ADR-003."
}

variable "schema_owner_role" {
  type        = string
  description = <<-EOT
    Role that owns the objects inside the schema, i.e. the role migrations run as.
    It is **not** the tenant's application role: separating DDL from DML means a
    SQL-injection in the application cannot `ALTER TABLE`, cannot `GRANT`, and
    cannot reach another schema.
  EOT
}

variable "public_hostname" {
  type        = string
  default     = ""
  description = <<-EOT
    Public name. Empty derives `<slug>.<dns_zone>`, which the wildcard certificate
    already covers and which therefore needs no certificate action. Set it only for
    a tenant's own domain, which then needs its own certificate and its own DNS
    delegation — two operational commitments that a derived name does not carry.
  EOT
}

variable "dns_zone" {
  type        = string
  default     = "viavitae.com."
  description = "Authoritative zone for the derived hostname. Trailing dot required: the DNS provider treats a name without one as relative and will create the wrong record."

  validation {
    condition     = endswith(var.dns_zone, ".")
    error_message = "dns_zone must be fully qualified with a trailing dot."
  }
}

variable "dns_target" {
  type        = string
  description = "CNAME target for the tenant hostname — the load balancer's public name, never a raw IP. An A record here would survive a load-balancer change and quietly point tenants at an address nobody owns any more."
}

variable "dns_ttl" {
  type        = number
  default     = 300
  description = "Record TTL in seconds. 300 is short enough to move a tenant during an incident and long enough not to make the authoritative server the busiest component in the estate."

  validation {
    condition     = var.dns_ttl >= 60 && var.dns_ttl <= 86400
    error_message = "dns_ttl must be between 60 and 86400 seconds."
  }
}

variable "manage_dns" {
  type        = bool
  default     = true
  description = "Set false for a tenant whose hostname is delegated elsewhere (a CNAME the tenant's own DNS provider owns). Off means this module creates no record and the output says so, rather than silently creating a record nobody reads."
}

variable "environment_name" {
  type        = string
  description = "Environment this tenant lives in. `prod` triggers the DPIA precondition."
}

variable "dpia_infra_001_signed_off" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether INFRA-001 carries the managing-director signature. INFRA-001 control M20:
    a `prod` tenant may not be instantiated while the overall residual risk of the
    platform's own processing is Medium-High and unsigned. Defaults to false so the
    safe state is the default, and so flipping it is a reviewed change rather than a
    value nobody notices.
  EOT
}
