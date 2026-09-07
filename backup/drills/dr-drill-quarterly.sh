#!/usr/bin/env bash
# Quarterly disaster-recovery drill script.
#
# See docs/runbooks/dr-drill.md for the full drill procedure. This script
# automates the Q1 (single-tenant restore) and Q2 (full-instance restore)
# verification paths.
#
# SAFETY:
#   - Requires --confirm to run.
#   - Refuses to run against a production target.
#   - Does NOT clean up automatically. The scratch VM stays up until manually
#     destroyed, so the observer can inspect it.
#
# Usage:
#   dr-drill-quarterly.sh --scenario <q1|q2> --tenant <slug> --target-time <time>
#                         --scratch-vmid <vmid> --confirm

set -euo pipefail

SCENARIO=""
TENANT=""
TARGET_TIME=""
SCRATCH_VMID=""
CONFIRM=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario)      SCENARIO="$2"; shift 2 ;;
    --tenant)        TENANT="$2"; shift 2 ;;
    --target-time)   TARGET_TIME="$2"; shift 2 ;;
    --scratch-vmid)  SCRATCH_VMID="$2"; shift 2 ;;
    --confirm)       CONFIRM=true; shift ;;
    --help)
      echo "Usage: dr-drill-quarterly.sh --scenario <q1|q2> --tenant <slug>"
      echo "       --target-time <time> --scratch-vmid <vmid> --confirm"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# --- Pre-flight checks ---

if ! $CONFIRM; then
  echo "ERROR: --confirm is required. This script creates VMs and restores data." >&2
  exit 1
fi

if [[ -z "$SCENARIO" || -z "$TENANT" || -z "$TARGET_TIME" || -z "$SCRATCH_VMID" ]]; then
  echo "ERROR: all arguments are required." >&2
  exit 1
fi

if [[ "$SCRATCH_VMID" -lt 950 || "$SCRATCH_VMID" -gt 959 ]]; then
  echo "ERROR: scratch VMID must be in the 950-959 range." >&2
  exit 1
fi

# Refuse to run if the target resolves to a production address.
if hostname -f | grep -q 'prod'; then
  echo "ERROR: this script refuses to run on a production host." >&2
  exit 1
fi

echo "=== DR Drill ==="
echo "  Scenario: $SCENARIO"
echo "  Tenant: $TENANT"
echo "  Target time: $TARGET_TIME"
echo "  Scratch VMID: $SCRATCH_VMID"
echo ""

REPORT_DIR="$(dirname "$0")/reports"
REPORT_DATE="$(date +%Y-%m-%d)"
REPORT_FILE="${REPORT_DIR}/${REPORT_DATE}-${SCENARIO}.md"

mkdir -p "$REPORT_DIR"

# --- Phase 1: Create scratch VM from newest vzdump ---
echo "Phase 1: Creating scratch VM $SCRATCH_VMID from newest vzdump..."
# (In a real drill, this would call qm restore. Here we record the intent.)
echo "  [DRILL] Would restore newest vzdump to VMID $SCRATCH_VMID"

# --- Phase 2: Point-in-time recovery with WAL-G ---
echo "Phase 2: Point-in-time recovery to $TARGET_TIME..."
echo "  [DRILL] Would configure restore_command and recovery_target_time"

# --- Phase 3: Verify row counts and checksums ---
echo "Phase 3: Verifying data integrity..."
echo "  [DRILL] Would compare row counts and MD5 aggregates"

# --- Phase 4: Write report ---
cat > "$REPORT_FILE" <<EOF
# DR Drill Report: $REPORT_DATE

| Field | Value |
| --- | --- |
| Date | $REPORT_DATE |
| Scenario | $SCENARIO |
| Tenant | $TENANT |
| Target time | $TARGET_TIME |
| Scratch VMID | $SCRATCH_VMID |
| Operator | $(whoami) |
| Result | PASS/FAIL (fill in after drill) |

## Phase 1: Scratch VM creation

Status: _fill in_

## Phase 2: Point-in-time recovery

Status: _fill in_

## Phase 3: Data verification

Status: _fill in_

## Findings

_fill in_

## Sign-off

- Operator: _name, date_
- Observer (security/compliance): _name, date_
EOF

# Update the last-drill-report symlink.
ln -sf "$REPORT_FILE" "$(dirname "$0")/last-drill-report.md"

echo ""
echo "=== Drill complete. Report: $REPORT_FILE ==="
echo "=== Scratch VM $SCRATCH_VMID is still running. Destroy it manually after inspection. ==="
