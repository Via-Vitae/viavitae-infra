# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Entries are derived from [Conventional Commits](https://www.conventionalcommits.org/). A
commit whose title does not parse produces no release note, which is a defect in the
commit, not in the changelog.

## Commit types

| Type | Changelog section | Meaning |
| --- | --- | --- |
| `feat` | **Added** | A new feature. |
| `fix` | **Fixed** | A bug fix. |
| `perf` | **Changed** | A code change that improves performance. |
| `refactor` | **Changed** | A code change that neither fixes a bug nor adds a feature. |
| `docs` | **Documentation** | Documentation-only changes. |
| `test` | not released | Adding or correcting tests. |
| `build` / `ci` | **Infrastructure** | Build system, dependencies, or CI changes. |
| `chore` | not released | Other changes that do not modify source or tests. |
| `revert` | **Reverted** | Reverting a previous commit. |

Append `!` after the type or scope, and add a `BREAKING CHANGE:` footer, to mark a
**breaking change**. Breaking changes trigger a major version bump and are called out at
the top of the release section with the migration steps.

In this repository a breaking change is defined by its effect on running infrastructure,
not by its API surface: a plan containing `destroy` or `replace` against a `prod`
resource, a change of state backend or state key, a VMID renumbering, a VLAN or firewall
re-segmentation, a retention reduction, or a Kubernetes admission policy switched to
`Enforce` all require `!` and a `BREAKING CHANGE:` footer naming the maintenance window
and the rollback path.

## Enforcement

Changelog accuracy is enforced mechanically, not by goodwill:

- **Commits** are validated against the Conventional Commits grammar in CI. A malformed
  title fails the lint job.
- **Releases** are produced by `release-please` from the conventional commit history. It
  opens a release pull request that updates this file and bumps the version; merging it
  creates the tag. Where `release-please` is not enabled on a repository, the manual rule
  applies instead: the release pull request must update this file in the same change that
  bumps the version, and a version header without a date is a review blocker.
- **Every section** below a version header is present, even when empty, marked _None._ This
  makes a missing section visible as an omission rather than invisible as an absence.
- **Security** entries for a vulnerability are published only after the fix is deployed,
  and link the advisory rather than describing the exploit. See
  [SECURITY.md](SECURITY.md).

## Version headers

Format: `## [MAJOR.MINOR.PATCH] - YYYY-MM-DD`, using the UTC release date. The `Unreleased`
section collects changes that have landed on `main` but are not yet tagged.

Compare links for each version are maintained at the bottom of this file.

---

## [Unreleased]

### Added

_None._

### Changed

_None._

### Deprecated

_None._

### Removed

_None._

### Fixed

_None._

### Security

_None._

### Documentation

_None._

### Infrastructure

_None._

### Reverted

_None._

---

## [1.0.0] - 2026-09-06

Initial release of `viavitae-infra`: infrastructure as code and GitOps for the ViaVitae
platform on self-hosted, EU-resident Proxmox VE. Generated from `viavitae-template`
v1.0.0; the compliance baseline files are inherited unchanged except where this entry
records an infrastructure-specific extension.

### Added

- **Governance baseline** inherited from the template: `LICENSE`, `SECURITY.md`,
  `.editorconfig`, and the `.github/` ownership, Dependabot, pull-request and issue-form
  artefacts.
- `README.md` — architecture overview, environment topology, the Terraform/Ansible/Argo CD
  ownership boundary, quickstart, SLO and RPO/RTO tables, runbook index, quality gates, and
  the accepted-risk register.
- `QODER.md` — Rule 8 added: infrastructure stop-conditions covering irreversibility,
  ownership boundaries, quorum and capacity claims, secrets in state, backup verification
  and mandatory verification evidence.
- `CONTRIBUTING.md` — the `[infra]` change workflow (branch → local gates → plan → PR gates
  → approval → merge → apply), the evidence table per change class, and the rollback-path
  requirement.
