# Runbook: MinIO State Backend Bootstrap

**This runbook must be completed before the first `terraform init` against the new MinIO backend.** Terraform cannot create its own state bucket — the bucket must exist before Terraform can use it. This is the classic bootstrap paradox.

---

## Purpose

[`terraform/backend.tf`](../terraform/backend.tf) declares an S3-compatible backend for remote state. The backend requires a bucket, versioning, encryption, and specific security settings. If a Terraform run is executed before the backend is configured, the run will fail because the bucket doesn't exist yet. This runbook documents the manual steps to provision the MinIO state backend.

**This runbook is executed once, before the first deploy, and then only when bucket policy changes are needed.** After the initial setup, the state bucket should not be touched again except through Terraform itself.

---

## Prerequisites

| Requirement | Detail |
|---|---|
| **Proxmox access** | You must have access to a Proxmox node that is **not** part of the workload cluster (e.g., a separate physical host, or a different rack). This is the "state-01" VM. |
| **MinIO binary** | Download the pinned MinIO release from <https://dl.min.io/server/minio/release/linux-amd64/minio>. Verify the SHA-256 checksum against the official release. |
| **`mc` CLI** | Download the MinIO Client from <https://dl.min.io/client/mc/release/linux-amd64/mc>. Verify the SHA-256 checksum. |
| **TLS certificates** | Generate TLS certificates for `minio-state-01.viavitae.internal` using the internal CA (see `k8s/ingress/cert-manager/`). |
| **Network access** | The Terraform runners (on the `mgmt` VLAN) must have network access to `minio-state-01.viavitae.internal:9000`. |

---

## Step 1: Provision the `state-01` VM

The `state-01` VM must be on a **separate Proxmox node** (not the workload cluster) to satisfy the "state must not live on the infrastructure it describes" constraint (QODER.md Rule 8, ADR-010).

### VM Specifications

| Resource | Value |
|---|---|
| **VMID** | Allocate from the shared infrastructure block (900–999) — e.g., 950 |
| **vCPUs** | 2 |
| **RAM** | 4 GB |
| **Disk** | 100 GB (ZFS, encrypted) |
| **OS** | Debian 12 (minimal) |
| **Network** | `mgmt` VLAN (10.10.10.0/24), static IP (e.g., 10.10.10.50) |

### Provisioning

1. Create the VM via the Proxmox UI or `qm create` command.
2. Install Debian 12 minimal.
3. Apply the `common` and `hardening` Ansible roles (SSH, auditd, fail2ban, AIDE).
4. Assign a static IP and DNS name: `minio-state-01.viavitae.internal` → 10.10.10.50.
5. Verify network access from the Terraform runners:
   ```bash
   # From runner-01 (mgmt VLAN)
   nc -zv minio-state-01.viavitae.internal 9000
   ```

---

## Step 2: Install MinIO

### Download and verify

```bash
# On state-01
cd /tmp

# Download MinIO server (pin the version — check https://dl.min.io/server/minio/release/linux-amd64/)
MINIO_VERSION="2026-09-01T01-02-03Z"  # Replace with the actual pinned version
curl -fsSL "https://dl.min.io/server/minio/release/linux-amd64/archive/minio.${MINIO_VERSION}" -o minio
curl -fsSL "https://dl.min.io/server/minio/release/linux-amd64/archive/minio.${MINIO_VERSION}.sha256sum" -o minio.sha256sum

# Verify checksum
sha256sum --check minio.sha256sum

# Install
chmod +x minio
mv minio /usr/local/bin/

# Download mc CLI
curl -fsSL "https://dl.min.io/client/mc/release/linux-amd64/mc" -o mc
curl -fsSL "https://dl.min.io/client/mc/release/linux-amd64/mc.sha256sum" -o mc.sha256sum
sha256sum --check mc.sha256sum
chmod +x mc
mv mc /usr/local/bin/
```

### Create MinIO service account

```bash
useradd -r -s /sbin/nologin minio-user
mkdir -p /data/minio
chown minio-user:minio-user /data/minio
```

### Configure TLS

Place the TLS certificates in `/etc/minio/certs/`:

```bash
mkdir -p /etc/minio/certs
cp /path/to/internal-ca-cert.pem /etc/minio/certs/public.crt
cp /path/to/internal-ca-key.pem /etc/minio/certs/private.key
chown -R minio-user:minio-user /etc/minio/certs
chmod 600 /etc/minio/certs/private.key
```

### Create systemd service

```bash
cat > /etc/systemd/system/minio.service <<'EOF'
[Unit]
Description=MinIO Object Storage
After=network.target

[Service]
User=minio-user
Group=minio-user
ExecStart=/usr/local/bin/minio server /data/minio --console-address ":9001" --address ":9000"
Restart=always
LimitNOFILE=65536
Environment=MINIO_ROOT_USER=minio-admin
Environment=MINIO_ROOT_PASSWORD=<generate-a-strong-password>

[Install]
WantedBy=multi-user.target
EOF
```

