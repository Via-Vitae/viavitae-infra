# Provider requirements for modules/tenant.
#
# No `hashicorp/kubernetes` provider appears here, and that is a decision rather
# than an omission. Tenant Kubernetes objects are created by the `clients`
# ApplicationSet Git generator (ADR-004); adding a Terraform path for them would
# mean two writers for one object, and would put a cluster-admin kubeconfig into
# the CI credential set. See the consequence recorded in ADR-004.

terraform {
  required_version = ">= 1.16.1, < 2.0.0"

  required_providers {
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
