# Audit Evidence Pack

**Purpose:** Centralized collection of evidence artifacts for SOC 2 / ISO 27001 / GDPR audits.

**Structure:**
- `soc2/` — SOC 2 Trust Services Criteria evidence
- `iso/` — ISO 27001 Annex A control evidence
- `gdpr/` — GDPR Article 32/35 evidence

**How to use:**
1. Each subdirectory contains a README listing required evidence
2. Evidence is collected during the 6-month observation period (for SOC 2 Type II)
3. Quarterly DR drills, access reviews, and redaction audits are stored here
4. External auditor reviews this pack during the certification audit

**Status:** Phase 1–5 complete. Internal audit report and compliance matrix produced. Evidence collection ongoing during 6-month observation period.

## Key Artifacts

- [`internal-audit-report.md`](./internal-audit-report.md) — Summary of all remediation work (WS1–WS7, WS9), readiness assessment, outstanding actions
- [`compliance-matrix.md`](./compliance-matrix.md) — Maps 50 controls (SOC 2, ISO 27001, GDPR) to evidence artifacts with status tracking

---

## SOC 2 Evidence (soc2/)

- CC1.4: CODEOWNERS, job descriptions
- CC2.2: Updated README, ADRs, runbooks
- CC3.4: ADR-010 (state backend), processor register (INFRA-001 §7)
- CC6.1: Keycloak config, MFA enforcement, RBAC policies
- CC6.3: Keycloak MFA config, break-glass procedure
- CC6.6: Network topology, firewall rules, K8s NetworkPolicies
- CC7.1: CI workflows, drift detection, Alertmanager config
- CC7.2: Retention policy (ADR-011), Loki/Prometheus config
- CC7.4: DR drill reports, backup config
- CC8.1: PR gates (ci.yml, compliance-check.yml, codeql.yml, security.yml)
- A1.2: HA config (Proxmox HA, k3s control plane, qdevice)
- PI1.4: Terraform preconditions (DPIA gate, VMID validation)

## ISO 27001 Evidence (iso/)

- A.5.1: SECURITY.md, QODER.md, CONTRIBUTING.md
- A.5.2: CODEOWNERS, INFRA-001 sign-off
- A.5.16: Keycloak config, MFA enforcement
- A.5.17: Keycloak password policy, session config
- A.5.28: Log retention policy (ADR-011), audit-log store
- A.5.29: DR drill reports, runbooks
- A.5.30: Proxmox HA config, k3s control plane, qdevice
- A.5.31: LICENCE, SECURITY.md, DPIA
- A.5.34: ADR-010 (state backend), processor register
- A.5.35: Audit plan, external auditor report
- A.8.8: PSS labels (ADR-012), Keycloak RBAC
- A.8.9: Terraform/Ansible/K8s manifests, drift detection
- A.8.14: Proxmox HA, k3s control plane, qdevice, offsite backup
- A.8.15: Loki/Prometheus config, auditd, k3s audit log
- A.8.20: Network topology, firewall rules, K8s NetworkPolicies
- A.8.22: VLAN plan, K8s NetworkPolicies, tenant isolation
- A.8.24: SOPS config, age keys, encryption at rest
- A.8.28: CI workflows (checksums, action pinning)
- A.15.1: CI workflows (checksums, action pinning, .terraform.lock.hcl)
- A.15.2: Processor register (INFRA-001 §7), DPAs

## GDPR Evidence (gdpr/)

- Art. 5: INFRA-001 DPIA, retention policy, redaction pipeline
- Art. 28: Processor register (INFRA-001 §7), DPAs
- Art. 32: Network topology, hardening, SOPS, encryption at rest
- Art. 33–34: SECURITY.md breach workflow, Alertmanager config
- Art. 35: INFRA-001, DPIA-001, DPIA-002, Terraform precondition (M20)
- Art. 44–49: ADR-010 (state backend), INFRA-001 F10 (GitHub), SCCs + TIA
