# modules/tenant — one tenant's database identity and DNS name.
#
# Creates exactly three things Git cannot: a PostgreSQL schema, a login role with
# no password, and a CNAME record. Everything a tenant runs is created by the
# `clients` ApplicationSet from viavitae-clients/clients/<slug>/, and this module's
# outputs are the values that generator must agree with.
#
# ADR-003 decision 3 is the reason there is no password argument anywhere below.

locals {
  schema_name = "t_${var.slug}"
  role_name   = "app_${var.slug}"
  namespace   = "tenant-${var.slug}"

  # Plan ceilings. The middle tier is the one docs/capacity-plan.md sizes the estate
  # from — 2 vCPU, 4 GiB, 10 GiB per tenant — so changing it changes the density
  # model, the break-even table and tools/cost-estimate.py together, or not at all.
  plans = {
    community = {
      cpu_millicores   = 500
      memory_mi        = 1024
      storage_gi       = 5
      connection_limit = 20
    }
    essential = {
      cpu_millicores   = 2000
      memory_mi        = 4096
      storage_gi       = 10
      connection_limit = 60
    }
    professional = {
      cpu_millicores   = 4000
      memory_mi        = 8192
      storage_gi       = 40
      connection_limit = 120
    }
  }

  plan = local.plans[var.plan]

  cpu_millicores   = coalesce(var.quota_cpu_millicores, local.plan.cpu_millicores)
  memory_mi        = coalesce(var.quota_memory_mi, local.plan.memory_mi)
  storage_gi       = coalesce(var.quota_storage_gi, local.plan.storage_gi)
  connection_limit = coalesce(var.connection_limit, local.plan.connection_limit)

  # Derived unless the tenant brings its own domain. A derived name is covered by
  # the wildcard certificate, so onboarding it needs no certificate action at all.
  hostname = var.public_hostname == "" ? "${var.slug}.${var.dns_zone}" : var.public_hostname

  # NOLOGIN is the enforcement behind `suspended`: the application stops at the
  # database, immediately, without a deployment and without waiting for a rollout.
  can_login = var.lifecycle_state == "active"

  # `erasure_pending` revokes the grants as well, so that a restore performed while
  # the erasure runbook is in flight cannot resurrect a readable schema. An empty
  # set here is a real revocation, not a no-op: the provider issues REVOKE for every
  # privilege that disappears.
  erased = var.lifecycle_state == "erasure_pending"
  # A filtered `for` rather than a conditional between two literals: an empty tuple
  # literal makes the whole expression dynamically typed, and `toset()` on a
  # dynamic value cannot be checked against the provider's `set(string)` at
  # validate time. The filter keeps the type static, and an empty result is still a
  # real REVOKE rather than a no-op.
  table_privileges    = [for privilege in ["SELECT", "INSERT", "UPDATE", "DELETE"] : privilege if !local.erased]
  sequence_privileges = [for privilege in ["USAGE", "SELECT"] : privilege if !local.erased]
}

# A stable, non-identifying reference for this tenant. It exists so that logs,
# metrics and support tickets can refer to a tenant without carrying the slug,
# which is closer to an identifier than it looks when it is a parish name.
resource "random_id" "tenant_ref" {
  byte_length = 4

  keepers = {
    slug = var.slug
  }
}

resource "postgresql_schema" "tenant" {
  name  = local.schema_name
  owner = var.schema_owner_role

  # The provider has no `comment` argument, so the human-readable ownership record
  # lives in this module's outputs and in the tenant's folder in viavitae-clients
  # rather than in the database catalogue. `\dn+` shows the owner role, which is
  # enough to trace a schema back to a tenant, because the role is named after it.
}

resource "postgresql_role" "app" {
  name  = local.role_name
  login = local.can_login

  # Every privilege that would let this role escape its own schema is off. These
  # are explicit rather than defaulted, because the defaults are what they are and
  # a future provider version is not a reason to change a security posture.
  superuser                 = false
  create_database           = false
  create_role               = false
  inherit                   = false
  replication               = false
  bypass_row_level_security = false
  connection_limit          = local.connection_limit
  # Milliseconds, as PostgreSQL stores it for a role. 30 s is long enough for a
  # report query and short enough that a tenant's runaway query cannot hold a
  # connection from the pool while everyone else waits.
  statement_timeout = 30000

  # **No password.** Set inside the guest by ansible/roles/postgres from the
  # SOPS-encrypted inventory. A password given here would be stored in Terraform
  # state, in the plan file attached to the pull request, and in the provider's
  # debug log — three copies nobody asked for. Until Ansible sets it, the role
  # cannot authenticate, which is the correct order: the schema exists before the
  # credential does, never after.
}

