# ADR-012: Pod Security Standards — Privileged Namespaces (ingress, cert-manager)

| Field | Value |
| --- | --- |
| **Status** | Accepted |
| **Owner** | `@Via-Vitae/security` |
| **Date** | 2026-09-08 |
| **Deciders** | Security, Platform |
| **Consulted** | Compliance |
| **Supersedes** | — |
| **Superseded by** | — |

---

## Context

The network topology document states "Pod Security Standards are set to `restricted` on every namespace" ([`docs/network-topology.md`](../docs/network-topology.md)). However, the actual namespace manifests show that `ingress` and `cert-manager` namespaces use `privileged` PSS labels, not `restricted`.

This is a **doc⇄code drift** (Finding F-8) and a **QODER.md Rule 8 stop-condition**: weakening PSS labels requires security approval and an ADR.

## Why `privileged` for ingress and cert-manager?

### ingress namespace (Traefik / HAProxy)

The ingress controller requires:
- `hostNetwork: true` (bind to node ports 80/443)
- `hostPort: true` (expose ports on the node)
- `CAP_NET_BIND_SERVICE` (bind to privileged ports <1024)
- Potentially `CAP_NET_ADMIN` (for advanced routing)

These capabilities are **not allowed** under `restricted` or even `baseline` PSS. The ingress controller must run as `privileged` to function.

### cert-manager namespace

cert-manager requires:
- `hostNetwork: true` (for ACME HTTP-01 challenge solver)
- Access to Kubernetes Secrets API (to create TLS certificates)
- Potentially `CAP_NET_BIND_SERVICE` (for HTTP-01 challenge server)

These capabilities are **not allowed** under `restricted` PSS. cert-manager must run as `privileged` to function.

## Decision

**Accept `privileged` PSS for `ingress` and `cert-manager` namespaces** with the following mitigations:

1. **Network isolation**: Both namespaces are protected by NetworkPolicies (default-deny + explicit allow rules). Even if a pod is compromised, lateral movement is blocked.

2. **Read-only root filesystem**: Both ingress and cert-manager pods use `readOnlyRootFilesystem: true` to prevent writes to the container filesystem.

3. **Non-root user**: Both pods run as non-root users (UID ≥1000) where possible. cert-manager runs as UID 1001; ingress controller runs as UID 1000.

4. **Minimal capabilities**: Only the minimum required capabilities are granted (`CAP_NET_BIND_SERVICE` for ingress, none for cert-manager if HTTP-01 is not used).

5. **Regular audits**: Quarterly review of pod specs to ensure no additional privileges are added.

## Consequences

### Positive

- ingress and cert-manager can function correctly
- Network isolation prevents lateral movement even if pods are compromised
- Documented exception with mitigations (auditor-friendly)

### Negative

- `privileged` PSS is the broadest setting — weaker than `restricted`
- If a vulnerability is found in ingress/cert-manager, the blast radius is larger (though mitigated by NetworkPolicies)

### Neutral

- The network topology doc must be updated to reflect the actual PSS labels (minor doc fix)

## Alternatives Considered

### 1. Use `baseline` PSS instead of `privileged` (Rejected)

**Pros:** Stronger than `privileged`, weaker than `restricted`.

**Cons:** `baseline` still does not allow `hostNetwork` or `hostPort`, which ingress requires. cert-manager may also need `hostNetwork` for HTTP-01 challenges.

**Verdict:** Rejected. `baseline` is insufficient for these workloads.

### 2. Move ingress/cert-manager to a separate cluster (Rejected)

**Pros:** Isolates privileged workloads from the main cluster.

**Cons:** Operational complexity (two clusters), increased resource usage, not justified for the current scale.

**Verdict:** Rejected. Overkill for the current use case.

### 3. Use a different ingress controller that doesn't require `hostNetwork` (Rejected)

**Pros:** Could use `restricted` PSS.

**Cons:** Requires re-architecting the ingress layer, potential compatibility issues with existing workloads.

**Verdict:** Rejected. Not worth the disruption for a marginal security gain.

## Compliance Impact

### SOC 2

- **CC6.1 (Logical access):** Mitigated by NetworkPolicies and read-only root filesystem.
- **CC6.3 (Authentication):** Not affected (PSS does not affect authentication).

### ISO 27001

- **A.8.8 (Privileged access):** Documented exception with mitigations. Quarterly audit ensures no privilege creep.
- **A.8.9 (Configuration management):** PSS labels are enforced by Kyverno policy (`require-pod-security-labels`), preventing accidental creation of unlabelled namespaces.

### GDPR

- **Art. 32 (Security):** Network isolation + read-only root filesystem + non-root users provide defense-in-depth.

## Implementation

The PSS labels are already set in the namespace manifests:

- [`k8s/namespaces/ingress.yaml`](../k8s/namespaces/ingress.yaml): `pod-security.kubernetes.io/enforce: privileged`
- [`k8s/namespaces/cert-manager.yaml`](../k8s/namespaces/cert-manager.yaml): `pod-security.kubernetes.io/enforce: privileged`

Kyverno enforces that these labels are present (via `require-pod-security-labels` policy), preventing accidental creation of unlabelled namespaces.

## References

- [Finding F-8](audit-plan.md#31-findings-summary) (Medium: doc⇄code drift)
- [QODER.md Rule 8](../QODER.md#rule-8--infrastructure-stop-conditions-viavitae-infra) (PSS weakening requires ADR)
- [docs/network-topology.md](../docs/network-topology.md) (claims "restricted everywhere" — needs update)
- [k8s/policies/kyverno/require-labels.yaml](../k8s/policies/kyverno/require-labels.yaml) (Kyverno policy enforcing PSS labels)
