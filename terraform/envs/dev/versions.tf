terraform {
  required_version = ">= 1.16.1, < 2.0.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.112"
    }
  }
}

# Credentials and the SSH transport come from the environment, never from a file:
#   PM_API_URL, PM_API_TOKEN_ID, PM_API_TOKEN_SECRET   (read-only for plan)
#   PM_SSH_USERNAME, PM_SSH_PRIVATE_KEY                (apply only)
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY           (state backend)
provider "proxmox" {
  insecure = false
}
