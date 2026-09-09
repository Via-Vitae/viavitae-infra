# Runbook: state bucket bootstrap

> **⚠️ DEPRECATED — 2026-09-08**
>
> This runbook documents the **old AWS S3** state backend configuration. The state backend has been migrated to **self-hosted MinIO** on `state-01` per [ADR-010](../adr/ADR-010-state-backend-residency.md).
>
> **Current runbook:** [`minio-state-bootstrap.md`](minio-state-bootstrap.md)
>
> This document is retained for historical reference and for the 30-day rollback window after migration. After the AWS S3 bucket is deleted (30 days post-migration), this runbook can be removed.

---

# Runbook: state bucket bootstrap (AWS S3 — DEPRECATED)

**Audience.** Platform engineer performing initial infrastructure setup. **Run this
before the first `terraform init`.** Terraform cannot create its own state bucket —
the bucket must exist before Terraform can use it, and a bucket that Terraform
creates for itself is a self-referential loop.

| Field | Value |
| --- | --- |
| Owner | `@Via-Vitae/platform` |
| Frequency | Once, before first deploy; then only for bucket policy changes |
| Related | `terraform/backend.tf`, ADR-005, INFRA-001 flow F9 |
| Prerequisites | AWS CLI v2 configured with credentials that have `s3:*` and `kms:*` on the target account |

---

## Why this is manual

`terraform/backend.tf` declares an S3 backend for remote state. The backend
requires a bucket, a KMS key, and specific security settings. If a Terraform
stack created these resources, it would need to store its own state somewhere —
but the state bucket doesn't exist yet. This is the classic bootstrap paradox.

The solution is a one-time manual creation, verified immediately, then never
touched again except through the AWS console or CLI by a human with appropriate
IAM permissions.

---

## Step 1: Create the KMS key

The KMS key encrypts state at rest. State contains infrastructure descriptions
(not personal data directly), but encryption at rest is a backend.tf requirement
and an INFRA-001 control.

```bash
aws kms create-key \
  --description "viavitae-infra Terraform state encryption" \
  --key-usage ENCRYPT_DECRYPT \
  --origin AWS_KMS \
  --region eu-central-1

# Note the KeyId from the output
KEY_ID="<from above>"

# Create the alias referenced in backend.tf (kms_key_id = "alias/viavitae-state")
aws kms create-alias \
  --target-key-id "$KEY_ID" \
  --alias-name "alias/viavitae-state" \
  --region eu-central-1
```

## Step 2: Create the S3 bucket

```bash
aws s3api create-bucket \
  --bucket viavitae-infra-tfstate \
  --region eu-central-1 \
  --create-bucket-configuration LocationConstraint=eu-central-1
```

## Step 3: Block public access (IMMEDIATE — not a later checklist item)

A state bucket with public access is a state bucket that leaks infrastructure
descriptions to the internet. Verify before proceeding.

```bash
aws s3api put-public-access-block \
  --bucket viavitae-infra-tfstate \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

**Verify immediately:**

```bash
aws s3api get-public-access-block --bucket viavitae-infra-tfstate
# All four values must be true. If any is false, stop and fix before continuing.
```

## Step 4: Enable versioning

Versioning allows state rollback if a corrupt version is written. The backend.tf
comment documents this as a requirement.

```bash
aws s3api put-bucket-versioning \
  --bucket viavitae-infra-tfstate \
  --versioning-configuration Status=Enabled
```

**Verify immediately:**

```bash
aws s3api get-bucket-versioning --bucket viavitae-infra-tfstate
# Status must be "Enabled".
```

## Step 5: Enable default SSE-KMS encryption

All objects written to the bucket are encrypted with the KMS key. This is the
`encrypt = true` + `kms_key_id` in backend.tf.

```bash
aws s3api put-bucket-encryption \
  --bucket viavitae-infra-tfstate \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "aws:kms",
          "KMSMasterKeyID": "alias/viavitae-state"
        },
        "BucketKeyEnabled": true
      }
    ]
  }'
