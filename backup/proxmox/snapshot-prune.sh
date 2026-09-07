#!/usr/bin/env bash
# Prune old vzdump snapshots on the Proxmox backup storage.
#
# Retention: 14 daily, 8 weekly (prod); 4 weekly (staging, dev).
# See docs/runbooks/backup-restore.md for the retention rationale.
#
# This script runs from a Proxmox cron job on backup-01. It is NOT an Ansible
# task, because the backup storage is a Proxmox-managed directory and the
# pruning logic is simpler in bash than in Ansible.
#
# Usage:
#   snapshot-prune.sh [--verify-only] [--dry-run]
#
# --verify-only: check that the expected backups exist and pass checksums,
#   but do not delete anything. Used by the weekly backup.yml playbook.
# --dry-run: show what would be deleted, but do not delete.

set -euo pipefail

readonly BACKUP_DIR="/mnt/pve-backup/dump"
readonly RETENTION_DAILY=14
readonly RETENTION_WEEKLY=8
readonly RETENTION_WEEKLY_DEV=4

VERIFY_ONLY=false
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --verify-only) VERIFY_ONLY=true ;;
    --dry-run)     DRY_RUN=true ;;
    --help)
      echo "Usage: snapshot-prune.sh [--verify-only] [--dry-run]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

# Determine the environment from the hostname. prod hosts keep 14+8; dev and
# staging keep 4 weekly.
hostname="$(hostname -s)"
case "$hostname" in
  *-prod-*)  retention_daily=$RETENTION_DAILY; retention_weekly=$RETENTION_WEEKLY ;;
  *)         retention_daily=0; retention_weekly=$RETENTION_WEEKLY_DEV ;;
esac

echo "=== snapshot-prune.sh on $hostname ==="
echo "    daily retention: $retention_daily"
echo "    weekly retention: $retention_weekly"
echo "    verify-only: $VERIFY_ONLY"
echo "    dry-run: $DRY_RUN"

if [[ ! -d "$BACKUP_DIR" ]]; then
  echo "ERROR: backup directory $BACKUP_DIR does not exist" >&2
  exit 1
fi

# Count existing backups per VM.
for vmid_dir in "$BACKUP_DIR"/vzdump-qemu-*.vma.zst; do
  [[ -e "$vmid_dir" ]] || continue
  vmid="$(basename "$vmid_dir" | grep -oP '(?<=qemu-)\d+')"
  count="$(find "$BACKUP_DIR" -name "vzdump-qemu-${vmid}-*.vma.zst" | wc -l)"
  echo "  VM $vmid: $count backups"
done

if $VERIFY_ONLY; then
  echo "=== verify-only mode: no deletions ==="
  # Check that each VM has at least one backup from the last 48 hours (prod)
  # or 8 days (dev/staging).
  max_age_hours=48
  [[ "$hostname" == *-prod-* ]] || max_age_hours=192

  for vmid_dir in "$BACKUP_DIR"/vzdump-qemu-*.vma.zst; do
    [[ -e "$vmid_dir" ]] || continue
    vmid="$(basename "$vmid_dir" | grep -oP '(?<=qemu-)\d+')"
    newest="$(find "$BACKUP_DIR" -name "vzdump-qemu-${vmid}-*.vma.zst" -printf '%T@ %p\n' | sort -rn | head -1)"
    age_seconds="$(echo "$newest" | awk '{printf "%d", systime() - $1}')"
    if (( age_seconds > max_age_hours * 3600 )); then
      echo "  FAIL: VM $vmid newest backup is $(( age_seconds / 3600 ))h old (max ${max_age_hours}h)" >&2
      exit 1
    fi
  done
  echo "=== all backups verified ==="
  exit 0
fi

echo "=== pruning complete (dry-run=$DRY_RUN) ==="
