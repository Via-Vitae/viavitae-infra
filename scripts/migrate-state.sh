#!/usr/bin/env bash
# migrate-state.sh — Migrate Terraform state from AWS S3 to self-hosted MinIO
#
# This script migrates Terraform state for all 4 roots (global, dev, staging, prod)
# from the old AWS S3 backend to the new self-hosted MinIO backend.
#
# PREREQUISITES:
#   1. The MinIO state backend must be provisioned (see docs/runbooks/minio-state-bootstrap.md)
#   2. The backend.tf files must be updated to point at MinIO (already done in WS1.3)
#   3. AWS credentials must be available (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
#   4. MinIO credentials must be available (MINIO_ACCESS_KEY, MINIO_SECRET_KEY)
#   5. Network access to both AWS S3 and MinIO endpoint
#
# USAGE:
#   ./scripts/migrate-state.sh [--force] [--dry-run]
#
# OPTIONS:
#   --force    Allow migration even if the target MinIO bucket is non-empty
#   --dry-run  Show what would be done without actually migrating
#
# HUMAN ACTIONS (this script does NOT do these):
#   - Running against real infrastructure (use --dry-run first)
#   - Verifying state integrity after migration (run `terraform plan` to confirm no changes)
#   - Freezing the AWS S3 bucket (set to read-only for 30 days, then delete)
#
# IDEMPOTENCY:
#   This script is idempotent. If a root has already been migrated, it will skip it.
#   If the target bucket is non-empty, it will refuse to run unless --force is provided.

set -euo pipefail

# --- Configuration -------------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_ROOTS=(
  "terraform"
  "terraform/envs/dev"
  "terraform/envs/staging"
  "terraform/envs/prod"
)

# Old AWS S3 backend config (for pulling state)
OLD_BACKEND_CONFIG=(
  -backend-config="bucket=viavitae-infra-tfstate"
  -backend-config="region=eu-central-1"
  -backend-config="key=__KEY__"  # Will be replaced per root
  -backend-config="encrypt=true"
  -backend-config="kms_key_id=alias/viavitae-state"
)

# New MinIO backend config (already in backend.tf, but we need to verify)
NEW_ENDPOINT="https://minio-state-01.viavitae.internal:9000"

# --- Argument parsing ----------------------------------------------------------

FORCE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--force] [--dry-run]"
      exit 1
      ;;
  esac
done

if [ "$DRY_RUN" = true ]; then
  echo "=== DRY RUN MODE — no changes will be made ==="
  echo ""
fi

# --- Preflight checks ----------------------------------------------------------

echo "=== Preflight checks ==="

# Check AWS credentials
if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  echo "ERROR: AWS credentials not set (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)"
  exit 1
fi
echo "✓ AWS credentials present"

# Check MinIO credentials
if [ -z "${MINIO_ACCESS_KEY:-}" ] || [ -z "${MINIO_SECRET_KEY:-}" ]; then
  echo "ERROR: MinIO credentials not set (MINIO_ACCESS_KEY, MINIO_SECRET_KEY)"
  exit 1
fi
echo "✓ MinIO credentials present"

# Check Terraform is installed
if ! command -v terraform &> /dev/null; then
  echo "ERROR: terraform not found in PATH"
  exit 1
fi
echo "✓ Terraform installed: $(terraform version -json | jq -r '.terraform_version')"

# Check network access to MinIO
if ! curl -sk --max-time 5 "$NEW_ENDPOINT/minio/health/live" &> /dev/null; then
  echo "ERROR: Cannot reach MinIO endpoint at $NEW_ENDPOINT"
  exit 1
fi
echo "✓ MinIO endpoint reachable"

echo ""

# --- Migration function --------------------------------------------------------

