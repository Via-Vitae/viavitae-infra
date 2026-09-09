# Retention Policy — ViaVitae Infrastructure

**Status:** Proposed (pending DPO sign-off)  
**Effective Date:** — (upon DPO approval)  
**Last Reviewed:** 2026-09-08  
**Next Review:** 2027-09-08 (annual) or upon significant change  
**Owner:** `@Via-Vitae/dpo`, `@Via-Vitae/security`  
**Related ADR:** [ADR-011: Security Log Retention](adr/ADR-011-security-log-retention.md)

---

## 1. Purpose

This policy defines the retention periods for infrastructure logs, audit trails, and operational data across the ViaVitae platform. It reconciles:

- **GDPR Art. 5(1)(e)** (storage limitation): Personal data must be retained no longer than necessary.
- **SOC 2 Type II CC7.2** and **ISO 27001:2022 A.8.15**: Security audit logs must be retained ≥1 year for audit evidence and forensic capability.

---

## 2. Scope

This policy applies to:

- **Infrastructure logs**: auditd, k3s API audit log, Keycloak auth events, application logs (Loki).
- **Metrics**: Prometheus TSDB, aggregated operational metrics.
- **Backup data**: PostgreSQL WAL-G snapshots, Proxmox vzdump backups, offsite replicas.
- **Terraform state**: State files, plan outputs, drift detection logs.

**Out of scope:** Application-layer business data (e.g., tenant records, deletion audit logs) — governed by the application's data retention policy.

---

## 3. Retention Periods

| Data Category | Retention | Storage Location | Protection | Legal Basis |
|---|---|---|---|---|
| **Raw application logs** (Loki, redacted) | 30 days | Self-hosted Loki, Vilnius LT | AES-256 at rest, redaction at ingestion | GDPR Art. 6(1)(f) legitimate interests (operational debugging); minimization per DPO decision |
| **Raw metrics** (Prometheus) | 30 days | Self-hosted Prometheus, Vilnius LT | AES-256 at rest, no person-level labels | GDPR Art. 6(1)(f); minimization |
| **PII-minimized security audit stream** (Option A, if approved) | 1 year | MinIO WORM bucket (`viavitae-security-audit`), Vilnius LT | Object lock (WORM), field exclusion, actor/resource hashing | GDPR Art. 6(1)(f) + Art. 4(1) (not "personal data" after hashing); SOC 2 CC7.2, ISO A.8.15 |
| **auditd host-level audit logs** | 90 days on-node, then overwritten | Each Proxmox/k3s node, Vilnius LT | Filesystem permissions (root-only), AES-256 at rest | GDPR Art. 6(1)(f); SOC 2 CC7.2 |
| **k3s API audit log** | 30 days | k3s control plane nodes, Vilnius LT | AES-256 at rest | GDPR Art. 6(1)(f); minimization |
| **Keycloak auth events** | 30 days (raw), 1 year (if shipped to WORM) | Keycloak DB → WORM bucket (if Option A) | AES-256 at rest, WORM (if shipped) | GDPR Art. 6(1)(f); SOC 2 CC7.2 |
| **PostgreSQL WAL-G backups** | 35 days | Offsite S3-compatible store, Vilnius LT | AES-256 at rest, encrypted with age | GDPR Art. 6(1)(f) (business continuity); contractual |
| **Proxmox vzdump backups** | 14 days (daily), 35 days (weekly) | Offsite S3-compatible store, Vilnius LT | AES-256 at rest, encrypted with age | GDPR Art. 6(1)(f); contractual |
| **Terraform state files** | Indefinite (versioned) | MinIO (`viavitae-tfstate-*`), Vilnius LT | AES-256 at rest, versioning, object lock | GDPR Art. 6(1)(f) (infrastructure continuity); SOC 2 CC8.1 |
| **Terraform plan outputs** | 90 days | MinIO (`viavitae-tfstate-*`), Vilnius LT | AES-256 at rest | GDPR Art. 6(1)(f); SOC 2 CC8.1 |

---

## 4. Decision Required: Security Audit Log Retention

**ADR-011** presents three options for reconciling GDPR minimization with SOC 2/ISO audit evidence requirements. The DPO must choose one:

### Option A: PII-Minimized Tamper-Evident Security Audit Stream (Recommended)

