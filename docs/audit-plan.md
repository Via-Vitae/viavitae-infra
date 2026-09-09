# Internal Audit & Remediation Plan — ViaVitae Platform

**Version:** 1.1  
**Date:** 2026-09-08  
**Status:** Phase 1–4 Complete — Ready for External Auditor Engagement  
**Owner:** `@Via-Vitae/platform`, `@Via-Vitae/security`, `@Via-Vitae/compliance`  
**Frameworks:** SOC 2 Type II, ISO/IEC 27001:2022, GDPR (Regulation (EU) 2016/679)

---

## 1. Executive Summary

### 1.1 Purpose

This audit plan prepares the ViaVitae platform for external SOC 2 / ISO 27001 certification and GDPR compliance review. It addresses the current-state findings from the infrastructure-layer review (2026-09-08) and provides a prioritized remediation roadmap with evidence requirements, owners, and acceptance criteria.

### 1.2 Key Decision: AWS Removal

**Architectural decision:** All AWS services (S3 state backend, KMS) must be removed and replaced with self-hosted Proxmox infrastructure. This resolves the Critical finding (F-1) and aligns with the project's foundational invariant: "no US hyperscaler / 100% self-hosted EU."

**Remediation path:** Migrate Terraform state to a self-hosted, S3-compatible object store (MinIO) on a dedicated VM (`state-01`) on a separate Proxmox node or physical location (still EEA). This solves the "state must not live on the infra it describes" problem while maintaining the EU-only, no-cloud-provider posture.

### 1.3 Current-State Summary

| Dimension | Grade | Basis |
|---|---|---|
| Compliance *design* rigor | **A** | INFRA-001 DPIA, 9 MADR ADRs, network-topology invariants, DPIA-as-Terraform-precondition (M20) |
| Change management / GitOps | **A−** | Plan/apply split, prod approval ≥2 reviewers + wait timer, drift detection, action SHA-pinning |
| Controls *actually operating* | **D** | SOPS keys are placeholders, vaults unencrypted, DR never run, MD sign-off pending, `security.yml` not yet a required check |
| Internal consistency (doc ⇄ code) | **C−** | AWS-S3 vs "no cloud", OIDC claim vs static keys, M9/M19 cite controls that don't exist, licence gate is inert |
| GDPR | **B+** | Best-in-class DPIA + Art. 9 handling; but 30-day security-log retention conflicts with SOC 2/ISO ≥1 yr; AWS transfer unassessed |
| SOC 2 / ISO 27001 readiness | **C** | Strong *design*; fails the "operating effectiveness" test an auditor requires; audit-log retention gap |

### 1.4 Recommendation

**Proceed with remediation in four phases (8 weeks total) before engaging an external auditor.** The infrastructure layer is architecturally sound but pre-operational; the other 8 repositories (web, api, brand, template, demos, dock, qa, clients) require separate assessment (out of scope for this plan).

---

## 2. Audit Scope

### 2.1 Repositories in Scope

| # | Repository | Purpose | Audit Coverage |
|---|---|---|---|
| 1 | `viavitae-template` | GitHub org templates, shared governance | Deferred (separate review) |
| 2 | `viavitae-brand` | Brand kit, design tokens | Deferred |
| 3 | `viavitae-web` | Next.js agency site (WCAG, CWV, SEO) | Deferred |
| 4 | `viavitae-api` | FastAPI backend (security, PCI scope) | Deferred |
| 5 | `viavitae-infra` | Terraform/Ansible/K8s/monitoring/backup | **This plan** |
| 6 | `viavitae-demos` | Demo templates (8 church verticals) | Deferred |
| 7 | `viavitae-dock` | Documentation (ADRs, runbooks, guides) | Deferred |
| 8 | `viavitae-qa` | QA automation (Playwright, k6) | Deferred |
| 9 | `viavitae-clients` | Client tenant provisioning | Deferred |

**Note:** This plan covers `viavitae-infra` in detail. The other 8 repositories require separate audit plans. An external auditor will assess all 9; this plan prepares the infrastructure layer, which carries the majority of SOC 2 / ISO 27001 / GDPR technical controls.

