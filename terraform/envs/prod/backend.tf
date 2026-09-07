# Remote state for the `prod` environment.
#
# Separate key from every other environment, in the same bucket. One bucket is
# enough because the credentials are scoped per key prefix in the GitHub
# Environment; separate *states* are not optional, because a shared state file
# makes `terraform destroy -target` in dev capable of reaching prod.

terraform {
  backend "s3" {
    bucket = "viavitae-infra-tfstate"
    key    = "envs/prod/terraform.tfstate"
    region = "eu-central-1"

    endpoints = {
      s3 = "https://s3.eu-central-1.viavitae-state.example.com"
    }

    use_lockfile                = true
    encrypt                     = true
    skip_credentials_validation = false
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
  }
}
