# Provider requirements for this module.
#
# This file is not decoration. A child module that references `proxmox_*`
# resources without declaring the provider's source address is assumed by
# Terraform to mean `hashicorp/proxmox`, which does not exist, and the error
# surfaces in the *root* module as "Provider type mismatch" — pointing at the
# caller rather than at the cause. Declaring it here makes every module
# independently resolvable.

terraform {
  required_version = ">= 1.16.1, < 2.0.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.112"
    }
  }
}
