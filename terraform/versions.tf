# Shared version constraints for the `global` root module.
#
# The environment root modules under terraform/envs/ carry their own copy. That
# duplication is deliberate: Terraform resolves provider requirements from the
# root module, so a child module's constraint is only advisory and each root
# module must state its own.

terraform {
  required_version = ">= 1.16.1, < 2.0.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.112"
    }
  }
}

# Provider configuration is intentionally minimal. Credentials come from the
# environment, never from a file, a variable default or state:
#
#   PM_API_URL          https://pve-01.viavitae.internal:8006/api2/json
#   PM_API_TOKEN_ID     terraform@pve!global       (read-only token for plan)
#   PM_API_TOKEN_SECRET ...
#   PM_SSH_USERNAME     terraform
#   PM_SSH_PRIVATE_KEY  ...                        (apply only; cloud-init snippets)
#
# `PM_SSH_*` is required at apply time only, because uploading cloud-init
# snippets uses the provider's SSH path. `terraform plan` never needs it, which
# is what keeps the read-only plan credential free of node SSH access.
provider "proxmox" {
  insecure = false
}
