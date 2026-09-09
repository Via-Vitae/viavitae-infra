# ADR-010: State Backend Residency — Self-Hosted MinIO, Not AWS S3

| Field | Value |
| --- | --- |
| **Status** | Accepted |
| **Owner** | `@Via-Vitae/architects` |
| **Date** | 2026-09-08 |
| **Deciders** | Architects, Platform, Security |
| **Consulted** | Compliance, DPO |
| **Supersedes** | — |
| **Superseded by** | — |

---

## Context

The Terraform state backend for `viavitae-infra` was initially configured to use **AWS S3** (`eu-central-1`, Frankfurt) with **AWS KMS** for encryption at rest. This configuration was documented in [`terraform/backend.tf`](../terraform/backend.tf) and the bootstrap runbook [`docs/runbooks/state-bucket-bootstrap.md`](../runbooks/state-bucket-bootstrap.md).

This configuration **contradicts the project's foundational invariant**: "no US hyperscaler / 100% self-hosted EU / no cloud providers" (master prompt §2, §31; README "No cloud providers"; QODER.md Rule 7). The contradiction was identified as **Finding F-1 (Critical)** in the compliance review (2026-09-08).

### The Contradiction

1. **All nine prior ADRs** (ADR-001 through ADR-009) reject cloud/managed services on residency and self-hosting grounds:
   - ADR-001 rejects EKS/GKE/AKS: *"Would remove the control-plane operational burden entirely. Rejected on data residency and on the self-hosting requirement."*
   - ADR-008 rejects GitHub-hosted runners: *"Directly violates the residency rule for CI runners, and would execute `terraform plan` holding a Proxmox API token on US infrastructure."*
   - ADR-005 rejects cloud KMS: *"External Secrets Operator against a cloud KMS — Rejected on residency and on the self-hosting requirement."*

2. **The DPIA (INFRA-001)** marks Terraform state (flow F9) as *"EEA, Cross-border? No"* and defers the processor to *"named in `docs/capacity-plan.md`"* — but `capacity-plan.md` names **no** object-storage provider for state/backup (only a *future* wish for an "EU-sovereign object store"). Condition C2 (DPA with the object-storage provider) is **unmet**.

3. **AWS is a US-jurisdiction processor** subject to the US CLOUD Act, regardless of the Frankfurt region. The DPIA applies a strict Schrems-II lens to GitHub (F10 = "cross-border **Yes**, SCCs + TIA required") but marks the AWS state bucket F9 = "cross-border **No**" — an **inconsistent transfer methodology**.

4. **Terraform state contains secrets in plaintext** (QODER.md Rule 8 warns: *"Terraform state is plaintext to anyone who can read the bucket; a password passed as a resource argument lands there"*). Placing state on AWS S3 means a US hyperscaler holds all infrastructure secrets.

5. **No ADR authorizes AWS S3** despite the repo's own rule (architecture.md §"When an ADR is required"): *"any decision that touches personal data or residency cannot be taken without [an ADR]."*

### Why State Must Not Live on the Infrastructure It Describes

QODER.md Rule 8 states: *"State must not live on the infrastructure it describes. If the state store runs on the Proxmox cluster, a cluster outage makes Terraform unreachable at exactly the moment it is needed for recovery."*

This is a **bootstrap paradox**: Terraform needs the state bucket to exist before it can run, but if the state bucket is on the cluster Terraform manages, a cluster outage locks out recovery. The state store must be **physically separate** from the workload cluster.

---

## Decision

**Migrate Terraform state to a self-hosted MinIO instance on a dedicated VM (`state-01`) on a separate Proxmox node or physical location (still EEA).**

### Implementation

1. **Provision `state-01`**: A dedicated VM on a Proxmox node that is **not** part of the workload cluster (e.g., a separate physical host, or a different rack in the same data center). This satisfies the "state must not live on the infrastructure it describes" constraint.

2. **Install MinIO**: Pin the version, enable TLS via internal CA, configure S3-compatible API.

3. **Create buckets**: `viavitae-tfstate-{global,dev,staging,prod}` — one bucket per Terraform root, with versioning ON, object lock / retention where supported, separate credentials per environment, minimal IAM policy per bucket.

