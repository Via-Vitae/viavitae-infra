# SOPS Operations Runbook

**Audience.** Platform engineer managing SOPS-encrypted secrets. **Prerequisites:** `age` and `sops` installed, age private key available (from offline media or CI secret).

---

## Table of Contents

1. [Encrypt a file](#encrypt-a-file)
2. [Decrypt a file](#decrypt-a-file)
3. [Edit an encrypted file](#edit-an-encrypted-file)
4. [Rotate keys (rekey)](#rotate-keys-rekey)
5. [Operator offboarding](#operator-offboarding)
6. [Gate 6: Offline share splitting](#gate-6-offline-share-splitting)
7. [Troubleshooting](#troubleshooting)

---

## Encrypt a file

### Encrypt a new file

```bash
# Set the age key file (from offline media or CI secret)
export SOPS_AGE_KEY_FILE=/path/to/age-key.txt

# Encrypt a file (SOPS uses .sops.yaml to determine recipients)
sops --encrypt --in-place ansible/inventories/prod/group_vars/vault.sops.yml
```

### Verify encryption

```bash
# Check the file is encrypted (should contain "sops:" metadata)
head -5 ansible/inventories/prod/group_vars/vault.sops.yml
# Expected: sops:
#   version: 3.x.x
#   ...

# Run the encryption-coverage check
grep -q 'sops:' ansible/inventories/prod/group_vars/vault.sops.yml && echo "✓ Encrypted" || echo "✗ Not encrypted"
```

---

## Decrypt a file

### Decrypt for viewing

```bash
# Set the age key file
export SOPS_AGE_KEY_FILE=/path/to/age-key.txt

# Decrypt to stdout
sops --decrypt ansible/inventories/prod/group_vars/vault.sops.yml

# Decrypt to a file
sops --decrypt --output /tmp/vault-decrypted.yml ansible/inventories/prod/group_vars/vault.sops.yml
```

### ⚠️ Security warning

- Never commit decrypted files
- Never copy decrypted content to clipboard (use a secure password manager)
- Delete decrypted files immediately after use: `rm -f /tmp/vault-decrypted.yml`
- Decrypted files in CI logs are a secret leak (Gitleaks will catch them, but prevention is better)

---

## Edit an encrypted file

### Edit in place (recommended)

```bash
# Set the age key file
export SOPS_AGE_KEY_FILE=/path/to/age-key.txt

# Edit the file (SOPS decrypts to a temp file, opens in $EDITOR, re-encrypts on save)
sops ansible/inventories/prod/group_vars/vault.sops.yml
```

### Edit workflow

1. Run `sops <file>` — your `$EDITOR` opens with the decrypted content
2. Make changes in the editor
3. Save and close the editor — SOPS re-encrypts the file
4. Commit the encrypted file (never the decrypted content)

### Verify the edit

```bash
# Check the file is still encrypted
head -5 ansible/inventories/prod/group_vars/vault.sops.yml

# Decrypt and verify the changes
sops --decrypt ansible/inventories/prod/group_vars/vault.sops.yml | grep <changed-key>
```

---

## Rotate keys (rekey)

### When to rekey

- An operator leaves the team
- An age key is compromised
- Scheduled rotation (every 180 days per INFRA-001 M19)

### Rekey procedure

**Step 1: Generate new age keys** (if replacing an operator)

```bash
# Run the provisioning script
./scripts/provision-age-keys.sh --output-dir ./age-keys-rotation

# Note the new public keys
```

**Step 2: Update .sops.yaml and .sops-recipients.allowlist**

```bash
# Edit .sops.yaml — replace the old operator's public key with the new one
# Edit .sops-recipients.allowlist — update to match .sops.yaml
# Both files must be updated in the SAME PR (Gate 7 will diff them)
```

**Step 3: Re-encrypt all SOPS-governed files**

```bash
# Set the OLD age key file (to decrypt)
export SOPS_AGE_KEY_FILE=/path/to/old-age-key.txt

# Re-encrypt each SOPS-governed file
find ansible/inventories -name 'vault.sops.yml' -exec sops --rotate --in-place {} \;
find k8s/secrets -name '*.sops.yaml' -exec sops --rotate --in-place {} \;
find terraform -name '*.sops.tfvars' -exec sops --rotate --in-place {} \;
```

The `--rotate` flag decrypts with the old keys and re-encrypts with the new keys from `.sops.yaml`.

**Step 4: Verify**

```bash
# Set the NEW age key file (to decrypt)
export SOPS_AGE_KEY_FILE=/path/to/new-age-key.txt

# Verify decryption works with the new key
sops --decrypt ansible/inventories/prod/group_vars/vault.sops.yml > /dev/null && echo "✓ Rekey successful"

# Run Gate 8 (CI will do this automatically)
# Gate 8 encrypts with .sops.yaml recipients and decrypts with AGE_SECRET_KEY_CI
```

**Step 5: Commit**

```bash
git add .sops.yaml .sops-recipients.allowlist
git add ansible/inventories/*/group_vars/vault.sops.yml
git add k8s/secrets/**/*.sops.yaml
git add terraform/**/*.sops.tfvars
git commit -m "security: rotate age keys (operator offboarding / scheduled rotation)"
```

---

## Operator offboarding

When an operator leaves the team:

### Immediate actions (within 24 hours)

1. **Revoke access:**
   - Remove the operator from GitHub org
   - Remove their age public key from `.sops.yaml` and `.sops-recipients.allowlist`
   - Update `AGE_SECRET_KEY_CI` if they had access to the CI key

2. **Rekey all secrets:**
   - Follow the [rekey procedure](#rotate-keys-rekey) above
   - Generate a new operator key to replace the departing operator's key
   - Re-encrypt all SOPS-governed files with the new key set

3. **Verify:**
   - Confirm the departing operator's key can no longer decrypt secrets
   - Run Gate 8 in CI to verify the new trust model works

### Within 7 days

4. **Offline key ceremony:**
   - If the departing operator was a custodian of an offline share, retrieve their share
   - Perform a new M=2/N=3 split for the remaining operator keys
   - Update the custodian list in this runbook

5. **Audit:**
   - Review the operator's access logs (GitHub, Proxmox, Keycloak)
   - Check for any unusual decryption activity
   - Document the offboarding in the security log

---

## Gate 6: Offline share splitting

### Purpose

The two operator age keys (for prod) should be split using **Shamir's Secret Sharing** (M=2, N=3) so that:
- Any 2 of 3 shares can reconstruct the key
- No single share is sufficient to decrypt
- Loss of one custodian does not prevent recovery

### Procedure

**Step 1: Install a Shamir tool**

```bash
# Option A: ssss (Shamir's Secret Sharing Scheme)
sudo apt install ssss

# Option B: horcrux (Go-based, cross-platform)
go install github.com/Uniqkey/horcrux@latest
```

**Step 2: Split the operator key**

```bash
# Using ssss
cat /path/to/operator1.txt | ssss-split -n 3 -t 2

# Output:
# Enter secret to share:
# Generated 3 shares:
# 1-abc123...
# 2-def456...
# 3-ghi789...
```

**Step 3: Distribute shares**

- Give each share to a different trusted custodian (geographically separated)
- Each custodian stores their share on encrypted media (USB drive, password manager)
- Document the custodian list below

**Step 4: Record the ceremony**

| Key | Share | Custodian | Location | Date |
|---|---|---|---|---|
| operator1 | 1-abc123... | Alice | Zurich, CH | 2026-09-08 |
| operator1 | 2-def456... | Bob | Vilnius, LT | 2026-09-08 |
| operator1 | 3-ghi789... | Carol | Berlin, DE | 2026-09-08 |
| operator2 | 1-jkl012... | Alice | Zurich, CH | 2026-09-08 |
| operator2 | 2-mno345... | Bob | Vilnius, LT | 2026-09-08 |
| operator2 | 3-pqr678... | Carol | Berlin, DE | 2026-09-08 |

**Step 5: Test recovery**

```bash
# Retrieve any 2 shares (e.g., from Alice and Bob)
echo "1-abc123..." > /tmp/share1
echo "2-def456..." > /tmp/share2

# Reconstruct the key
sssss-combine -n 2 -t 2 < /tmp/share1 /tmp/share2 > /tmp/recovered-key.txt

# Verify the recovered key matches the original
diff /path/to/operator1.txt /tmp/recovered-key.txt && echo "✓ Recovery successful"

# Cleanup
rm -f /tmp/share1 /tmp/share2 /tmp/recovered-key.txt
```

---

## Troubleshooting

### "Failed to decrypt: no key found"

**Cause:** The age key file does not match any recipient in `.sops.yaml`.

**Fix:**
- Verify `SOPS_AGE_KEY_FILE` points to the correct key
- Check the public key in `.sops.yaml` matches the private key
- If the key was rotated, use the new key file

### "sops: command not found"

**Fix:**
```bash
# Install SOPS
curl -fsSL https://github.com/getsops/sops/releases/download/v3.13.3/sops-v3.13.3.linux.amd64 -o /usr/local/bin/sops
chmod +x /usr/local/bin/sops
```

### "age: command not found"

**Fix:**
```bash
# Install age
curl -fsSL https://dl.filippo.io/age/v1.2.0?for=linux/amd64 -o age.tar.gz
tar -xzf age.tar.gz
mv age/age age/age-keygen /usr/local/bin/
rm -rf age age.tar.gz
```

### Gate 7 fails: ".sops.yaml recipients do not match .sops-recipients.allowlist"

**Cause:** The two files are out of sync.

**Fix:**
- Update `.sops-recipients.allowlist` to match `.sops.yaml` (same age keys, same order)
- Both files must be updated in the same PR

### Gate 8 fails: "AGE_SECRET_KEY_CI is not set"

**Cause:** The CI age private key is not in GitHub Secrets.

**Fix:**
```bash
# Set the CI key in GitHub Secrets
gh secret set AGE_SECRET_KEY_CI < /path/to/ci-key.txt
```

---

## References

- [ADR-005: Secrets with SOPS and age, not Vault](../docs/architecture.md#adr-005-secrets-with-sops-and-age-not-vault-in-the-pilot)
- [INFRA-001 DPIA](DPIA-template.md#infra-001-infrastructure-platform-processing) (controls M19, condition C1)
- [scripts/provision-age-keys.sh](../scripts/provision-age-keys.sh)
- [.sops.yaml](../.sops.yaml)
- [.sops-recipients.allowlist](../.sops-recipients.allowlist)
- [security.yml workflow](../.github/workflows/security.yml) (Gate 7, Gate 8, encryption-coverage)