# `postgresql_grant` in provider >= 1.20 takes a single `object_type` and a set of
# privileges, not a map of object types. One resource per object type is therefore
# not a stylistic choice; it is the schema.

resource "postgresql_grant" "schema_usage" {
  database    = var.database
  role        = postgresql_role.app.name
  object_type = "schema"

  # USAGE on the schema and nothing else. Without it the role cannot see any object
  # inside; with CREATE it could put objects in a schema it does not own.
  privileges = toset([for privilege in ["USAGE"] : privilege if !local.erased])
}

resource "postgresql_grant" "tables" {
  database    = var.database
  schema      = local.schema_name
  role        = postgresql_role.app.name
  object_type = "table"

  # DML only. No TRUNCATE, no REFERENCES, no TRIGGER: DDL belongs to the migration
  # role, and a tenant application that can truncate its own tables can also
  # truncate them by accident.
  privileges = toset(local.table_privileges)
}

resource "postgresql_grant" "sequences" {
  database    = var.database
  schema      = local.schema_name
  role        = postgresql_role.app.name
  object_type = "sequence"

  # No UPDATE on sequences. Letting an application setval() its own identity
  # sequence is how a tenant ends up with colliding primary keys after a restore.
  privileges = toset(local.sequence_privileges)
}

resource "postgresql_default_privileges" "tables" {
  database    = var.database
  schema      = local.schema_name
  owner       = var.schema_owner_role
  role        = postgresql_role.app.name
  object_type = "table"

  privileges = toset(local.table_privileges)
}

resource "postgresql_default_privileges" "sequences" {
  database    = var.database
  schema      = local.schema_name
  owner       = var.schema_owner_role
  role        = postgresql_role.app.name
  object_type = "sequence"

  privileges = toset(local.sequence_privileges)
}

resource "dns_cname_record" "tenant" {
  count = var.manage_dns ? 1 : 0

  zone  = var.dns_zone
  name  = var.public_hostname == "" ? var.slug : replace(trimsuffix(var.public_hostname, ".${var.dns_zone}"), ".", "_")
  cname = var.dns_target
  ttl   = var.dns_ttl
}

resource "terraform_data" "tenant_invariants" {
  input = {
    slug      = var.slug
    plan      = var.plan
    state     = var.lifecycle_state
    quota_cpu = local.cpu_millicores
    quota_mem = local.memory_mi
    quota_sto = local.storage_gi
  }

  lifecycle {
    # INFRA-001 control M20. The platform's own processing carries a Medium-High
    # residual risk until the managing director signs, and this is the mechanical
    # form of "then do not put tenant data on it yet".
    precondition {
      condition     = var.environment_name == "prod" ? var.dpia_infra_001_signed_off : true
      error_message = <<-EOT
        A prod tenant requires dpia_infra_001_signed_off = true. INFRA-001 stands at
        DPO approval with conditions and its overall residual risk is Medium-High;
        the managing-director signature is pending, and until it exists the platform
        may be provisioned but must not carry tenant personal data.
      EOT
    }

    # A quota above the tier's ceiling means the tenant is being sold one tier and
    # provisioned at another, and docs/capacity-plan.md stops describing reality.
    precondition {
      condition     = local.cpu_millicores <= local.plan.cpu_millicores
      error_message = "CPU quota ${local.cpu_millicores}m exceeds the ${var.plan} ceiling of ${local.plan.cpu_millicores}m. Raise the plan instead of the override."
    }

    precondition {
      condition     = local.memory_mi <= local.plan.memory_mi
      error_message = "Memory quota ${local.memory_mi}Mi exceeds the ${var.plan} ceiling of ${local.plan.memory_mi}Mi."
    }

    precondition {
      condition     = local.storage_gi <= local.plan.storage_gi
      error_message = "Storage quota ${local.storage_gi}Gi exceeds the ${var.plan} ceiling of ${local.plan.storage_gi}Gi."
    }

    # The sum of tenant quotas must stay inside what the estate can actually give.
    # 4 tenants per worker at quota (docs/capacity-plan.md §Tenant density model)
    # means a professional tenant at 8 GiB consumes half a worker on its own.
    precondition {
      condition     = local.memory_mi <= 8192
      error_message = "Memory quota ${local.memory_mi}Mi exceeds 8 GiB, which is more than half a worker VM. At that size the tenant needs a dedicated node, not a larger quota — see the density model in docs/capacity-plan.md."
    }

    precondition {
      condition     = var.manage_dns ? var.dns_target != "" : true
      error_message = "dns_target is required when manage_dns is true."
    }

    # A tenant on its own domain is a certificate commitment, not just a DNS record.
    precondition {
      condition = var.public_hostname == "" ? true : (
        endswith(var.public_hostname, ".") == false
      )
      error_message = "public_hostname must not carry a trailing dot; the zone already does."
    }
  }
}