- `.github/CODEOWNERS` — infrastructure ownership map: `@Via-Vitae/platform` for
  `terraform/`, `ansible/` and `k8s/`; `@Via-Vitae/security` for policies, secrets,
  backups and firewall rules; `@Via-Vitae/compliance` and `@Via-Vitae/dpo` for
  `docs/DPIA-template.md` and `docs/runbooks/`.
- `.github/dependabot.yml` — `terraform` and `github-actions` ecosystems only, weekly and
  grouped; the `npm`, `pip` and `docker` ecosystems from the baseline are removed because
  this repository has no Node, no third-party Python dependency and no Dockerfile.
- `.github/PULL_REQUEST_TEMPLATE.md` — adds the plan-output, rollback-path, DR-impact and
  maintenance-window sections required for infrastructure changes.
- `.github/workflows/ci.yml` — `terraform fmt`/`validate` per environment, `tflint`,
  `ansible-lint`, `helm template`, `kubectl --dry-run`, Kyverno policy tests, `shellcheck`
  and the Python tool tests.
- `.github/workflows/compliance-check.yml` — Gitleaks over full history, Trivy config
  (IaC misconfiguration), Checkov, the licence allow-list, governance presence checks and
  the action SHA-pinning gate.
- `.github/workflows/codeql.yml` — matrix of `actions` and `python`: GitHub Actions
  workflow analysis plus `tools/cost-estimate.py`.
- `.github/workflows/deploy.yml` — plan on pull request with the output posted as a
  comment, manual approval per GitHub Environment, then apply; no Argo CD sync, because
  ADR-004 makes delivery pull-based.
- `docs/architecture.md` — ADR-001 k3s over Talos, ADR-002 ZFS replication on two nodes
  with the quorum constraint stated, ADR-003 schema-per-tenant PostgreSQL, ADR-004 GitOps
  via Argo CD pull, ADR-005 SOPS/age over Vault, ADR-006 IaC scanner consolidation,
  ADR-007 Bitrix24 isolation, ADR-008 CI control-plane residency.
- `docs/DPIA-template.md` — INFRA-001, the infrastructure processing record covering logs,
  monitoring labels, IAM identities, backups and the CI control plane.
- `docs/network-topology.md` — VLAN plan, addressing, VMID allocation, the firewall rule
  table and the segmentation invariants.
- `docs/capacity-plan.md` — cluster sizing, growth assumptions, the tenant density model
  and the trigger points for the next hardware purchase.
- `docs/runbooks/` — `backup-restore.md`, `dr-drill.md`, `proxmox-node-failure.md`,
  authoritative in this repository and linked (not copied) from `viavitae-docs`.
- `terraform/` — a `global` root module owning Proxmox resource pools and the VMID
  allocation policy; seven modules (`proxmox-vm`, `k3s-node`, `postgres-vm`, `keycloak-vm`,
  `bitrix24-vm`, `tenant`, `monitoring-vm`); and `dev`, `staging`, `prod` environments each
  with their own S3 state key.
- `.tflint.hcl` — companion configuration required by the `tflint` gate in `ci.yml`.
- `ansible/` — `ansible.cfg` with the SOPS vars plugin and SSH hardening, pinned collection
  requirements, three inventories, nine playbooks and nine roles.
- `k8s/` — Argo CD install values, two `AppProject`s, five ApplicationSets and the
  app-of-apps root; platform namespaces with quotas and limit ranges; default-deny network
  policies, Pod Security Standards, least-privilege RBAC and Kyverno policies with test
  fixtures; HAProxy edge configuration and cert-manager issuers; SOPS recipient
  configuration.
- `monitoring/` — Prometheus, Alertmanager, Grafana and Loki values, six dashboards,
  Uptime Kuma monitors, and four alert-rule groups (SLO burn rate, backup failure,
  certificate expiry, tenant quota).