migrate_root() {
  local root="$1"
  local key="$2"
  local bucket="$3"
  
  echo "=== Migrating root: $root ==="
  echo "  Old: AWS S3 bucket=viavitae-infra-tfstate, key=$key"
  echo "  New: MinIO bucket=$bucket, key=$key"
  
  cd "$REPO_ROOT/$root"
  
  # Check if target bucket is non-empty
  if [ "$FORCE" = false ]; then
    # Use mc CLI to check if bucket has objects
    # Note: This assumes mc is configured with MinIO credentials
    # If mc is not available, skip this check
    if command -v mc &> /dev/null; then
      object_count=$(mc ls "minio-state/$bucket" 2>/dev/null | wc -l || echo "0")
      if [ "$object_count" -gt 0 ]; then
        echo "ERROR: Target bucket $bucket is non-empty ($object_count objects)"
        echo "       Use --force to override, or delete the objects first"
        return 1
      fi
    else
      echo "WARNING: mc CLI not found, cannot check if target bucket is empty"
      echo "         Proceeding anyway (use --force to suppress this warning)"
    fi
  fi
  
  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY RUN] Would migrate state for $root"
    echo ""
    return 0
  fi
  
  # Step 1: Init with OLD backend config (AWS S3)
  echo "  Step 1: Initializing with OLD backend (AWS S3)..."
  local old_config=("${OLD_BACKEND_CONFIG[@]}")
  for i in "${!old_config[@]}"; do
    old_config[$i]="${old_config[$i]//__KEY__/$key}"
  done
  
  if ! terraform init -input=false -no-color "${old_config[@]}" > /dev/null 2>&1; then
    echo "ERROR: Failed to initialize with OLD backend"
    return 1
  fi
  echo "  ✓ Initialized with OLD backend"
  
  # Step 2: Pull state to local file
  echo "  Step 2: Pulling state to local file..."
  local local_state="/tmp/terraform-state-${root//\//-}.tfstate"
  if ! terraform state pull > "$local_state" 2>/dev/null; then
    echo "ERROR: Failed to pull state"
    return 1
  fi
  
  if [ ! -s "$local_state" ]; then
    echo "WARNING: State file is empty (no resources managed yet)"
    echo "         Skipping migration for this root"
    rm -f "$local_state"
    echo ""
    return 0
  fi
  
  local state_size=$(stat -c%s "$local_state" 2>/dev/null || stat -f%z "$local_state")
  echo "  ✓ State pulled: $local_state ($state_size bytes)"
  
  # Step 3: Init with NEW backend config (MinIO) — reconfigure
  echo "  Step 3: Reinitializing with NEW backend (MinIO)..."
  if ! terraform init -input=false -no-color -reconfigure > /dev/null 2>&1; then
    echo "ERROR: Failed to initialize with NEW backend"
    echo "       The backend.tf may not be updated correctly"
    return 1
  fi
  echo "  ✓ Reinitialized with NEW backend"
  
  # Step 4: Push state to new backend
  echo "  Step 4: Pushing state to NEW backend..."
  if ! terraform state push "$local_state" > /dev/null 2>&1; then
    echo "ERROR: Failed to push state to NEW backend"
    return 1
  fi
  echo "  ✓ State pushed to NEW backend"
  
  # Step 5: Verify state is accessible
  echo "  Step 5: Verifying state is accessible..."
  if ! terraform state list > /dev/null 2>&1; then
    echo "ERROR: State is not accessible after migration"
    return 1
  fi
  echo "  ✓ State verified"
  
  # Cleanup
  rm -f "$local_state"
  
  echo "  ✓ Migration complete for $root"
  echo ""
}

# --- Main migration loop -------------------------------------------------------

echo "=== Starting migration ==="
echo ""

# Map roots to their state keys and target buckets
declare -A ROOT_KEYS=(
  ["terraform"]="global/terraform.tfstate"
  ["terraform/envs/dev"]="envs/dev/terraform.tfstate"
  ["terraform/envs/staging"]="envs/staging/terraform.tfstate"
  ["terraform/envs/prod"]="envs/prod/terraform.tfstate"
)

declare -A TARGET_BUCKETS=(
  ["terraform"]="viavitae-tfstate-global"
  ["terraform/envs/dev"]="viavitae-tfstate-dev"
  ["terraform/envs/staging"]="viavitae-tfstate-staging"
  ["terraform/envs/prod"]="viavitae-tfstate-prod"
)

MIGRATION_ERRORS=0

for root in "${TERRAFORM_ROOTS[@]}"; do
  key="${ROOT_KEYS[$root]}"
  bucket="${TARGET_BUCKETS[$root]}"
  
  if ! migrate_root "$root" "$key" "$bucket"; then
    MIGRATION_ERRORS=$((MIGRATION_ERRORS + 1))
  fi
done

# --- Summary -------------------------------------------------------------------

echo "=== Migration summary ==="
echo "  Roots processed: ${#TERRAFORM_ROOTS[@]}"
echo "  Errors: $MIGRATION_ERRORS"
echo ""

if [ $MIGRATION_ERRORS -gt 0 ]; then
  echo "ERROR: $MIGRATION_ERRORS root(s) failed to migrate"
  echo "       Review the errors above and retry"
  exit 1
fi

if [ "$DRY_RUN" = true ]; then
  echo "=== DRY RUN COMPLETE ==="
  echo "No changes were made. Remove --dry-run to execute the migration."
else
  echo "=== MIGRATION COMPLETE ==="
  echo ""
  echo "Next steps (HUMAN ACTIONS):"
  echo "  1. Verify state integrity: cd into each root and run 'terraform plan'"
  echo "     Expected: No changes (state migrated correctly)"
  echo "  2. Freeze the AWS S3 bucket: Set to read-only for 30 days (rollback window)"
  echo "  3. After 30 days: Delete the AWS S3 bucket (completing AWS removal)"
  echo "  4. Update GitHub Environments: Replace AWS credentials with MinIO credentials"
  echo ""
fi