- Ship auditd + k3s API audit + Keycloak auth events to a **WORM bucket** on MinIO.
- Apply aggressive field exclusion: strip user-agent, source IP, session tokens; hash actor and resource names.
- Retain for **1 year** (or longer if required by legal).
- **GDPR status**: After hashing, logs are not "personal data" (Art. 4(1)), so 1-year retention is permissible.
- **SOC 2/ISO status**: Compliant (CC7.2, A.8.15).
- **Effort**: Medium (1–2 weeks).

### Option B: Accept 30-Day Retention, Downgrade SOC 2/ISO Claims

- Keep current 30-day retention for all logs.
- Formally downgrade SOC 2/ISO claims to "30-day audit evidence."
- **GDPR status**: Compliant (minimal retention).
- **SOC 2/ISO status**: Non-compliant (cannot provide 12 months of audit evidence).
- **Effort**: Low (documentation only).

### Option C: Hybrid — Raw 30d + Anonymized Security Signals 1yr

- Retain raw logs 30 days; ship anonymized aggregates (event counts, failure rates) to 1-year store.
- **GDPR status**: Compliant (raw logs minimized; aggregates not personal data).
- **SOC 2/ISO status**: Partial compliance (aggregates insufficient for individual event reconstruction).
- **Effort**: Medium (1–2 weeks).

**Recommendation:** Option A (see [ADR-011](adr/ADR-011-security-log-retention.md) for full analysis).

---

## 5. DPO Sign-Off

The DPO must approve:

1. **The chosen retention option** (A, B, or C) for security audit logs.
2. **The field exclusion list** (if Option A): which fields are stripped or hashed before long-term retention.
3. **The annual review date** (default: 1 year from approval).

**Sign-off is recorded below and in [ADR-011](adr/ADR-011-security-log-retention.md).**

| Role | Name | Decision | Date | Signature |
|---|---|---|---|---|
| **DPO** | — | ☐ Option A ☐ Option B ☐ Option C | — | — |
| **Security** | — | ☐ Option A ☐ Option B ☐ Option C | — | — |
| **Platform** | — | ☐ Option A ☐ Option B ☐ Option C | — | — |

**Field Exclusion List (Option A only):**

| Field | Action | Rationale |
|---|---|---|
| User-agent | Strip | Not needed for audit; high PII value |
| Source IP | Strip | High PII value; not needed after hashing actor |
| Session tokens | Strip | Secrets; never retained |
| Actor (username) | Hash (SHA-256) | Traceable but not reversible |
| Resource (object name) | Hash (SHA-256) | Traceable but not reversible |
| Event type | Retain | Needed for audit (e.g., `login`, `sudo`, `api-call`) |
| Timestamp | Retain | Needed for timeline reconstruction |
| Outcome (success/failure) | Retain | Needed for audit |

**DPO approval of field exclusion list:** ☐ Approved ☐ Rejected ☐ Modified (see comments below)

---

## 6. Review and Amendment

- **Annual review**: This policy is reviewed at least annually by the DPO.
- **Trigger-based review**: Mandatory immediate review on:
  - A personal data breach affecting log data.
  - A change in legal requirements (e.g., new GDPR guidance, SOC 2 criteria update).
  - A change in infrastructure (e.g., new log source, new storage location).
  - A data subject request that reveals a gap in retention or erasure capability.
- **Amendment process**: Changes to retention periods or field exclusion lists require DPO re-approval and an updated ADR.

---

## 7. Enforcement

- **Technical enforcement**: Retention periods are enforced by:
  - Loki `retention_period` configuration ([`monitoring/loki/values.yaml`](../monitoring/loki/values.yaml)).
  - Prometheus `storage.tsdb.retention.time` configuration.
  - MinIO lifecycle rules and object lock configuration.
  - auditd `max_log_file_action` and `num_logs` settings.
- **Audit enforcement**: Drift detection and CI gates verify that retention configurations match this policy.
- **Exception process**: Any deviation from this policy requires DPO written approval and an ADR documenting the risk acceptance.

---

## 8. References

- [ADR-011: Security Log Retention](adr/ADR-011-security-log-retention.md) — full analysis of options.
- [INFRA-001 DPIA](DPIA-template.md) — flows F5, M4 (logging and retention).
- [audit-plan.md](audit-plan.md) — Finding F-3 (retention conflict).
- [monitoring/loki/values.yaml](../monitoring/loki/values.yaml) — Loki retention configuration.
- [ansible/roles/k3s/templates/config.yaml.j2](../ansible/roles/k3s/templates/config.yaml.j2) — k3s API audit log configuration.