- `backup/` — WAL-G configuration and per-database schedules, the Proxmox `vzdump` schedule
  and a guarded snapshot prune script, the offsite 3-2-1 replication procedure, and the
  quarterly DR drill script with its report.
- `tools/` — `tenant-provision.sh` (validate and stage a tenant, then apply the Terraform
  half), `preflight.sh` (every local gate in one command) and `cost-estimate.py` (per-tenant
  infrastructure cost against the €30–50 monthly ceiling), standard library only.

### Changed

- `.gitignore` — extended from the baseline with Ansible, SOPS, Kubernetes, Proxmox backup
  and DR-drill artefact patterns.
- Proxmox VM snapshot cadence for `prod` from weekly to daily. A weekly VM snapshot
  alongside 5-minute WAL archiving is an incoherent RPO: the database recovers to within
  minutes while everything that is not the database loses a week.

### Deprecated

_None._

### Removed

- `main.py` and the IDE-generated `.idea/` project files. They were not part of the
  requested tree and their presence made the CI stack detector treat this repository as a
  Python application with no tests.
- `tfsec` and `KICS` from the compliance scanner list. `tfsec` reached end of life and was
  folded into Trivy; running three overlapping IaC scanners produces duplicate findings and
  alert fatigue without adding control coverage. See ADR-006.
- `argocd app sync` from `deploy.yml`. A push from CI contradicts the pull model decided in
  ADR-004 and creates a second writer for cluster state.
- The `npm`, `pip` and `docker` Dependabot ecosystems — no `package.json`, no third-party
  Python dependency and no Dockerfile exists in this repository. An ecosystem with nothing
  to update reports success while scanning nothing.

### Fixed

- `.terraform.lock.hcl` is committed rather than ignored. The template baseline ignores it,
  which discards the provider hashes and makes plans unreproducible; this repository
  negates that pattern and the `state-hygiene` gate in `ci.yml` enforces it.
- `k8s/secrets/` is re-included in `.gitignore`. The baseline `secrets/` pattern matched it
  and would have silently excluded `k8s/secrets/sops/.sops.yaml`, which holds the age
  recipients every decrypt depends on.
- `control_plane_count = 3` is rejected by a Terraform validation unless three distinct
  Proxmox target nodes are declared. Three etcd members on two nodes loses quorum on the
  first node failure by the pigeonhole principle, so the previous shape would have
  documented HA it could not deliver.
- The `dev` environment has a VLAN. The original four-VLAN plan (mgmt, prod, staging, dmz)
  left disposable `dev` workloads sharing a broadcast domain with `staging`.

### Security

- Bitrix24 is placed in the `dmz` VLAN with a default-deny egress allow-list and no route
  to the `mgmt` or `prod` VLANs. It is a closed-source vendor box that phones home for
  licence validation, so it is treated as untrusted rather than as a member of the platform.
  See ADR-007.
- Terraform never creates a database credential. The `tenant` module provisions the schema,
  the grants and the DNS record; the password is generated outside Terraform and delivered
  through SOPS, because any value passed as a resource argument is written to state in
  plaintext.
- PostgreSQL log and Loki pipeline redaction is applied at the collector, not at query time.
  Loki stores what it receives, so a redaction filter in Grafana would leave the personal
  data on disk.

### Documentation

- Every module carries a `README.md` with an inputs/outputs table and a usage example, and
  every Ansible role carries a `README.md` stating what it owns and what it must not touch.

### Infrastructure

- All CI jobs run on the self-hosted EEA runner pool. GitHub-hosted runners would place
  Terraform plans, Proxmox API tokens and kubeconfigs on US infrastructure, which the
  organisation's residency rule forbids. See ADR-008.

### Reverted

_None._

---

[Unreleased]: https://github.com/Via-Vitae/viavitae-infra/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Via-Vitae/viavitae-infra/releases/tag/v1.0.0
