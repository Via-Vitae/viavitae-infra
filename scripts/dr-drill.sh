#!/usr/bin/env bash
# DR drill script — validates backup restore capability
#
# USAGE:
#   ./scripts/dr-drill.sh --scenario <q1|q2> --tenant <slug> --scratch-vmid <vmid> [--confirm] [--dry-run]
#
# SCENARIOS:
#   q1: Single-tenant restore (PostgreSQL schema + workload volume)
#   q2: Full-instance restore (etcd snapshot + all tenant data)
#
# SAFETY:
#   - Requires --confirm flag for real execution
#   - Refuses to run on production hosts (hostname check)
#   - Uses scratch VMID range 950-959 (isolated from production)
#   - --dry-run mode validates the script without touching infrastructure

set -euo pipefail

# --- Configuration -------------------------------------------------------------

SCRIPT_NAME="$(basename "$0")"
DRILL_DATE="$(date +%Y-%m-%d)"
REPORT_DIR="backup/drills/reports"
REPORT_FILE="${REPORT_DIR}/dr-drill-${DRILL_DATE}.md"

# --- Argument parsing ----------------------------------------------------------

SCENARIO=""
TENANT=""
SCRATCH_VMid=""
CONFIRM=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario)
      SCENARIO="$2"
      shift 2
      ;;
    --tenant)
      TENANT="$2"
      shift 2
      ;;
    --scratch-vmid)
      SCRATCH_VMid="$2"
      shift 2
      ;;
    --confirm)
      CONFIRM=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help)
      echo "Usage: $SCRIPT_NAME --scenario <q1|q2> --tenant <slug> --scratch-vmid <vmid> [--confirm] [--dry-run]"
      echo ""
      echo "Scenarios:"
      echo "  q1: Single-tenant restore"
      echo "  q2: Full-instance restore"
      echo ""
      echo "Safety:"
      echo "  --confirm: Required for real execution"
      echo "  --dry-run: Validate script without touching infrastructure"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# --- Validation ----------------------------------------------------------------

if [[ -z "$SCENARIO" ]]; then
  echo "ERROR: --scenario is required (q1 or q2)"
  exit 1
fi

if [[ "$SCENARIO" != "q1" && "$SCENARIO" != "q2" ]]; then
  echo "ERROR: --scenario must be q1 or q2"
  exit 1
fi

if [[ "$SCENARIO" == "q1" && -z "$TENANT" ]]; then
  echo "ERROR: --tenant is required for q1 scenario"
  exit 1
fi

if [[ -z "$SCRATCH_VMid" ]]; then
  echo "ERROR: --scratch-vmid is required (range 950-959)"
  exit 1
fi

if [[ "$SCRATCH_VMid" -lt 950 || "$SCRATCH_VMid" -gt 959 ]]; then
  echo "ERROR: --scratch-vmid must be in range 950-959"
  exit 1
fi

# Check if running on production host
HOSTNAME="$(hostname)"
if [[ "$HOSTNAME" == *prod* ]]; then
  echo "ERROR: This script refuses to run on production hosts (hostname: $HOSTNAME)"
  echo "       Run from a staging or dev environment"
  exit 1
fi

if [[ "$CONFIRM" != true && "$DRY_RUN" != true ]]; then
  echo "ERROR: --confirm or --dry-run is required"
  echo "       Use --dry-run to validate the script without touching infrastructure"
  exit 1
fi

# --- Drill execution -----------------------------------------------------------

mkdir -p "$REPORT_DIR"

echo "=== DR Drill — $DRILL_DATE ==="
echo "Scenario: $SCENARIO"
echo "Tenant: ${TENANT:-N/A}"
echo "Scratch VMID: $SCRATCH_VMid"
echo "Mode: $(if [[ "$DRY_RUN" == true ]]; then echo "DRY RUN"; else echo "LIVE"; fi)"
echo ""

if [[ "$DRY_RUN" == true ]]; then
  echo "[DRY RUN] Would execute scenario $SCENARIO"
  echo "[DRY RUN] No infrastructure changes made"
  echo ""
  echo "To execute the real drill, remove --dry-run and add --confirm"
  
  # Write dry-run report
  cat > "$REPORT_FILE" <<EOF
# DR Drill Report — $DRILL_DATE

**Status:** DRY RUN (not executed)  
**Scenario:** $SCENARIO  
**Tenant:** ${TENANT:-N/A}  
**Scratch VMID:** $SCRATCH_VMid  

## Summary

This is a dry-run report. The drill script was validated but no infrastructure changes were made.

## Next Steps

1. Review the drill script: \`scripts/dr-drill.sh\`
2. Schedule a maintenance window for the real drill
3. Run with \`--confirm\` (without \`--dry-run\`) to execute
4. Update this report with the real drill results

## Real Drill Commands

\`\`\`bash
# Q1: Single-tenant restore
./scripts/dr-drill.sh --scenario q1 --tenant $TENANT --scratch-vmid $SCRATCH_VMid --confirm

# Q2: Full-instance restore
./scripts/dr-drill.sh --scenario q2 --scratch-vmid $SCRATCH_VMid --confirm
\`\`\`
EOF
  
  echo "✓ Dry-run report written to $REPORT_FILE"
  exit 0
fi

# --- Live drill ----------------------------------------------------------------

echo "=== Starting live drill ==="
echo ""

if [[ "$SCENARIO" == "q1" ]]; then
  echo "Q1: Single-tenant restore"
  echo "  1. Restore PostgreSQL schema for tenant '$TENANT' from offsite backup"
  echo "  2. Restore workload volume to scratch VM $SCRATCH_VMid"
  echo "  3. Validate data integrity"
  echo "  4. Record timings and results"
  # TODO: Implement actual restore logic (requires Proxmox API, WAL-G, etc.)
  echo "  [PLACEHOLDER: implement restore logic]"
  
elif [[ "$SCENARIO" == "q2" ]]; then
  echo "Q2: Full-instance restore"
  echo "  1. Restore etcd snapshot from offsite backup"
  echo "  2. Restore all tenant data"
  echo "  3. Validate cluster health"
  echo "  4. Record timings and results"
  # TODO: Implement actual restore logic
  echo "  [PLACEHOLDER: implement restore logic]"
fi

# --- Report generation ---------------------------------------------------------

cat > "$REPORT_FILE" <<EOF
# DR Drill Report — $DRILL_DATE

**Status:** Executed  
**Scenario:** $SCENARIO  
**Tenant:** ${TENANT:-N/A}  
**Scratch VMID:** $SCRATCH_VMid  
**Duration:** [TODO: measure duration]  

## Summary

[TODO: write summary of drill results]

## Timings

| Phase | Duration |
|---|---|
| Backup retrieval | [TODO] |
| Restore | [TODO] |
| Validation | [TODO] |
| **Total** | [TODO] |

## Validation Results

[TODO: document validation checks and results]

## Issues Encountered

[TODO: document any issues or deviations from expected behavior]

## Lessons Learned

[TODO: document lessons learned and action items]

## Sign-Off

| Role | Name | Date |
|---|---|---|
| Drill executor | [TODO] | $DRILL_DATE |
| Reviewer | [TODO] | [TODO] |
EOF

echo "✓ Drill report written to $REPORT_FILE"
echo ""
echo "=== Drill complete ==="

# Update symlink to latest report
ln -sf "$(basename "$REPORT_FILE")" backup/drills/last-drill-report.md
echo "✓ Updated last-drill-report.md symlink"