**Replace `<generate-a-strong-password>` with a strong, randomly generated password.** Store it in a secure location (e.g., a password manager). This is the MinIO root credentials — treat it like a database root password.

### Start MinIO

```bash
systemctl daemon-reload
systemctl enable minio
systemctl start minio
systemctl status minio
```

### Verify MinIO is running

```bash
# Check the service
systemctl status minio

# Check the API endpoint (from state-01)
curl -k https://localhost:9000/minio/health/live

# Check the console (from state-01)
curl -k https://localhost:9001/
```

---

## Step 3: Configure `mc` CLI

On your **local workstation** (not state-01), configure the `mc` CLI to connect to MinIO:

```bash
# Alias the MinIO instance
mc alias set minio-state \
  https://minio-state-01.viavitae.internal:9000 \
  minio-admin \
  <the-root-password-from-step-2>

# Verify connectivity
mc admin info minio-state
```

---

## Step 4: Create the State Buckets

Create one bucket per Terraform root (global, dev, staging, prod):

```bash
# Create buckets
mc mb minio-state/viavitae-tfstate-global
mc mb minio-state/viavitae-tfstate-dev
mc mb minio-state/viavitae-tfstate-staging
mc mb minio-state/viavitae-tfstate-prod

# Enable versioning (required for Terraform state)
mc version enable minio-state/viavitae-tfstate-global
mc version enable minio-state/viavitae-tfstate-dev
mc version enable minio-state/viavitae-tfstate-staging
mc version enable minio-state/viavitae-tfstate-prod

# Enable object lock (WORM, prevents accidental deletion)
mc lock enable minio-state/viavitae-tfstate-global
mc lock enable minio-state/viavitae-tfstate-dev
mc lock enable minio-state/viavitae-tfstate-staging
mc lock enable minio-state/viavitae-tfstate-prod
```

---

## Step 5: Block Public Access

MinIO does not have a direct "block public access" setting like AWS S3, but we can ensure the buckets are not publicly accessible by:

1. **Not creating any public policies** (the default is private).
2. **Restricting network access** via firewall rules (only `mgmt` VLAN can reach port 9000).

Verify the buckets are private:

```bash
# Check bucket policy (should be empty/private)
mc anonymous get minio-state/viavitae-tfstate-global
mc anonymous get minio-state/viavitae-tfstate-dev
mc anonymous get minio-state/viavitae-tfstate-staging
mc anonymous get minio-state/viavitae-tfstate-prod
```

---

## Step 6: Create Per-Environment Credentials

Create separate access keys for each environment (least-privilege):

```bash
# Generate access keys for each environment
# Global (read-only for drift detection)
mc admin user add minio-state terraform-global <generate-a-strong-password>
mc admin policy attach minio-state read-only --user terraform-global

# Dev (read-write)
mc admin user add minio-state terraform-dev <generate-a-strong-password>
mc admin policy attach minio-state readwrite --user terraform-dev

# Staging (read-write)
mc admin user add minio-state terraform-staging <generate-a-strong-password>
mc admin policy attach minio-state readwrite --user terraform-staging

# Prod (read-write)
mc admin user add minio-state terraform-prod <generate-a-strong-password>
mc admin policy attach minio-state readwrite --user terraform-prod
```

**Replace `<generate-a-strong-password>` with strong, randomly generated passwords for each user.** Store them in a secure location (e.g., a password manager). These credentials will be stored in GitHub Environments (see Step 7).

### Create per-bucket policies (optional, for stricter isolation)

If you want stricter isolation (each environment can only access its own bucket), create custom policies:

```bash
# Create a policy for dev bucket only
cat > /tmp/dev-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:*"],
      "Resource": [
        "arn:aws:s3:::viavitae-tfstate-dev",
        "arn:aws:s3:::viavitae-tfstate-dev/*"
      ]
    }
  ]
}
EOF

mc admin policy create minio-state terraform-dev-policy /tmp/dev-policy.json
mc admin policy attach minio-state terraform-dev-policy --user terraform-dev

# Repeat for staging and prod (adjust bucket name)
```

---

## Step 7: Store Credentials in GitHub Environments

The Terraform workflows (`.github/workflows/deploy.yml`) need the MinIO credentials to run `terraform init`. Store them in GitHub Environments:

| Environment | Secrets |
|---|---|
| `global-apply` | `MINIO_ENDPOINT`, `MINIO_ACCESS_KEY` (terraform-global), `MINIO_SECRET_KEY` |
| `dev-apply` | `MINIO_ENDPOINT`, `MINIO_ACCESS_KEY` (terraform-dev), `MINIO_SECRET_KEY` |
| `staging-apply` | `MINIO_ENDPOINT`, `MINIO_ACCESS_KEY` (terraform-staging), `MINIO_SECRET_KEY` |
| `prod-apply` | `MINIO_ENDPOINT`, `MINIO_ACCESS_KEY` (terraform-prod), `MINIO_SECRET_KEY` |

