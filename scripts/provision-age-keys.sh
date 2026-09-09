#!/usr/bin/env bash
# provision-age-keys.sh — Generate age identities for SOPS secret management
#
# This script generates the age keys required for the SOPS trust model:
#   - 2 operator identities (human custodians for prod)
#   - 1 CI identity (for automated encryption/decryption in CI)
#
# USAGE:
#   ./scripts/provision-age-keys.sh [--output-dir <path>]
#
# OUTPUT:
#   - Public keys printed to stdout (copy these to .sops.yaml)
#   - Private keys written to <output-dir>/<name>.txt (mode 600)
#
# HUMAN ACTIONS (this script does NOT do these):
#   - Copy the public keys to .sops.yaml and .sops-recipients.allowlist
#   - Store the CI private key in GitHub Secrets as AGE_SECRET_KEY_CI
#   - Perform the offline M=2/N=3 share splitting for operator keys (Gate 6)
#   - Seal the offline copies in an envelope with the written procedure
#
# SECURITY:
#   - Private keys are written with mode 600 (owner read/write only)
#   - The output directory should be on encrypted storage
#   - After copying the public keys, move the private keys to offline media
#   - Delete the private keys from this machine after the ceremony
#
# GATE 6 (Offline share splitting):
#   The two operator keys should be split using Shamir's Secret Sharing (M=2, N=3)
#   so that any 2 of 3 shares can reconstruct the key, but no single share is sufficient.
#   This protects against loss of a single key custodian while preventing any single
#   person from decrypting prod secrets alone. See docs/runbooks/sops-operations.md
#   for the written procedure.

set -euo pipefail

# --- Configuration -------------------------------------------------------------

OUTPUT_DIR="./age-keys"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# --- Argument parsing ----------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--output-dir <path>]"
      exit 1
      ;;
  esac
done

# --- Preflight checks ----------------------------------------------------------

echo "=== SOPS age key provisioning ==="
echo ""

# Check age is installed
if ! command -v age-keygen &> /dev/null; then
  echo "ERROR: age-keygen not found in PATH"
  echo "       Install age: https://github.com/FiloSottile/age#installation"
  exit 1
fi
echo "✓ age installed: $(age-keygen --version 2>&1 | head -1)"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chmod 700 "$OUTPUT_DIR"
echo "✓ Output directory: $OUTPUT_DIR (mode 700)"
echo ""

# --- Key generation ------------------------------------------------------------

echo "=== Generating age identities ==="
echo ""

# Operator 1 (human custodian for prod)
OPERATOR1_KEY="$OUTPUT_DIR/operator1-$TIMESTAMP.txt"
age-keygen -o "$OPERATOR1_KEY" 2>&1 | grep "Public key:" | awk '{print $3}' > "$OPERATOR1_KEY.pub"
chmod 600 "$OPERATOR1_KEY"
OPERATOR1_PUB=$(cat "$OPERATOR1_KEY.pub")
echo "✓ Operator 1 key generated"
echo "  Public key: $OPERATOR1_PUB"
echo "  Private key: $OPERATOR1_KEY (mode 600)"
echo ""

# Operator 2 (human custodian for prod)
OPERATOR2_KEY="$OUTPUT_DIR/operator2-$TIMESTAMP.txt"
age-keygen -o "$OPERATOR2_KEY" 2>&1 | grep "Public key:" | awk '{print $3}' > "$OPERATOR2_KEY.pub"
chmod 600 "$OPERATOR2_KEY"
OPERATOR2_PUB=$(cat "$OPERATOR2_KEY.pub")
echo "✓ Operator 2 key generated"
echo "  Public key: $OPERATOR2_PUB"
echo "  Private key: $OPERATOR2_KEY (mode 600)"
echo ""

# CI identity (for automated encryption/decryption in CI)
CI_KEY="$OUTPUT_DIR/ci-$TIMESTAMP.txt"
age-keygen -o "$CI_KEY" 2>&1 | grep "Public key:" | awk '{print $3}' > "$CI_KEY.pub"
chmod 600 "$CI_KEY"
CI_PUB=$(cat "$CI_KEY.pub")
echo "✓ CI identity generated"
echo "  Public key: $CI_PUB"
echo "  Private key: $CI_KEY (mode 600)"
echo ""

# --- Summary -------------------------------------------------------------------

echo "=== Public keys (copy to .sops.yaml and .sops-recipients.allowlist) ==="
echo ""
echo "# .sops.yaml creation rules:"
echo "#   - ansible/inventories/.*/group_vars/vault\\.sops\\.yml\$"
echo "#     age: >-"
echo "#       $OPERATOR1_PUB,"
echo "#       $OPERATOR2_PUB"
echo "#"
echo "#   - k8s/secrets/.*\\.sops\.yaml\$"
echo "#     age: >-"
echo "#       $CI_PUB,"
echo "#       $OPERATOR1_PUB,"
echo "#       $OPERATOR2_PUB"
echo "#"
echo "#   - terraform/.*\\.sops\.tfvars\$"
echo "#     age: >-"
echo "#       $CI_PUB,"
echo "#       $OPERATOR1_PUB,"
echo "#       $OPERATOR2_PUB"
echo ""
echo "# .sops-recipients.allowlist (one per line, in same order as .sops.yaml):"
echo "$OPERATOR1_PUB"
echo "$OPERATOR2_PUB"
echo "$CI_PUB"
echo "$OPERATOR1_PUB"
echo "$OPERATOR2_PUB"
echo "$CI_PUB"
echo "$OPERATOR1_PUB"
echo "$OPERATOR2_PUB"
echo ""

echo "=== Next steps (HUMAN ACTIONS) ==="
echo ""
echo "1. Copy the public keys above to .sops.yaml and .sops-recipients.allowlist"
echo "   (both files must be updated in the SAME PR — Gate 7 will diff them)"
echo ""
echo "2. Store the CI private key in GitHub Secrets:"
echo "   gh secret set AGE_SECRET_KEY_CI < $CI_KEY"
echo "   (The CI key is needed for Gate 8 round-trip verification)"
echo ""
echo "3. Perform offline M=2/N=3 share splitting for operator keys (Gate 6):"
echo "   - Use a Shamir's Secret Sharing tool (e.g., 'ssss' or 'horcrux')"
echo "   - Split each operator key into 3 shares with threshold M=2"
echo "   - Distribute shares to 3 trusted custodians (geographically separated)"
echo "   - Document the procedure in docs/runbooks/sops-operations.md"
echo ""
echo "4. Move private keys to offline media:"
echo "   - Copy $OPERATOR1_KEY, $OPERATOR2_KEY, $CI_KEY to encrypted USB drives"
echo "   - Store the drives in separate physical locations (e.g., safe deposit boxes)"
echo "   - Delete the private keys from this machine:"
echo "     rm -f $OUTPUT_DIR/*.txt"
echo "   - Keep only the .pub files for reference"
echo ""
echo "5. Commit .sops.yaml and .sops-recipients.allowlist in a security-reviewed PR"
echo "   (Gate 7 will verify they match)"
echo ""
echo "6. After merge, Gate 8 will verify the CI key can decrypt real secrets"
echo ""

echo "=== Key ceremony complete ==="
echo ""
echo "Private keys are in: $OUTPUT_DIR/"
echo "  - $OPERATOR1_KEY"
echo "  - $OPERATOR2_KEY"
echo "  - $CI_KEY"
echo ""
echo "⚠️  WARNING: Delete these private keys from this machine after the ceremony!"
echo "    They should only exist on offline media (encrypted USB drives)."
