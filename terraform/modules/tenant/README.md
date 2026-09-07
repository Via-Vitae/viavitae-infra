# terraform/modules/tenant

The tenant module creates one PostgreSQL schema, one database role, and one DNS CNAME
for a single tenant. It is the only path to a tenant's data layer; a tenant that is
not created by this module is a tenant whose schema ownership and privilege model are
not reviewed.

## Inputs

| Name | Type | Required | Description |
| --- | --- | --- | --- |
| `tenant_slug` | `string` | yes | URL-safe identifier for the tenant. Used in the schema name, role name and DNS CNAME. |
| `tenant_plan` | `string` | yes | One of `community`, `essential`, `professional`. Decides the resource ceiling. |
| `database_name` | `string` | yes | The shared database this tenant's schema lives in. |
| `schema_owner_role` | `string` | yes | The role that owns the schema and sets default privileges. |
| `public_domain` | `string` | yes | The public domain for the tenant's CNAME (e.g. `viavitae.com`). |
| `dns_zone_id` | `string` | yes | The DNS zone to create the CNAME in. |
| `environment` | `string` | yes | The environment name (`dev`, `staging`, `prod`). |
| `lifecycle_state` | `string` | no | One of `active`, `suspended`, `erasure_pending`. Default `active`. |
| `dpia_infra_001_signed_off` | `bool` | no | Must be `true` in `prod`. The module refuses to create a tenant while the DPIA is unsigned. |

## Outputs

| Name | Description |
| --- | --- |
| `schema_name` | The schema name created for this tenant. |
| `role_name` | The database role created for this tenant. |
| `tenant_fqdn` | The fully qualified domain name for this tenant's CNAME. |
| `erasure_command` | The SQL command to erase this tenant's data. Run only after legal approval. |

## Privilege model

The module creates a role with the minimum privileges required:

- `SELECT`, `INSERT`, `UPDATE`, `DELETE` on tables in the tenant's schema.
- `USAGE`, `SELECT` on sequences in the tenant's schema.
- No privileges on other schemas.
- No `SUPERUSER`, `CREATEDB`, `CREATEROLE`, `REPLICATION`, or `BYPASSRLS`.

When `lifecycle_state` is `suspended`, the role is set to `NOLOGIN`, which prevents
all connections. When `lifecycle_state` is `erasure_pending`, all privileges are
revoked and the `erasure_command` output provides the SQL to drop the schema and role.

## DPIA enforcement

In `prod`, the module requires `dpia_infra_001_signed_off` to be `true`. This is a
mechanical enforcement of INFRA-001 control M20: a tenant cannot be created while the
DPIA is unsigned. The constraint is enforced by a `lifecycle` precondition, not by
discipline.

## What the module does not do

- It does not create the database. That is the `postgres` role's job.
- It does not create the schema owner role. That is the `schema_owner_role` input.
- It does not configure backups. That is the `wal-g` role's job.
- It does not configure the application. That is the Argo CD ApplicationSet's job.
