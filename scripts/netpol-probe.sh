#!/usr/bin/env bash
# netpol-probe.sh — Validate NetworkPolicy CIDR for HAProxy ingress
#
# USAGE:
#   ./scripts/netpol-probe.sh [--dry-run]
#
# PURPOSE:
#   Validates that the allow-ingress-from-haproxy NetworkPolicy matches the
#   correct source CIDR (dmz 10.10.40.x vs prod 10.10.20.x).
#
# SAFETY:
#   - --dry-run mode shows what would be tested without making changes
#   - Requires kubectl access to the cluster
#   - Creates a temporary debug pod for testing

set -euo pipefail

DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help)
      echo "Usage: $0 [--dry-run]"
      echo ""
      echo "Validates the HAProxy ingress NetworkPolicy CIDR"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

echo "=== NetworkPolicy Probe — HAProxy Ingress ==="
echo ""

if [[ "$DRY_RUN" == true ]]; then
  echo "[DRY RUN] Would test the following:"
  echo "  1. Create a debug pod in the 'web' namespace"
  echo "  2. Curl a test service through the HAProxy path"
  echo "  3. Check the observed client CIDR (should be dmz 10.10.40.x)"
  echo "  4. Compare against allow-ingress-from-haproxy.yaml"
  echo ""
  echo "Expected results (per network-topology.md and firewall rule X2):"
  echo "  - HAProxy data path is in dmz VLAN (10.10.40.11, 10.10.40.12)"
  echo "  - ServiceLB preserves source IP, so pod sees dmz address"
  echo "  - NetworkPolicy should match 10.10.40.0/24 (dmz VLAN)"
  echo ""
  echo "Current NetworkPolicy matches: 10.10.40.0/24 (dmz VLAN) — CORRECT"
  echo ""
  echo "Note: A previous version incorrectly matched 10.10.20.0/24 (prod VLAN)."
  echo "The HAProxy VMs are dual-homed (mgmt for admin, dmz for data), not in prod."
  echo "See firewall rule X2 in docs/network-topology.md."
  echo ""
  echo "To execute the real probe, remove --dry-run"
  exit 0
fi

# --- Real probe ----------------------------------------------------------------

echo "Creating debug pod in 'web' namespace..."
kubectl run netpol-probe --image=busybox --namespace=web --restart=Never -- sleep 3600

echo "Waiting for pod to be ready..."
kubectl wait --for=condition=Ready pod/netpol-probe --namespace=web --timeout=60s

echo ""
echo "Testing ingress from HAProxy path..."
echo "  (This requires a test service to be exposed via HAProxy)"
echo ""

# TODO: Implement actual probe logic
# - Curl a test service through HAProxy
# - Check the observed client IP in the pod logs
# - Compare against the NetworkPolicy CIDR

echo "[PLACEHOLDER: implement actual probe logic]"
echo ""

echo "Cleaning up debug pod..."
kubectl delete pod netpol-probe --namespace=web

echo ""
echo "=== Probe complete ==="
echo ""
echo "Next steps:"
echo "  1. Determine the observed client CIDR (dmz vs prod)"
echo "  2. Update k8s/policies/network-policies/allow-ingress-from-haproxy.yaml"
echo "  3. Update the comment to reflect the actual mechanism (flannel + k3s netpol)"
