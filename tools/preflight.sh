#!/usr/bin/env bash
# Preflight checks before a deployment. Runs the same validations the CI
# pipeline runs, but locally, so a developer can catch problems before pushing.
#
# Usage:
#   preflight.sh [--quick]
#
# --quick: skip Terraform validate and Ansible syntax-check (fast feedback).
#          These checks require `terraform init -backend=false` per root and
#          an Ansible venv with galaxy collections installed, so they are
#          opt-in for rapid local iteration. Full parity with CI requires
#          running without --quick.

set -euo pipefail

QUICK=false
[[ "${1:-}" == "--quick" ]] && QUICK=true

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Preflight checks ==="
echo "  Repository: $REPO_ROOT"
echo "  Quick mode: $QUICK"
echo ""

ERRORS=0

# --- Credential presence (never values) ---
# The README Quickstart step 2 exports these variables. If any is missing,
# Terraform and Ansible will fail in opaque ways; failing here gives a clear
# message before any plan is run.
echo "--- Credential presence ---"
REQUIRED_VARS=(
  PM_API_URL
  PM_API_TOKEN_ID
  PM_API_TOKEN_SECRET
  AWS_ENDPOINT_URL_S3
  AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY
)
MISSING_VARS=()
for v in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!v:-}" ]]; then
    MISSING_VARS+=("$v")
  fi
done
if [[ ${#MISSING_VARS[@]} -gt 0 ]]; then
  echo "  FAIL: the following environment variables are unset:" >&2
  for v in "${MISSING_VARS[@]}"; do
    echo "    - $v" >&2
  done
  echo "  Export them per README Quickstart step 2 before running preflight." >&2
  ERRORS=$((ERRORS + 1))
else
  echo "  PASS: all required environment variables are set"
fi

# --- YAML syntax ---
echo ""
echo "--- YAML syntax ---"
if python3 -c "
import yaml, pathlib, sys
errors = []
for f in sorted(pathlib.Path('$REPO_ROOT').rglob('*.yaml')):
    if '.sops' in str(f) or '.venv' in str(f) or '.git' in str(f):
        continue
    try:
        list(yaml.safe_load_all(f.read_text()))
    except Exception as e:
        errors.append(f'{f}: {e}')
if errors:
    for e in errors: print(f'FAIL: {e}', file=sys.stderr)
    sys.exit(1)
"; then
  echo "  PASS: all YAML files parse"
else
  echo "  FAIL: YAML parse errors" >&2
  ERRORS=$((ERRORS + 1))
fi

# --- Terraform fmt (always) ---
echo ""
echo "--- Terraform fmt ---"
if terraform -chdir="$REPO_ROOT/terraform" fmt -check -recursive -diff; then
  echo "  PASS: terraform fmt"
else
  echo "  FAIL: terraform fmt" >&2
  ERRORS=$((ERRORS + 1))
fi

# --- Terraform validate (full mode only) ---
# Uses -backend=false so no S3 credentials are needed for the init step.
# This catches HCL validity errors, missing provider declarations, and
# variable/reference mismatches without touching remote state.
if ! $QUICK; then
  echo ""
  echo "--- Terraform validate ---"
  TF_ROOTS=(terraform terraform/envs/dev terraform/envs/staging terraform/envs/prod)
  TF_VALIDATE_ERRORS=0
  for root in "${TF_ROOTS[@]}"; do
    if ! terraform -chdir="$REPO_ROOT/$root" init -backend=false -input=false -no-color > /dev/null 2>&1; then
      echo "  FAIL: $root — terraform init -backend=false failed" >&2
      TF_VALIDATE_ERRORS=$((TF_VALIDATE_ERRORS + 1))
      continue
    fi
    if ! terraform -chdir="$REPO_ROOT/$root" validate -no-color > /dev/null 2>&1; then
      echo "  FAIL: $root — terraform validate failed" >&2
      TF_VALIDATE_ERRORS=$((TF_VALIDATE_ERRORS + 1))
    fi
  done
  if [[ $TF_VALIDATE_ERRORS -eq 0 ]]; then
    echo "  PASS: terraform validate (${#TF_ROOTS[@]} roots)"
  else
    ERRORS=$((ERRORS + TF_VALIDATE_ERRORS))
  fi
fi

# --- Ansible syntax-check (full mode only) ---
# Must run from the ansible/ directory because ansible.cfg sets roles_path=roles
# (relative). Uses the dev inventory for syntax validation; the check is
# syntactic, not connectivity-dependent.
if ! $QUICK; then
  echo ""
  echo "--- Ansible syntax-check ---"
  ANSIBLE_DIR="$REPO_ROOT/ansible"
  if [[ -d "$ANSIBLE_DIR" ]]; then
    ANSIBLE_ERRORS=0
    ANSIBLE_TOTAL=0
    for inv in "$ANSIBLE_DIR"/inventories/*/hosts.yml; do
      for pb in "$ANSIBLE_DIR"/playbooks/*.yml; do
        ANSIBLE_TOTAL=$((ANSIBLE_TOTAL + 1))
        if ! (cd "$ANSIBLE_DIR" && ansible-playbook --syntax-check -i "$inv" "$pb" > /dev/null 2>&1); then
          ANSIBLE_ERRORS=$((ANSIBLE_ERRORS + 1))
          echo "  FAIL: $(basename "$pb") × $(basename "$(dirname "$(dirname "$inv")")")" >&2
        fi
      done
    done
    if [[ $ANSIBLE_ERRORS -eq 0 ]]; then
      echo "  PASS: ansible syntax-check ($ANSIBLE_TOTAL combinations)"
    else
      echo "  FAIL: $ANSIBLE_ERRORS/$ANSIBLE_TOTAL ansible syntax-check combinations failed" >&2
      ERRORS=$((ERRORS + ANSIBLE_ERRORS))
    fi
  else
    echo "  SKIP: no ansible/ directory found"
  fi
fi

# --- Shellcheck ---
echo ""
echo "--- Shellcheck ---"
mapfile -t SHELL_SCRIPTS < <(find "$REPO_ROOT" -name '*.sh' -not -path '*/.venv/*' -not -path '*/.git/*')
if [[ ${#SHELL_SCRIPTS[@]} -gt 0 ]]; then
  if shellcheck "${SHELL_SCRIPTS[@]}"; then
    echo "  PASS: shellcheck"
  else
    echo "  FAIL: shellcheck" >&2
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "  SKIP: no shell scripts found"
fi

# --- Summary ---
echo ""
if [[ $ERRORS -eq 0 ]]; then
  echo "=== All preflight checks passed ==="
else
  echo "=== $ERRORS preflight check(s) FAILED ===" >&2
  exit 1
fi
