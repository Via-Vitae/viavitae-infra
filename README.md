# viavitae-infra

[![CI](https://github.com/Via-Vitae/viavitae-infra/actions/workflows/ci.yml/badge.svg)](https://github.com/Via-Vitae/viavitae-infra/actions/workflows/ci.yml)
[![Compliance](https://github.com/Via-Vitae/viavitae-infra/actions/workflows/compliance-check.yml/badge.svg)](https://github.com/Via-Vitae/viavitae-infra/actions/workflows/compliance-check.yml)
[![CodeQL](https://github.com/Via-Vitae/viavitae-infra/actions/workflows/codeql.yml/badge.svg)](https://github.com/Via-Vitae/viavitae-infra/actions/workflows/codeql.yml)
[![Licence](https://img.shields.io/badge/licence-Proprietary-0E1B3D?labelColor=F7F4EC)](LICENSE)
[![EU hosted](https://img.shields.io/badge/hosted-EU-0E1B3D?labelColor=F7F4EC)](SECURITY.md)

> Infrastructure-as-code for the ViaVitae self-hosted platform: Proxmox VE
> hypervisors, Kubernetes (k3s) clusters, PostgreSQL, monitoring, backup, and
> the CI/CD pipeline that deploys everything. EU-only, no cloud providers.

ViaVitae builds church-vertical websites, e-commerce and a marketplace for an EU pilot
in Lithuania, on self-hosted Proxmox infrastructure. Personal data stays in the EEA.

---

## Table of Contents

- [Architecture](#architecture)
- [Repository layout](#repository-layout)
- [Secret management](#secret-management)
- [Quality gates](#quality-gates)
- [Security and compliance](#security-and-compliance)
- [Branch protection](#branch-protection)
- [Documentation](#documentation)
- [Licence](#licence)

---

## Architecture

| Layer | Technology | Purpose |
| --- | --- | --- |
| Hypervisor | Proxmox VE 8.x | Bare-metal VM host, VLAN isolation |
| Kubernetes | k3s (lightweight) | Container orchestration for app workloads |
| Ingress | HAProxy + cert-manager | TLS termination, Let's Encrypt automation |
| GitOps | Argo CD | Declarative deployment from Git |
| Database | PostgreSQL 16 | Multi-tenant RDBMS with per-tenant schemas + RLS |
| IAM | Keycloak | Identity provider, SSO, SAML/OIDC |
| Monitoring | Prometheus + Grafana + Loki + Alertmanager | Metrics, logs, alerts |
| Backup | WAL-G (Postgres) + Proxmox vzdump | Point-in-time + snapshot backup |
| Secrets | SOPS + age | Encrypted-at-rest secrets in Git |
| IaC | Terraform (Proxmox provider) + Ansible | Provisioning and configuration |

## Repository layout

```text
viavitae-infra/
+-- README.md                     # This file
+-- LICENSE / SECURITY.md / QODER.md / CONTRIBUTING.md / CHANGELOG.md
+-- .sops.yaml                    # SOPS encryption rules (age key recipients)
+-- .editorconfig / .gitignore
+-- .github/
|   +-- CODEOWNERS                # @JourneyOfLife + @IterVitae — see ADR-000
|   +-- dependabot.yml            # terraform + github-actions ecosystems
|   +-- workflows/
|       +-- ci.yml                # Lint (terraform fmt, ansible-lint), SAST, Trivy
|       +-- compliance-check.yml  # Gitleaks, licences, governance, action-pinning
|       +-- codeql.yml            # Static analysis
|       +-- deploy.yml            # Terraform plan/apply + Ansible via OIDC
+-- terraform/
|   +-- main.tf / versions.tf / outputs.tf   # Root module
|   +-- envs/{dev,staging,prod}/             # Per-env roots (backend.tf, vars)
+-- ansible/
|   +-- ansible.cfg / requirements.yml
|   +-- playbooks/                # k3s-bootstrap, hardening, postgres, keycloak, etc.
|   +-- roles/                    # 9 roles: common, hardening, k3s, postgres, etc.
|   +-- inventories/{dev,staging,prod}/  # Hosts + SOPS-encrypted vault vars
+-- k8s/
|   +-- argocd/                   # Root app, applicationsets, projects
|   +-- namespaces/               # api, web, cert-manager, ingress, monitoring
|   +-- platform/{dev,staging,prod}/  # Per-env workload placeholders
|   +-- policies/                 # Network policies, Kyverno, pod-security, RBAC
|   +-- secrets/external-secrets/ # ClusterSecretStore, namespace
|   +-- ingress/                  # cert-manager ClusterIssuer, HAProxy
+-- monitoring/
|   +-- prometheus/ / loki/ / grafana/ / alertmanager/  # Helm values
|   +-- alert-rules/              # SLO burn rate, backup failure alerts
|   +-- uptime-kuma/              # External uptime monitoring
+-- backup/
|   +-- drills/                   # Quarterly DR drill script + reports
|   +-- offsite/                  # Replication documentation
|   +-- proxmox/                  # Snapshot prune scripts
|   +-- wal-g/                    # WAL-G config + schedules
+-- docs/
    +-- architecture.md           # MADR ADRs (Talos-vs-k3s, Ceph-vs-ZFS, etc.)
    +-- adr/                      # ADR-000 governance, ADR-010..012
    +-- DPIA-template.md          # GDPR Article 35 assessment template
    +-- capacity-plan.md          # Resource planning
    +-- network-topology.md       # VLAN and network diagram
    +-- runbooks/                 # backup-restore, dr-drill, proxmox-node-failure
```

## Secret management

**No inline secrets are committed.** All sensitive values are encrypted via
[SOPS](https://github.com/getsops/sops) with [age](https://age-encryption.org/) keys.

- Ansible vault files: `ansible/inventories/*/group_vars/vault.sops.yml`
- Kubernetes secrets: `k8s/secrets/**/*.sops.yaml`
- Terraform vars: `terraform/**/*.sops.tfvars` (where needed)

The `.sops.yaml` at root defines creation rules mapping file paths to age key
recipients. The placeholder age keys must be replaced with actual operator public
keys before first encryption. Private keys must never be committed.

## Quality gates

Every pull request must pass:

| Gate | Tool | Threshold |
| --- | --- | --- |
| Terraform format | `terraform fmt -check` | zero diffs |
| Terraform validate | `terraform validate` per env | zero errors |
| Ansible lint | `ansible-lint` | zero findings |
| SAST | Semgrep, CodeQL | zero findings at or above the failure severity |
| Config scan | Trivy config | fail on `CRITICAL` |
| Dependencies | Trivy filesystem | fail on `CRITICAL` |
| Secrets | Gitleaks, full history | fail on any finding |
| Licences | allow-list scan | unknown licence fails |
| Governance | presence checks | all required files present |

## Security and compliance

- To report a vulnerability, follow the private disclosure process in
  [SECURITY.md](SECURITY.md). Do **not** open a public issue.
- All infrastructure is EU-hosted (Proxmox on-prem, Lithuania). No cloud providers.
- Network isolation via VLANs; Kubernetes network policies enforce pod-level isolation.
- Encrypted at rest: Postgres WAL, Proxmox VM disks, S3-compatible backup storage.
- A GDPR personal-data breach is notified to the supervisory authority within 72 hours.

## Branch protection

`main` is protected in the GitHub UI, not by anything in this repository, so the enforced
settings are recorded here as a checklist. Verify the live state with:

```bash
gh api repos/Via-Vitae/viavitae-infra/branches/main/protection
gh api repos/Via-Vitae/viavitae-infra/codeowners/errors   # must return zero errors
```

| Setting | Required | Verified 2026-09-09 |
| --- | --- | --- |
| Require a pull request before merging | on | on |
| Required approving reviews | 1 | 1 |
| Dismiss stale approvals on new commits | on | on |
| Require review from code owners | on | on |
| Require status checks to pass, strict | on | on |
| Required contexts | `CI status`, `Compliance status` | both present |
| Do not allow bypassing the above (enforce admins) | on | on |
| Require linear history | on | on |
| Allow force pushes | off | off |
| Allow deletions | off | off |
| Secret scanning and push protection | on | on |
| Dependabot alerts and security updates | on | on |
| Private vulnerability reporting | on | on |

Two deliberate deviations, both recorded in
[ADR-000](docs/adr/ADR-000-governance-sole-owner-four-eyes.md):

- **CodeQL is not a required context.** `codeql.yml` publishes `Analyze (<language>)`, which
  varies with what its `detect` job finds and reports nothing at all when it finds no
  scannable language. A required context that can silently never report blocks every pull
  request forever. It becomes required once the workflow publishes an aggregate status job.
- **Four-eyes review is configured but not yet enforceable.** A required approving review
  must come from a reviewer with write access, and `@IterVitae` currently has none, so the
  intended reviewer cannot satisfy the count. Until that access is granted, merging requires
  temporarily suspending `enforce_admins`, and every such merge must state the reason in the
  pull request. This is an accepted risk with compensating controls, not a satisfied control.

## Documentation

| Document | Purpose |
| --- | --- |
| [SECURITY.md](SECURITY.md) | Disclosure policy, SLA table, scope. |
| [ADR-000](docs/adr/ADR-000-governance-sole-owner-four-eyes.md) | Sole-owner governance, four-eyes model, and the DPO position. |
| [docs/architecture.md](docs/architecture.md) | MADR decision records (ADRs 001-009). |
| [docs/adr/](docs/adr/) | Standalone decision records (ADR-010 and later). |
| [docs/network-topology.md](docs/network-topology.md) | VLAN and network diagram. |
| [docs/capacity-plan.md](docs/capacity-plan.md) | Resource planning. |
| [docs/runbooks/](docs/runbooks/) | Operational runbooks (backup, DR, node failure). |

## Licence

Proprietary — All Rights Reserved. (c) ViaVitae IT Technologies. Governed by the
law of Lithuania (EU). See [LICENSE](LICENSE).
