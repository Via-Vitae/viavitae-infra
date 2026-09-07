# Remote state for the `global` root module.
#
# A backend block cannot interpolate variables, so every value here is a literal.
# The endpoint below is a placeholder that MUST be replaced before the first
# `terraform init`; it is the only file in this repository that has to be edited
# by hand rather than configured, and the governance gate in
# .github/workflows/compliance-check.yml asserts the placeholder has been
# replaced before any apply can run.
#
# Why an external S3-compatible service rather than self-hosted MinIO: state must
# not live on the infrastructure it describes. If the state store runs on the
# Proxmox cluster, a cluster outage makes Terraform unreachable at exactly the
# moment it is needed for recovery. INFRA-001 flow F9 records the residency and
# encryption position; condition C2 records the processor agreement.

terraform {
  backend "s3" {
    bucket = "viavitae-infra-tfstate"
    key    = "global/terraform.tfstate"
    region = "eu-central-1"

    endpoints = {
      s3 = "https://s3.eu-central-1.viavitae-state.example.com"
    }

    # Native S3 locking (Terraform >= 1.10). Replaces the DynamoDB lock table
    # that an AWS-shaped backend block would ask for, and which an S3-compatible
    # provider cannot supply.
    use_lockfile = true

    encrypt                     = true
    skip_credentials_validation = false
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true

    # Credentials come from AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY in the
    # GitHub Environment, scoped to this bucket only. Never hard-code them here:
    # a backend block is committed, and a committed key is a leaked key.
  }
}
