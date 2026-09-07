terraform {
  required_version = ">= 1.16.1, < 2.0.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.112"
    }

    # Tenants exist in staging too, and a tenant that has never been provisioned in
    # staging is a tenant whose first provisioning happens in production.
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.27"
    }

    dns = {
      source  = "hashicorp/dns"
      version = "~> 3.6"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }
}

# Credentials come from the environment, never from a file:
#
#   PM_API_URL, PM_API_TOKEN_ID, PM_API_TOKEN_SECRET   Proxmox API (read-only for plan)
#   PM_SSH_USERNAME, PM_SSH_PRIVATE_KEY                Proxmox nodes, apply only
#   PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD,
#   PGSSLMODE                                          libpq variables; the provisioner
#                                                      role, NOT a superuser
#   DNS_UPDATE_SERVER, DNS_UPDATE_KEY_NAME,
#   DNS_UPDATE_KEY_ALGORITHM, DNS_UPDATE_KEY_SECRET    RFC 2136 TSIG key, scoped to the zone
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY           state backend
#
# Every one of these is scoped to the `staging` GitHub Environment. The `plan`
# environment holds read-only credentials and no SSH key, which is what makes a plan
# safe to run on a pull request.
provider "proxmox" {
  insecure = false
}

# Configured entirely from libpq environment variables, so that no credential is a
# Terraform variable and none can appear in a tfvars file, a plan input listing or a
# state export:
#
#   PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD, PGSSLMODE=require
#
# `superuser = false` is set explicitly even though it is the default: the
# provisioner role must not be a superuser, and a provider argument that says so is
# a claim a reviewer can check against the role Ansible created.
provider "postgresql" {
  superuser = false
}

provider "dns" {
  update {
    server        = var.dns_update_server
    key_name      = var.dns_update_key_name
    key_algorithm = var.dns_update_key_algorithm
    key_secret    = var.dns_update_key_secret
  }
}