```

**Verify immediately:**

```bash
aws s3api get-bucket-encryption --bucket viavitae-infra-tfstate
# SSEAlgorithm must be "aws:kms" and KMSMasterKeyID must reference the alias.
```

## Step 6: Enable MFA delete

MFA delete prevents accidental or malicious deletion of state versions. This is
the highest-severity protection on the bucket — without it, a compromised IAM
credential can destroy every state version.

```bash
# MFA delete requires the root account MFA ARN and a current MFA code.
# This cannot be done with IAM user credentials.
aws s3api put-bucket-versioning \
  --bucket viavitae-infra-tfstate \
  --versioning-configuration Status=Enabled,MFADelete=Enabled \
  --mfa "arn:aws:iam::<ACCOUNT_ID>:mfa/<MFA_DEVICE_NAME> <MFA_CODE>"
```

**Verify immediately:**

```bash
aws s3api get-bucket-versioning --bucket viavitae-infra-tfstate
# MFADelete must be "Enabled".
```

## Step 7: Create the IAM user/policy for Terraform

The GitHub Actions workflows inject `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
as repository secrets. These credentials must be scoped to the state bucket only.

```bash
# Create the IAM user
aws iam create-user --user-name viavitae-terraform

# Create an access key (save the output — it goes into GitHub secrets)
aws iam create-access-key --user-name viavitae-terraform

# Attach a policy scoped to the state bucket
aws iam put-user-policy \
  --user-name viavitae-terraform \
  --policy-name viavitae-tfstate-access \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": ["s3:ListBucket"],
        "Resource": "arn:aws:s3:::viavitae-infra-tfstate"
      },
      {
        "Effect": "Allow",
        "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
        "Resource": "arn:aws:s3:::viavitae-infra-tfstate/*"
      },
      {
        "Effect": "Allow",
        "Action": ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"],
        "Resource": "arn:aws:kms:eu-central-1:<ACCOUNT_ID>:key/<KEY_ID>"
      }
    ]
  }'
```

Store the access key ID and secret in GitHub repository secrets:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

## Step 8: Verify the full chain

Run these checks in order. Every one must pass before the first `terraform init`.

```bash
echo "=== Bucket exists ==="
aws s3api head-bucket --bucket viavitae-infra-tfstate

echo "=== Public access blocked ==="
aws s3api get-public-access-block --bucket viavitae-infra-tfstate \
  --query 'PublicAccessBlockConfiguration'

echo "=== Versioning enabled ==="
aws s3api get-bucket-versioning --bucket viavitae-infra-tfstate

echo "=== SSE-KMS configured ==="
aws s3api get-bucket-encryption --bucket viavitae-infra-tfstate \
  --query 'ServerSideEncryptionConfiguration.Rules[0]'

echo "=== KMS alias exists ==="
aws kms describe-key --key-id alias/viavitae-state --region eu-central-1 \
  --query 'KeyMetadata.{KeyId:KeyId,Enabled:Enabled,KeyState:KeyState}'

echo "=== IAM credentials work ==="
AWS_ACCESS_KEY_ID=<from step 7> AWS_SECRET_ACCESS_KEY=<from step 7> \
  aws s3api list-objects-v2 --bucket viavitae-infra-tfstate --max-items 1
```

If all six checks pass, the state bucket is ready. Proceed to `terraform init`.

---

## What to do if this goes wrong

| Symptom | Cause | Fix |
| --- | --- | --- |
| `terraform init` fails with `NoSuchBucket` | Bucket not created or wrong name | Re-check step 2; verify the bucket name matches `backend.tf` |
| `terraform init` fails with `AccessDenied` | IAM policy too narrow or wrong credentials | Re-check step 7; ensure the policy covers both `s3:*` on the bucket and `kms:*` on the key |
| `terraform init` fails with `KMS.NotFoundException` | KMS key or alias doesn't exist | Re-check step 1; verify the alias matches `alias/viavitae-state` |
| State file appears unencrypted | SSE-KMS not configured | Re-check step 5; the bucket encryption must be server-side with `aws:kms` |
| Someone deleted a state version | MFA delete was not enabled | Re-check step 6; restore from a remaining version if versioning was on |

---

## Bootstrap paradox warning

If a future Terraform stack is added to manage the state bucket itself (e.g., a
"bootstrap" or "foundations" stack), it **must** use local state or a *different*
backend. This backend cannot hold its own provisioning state — the bucket must
exist before Terraform can write to it. See the `BOOTSTRAP` comment in
`terraform/backend.tf`.
