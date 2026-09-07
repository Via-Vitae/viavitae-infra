terraform {
  required_version = ">= 1.16.1, < 2.0.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.112"
    }

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
#   PM_API_URL, PM_API_TOKEN_ID, PM_API_TOKEN_SECRET   Proxmox API
#   PM_SSH_USERNAME, PM_SSH_PRIVATE_KEY                Proxmox nodes, apply only
#   PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD,
#   PGSSLMODE                                          libpq variables; the provisioner
#                                                      role, NOT a superuser
#   DNS_UPDATE_SERVER, DNS_UPDATE_KEY_NAME,
#   DNS_UPDATE_KEY_ALGORITHM, DNS_UPDATE_KEY_SECRET    RFC 2136 TSIG key, scoped to the zone
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY           state backend
#
# The `prod-plan` GitHub Environment holds a **read-only** Proxmox token, a
# read-only database role and no SSH key. The `prod-apply` Environment holds the
# write token, the provisioner role and the SSH key, and requires a human approval
# plus a typed `prod` confirmation. That split is what makes a plan safe to run on a
# pull request and an apply expensive to run by accident.
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
