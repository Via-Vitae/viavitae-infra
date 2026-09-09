# ADR-011: Security Log Retention — GDPR Minimization vs. SOC 2/ISO 27001 Audit Evidence

| Field | Value |
| --- | --- |
| **Status** | Proposed (pending DPO + Security sign-off) |
| **Owner** | `@Via-Vitae/security`, `@Via-Vitae/dpo` |
| **Date** | 2026-09-08 |
| **Deciders** | DPO, Security, Platform |
| **Consulted** | Compliance, Legal |
| **Supersedes** | — |
| **Superseded by** | — |

---

## Context

The platform's logging retention policy is currently **30 days** for all security-relevant logs:

- **Loki** (application logs, redacted): 30 days ([`monitoring/loki/values.yaml`](../monitoring/loki/values.yaml#L16))
- **Prometheus** (metrics, raw): 30 days ([`monitoring/prometheus/values.yaml`](../monitoring/prometheus/values.yaml#L12))
- **auditd** (host-level audit): 90 days on-node, then overwritten
- **k3s API audit log**: 30 days (`audit-log-maxage=30` in [`ansible/roles/k3s/templates/config.yaml.j2`](../ansible/roles/k3s/templates/config.yaml.j2#L37))

This retention was chosen by the DPO as a **GDPR minimization measure** (INFRA-001 M4, F5): personal data in logs should be retained no longer than necessary, and 30 days is sufficient for most operational debugging.

However, **SOC 2 Type II** (CC7.2) and **ISO 27001:2022** (A.8.15, A.5.28) expect security audit logs to be retained for **≥1 year** to support:
- Incident investigation (retrospective analysis)
- Compliance audits (evidence of control operation over time)
- Forensic analysis (reconstructing attack timelines)

This creates a **conflict**: GDPR says "minimize retention" (30 days), while SOC 2/ISO say "retain audit evidence" (≥1 year). The master prompt §35/36 explicitly claims "logging retention ≥1yr", but the implementation is 30 days.

### Why This Matters

1. **SOC 2 audit failure**: An auditor will request 12 months of security logs. If we can only provide 30 days, we fail the audit.
2. **ISO 27001 non-conformity**: A.8.15 requires logging to be retained for a "defined period" — typically 1 year for security logs.
3. **Incident response limitation**: If a breach is discovered 6 months after it occurred, we cannot reconstruct the attack timeline.
4. **GDPR compliance**: Retaining personal data longer than necessary violates Art. 5(1)(e) (storage limitation).

### Current Mitigations

- **Redaction at ingestion** (INFRA-001 M3): Logs are redacted on-host before reaching Loki, removing most personal data (emails, IPs, tokens).
- **Downsampled metrics**: Prometheus retains 1-year aggregates without person-level labels (F2), but these are not audit logs.
- **Application-layer audit**: The app (not in this repo) may retain a 7-year deletion audit log (INFRA-001 R6 mitigation), but this is separate from infrastructure security logs.

---

## Decision

**This ADR presents three options. The DPO and Security teams must choose one.**

### Option A: PII-Minimized Tamper-Evident Security Audit Stream (Recommended)

**Description:** Create a separate, PII-minimized security audit stream retained for ≥1 year in a tamper-evident (WORM) store.

**Implementation:**
1. Ship auditd + k3s API audit logs + Keycloak auth events to a **dedicated WORM bucket** on MinIO (reuse `state-01` or the offsite write-once target).
2. Apply aggressive field exclusion (strip user-agent, source IP, session tokens) — retain only:
   - Timestamp
   - Event type (e.g., `login`, `sudo`, `api-call`)
   - Actor (username, hashed)
   - Resource (object name, hashed)
   - Outcome (success/failure)
3. Enable object lock (WORM) on the bucket — logs cannot be deleted or modified.
4. Retain for 1 year (or longer if required by legal).

**Pros:**
- Satisfies SOC 2/ISO audit evidence requirements
- GDPR-compliant (PII minimized, not "personal data" after hashing)
- Tamper-evident (WORM) — auditor can trust the logs
- Reuses existing MinIO infrastructure

**Cons:**
- New ops burden (WORM bucket, log shipper config)
- Hashing makes logs less useful for debugging (can't reverse hashes)
- Requires DPO approval of the field exclusion list

**Effort:** Medium (1–2 weeks)

---

### Option B: Accept 30-Day Retention, Downgrade SOC 2/ISO Claims

**Description:** Keep the current 30-day retention and formally downgrade the SOC 2/ISO claims.

**Implementation:**
1. Update master prompt §35/36 to state: "Security logs retained 30 days (GDPR minimization). SOC 2/ISO audit evidence is limited to 30 days."
2. Document the risk acceptance in INFRA-001 §8 (residual risk).
3. Compensate with:
   - More frequent log reviews (weekly, not quarterly)
   - Real-time alerting (Alertmanager) for critical events
   - Application-layer audit logs (7-year retention) as the primary audit trail

**Pros:**
- No implementation effort
- GDPR-compliant (minimal retention)
- Simpler ops

**Cons:**
- Fails SOC 2 Type II audit (cannot provide 12 months of logs)
- ISO 27001 non-conformity (A.8.15)
- Limited forensic capability (>30 days)
- May disqualify the platform from certain compliance-driven customers

**Effort:** Low (documentation only)

---

### Option C: Hybrid — Raw 30d + Anonymized Security Signals 1yr

**Description:** Retain raw logs for 30 days (GDPR), but ship anonymized security signals to a 1-year store.

**Implementation:**
1. Keep Loki/Prometheus at 30 days (raw logs, redacted).
2. Ship anonymized security signals (event counts, failure rates, actor hashes) to a separate 1-year store.
3. The 1-year store contains **aggregates, not individual events** — sufficient for trend analysis, not forensic reconstruction.

**Pros:**
- GDPR-compliant (raw logs minimized)
- Provides some long-term visibility (trends, anomalies)
- Lower storage cost than Option A

**Cons:**
- Cannot reconstruct individual events (>30 days)
- Less useful for forensics than Option A
- Still fails SOC 2 audit (requires individual event logs, not aggregates)

**Effort:** Medium (1–2 weeks)

---

## Recommendation

**Option A (PII-minimized tamper-evident stream)** is recommended because:

1. **Satisfies both GDPR and SOC 2/ISO**: After hashing, the logs are not "personal data" (GDPR Art. 4(1)), so the 1-year retention is permissible. The WORM store satisfies SOC 2 CC7.2.
2. **Forensic capability**: Individual events are retained (hashed, but traceable), enabling retrospective investigation.
3. **Reuses existing infrastructure**: MinIO on `state-01` already has object lock (WORM) enabled (per ADR-010).
4. **Auditor-friendly**: A WORM store with a documented field exclusion list is easy to explain to an auditor.

**Fallback:** If Option A is rejected (e.g., DPO concerns about hashing), use **Option C** as a compromise. **Option B** should only be chosen if the platform will never pursue SOC 2/ISO certification.

---

## Consequences

### If Option A is chosen

- **Positive:**
  - SOC 2/ISO audit-ready (1-year security log retention)
  - GDPR-compliant (PII minimized after hashing)
  - Forensic capability for >30-day incidents
  - Tamper-evident (WORM) — auditor trust

- **Negative:**
  - New ops burden (WORM bucket, log shipper)
  - Hashing reduces log usability (can't reverse hashes)
  - Requires DPO approval of field exclusion list

- **Neutral:**
  - Storage cost increase (1-year retention vs. 30 days) — mitigated by hashing (smaller logs)

### If Option B is chosen

- **Positive:**
  - No implementation effort
  - GDPR-compliant (minimal retention)

- **Negative:**
  - Fails SOC 2/ISO audit
  - Limited forensic capability
  - May disqualify compliance-driven customers

### If Option C is chosen

- **Positive:**
  - GDPR-compliant (raw logs minimized)
  - Some long-term visibility (trends)

- **Negative:**
  - Cannot reconstruct individual events (>30 days)
  - Still fails SOC 2 audit (requires individual events)

---

## Compliance Impact

### GDPR

- **Option A**: Compliant. After hashing, logs are not "personal data" (Art. 4(1)), so 1-year retention is permissible. The field exclusion list must be approved by the DPO.
- **Option B**: Compliant. 30-day retention is minimal.
- **Option C**: Compliant. Raw logs are 30 days; aggregates are not personal data.

### SOC 2 Type II

- **Option A**: Compliant. CC7.2 requires "a defined retention period" — 1 year is standard.
- **Option B**: Non-compliant. Cannot provide 12 months of audit evidence.
- **Option C**: Non-compliant. Aggregates are not sufficient (requires individual events).

### ISO 27001:2022

- **Option A**: Compliant. A.8.15 requires logs to be retained for a "defined period" — 1 year is standard.
- **Option B**: Non-conformity. A.8.15 expects ≥1 year for security logs.
- **Option C**: Partial compliance. Aggregates provide some visibility, but not individual event reconstruction.

---

## Implementation Plan (Option A)

If Option A is chosen, the implementation is:

1. **Configure log shipper** (Vector or Fluent Bit) on each host to ship auditd + k3s API audit logs to a WORM bucket.
2. **Define field exclusion list** (DPO-approved): strip user-agent, source IP, session tokens; hash actor and resource names.
3. **Create WORM bucket** on MinIO (`viavitae-security-audit`) with object lock enabled.
4. **Set retention policy** to 1 year (or longer if required by legal).
5. **Update INFRA-001** F5/M4 to document the new audit stream.
6. **Update master prompt §35/36** to state "security audit logs retained 1 year (PII-minimized, WORM)."

**Deliverables:**
- Log shipper config (Vector/Fluent Bit)
- WORM bucket bootstrap (MinIO `mc` commands)
- Field exclusion list (DPO-approved)
- INFRA-001 update
- Master prompt update

**Timeline:** 1–2 weeks (after DPO + Security sign-off).

---

## Alternatives Considered

### 1. Extend Loki retention to 1 year (Rejected)

**Pros:** Simple (change one number in `loki/values.yaml`).

**Cons:** Violates GDPR (personal data retained longer than necessary). The DPO explicitly chose 30 days for minimization.

**Verdict:** Rejected. GDPR minimization takes precedence.

### 2. Use a third-party log archive service (e.g., AWS CloudTrail, Datadog) (Rejected)

**Pros:** Managed service, built-in compliance.

**Cons:** Introduces a new US-jurisdiction processor (CLOUD Act exposure), violates the "no cloud providers" invariant.

**Verdict:** Rejected. Residency invariant.

### 3. Retain logs on offline media (Rejected)

**Pros:** Maximum security (air-gapped).

**Cons:** Impractical for daily ops (slow retrieval), not auditable (auditor cannot verify integrity).

**Verdict:** Rejected. Operational impracticality.

---

## Sign-Off

**This ADR requires sign-off from DPO, Security, and Platform.** Sign-off is recorded in both this ADR and the [Retention Policy](../retention-policy.md).

**Instructions for sign-off:**
1. Review the three options above (A, B, C) and their compliance impact.
2. Each role marks their chosen option with an `X` in the checkbox.
3. Record the date and name.
4. If Option A is chosen, the DPO must also approve the field exclusion list in the Retention Policy.

| Role | Name | Decision | Date |
|---|---|---|---|
| **DPO** | — | ☐ Option A ☐ Option B ☐ Option C | — |
| **Security** | — | ☐ Option A ☐ Option B ☐ Option C | — |
| **Platform** | — | ☐ Option A ☐ Option B ☐ Option C | — |

---

## References

- [Finding F-3](audit-plan.md#31-findings-summary) (High: security/audit-log retention conflicts with SOC 2/ISO ≥1 yr)
- [INFRA-001 DPIA](DPIA-template.md#infra-001-infrastructure-platform-processing) (flows F5, M4)
- [monitoring/loki/values.yaml](../monitoring/loki/values.yaml#L16) (30-day retention)
- [ansible/roles/k3s/templates/config.yaml.j2](../ansible/roles/k3s/templates/config.yaml.j2#L37) (k3s API audit log 30 days)
- [ADR-010](adr/ADR-010-state-backend-residency.md) (MinIO with object lock — can be reused for audit stream)