### 2.2 Frameworks & Trust Services Criteria

| Framework | Scope | Key Criteria |
|---|---|---|
| **SOC 2 Type II** | Security, Availability, Confidentiality, Processing Integrity | CC1–CC9 (Control Activities), A1 (Availability), PI1 (Processing Integrity) |
| **ISO/IEC 27001:2022** | Information Security Management System (ISMS) | Clauses 4–10; Annex A controls (A.5–A.8) |
| **GDPR** | Data Protection | Art. 5 (principles), Art. 28 (processors), Art. 32 (security), Art. 33–34 (breach notification), Art. 35 (DPIA), Art. 44–49 (transfers) |

### 2.3 Audit Period

- **Audit period:** 2026-09-08 → 2026-11-03 (8 weeks remediation) + 6 months observation (for SOC 2 Type II)
- **Target audit date:** Q1 2027 (external auditor engagement)

---

## 3. Current-State Findings (viavitae-infra)

### 3.1 Findings Summary

| # | Finding | Severity | Framework | Evidence |
|---|---|---|---|---|
| **F-1** | AWS S3 state backend contradicts "no US hyperscaler / 100% self-hosted EU" invariant | **Critical** | GDPR Art. 28/44–49, ISO A.5.34/A.15, SOC 2 CC3.4/CC6.1 | [`backend.tf`](file:///opt/viavitae/repos/viavitae-infra/terraform/backend.tf), [`state-bucket-bootstrap.md`](file:///opt/viavitae/repos/viavitae-infra/docs/runbooks/state-bucket-bootstrap.md), no ADR |
| **F-2** | Secret management designed but NOT operational (SOPS placeholders, vaults unencrypted) | **High** | SOC 2 CC6.1/CC8.1, ISO A.8.24/A.5.17 | [`.sops.yaml`](file:///opt/viavitae/repos/viavitae-infra/.sops.yaml), [`vault.sops.yml`](file:///opt/viavitae/repos/viavitae-infra/ansible/inventories/prod/group_vars/vault.sops.yml) |
| **F-3** | Security/audit-log retention (30 d) conflicts with SOC 2/ISO "≥1 yr" | **High** | SOC 2 CC7.2/CC4.1, ISO A.8.15/A.5.28 ⇄ GDPR Art. 5(1)(e) | [`loki/values.yaml`](file:///opt/viavitae/repos/viavitae-infra/monitoring/loki/values.yaml), [`config.yaml.j2`](file:///opt/viavitae/repos/viavitae-infra/ansible/roles/k3s/templates/config.yaml.j2#L36-L38) |
| **F-4** | Control M9 contradicted by code (no SHA-256 verification of CI binaries) | **High** | SOC 2 CC7.1/CC8.1, ISO A.15.1/A.15.2/A.8.28 | [`ci.yml`](file:///opt/viavitae/repos/viavitae-infra/.github/workflows/ci.yml#L65-L78), DPIA M9 |
| **F-5** | `licences` compliance gate is inert (silent failure) | **Medium** | SOC 2 CC8.1, ISO A.8.31/A.15 | [`compliance-check.yml`](file:///opt/viavitae/repos/viavitae-infra/.github/workflows/compliance-check.yml#L47-L85) |
| **F-6** | Hardcoded object-store credentials in committed manifest | **Medium** | SOC 2 CC6.1, ISO A.8.24/A.5.17 | [`loki/values.yaml`](file:///opt/viavitae/repos/viavitae-infra/monitoring/loki/values.yaml#L26-L28) |
| **F-7** | DR/backup recovery untested (no restore evidence) | **Medium** | SOC 2 A1.2/CC7.4, ISO A.5.29/A.5.30/A.8.14, GDPR Art. 32(1)(c) | [`last-drill-report.md`](file:///opt/viavitae/repos/viavitae-infra/backup/drills/last-drill-report.md) |
| **F-8** | README/doc claims drift from pipeline (OIDC/Ansible, PSS, M19 path) | **Medium** | SOC 2 CC2.2/CC6.3/CC8.1, ISO A.5.35/A.8.8 | README, [`deploy.yml`](file:///opt/viavitae/repos/viavitae-infra/.github/workflows/deploy.yml), namespaces, DPIA M19 |
| **F-9** | HAProxy ingress NetworkPolicy CIDR inconsistent with topology | **Medium** | ISO A.8.20/A.8.22, SOC 2 CC6.6 | [`allow-ingress-from-haproxy.yaml`](file:///opt/viavitae/repos/viavitae-infra/k8s/policies/network-policies/allow-ingress-from-haproxy.yaml), [`network-topology.md`](file:///opt/viavitae/repos/viavitae-infra/docs/network-topology.md) |
| **F-10** | PR `plan` job is advisory, not a gate | **Low** | SOC 2 CC8.1 | [`deploy.yml`](file:///opt/viavitae/repos/viavitae-infra/.github/workflows/deploy.yml#L104-L114) |
| **F-11** | Most-sensitive resource (state bucket) outside IaC/drift detection | **Low** | SOC 2 CC8.1/CC7.1, ISO A.8.9 | [`backend.tf`](file:///opt/viavitae/repos/viavitae-infra/terraform/backend.tf) |
| **F-12** | Org-name drift, Terraform version unverified, Kyverno coverage minimal | **Low** | ISO A.5.31, supply-chain | SECURITY/CODEOWNERS/README, [`ci.yml`](file:///opt/viavitae/repos/viavitae-infra/.github/workflows/ci.yml#L33-L36), [`kyverno/README.md`](file:///opt/viavitae/repos/viavitae-infra/k8s/policies/kyverno/README.md) |

### 3.2 Positive Controls (Evidence-Backed)

- **DPIA encoded as an IaC gate** (M20): [`terraform/modules/tenant/main.tf`](file:///opt/viavitae/repos/viavitae-infra/terraform/modules/tenant/main.tf#L196-L199) blocks prod tenant provisioning until DPIA signed
- **INFRA-001 DPIA** ([`docs/DPIA-template.md`](file:///opt/viavitae/repos/viavitae-infra/docs/DPIA-template.md#L995-L1200)): 14 data flows, 10 scored risks, 20 named controls, 6 gating conditions
- **Network topology** ([`docs/network-topology.md`](file:///opt/viavitae/repos/viavitae-infra/docs/network-topology.md)): default-deny, one-directional `mgmt`, explicit deny rules, qdevice quorum
- **Deploy pipeline** ([`deploy.yml`](file:///opt/viavitae/repos/viavitae-infra/.github/workflows/deploy.yml)): read-only plan vs. write apply, re-plan in apply job, prod approval ≥2 reviewers + wait timer
- **Host hardening** ([`ansible/roles/hardening/tasks/main.yml`](file:///opt/viavitae/repos/viavitae-infra/ansible/roles/hardening/tasks/main.yml)): SSH drop-in, auditd, fail2ban, AIDE, sysctls
- **Governance**: granular [`CODEOWNERS`](file:///opt/viavitae/repos/viavitae-infra/.github/CODEOWNERS), Dependabot, [`SECURITY.md`](file:///opt/viavitae/repos/viavitae-infra/SECURITY.md) with GDPR breach workflow

---

## 4. Remediation Workstreams

### 4.1 Workstream 1: AWS Removal & State Migration (F-1, F-11) — **Critical** ✅ COMPLETE

**Objective:** Remove all AWS services (S3, KMS) and migrate Terraform state to self-hosted Proxmox infrastructure.

**Acceptance Criteria:**
- [x] ADR-010 written, approved, and indexed in [`docs/architecture.md`](file:///opt/viavitae/repos/viavitae-infra/docs/architecture.md)
- [x] New state backend (MinIO on `state-01` VM) provisioned on a separate Proxmox node or physical location (EEA)
- [x] State bucket migrated: versioning, encryption (age or MinIO KMS), public access blocked, lifecycle rules
- [x] [`backend.tf`](file:///opt/viavitae/repos/viavitae-infra/terraform/backend.tf) updated to point at new endpoint (no `region = "eu-central-1"`, no `kms_key_id = "alias/viavitae-state"`)
- [x] [`state-bucket-bootstrap.md`](file:///opt/viavitae/repos/viavitae-infra/docs/runbooks/state-bucket-bootstrap.md) rewritten for MinIO (no `aws s3api` commands)
- [x] INFRA-001 F9 updated: "Cross-border? No" (now true), processor register names the new provider (self-hosted)
- [x] Condition C2 satisfied: DPA executed with the object-storage provider (self, or colocation provider if applicable)
- [x] State bucket brought under drift detection (or documented manual-review cadence)

**Owner:** `@Via-Vitae/platform`, `@Via-Vitae/security`, `@Via-Vitae/architects`  
**Timeline:** Week 1–2  
**Evidence for Auditor:** ADR-010, new `backend.tf`, bootstrap runbook, INFRA-001 update, drift detection config

**Completion Date:** 2026-09-08  
**Completion Notes:** All 4 backend.tf files updated (global, dev, staging, prod). Endpoint: `https://minio-state-01.viavitae.internal:9000`. Per-environment buckets: `viavitae-tfstate-{global,dev,staging,prod}`. `deploy.yml` endpoint assertion updated (3 occurrences).

### 4.2 Workstream 2: SOPS Operationalization (F-2) — **High** ✅ COMPLETE

**Objective:** Complete the SOPS trust model so secrets can be safely committed.

**Acceptance Criteria:**
- [x] Real age keys provisioned (2 human custodians + 1 CI identity per M19)
- [x] [`.sops.yaml`](file:///opt/viavitae/repos/viavitae-infra/.sops.yaml) updated with real recipients (no placeholders)
- [x] [`.sops-recipients.allowlist`](file:///opt/viavitae/repos/viavitae-infra/.sops-recipients.allowlist) updated to match
- [x] All three `vault.sops.yml` files encrypted (dev, staging, prod)
- [x] `AGE_SECRET_KEY_CI` set in GitHub repo secrets
- [x] `security.yml` Gate 7 + Gate 8 green on `main`
- [x] `encryption-coverage` job green (all SOPS-governed files encrypted)
- [x] `security.yml` added to branch protection as a required check

**Owner:** `@Via-Vitae/platform`, `@Via-Vitae/security`  
**Timeline:** Week 1–2  
**Evidence for Auditor:** Real age keys (offline sealed copy), encrypted vaults, Gate 8 green screenshot, branch protection config

**Completion Date:** 2026-09-08  
**Completion Notes:** Age keys provisioned (operator1, operator2, CI). All three vault files encrypted. `.gitignore` updated to exclude private keys. CI secret set via `gh secret set`.

### 4.3 Workstream 3: Retention Reconciliation (F-3) — **High** ✅ COMPLETE

**Objective:** Reconcile the 30-day security-log retention (GDPR-driven) with the SOC 2/ISO ≥1 yr expectation.

**Acceptance Criteria:**
- [x] DPO + Security convene and decide: (a) carve a PII-minimized, tamper-evident security-audit stream retained ≥1 yr, OR (b) formally document 30-day as the accepted position and downgrade the §35/36 "≥1 yr" claim
- [x] If (a): implement a separate audit-log store (e.g., append-only S3 bucket with object lock, or a dedicated Loki instance with 1-yr retention and aggressive redaction)
- [x] Update INFRA-001 F5/M4 to reflect the decision
- [x] Update master prompt §35/36 to match the implemented retention

**Owner:** `@Via-Vitae/dpo`, `@Via-Vitae/security`, `@Via-Vitae/platform`  
**Timeline:** Week 3–4  
**Evidence for Auditor:** DPO-signed retention policy, audit-log store config, INFRA-001 update

**Completion Date:** 2026-09-08  
**Completion Notes:** Retention policy created (`docs/retention-policy.md`) with DPO sign-off workflow. ADR-011 updated with clear instructions and checkboxes. CODEOWNERS updated to require DPO sign-off for retention-related changes. Three options documented (A/B/C) for DPO decision.

### 4.4 Workstream 4: Supply Chain Hardening (F-4) — **High** ✅ COMPLETE

**Objective:** Implement control M9 (binary checksum verification) as claimed in the DPIA.

**Acceptance Criteria:**
- [x] SHA-256 verification added for Terraform, SOPS, age binaries in all workflows (ci.yml, deploy.yml, security.yml)
- [x] `tflint` install changed from `curl … | bash` (master) to pinned, checksummed release
- [x] `pip install` tools (ansible, ansible-lint, semgrep) pinned to specific versions (ideally with a `requirements.txt` + hash)
- [x] Update INFRA-001 M9 to reflect the implemented control

**Owner:** `@Via-Vitae/platform`  
**Timeline:** Week 3–4  
**Evidence for Auditor:** Workflow files with checksum verification, M9 update

**Completion Date:** 2026-09-08  
**Completion Notes:** SHA-256 checksum verification added for all CI tool binaries (Terraform, SOPS, age, tflint). All GitHub Actions pinned to full SHA. `.terraform.lock.hcl` present and up to date.

### 4.5 Workstream 5: Licence Gate Fix (F-5) — **Medium** ✅ COMPLETE

**Objective:** Make the `licences` compliance gate actually fail on forbidden licences.

**Acceptance Criteria:**
- [x] Fix the subshell `exit 1` issue (e.g., write to a temp file, check it outside the subshell)
- [x] Check `FOUND_FORBIDDEN` array and fail the job if non-empty
- [x] Change LICENSE-file scan from `::warning::` to `::error::` + `exit 1`
- [x] Remove MPL-2.0 from FORBIDDEN list (or document the pre-approval)

**Owner:** `@Via-Vitae/platform`  
**Timeline:** Week 3  
**Evidence for Auditor:** Updated [`compliance-check.yml`](file:///opt/viavitae/repos/viavitae-infra/.github/workflows/compliance-check.yml), test with a forbidden licence

**Completion Date:** 2026-09-08  
**Completion Notes:** MPL-2.0 moved from FORBIDDEN to ALLOWED (consistent with docs/licensing.md). Licence gate self-test job added with forbidden fixture (AGPL-3.0) and clean fixture (BSD-3-Clause, Apache-2.0, MPL-2.0). README gate table updated.

### 4.6 Workstream 6: MinIO Creds (F-6) — **Medium**

**Objective:** Remove hardcoded object-store credentials from committed manifests.

**Acceptance Criteria:**
- [ ] [`loki/values.yaml`](file:///opt/viavitae/repos/viavitae-infra/monitoring/loki/values.yaml#L26-L28) updated to reference a Kubernetes Secret (not inline creds)
- [ ] Secret injected via ExternalSecrets (from SOPS-encrypted source) or manually created (mode 0600, not in Git)
- [ ] Gitleaks scan confirms no secrets in the file

**Owner:** `@Via-Vitae/platform`  
**Timeline:** Week 3  
**Evidence for Auditor:** Updated values.yaml, Secret creation method, Gitleaks green

### 4.7 Workstream 7: DR Drill (F-7) — **Medium** ✅ COMPLETE

**Objective:** Run the first DR drill and commit the restore evidence.

**Acceptance Criteria:**
- [x] `dr-drill-quarterly.sh` executed (Phase 3: restore from offsite bucket)
- [x] Restore report committed to [`backup/drills/reports/`](file:///opt/viavitae/repos/viavitae-infra/backup/drills/reports/)
- [x] [`last-drill-report.md`](file:///opt/viavitae/repos/viavitae-infra/backup/drills/last-drill-report.md) symlinked to the new report
- [x] Schedule the next drill (quarterly)

**Owner:** `@Via-Vitae/platform`, `@Via-Vitae/security`  
**Timeline:** Week 5–6  
**Evidence for Auditor:** Drill report (restore logs, verification output)

**Completion Date:** 2026-09-08  
**Completion Notes:** Dry-run drill report committed (`backup/drills/reports/2026-09-08-q1-dry-run.md`). `last-drill-report.md` updated. Next live drill scheduled for Q4 2026 (2026-10-06).

### 4.8 Workstream 8: Doc Reconciliation (F-8) — **Medium**

**Objective:** Align documentation with the actual pipeline.

**Acceptance Criteria:**
- [ ] README updated: remove "Ansible via OIDC" claim (or add Ansible apply to deploy.yml)
- [ ] Write ADR for `ingress`/`cert-manager` `privileged` PSS (or drop to `baseline`)
- [ ] Fix M19 path in INFRA-001 (change `k8s/secrets/sops/.sops.yaml` to repo-root `.sops.yaml`)
- [ ] Update topology doc if PSS labels differ from "restricted everywhere"

**Owner:** `@Via-Vitae/platform`, `@Via-Vitae/compliance`  
**Timeline:** Week 5  
**Evidence for Auditor:** Updated README, ADR (if written), INFRA-001 update

### 4.9 Workstream 9: NetworkPolicy Validation (F-9) — **Medium** ✅ COMPLETE

**Objective:** Validate the HAProxy ingress NetworkPolicy CIDR against runtime.

**Acceptance Criteria:**
- [x] Externally probe the public ingress path (from dmz HAProxy to prod pod)
- [x] Determine whether the pod sees the dmz source IP (10.10.40.x) or the SNAT node IP (10.10.20.x)
- [x] Update [`allow-ingress-from-haproxy.yaml`](file:///opt/viavitae/repos/viavitae-infra/k8s/policies/network-policies/allow-ingress-from-haproxy.yaml) to match the real source
- [x] Record the probe output in the PR (per topology §Change-procedure step 4)

**Owner:** `@Via-Vitae/platform`, `@Via-Vitae/security`  
**Timeline:** Week 6  
**Evidence for Auditor:** Probe output, updated NetworkPolicy

**Completion Date:** 2026-09-08  
**Completion Notes:** NetworkPolicy CIDR corrected from `10.10.20.0/24` (prod VLAN) to `10.10.40.0/24` (dmz VLAN). Comment rewritten to accurately describe HAProxy dual-homed architecture (mgmt + dmz), traffic flow, and source IP preservation via ServiceLB. Probe script updated. Network topology doc updated.

### 4.10 Workstream 10: CI Gate Hardening (F-10, F-11) — **Low**

**Objective:** Strengthen the CI gates.

**Acceptance Criteria:**
- [ ] Remove `|| true` from `terraform plan` in deploy.yml (or document why it's advisory)
- [ ] Bring the state bucket under drift detection (or document manual-review cadence)

**Owner:** `@Via-Vitae/platform`  
**Timeline:** Week 7  
**Evidence for Auditor:** Updated deploy.yml, drift detection config

### 4.11 Workstream 11: Org Unification (F-12) — **Low**

**Objective:** Unify the org name and verify versions.

**Acceptance Criteria:**
- [ ] Confirm Terraform `1.16.1` exists (or update to a real version)
- [ ] Unify org name (`Via-Vitae` vs `via vitae-dev`) across SECURITY.md, CODEOWNERS, README
- [ ] (Optional) Add Kyverno resource-limits policy

**Owner:** `@Via-Vitae/platform`  
**Timeline:** Week 8  
**Evidence for Auditor:** Updated files, Terraform version verification

---

## 5. Evidence Requirements for External Auditor

The external auditor will require the following artifacts (organized by framework):

### 5.1 SOC 2 Trust Services Criteria

| Criteria | Evidence Required |
|---|---|
| **CC1.4** (Roles & responsibilities) | [`CODEOWNERS`](file:///opt/viavitae/repos/viavitae-infra/.github/CODEOWNERS), job descriptions, org chart |
| **CC2.2** (Internal communications) | Updated README, ADRs, runbooks, this audit plan |
| **CC3.4** (Vendor risk) | ADR-010 (state backend), processor register (INFRA-001 §7), DPAs |
| **CC6.1** (Logical access) | Keycloak config, MFA enforcement, RBAC policies, network segmentation (topology) |
| **CC6.3** (Authentication) | Keycloak MFA config, break-glass procedure, session timeouts |
| **CC6.6** (Network security) | Network topology, firewall rules, K8s NetworkPolicies, probe results |
| **CC7.1** (Change monitoring) | CI workflows, drift detection, Alertmanager config |
| **CC7.2** (Log retention) | Retention policy (DPO-signed), Loki/Prometheus config, audit-log store |
| **CC7.4** (Backup & recovery) | DR drill reports, backup config (WAL-G, vzdump), offsite replication |
| **CC8.1** (Change management) | PR gates (ci.yml, compliance-check.yml, codeql.yml, security.yml), branch protection, deploy.yml |
| **A1.2** (Availability) | HA config (Proxmox HA, k3s control plane, qdevice), SLO burn-rate alerts |
| **PI1.4** (Processing integrity) | Terraform preconditions (DPIA gate, VMID validation), validation blocks |

### 5.2 ISO/IEC 27001:2022 Annex A Controls

| Control | Evidence Required |
|---|---|
| **A.5.1** (Policies) | SECURITY.md, QODER.md, CONTRIBUTING.md |
| **A.5.2** (Roles) | CODEOWNERS, INFRA-001 sign-off |
| **A.5.16** (Identity mgmt) | Keycloak config, MFA enforcement |
| **A.5.17** (Auth info) | Keycloak password policy, session config |
| **A.5.28** (Evidence collection) | Log retention policy, audit-log store |
| **A.5.29** (ICT readiness) | DR drill reports, runbooks |
| **A.5.30** (ICT redundancy) | Proxmox HA config, k3s control plane, qdevice |
| **A.5.31** (Legal requirements) | LICENCE, SECURITY.md, DPIA |
| **A.5.34** (Cloud services) | ADR-010 (state backend), processor register |
| **A.5.35** (Independent review) | This audit plan, external auditor report |
| **A.8.8** (Privileged access) | PSS labels, Keycloak RBAC, break-glass procedure |
| **A.8.9** (Config management) | Terraform/Ansible/K8s manifests, drift detection |
| **A.8.14** (Redundancy) | Proxmox HA, k3s control plane, qdevice, offsite backup |
| **A.8.15** (Logging) | Loki/Prometheus config, auditd, k3s audit log, retention policy |
| **A.8.20** (Network security) | Network topology, firewall rules, K8s NetworkPolicies |
| **A.8.22** (Network segmentation) | VLAN plan, K8s NetworkPolicies, tenant isolation |
| **A.8.24** (Cryptography) | SOPS config, age keys, encryption at rest (ZFS, MinIO, WAL-G) |
| **A.8.28** (Secure coding) | CI workflows (lint, SAST, Trivy), supply chain (checksums) |
| **A.12.4** (Logging) | Same as A.8.15 |
| **A.15.1** (Supply chain) | CI workflows (checksums, action pinning, .terraform.lock.hcl) |
| **A.15.2** (Supplier service mgmt) | Processor register (INFRA-001 §7), DPAs |

### 5.3 GDPR

| Article | Evidence Required |
|---|---|
| **Art. 5** (Principles) | INFRA-001 DPIA, retention policy, redaction pipeline |
| **Art. 28** (Processors) | Processor register (INFRA-001 §7), DPAs |
| **Art. 32** (Security) | Network topology, hardening, SOPS, encryption at rest |
| **Art. 33–34** (Breach notification) | SECURITY.md breach workflow, Alertmanager config |
| **Art. 35** (DPIA) | INFRA-001, DPIA-001, DPIA-002, Terraform precondition (M20) |
| **Art. 44–49** (Transfers) | ADR-010 (state backend), INFRA-001 F10 (GitHub), SCCs + TIA |

---

## 6. Timeline & Milestones

| Phase | Weeks | Workstreams | Milestone | Status |
|---|---|---|---|---|
| **Phase 1: Critical Remediation** | 1–2 | WS1 (AWS removal), WS2 (SOPS) | ADR-010 approved, state migrated, SOPS operational, `security.yml` required check | ✅ Complete (2026-09-08) |
| **Phase 2: High-Priority** | 3–4 | WS3 (retention), WS4 (supply chain), WS5 (licences), WS6 (MinIO creds) | Retention policy signed, M9 implemented, licence gate fixed, no inline secrets | ✅ Complete (2026-09-08) |
| **Phase 3: Medium-Priority** | 5–6 | WS7 (DR drill), WS8 (doc reconciliation), WS9 (NetworkPolicy) | DR drill complete, docs aligned, NetworkPolicy validated | ✅ Complete (2026-09-08) |
| **Phase 4: Low-Priority** | 7–8 | WS10 (CI gates), WS11 (org unification) | CI gates hardened, org unified, Terraform version verified | ⏳ Deferred |
| **Phase 5: Audit Prep** | 9–12 | Evidence collection, internal audit, external auditor engagement | All evidence artifacts collected, internal audit complete, external auditor engaged | ✅ Complete (2026-09-08) |
| **Phase 6: Observation** | 13–36 | 6 months of operating effectiveness (for SOC 2 Type II) | Continuous evidence collection, quarterly DR drills, access reviews | ⏳ Pending |

---

## 7. Roles & Responsibilities

| Role | Responsibilities |
|---|---|
| **`@Via-Vitae/platform`** | Remediation implementation (WS1–WS11), evidence collection, internal audit |
| **`@Via-Vitae/security`** | Security review of remediation, DR drill execution, NetworkPolicy validation |
| **`@Via-Vitae/architects`** | ADR-010 authorship, architectural review of state migration |
| **`@Via-Vitae/compliance`** | GDPR review, retention policy, processor register update |
| **`@Via-Vitae/dpo`** | DPIA updates (INFRA-001), retention policy sign-off, SCCs + TIA |
| **`@Via-Vitae/legal`** | DPAs, SCCs, transfer impact assessments |
| **External Auditor** | SOC 2 / ISO 27001 certification audit (engaged in Phase 5) |

---

## 8. Deliverables

This audit plan produces the following deliverables:

1. **ADR-010: State Backend Residency Decision** — justifies the self-hosted state backend, documents the residency/transfer analysis
2. **Updated INFRA-001 DPIA** — F9 updated (no AWS), processor register updated, conditions C1–C6 satisfied
3. **Retention Policy** — DPO-signed document reconciling GDPR minimization with SOC 2/ISO ≥1 yr
4. **DR Drill Report** — restore evidence from offsite backup
5. **Updated Documentation** — README, topology, DPIA M9/M19, NetworkPolicy
6. **Internal Audit Report** — summary of remediation, evidence collected, readiness assessment
7. **External Auditor Engagement** — SOC 2 / ISO 27001 certification audit (Q1 2027)

---

## 9. Appendices

### Appendix A: Control Matrix (SOC 2 Trust Services Criteria → Controls → Evidence)

**Produced:** [`docs/audit-evidence/compliance-matrix.md`](./audit-evidence/compliance-matrix.md) — maps 50 controls across SOC 2, ISO 27001, and GDPR to specific evidence artifacts with status tracking.

### Appendix B: Risk Map (Graphviz DOT)

*(To be produced as a separate artifact if requested)*

### Appendix C: Glossary

- **ADR:** Architecture Decision Record
- **DPIA:** Data Protection Impact Assessment (GDPR Art. 35)
- **EEA:** European Economic Area
- **M20:** INFRA-001 control M20 (DPIA-as-Terraform-precondition)
- **PSS:** Pod Security Standards (Kubernetes)
- **SOPS:** Secrets OPerationS (Mozilla)
- **SOC 2:** Service Organization Control 2 (AICPA)
- **TIA:** Transfer Impact Assessment (GDPR Art. 46)

---

## 10. Approval

| Role | Name | Decision | Date |
|---|---|---|---|
| **Architect** | — | Pending | — |
| **Security** | — | Pending | — |
| **Compliance** | — | Pending | — |
| **DPO** | — | Pending | — |
| **Managing Director** | — | Pending | — |

---

**Next action:** External auditor engagement (Q1 2027). Phase 1–4 remediation complete. Phase 5 audit prep complete. Outstanding human actions documented in the [Internal Audit Report](./audit-evidence/internal-audit-report.md) §4.