4. **Encryption**: Use **SSE-S3** (server-side encryption with MinIO-managed keys) + TLS in transit + ZFS native encryption on the `state-01` disk. **Do not use SSE-KMS** (MinIO's KMS integration differs from AWS KMS; the trade-off is simpler ops vs. weaker key-management audit trails — documented below).

5. **Update `backend.tf`**: Replace AWS S3 endpoint with MinIO endpoint (`https://minio-state-01.viavitae.internal:9000`), remove `kms_key_id`, keep `use_lockfile = true`, add `skip_requesting_account_id` / `skip_metadata_api_check` for non-AWS S3.

6. **Migrate state**: Use `scripts/migrate-state.sh` to pull state from AWS S3 to local, reconfigure backend to MinIO, push. Idempotent, refuses to run if target bucket is non-empty unless `--force`.

7. **Freeze AWS bucket**: After migration, set the AWS S3 bucket to **read-only** for 30 days (rollback window), then delete (completing AWS removal).

### Why MinIO

- **S3-compatible**: Terraform's `backend "s3"` works with MinIO without code changes (only endpoint + credentials differ).
- **Self-hosted**: No US hyperscaler, no CLOUD Act exposure, no third-party processor.
- **EEA-only**: Runs on ViaVitae Proxmox hardware in the EEA.
- **Mature**: MinIO is production-grade, used by thousands of organizations, AGPL-3.0-licensed (pre-approved per ADR-009).

### Why `state-01` on a Separate Proxmox Node

- **Bootstrap paradox**: State must exist before Terraform can run; if state is on the cluster Terraform manages, a cluster outage locks out recovery.
- **Fault domain separation**: `state-01` must not share a failure domain with the workload cluster (different physical host, different rack, or different data center).
- **Availability**: Single-VM availability is acceptable because (a) state is rarely needed (only during `terraform plan/apply`), (b) the replication buddy + nightly offsite backup (per `backup/offsite/replication.md`) provide recovery, (c) the AWS S3 bucket is frozen for 30 days as rollback.

---

## Consequences

### Positive

- **No CLOUD Act exposure**: State is no longer held by a US-jurisdiction processor.
- **Residency invariant restored**: The project is now consistent with its own "no US hyperscaler / 100% self-hosted EU" claim.
- **DPIA F9 reconciled**: Flow F9 (Terraform state) is now genuinely "EEA, Cross-border? No" with a named processor (self-hosted, ViaVitae).
- **Condition C2 satisfied**: The object-storage provider is named (self-hosted MinIO on `state-01`), and the DPA is internal (no external processor).
- **No new external processor**: MinIO is self-hosted; no DPA with a third party is needed (only the colocation provider for the physical host, which is already an INFRA-001 processor).

### Negative

- **New ops burden**: `state-01` is a new VM to patch, monitor, and back up. Mitigation: add it to the `common` and `hardening` Ansible roles, monitor via Prometheus agent, back up via the existing offsite replication.
- **Single-VM availability**: If `state-01` fails, Terraform is unreachable until it is restored. Mitigation: (a) replication buddy + nightly offsite backup, (b) AWS S3 bucket frozen for 30 days as rollback, (c) state is rarely needed (only during `terraform plan/apply`).
- **Weaker key management**: SSE-S3 (MinIO-managed keys) is simpler than AWS KMS (customer-managed keys with audit trails). Mitigation: ZFS native encryption on disk + TLS in transit; the trade-off is documented and accepted.
- **Bootstrap paradox remains**: `state-01` itself is not managed by Terraform (it cannot be, because Terraform needs it to exist first). Mitigation: `docs/runbooks/minio-state-bootstrap.md` documents the manual provisioning, and a monthly manual review verifies the bucket config (versioning, encryption, public access blocked).

### Neutral

- **MinIO region string**: MinIO requires a `region` string (even though it's not AWS). We use `eu-central-1` as a label (not an actual AWS region); this is arbitrary and could be `eeu` or `local`. The choice is cosmetic.

---

## Alternatives Considered

### 1. Keep AWS S3 (Status: Rejected)

**Pros**: No migration effort, mature service, Frankfurt region is EEA.

**Cons**: Contradicts the residency invariant, CLOUD Act exposure, no ADR authorizes it, DPIA F9 is inconsistent, condition C2 is unmet.

**Verdict**: Rejected. The residency invariant is non-negotiable (QODER.md Rule 7, master prompt §2/§31, README).

### 2. Self-Hosted MinIO on the Workload Cluster (Status: Rejected)

**Pros**: No new VM, simpler ops.

**Cons**: Violates the "state must not live on the infrastructure it describes" constraint (QODER.md Rule 8). A cluster outage locks out Terraform recovery.

**Verdict**: Rejected. The bootstrap paradox is a hard constraint.

### 3. Other Object Stores (Wasabi, Backblaze B2, OVH Object Storage) (Status: Rejected)

**Pros**: EEA-hosted, S3-compatible, cheaper than AWS.

**Cons**: Still a third-party processor (requires DPA, transfer impact assessment if US-headquartered), still a cloud provider (contradicts "no cloud providers" invariant).

**Verdict**: Rejected. The invariant is "no cloud providers," not just "no US hyperscalers."

### 4. Offline State Escrow (Status: Rejected)

**Pros**: No network dependency, maximum security.

**Cons**: Impractical for daily ops (every `terraform plan` requires restoring from offline media), slow, error-prone.

**Verdict**: Rejected. State must be online and accessible for daily ops.

### 5. Separate Proxmox Cluster for State (Status: Rejected)

**Pros**: Maximum fault domain separation, HA.

**Cons**: Overkill for the use case (state is rarely needed), high cost (second cluster), ops burden.

**Verdict**: Rejected. Single VM with offsite backup is sufficient for the use case.

---

## Compliance Impact

### GDPR

- **Art. 28 (Processors)**: No new external processor. MinIO is self-hosted; the only processor is the colocation provider for the physical host (already in INFRA-001).
- **Art. 32 (Security)**: State is encrypted at rest (SSE-S3 + ZFS) and in transit (TLS). Access is restricted to Terraform runners on the `mgmt` VLAN.
- **Art. 44–49 (Transfers)**: No cross-border transfer. State is on ViaVitae hardware in the EEA.
- **DPIA INFRA-001**: Flow F9 updated (processor = self-hosted MinIO, cross-border = No). Condition C2 satisfied (provider named, DPA internal).

### ISO/IEC 27001:2022

- **A.5.34 (Cloud services)**: MinIO is self-hosted, not a cloud service. The control is satisfied.
- **A.8.24 (Cryptography)**: State is encrypted at rest (SSE-S3 + ZFS) and in transit (TLS). The control is satisfied.
- **A.15 (Supplier relationships)**: No new supplier relationship. The control is satisfied.

### SOC 2

- **CC3.4 (Vendor risk)**: No new vendor. The control is satisfied.
- **CC6.1 (Logical access)**: Access to `state-01` is restricted to Terraform runners on the `mgmt` VLAN. The control is satisfied.

---

## DPIA INFRA-001 Updates

### Flow F9 (Terraform state)

| Field | Before | After |
|---|---|---|
| **To** | S3-compatible object store (AWS S3, eu-central-1) | S3-compatible object store (self-hosted MinIO on `state-01`, EEA) |
| **Storage location** | EEA (AWS Frankfurt) | EEA (ViaVitae Proxmox, `state-01`) |
| **Encryption at rest** | Server-side encryption plus a bucket-level key (AWS KMS) | SSE-S3 + ZFS native encryption on `state-01` |
| **Cross-border?** | No (but AWS is US-jurisdiction) | No (genuinely self-hosted, no US-jurisdiction processor) |

### Condition C2

| Field | Before | After |
|---|---|---|
| **Status** | Outstanding (provider not named, DPA not executed) | Met (provider = self-hosted MinIO on `state-01`, DPA = internal) |

---

## Implementation Plan

See [`docs/audit-plan.md`](../audit-plan.md), Workstream WS1 (Weeks 1–2).

### Deliverables

1. ✅ This ADR (ADR-010)
2. `docs/runbooks/minio-state-bootstrap.md` (provision `state-01`, install MinIO, create buckets)
3. `terraform/backend.tf` + `terraform/envs/*/backend.tf` rewritten for MinIO
4. `scripts/migrate-state.sh` (idempotent migration script)
5. `.github/workflows/deploy.yml` updated (remove AWS refs, update drift detection)
6. Grep evidence: no remaining AWS references in the repo

### Human Actions (flagged, not automated)

- Running `migrate-state.sh` against real infrastructure
- Creating MinIO credentials (access keys for each bucket)
- DNS record for `minio-state-01.viavitae.internal`
- Freezing the AWS S3 bucket (read-only for 30 days, then delete)

---

## Verification

After implementation:

1. `terraform init` succeeds against the new MinIO backend for all 4 roots.
2. `terraform plan` shows no changes (state migrated correctly).
3. `scripts/migrate-state.sh --verify` confirms state integrity.
4. Grep for `aws|amazonaws|AWS_ENDPOINT_URL|aws kms` returns no hits (except this ADR and the migration script).
5. `tools/preflight.sh` passes (fmt, validate, tflint, checkov) on all 4 roots.

---

## References

- [Finding F-1](../audit-plan.md#31-findings-summary) (Critical: AWS S3 state backend violates residency invariant)
- [DPIA INFRA-001](DPIA-template.md#infra-001-infrastructure-platform-processing) (flows F9, condition C2)
- [QODER.md Rule 8](../QODER.md#rule-8--infrastructure-stop-conditions-viavitae-infra) (state must not live on the infrastructure it describes)
- [terraform/backend.tf](../terraform/backend.tf) (current AWS S3 config, to be replaced)
- [docs/runbooks/state-bucket-bootstrap.md](runbooks/state-bucket-bootstrap.md) (current AWS bootstrap runbook, to be replaced)
- [docs/audit-plan.md](audit-plan.md) (Workstream WS1)