Set `MINIO_ENDPOINT` to `https://minio-state-01.viavitae.internal:9000`.

**For the plan/drift jobs** (which use read-only credentials), store the `terraform-global` credentials at the repository level (not environment-scoped).

---

## Step 8: Verify the Setup

After completing the steps above, verify the setup:

### 1. Check bucket versioning

```bash
mc version get minio-state/viavitae-tfstate-global
mc version get minio-state/viavitae-tfstate-dev
mc version get minio-state/viavitae-tfstate-staging
mc version get minio-state/viavitae-tfstate-prod
```

**Expected output**: `Versioning is enabled`

### 2. Check bucket encryption

```bash
mc encrypt get minio-state/viavitae-tfstate-global
```

**Expected output**: `Auto encryption is enabled` (SSE-S3)

### 3. Check object lock

```bash
mc lock get minio-state/viavitae-tfstate-global
```

**Expected output**: `Object lock is enabled`

### 4. Test write access (dev)

```bash
# From your local workstation
echo "test" > /tmp/test.txt
mc cp /tmp/test.txt minio-state/viavitae-tfstate-dev/test.txt
mc cat minio-state/viavitae-tfstate-dev/test.txt
mc rm minio-state/viavitae-tfstate-dev/test.txt
```

**Expected**: File uploads, reads, and deletes successfully.

### 5. Test read-only access (global)

```bash
# Configure the global alias
mc alias set minio-global \
  https://minio-state-01.viavitae.internal:9000 \
  terraform-global \
  <the-global-password>

# Try to write (should fail)
mc cp /tmp/test.txt minio-global/viavitae-tfstate-global/test.txt
```

**Expected**: `Access denied` error.

### 6. Test network isolation

```bash
# From a host in the dmz VLAN (should fail)
nc -zv minio-state-01.viavitae.internal 9000

# From a host in the prod VLAN (should fail)
nc -zv minio-state-01.viavitae.internal 9000

# From a host in the mgmt VLAN (should succeed)
nc -zv minio-state-01.viavitae.internal 9000
```

**Expected**: Only `mgmt` VLAN hosts can reach MinIO.

---

## Step 9: Update Terraform Backend Configuration

After the MinIO backend is provisioned, update the Terraform backend configuration:

1. Edit `terraform/backend.tf` (and `terraform/envs/*/backend.tf`) to point at the new MinIO endpoint.
2. Run `terraform init -reconfigure` to reinitialize the backend.
3. Run `terraform plan` to verify the state is accessible.

See [ADR-010](../adr/ADR-010-state-backend-residency.md) for the decision rationale.

---

## Step 10: Freeze the AWS S3 Bucket (Rollback Window)

After successfully migrating to MinIO:

1. Set the AWS S3 bucket to **read-only** (update the bucket policy to deny `s3:PutObject`, `s3:DeleteObject`).
2. Keep the bucket frozen for **30 days** as a rollback window.
3. After 30 days, delete the AWS S3 bucket (completing the AWS removal).

---

## Troubleshooting

### MinIO service won't start

```bash
# Check the logs
journalctl -u minio -n 50

# Common issues:
# - TLS certificate mismatch (ensure the cert matches the hostname)
# - Port already in use (check with `ss -tlnp | grep 9000`)
# - Permission denied on /data/minio (ensure minio-user owns the directory)
```

### Terraform init fails with "access denied"

- Verify the access key and secret key are correct.
- Verify the user has the correct policy attached.
- Check the bucket name matches the Terraform root (global, dev, staging, prod).

### Terraform init fails with "no such host"

- Verify DNS resolution: `nslookup minio-state-01.viavitae.internal`
- Verify network access from the runner: `nc -zv minio-state-01.viavitae.internal 9000`

---

## Monthly Review

After the initial setup, perform a **monthly manual review** of the MinIO configuration:

1. **Versioning**: Verify versioning is still enabled on all buckets.
2. **Encryption**: Verify encryption is still enabled.
3. **Object lock**: Verify object lock is still enabled.
4. **Access logs**: Review MinIO access logs for unusual activity.
5. **Disk usage**: Monitor disk usage on `state-01` (alert at 70%, 85%).

Record the review output in a comment in the PR that updates this runbook, or in a separate review log.

---

## References

- [ADR-010: State Backend Residency](../adr/ADR-010-state-backend-residency.md)
- [terraform/backend.tf](../terraform/backend.tf)
- [docs/audit-plan.md](../audit-plan.md) (Workstream WS1)
- [QODER.md Rule 8](../QODER.md#rule-8--infrastructure-stop-conditions-viavitae-infra) (state must not live on the infrastructure it describes)
