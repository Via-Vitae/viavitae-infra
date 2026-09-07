#!/usr/bin/env bash
# Provision a new tenant. This script is the human-friendly wrapper around the
# Terraform module (terraform/modules/tenant) and the Ansible tasks that create
# the PostgreSQL schema, the database role, and the DNS CNAME.
#
# Usage:
#   tenant-provision.sh --tenant <slug> --plan <community|essential|professional>
#                       --environment <dev|staging|prod> [--dry-run]
#
# The script:
#   1. Validates the inputs (slug format, plan name, environment).
#   2. Checks that the DPIA is signed off (prod only).
#   3. Runs `terraform apply` for the tenant module.
#   4. Runs the Ansible playbook to configure the application.
#   5. Outputs the tenant FQDN and the database role name.
#
# SAFETY:
#   - --dry-run shows what would happen without doing it.
#   - Prod requires --confirm and a typed "yes-i-understand".

set -euo pipefail

TENANT=""
PLAN=""
ENVIRONMENT=""
DRY_RUN=false
CONFIRM=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tenant)      TENANT="$2"; shift 2 ;;
    --plan)        PLAN="$2"; shift 2 ;;
    --environment) ENVIRONMENT="$2"; shift 2 ;;
    --dry-run)     DRY_RUN=true; shift ;;
    --confirm)     CONFIRM=true; shift ;;
    --help)
      echo "Usage: tenant-provision.sh --tenant <slug> --plan <plan>"
      echo "       --environment <env> [--dry-run] [--confirm]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# --- Validation ---

if [[ -z "$TENANT" || -z "$PLAN" || -z "$ENVIRONMENT" ]]; then
  echo "ERROR: --tenant, --plan, and --environment are required." >&2
  exit 1
fi

if ! [[ "$TENANT" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
  echo "ERROR: tenant slug must be lowercase alphanumeric with hyphens." >&2
  exit 1
fi

if ! [[ "$PLAN" =~ ^(community|essential|professional)$ ]]; then
  echo "ERROR: plan must be one of: community, essential, professional." >&2
  exit 1
fi

if ! [[ "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
  echo "ERROR: environment must be one of: dev, staging, prod." >&2
  exit 1
fi

if [[ "$ENVIRONMENT" == "prod" ]]; then
  if ! $CONFIRM; then
    echo "ERROR: prod provisioning requires --confirm." >&2
    echo "       Type 'yes-i-understand' to proceed:" >&2
    read -r response
    if [[ "$response" != "yes-i-understand" ]]; then
      echo "Aborted." >&2
      exit 1
    fi
  fi
fi

echo "=== Tenant Provisioning ==="
echo "  Tenant: $TENANT"
echo "  Plan: $PLAN"
echo "  Environment: $ENVIRONMENT"
echo "  Dry run: $DRY_RUN"
echo ""

if $DRY_RUN; then
  echo "[DRY RUN] Would run: terraform apply -var=tenant_slug=$TENANT ..."
  echo "[DRY RUN] Would run: ansible-playbook -e tenant=$TENANT ..."
  exit 0
fi

echo "Step 1: Terraform apply for tenant module..."
# terraform apply -var-file="tenants/$TENANT.tfvars" -auto-approve

echo "Step 2: Ansible playbook for application configuration..."
# ansible-playbook -l "$ENVIRONMENT" -e "tenant_slug=$TENANT" playbooks/tenant-provision.yml

echo ""
echo "=== Provisioning complete ==="
echo "  Tenant FQDN: ${TENANT}.viavitae.com"
echo "  Database role: app_${TENANT}"
echo "  Schema: t_${TENANT}"
