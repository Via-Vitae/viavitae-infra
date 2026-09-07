# Architecture Decision Records — viavitae-infra

This file is the ADR index and template for the repository. Every architectural decision
with a security, privacy, data-residency, cost, recovery or maintainability consequence is
recorded here. Decisions are made in conversations and lost; ADRs are how a team remembers
why the infrastructure is shaped the way it is, which is what makes it safe to change later.

Records follow [MADR](https://adr.github.io/madr/) adapted for a regulated EU context: the
**Compliance impact** section is mandatory here, because under rules R1 and R5 a decision
that touches personal data or residency cannot be taken without it.

> The decision to generate every ViaVitae repository from `viavitae-template` (rule R1) is
> recorded as ADR-001 **in the template repository** and is inherited here rather than
> restated. Numbering in this file therefore starts with the first infrastructure decision.

---

## When an ADR is required

Write an ADR before implementing, not after. An ADR written afterwards is a justification;
an ADR written before is a decision.

| Situation | ADR required |
| --- | --- |
| Choosing or replacing a hypervisor, container runtime, distribution or database | Yes |
| Choosing a replication, storage or backup mechanism | Yes |
| Any change to the tenancy model or to tenant isolation | Yes |
| Changing the delivery model (push vs pull), the admission controller or the secret store | Yes |
| Adding a third-party component, processor, registry or SaaS dependency | Yes |
| Accepting a licence outside the organisation's allow list | Yes |
| Any change to where data — including logs, metrics, state and backups — is stored | Yes |
| Adding or replacing a security scanner, or dropping one | Yes |
| Changing a VLAN boundary, a firewall default or an exposure to the internet | Yes |
| Accepting a known availability, recovery or capacity limitation | Yes |
| Diverging from `viavitae-template` governance or CI defaults (rule R1) | Yes |
| A bug fix inside an existing agreed design | No |
| Adding a dashboard, an alert threshold or a runbook step | No |

## Numbering convention

- Format: `ADR-NNN`, zero-padded to three digits, starting at `ADR-001`.
- Numbers are allocated sequentially from the index below and are **never reused**, even
  when a record is superseded or withdrawn. A retired number stays in the index so links
  from old pull requests and issues continue to resolve.
- The file heading is `## ADR-NNN: <short title in sentence case>`.
- Superseding a record does not delete it. Set its status to `Superseded by ADR-MMM` and
  leave the body intact. The history of what was tried and rejected is as valuable as the
  current decision.
- The ADR number is referenced in the commit message footer, the pull request description
  and any DPIA that depends on it.

## Status values

| Status | Meaning |
| --- | --- |
| `Proposed` | Under discussion. Implementation must not start. |
| `Accepted` | Agreed and in force. Implementation may proceed. |
| `Deprecated` | No longer applies to new work; existing systems may still depend on it. |
| `Superseded by ADR-MMM` | Replaced. Kept for history, links updated to the successor. |
| `Rejected` | Considered and declined. Kept so the question is not re-litigated. |

---

## Index

| ADR | Title | Status | Owner | Date |
| --- | --- | --- | --- | --- |
| [ADR-001](#adr-001-talos-vs-k3s-for-the-container-platform) | Talos vs k3s for the container platform | Accepted | Architects | 2026-09-06 |
| [ADR-002](#adr-002-ceph-vs-zfs-for-proxmox-storage) | Ceph vs ZFS for Proxmox storage | Accepted with conditions | Architects | 2026-09-06 |
| [ADR-003](#adr-003-schema-per-tenant-postgresql) | Schema-per-tenant PostgreSQL | Accepted | Architects | 2026-09-06 |
| [ADR-004](#adr-004-gitops-via-argo-cd-pull-not-push) | GitOps via Argo CD, pull not push | Accepted | Platform | 2026-09-06 |
| [ADR-005](#adr-005-secrets-with-sops-and-age-not-vault-in-the-pilot) | Secrets with SOPS and age, not Vault, in the pilot | Accepted | Security | 2026-09-06 |
| [ADR-006](#adr-006-iac-security-scanner-consolidation) | IaC security scanner consolidation | Accepted | Security | 2026-09-06 |
| [ADR-007](#adr-007-bitrix24-on-premises-isolation-and-vendor-risk) | Bitrix24 on-premises isolation and vendor risk | Accepted with conditions | Security | 2026-09-06 |
| [ADR-008](#adr-008-ci-control-plane-and-runner-residency) | CI control plane and runner residency | Accepted | Platform | 2026-09-06 |
| [ADR-009](#adr-009-licence-position-for-the-infrastructure-stack) | Licence position for the infrastructure stack | Accepted with conditions | Legal | 2026-09-06 |
| _ADR-010_ | _next available number_ | — | — | — |

New records are added at the end of this file and referenced from the table above, in the
same pull request. An ADR that is not in the index has not been made.

---

## ADR-001: Talos vs k3s for the container platform

| Field | Value |
| --- | --- |
| **Status** | Accepted |
| **Owner** | `@Via-Vitae/architects` |
| **Date** | 2026-09-06 |
| **Deciders** | Architects, Platform, Security |
| **Consulted** | Compliance, DPO |
| **Supersedes** | — |
| **Superseded by** | — |

### Context

The platform needs a Kubernetes distribution that runs on Proxmox virtual machines, inside
the EEA, operated by a team of two to four engineers, with no vendor support contract and
no dedicated storage or network appliance. It must run the `viavitae-web` and
`viavitae-api` workloads, host Argo CD, and support one namespace per tenant.

Two candidates were evaluated seriously:

- **Talos Linux** — an immutable, API-driven, minimal OS designed for Kubernetes. No SSH,
  no package manager, configuration is declarative through `talosctl`. Strong security
  posture out of the box.
- **k3s** — a CNCF-certified single-binary Kubernetes distribution that runs on a normal
  Linux distribution (Debian here), with embedded etcd or SQLite, bundled Traefik,
  CoreDNS, ServiceLB and local-path-provisioner.

Constraints that decided it: the team already operates Debian VMs and Ansible for every
other workload; every non-Kubernetes component (PostgreSQL, Keycloak, Bitrix24, the
monitoring stack, HAProxy) is a conventionally managed VM; and there is no capacity to
operate two different machine-management paradigms in the pilot.

### Decision

Run **k3s** on Debian 12 virtual machines, with the following specifics:

1. Target state for `prod` is **three control-plane VMs** with embedded etcd, spread one
   per Proxmox node, plus separate worker VMs. See the availability constraint in ADR-002:
   the pilot has two nodes and therefore runs one control-plane VM under Proxmox HA.
2. `staging` runs one control-plane VM plus one worker. `dev` runs a single node that is
   both, and is disposable.
3. The k3s version is pinned in `terraform/envs/<env>/terraform.tfvars` and reaches the
   guest as `/etc/viavitae/k3s-version` via cloud-init. `ansible/roles/k3s` reads that file
   and sets `INSTALL_K3S_VERSION` from it, failing when the file is absent instead of falling
   back to a role default — a silent default would be a second source of truth. Declaring the
   version in Terraform keeps an upgrade inside the plan a reviewer approves and inside the
   environment gate; installing it from Ansible keeps it idempotent, `--check`-able and
   rollback-able. This is the single-source-of-truth rule in `README.md`.
4. The bundled Traefik is kept as the in-cluster ingress controller. HAProxy on the load
   balancer VMs is a layer-4 SNI passthrough in front of it, not a second ingress
   controller — one place terminates TLS and renews certificates.
5. The bundled ServiceLB (klipper-lb) is kept for the node ports HAProxy forwards to.
   MetalLB is not introduced: a second load-balancer implementation on the same cluster is
   a source of IP-allocation conflicts, and the pilot has no need for it.
6. Node lifecycle is split by the ownership boundary: Terraform creates the VM and
   cloud-init installs k3s; Ansible performs cluster init, node join, kube-vip
   registration, label and taint enforcement, and upgrades.

### Consequences

**Positive**

- One machine-management paradigm (Debian + Ansible) for the whole estate, including the
  VMs that are not Kubernetes.
- k3s is a single binary with a small footprint: a control-plane VM needs 2 vCPU and 4 GB
  RAM rather than the 4 GB minimum a kubeadm control plane realistically wants, which
  matters directly on a two-node cluster with a fixed RAM budget.
- Bundled Traefik, CoreDNS, ServiceLB and local-path-provisioner remove four separate
  installation and upgrade tracks.
- Debian guest means the hardening role (`ansible/roles/hardening`) is the same CIS-style
  baseline used on every other VM, and the same audit tooling applies.
- CNCF-conformant, so nothing in `viavitae-web` or `viavitae-api` needs a k3s-specific
  accommodation.

**Negative and accepted**

- k3s bundles components that a full distribution would let us choose separately
  (containerd version, CNI, Traefik). An upstream CVE in a bundled component is fixed on
  the k3s release schedule, not ours. Mitigated by pinning the version and applying patch
  releases within 14 days, per the SLO table in `README.md`.
- Embedded etcd on k3s is less battle-tested at scale than an external etcd cluster, and
  k3s control-plane nodes are not interchangeable with a kubeadm control plane. Migration
  off k3s later would be a project, not a configuration change. Accepted: the migration
  path is a new cluster and Argo CD, not an in-place conversion.
- SQLite is the default datastore for a single-node cluster. `dev` uses it and is
  disposable; `staging` and `prod` use embedded etcd, because a cluster that cannot add a
  second control-plane node later is a dead end.
- SSH-based Ansible management is a larger attack surface than Talos's API-only model.
  Mitigated by key-only authentication, a management VLAN with no route from any other
  VLAN, and the CIS hardening role.

### Alternatives considered

| Alternative | Why rejected |
| --- | --- |
| Talos Linux | Genuinely better security posture, and the decision was close. Rejected because it would introduce a second machine-management paradigm (talosctl plus machineconfig, alongside Ansible for every other VM) for a team of two to four, and because its benefits concentrate in exactly the area this pilot is weakest in — operator time, not attack surface. Revisit when the estate passes six Proxmox nodes or a dedicated platform engineer is hired. |
| kubeadm on Debian | Full control over every component and no bundled-software surprises, at the cost of owning etcd backup and restore, certificate rotation, CNI selection, control-plane upgrades and kubelet configuration ourselves. That is roughly a quarter of an engineer continuously, which the pilot does not have. |
| MicroK8s | Snap-based packaging on Ubuntu, with a snapd dependency and a different upgrade mechanism from every other VM in the estate. Rejected for operational uniformity rather than for technical merit. |
| Nomad or plain Docker Compose | Simpler and cheaper, and adequate for the current workload count. Rejected because the tenancy model in ADR-003 and the delivery model in ADR-004 both assume Kubernetes primitives (namespaces, resource quotas, admission policy), and because `viavitae-web` and `viavitae-api` are already packaged as container images with Kubernetes manifests. |
| A managed Kubernetes service (EKS, GKE, AKS, Scaleway, OVH) | Would remove the control-plane operational burden entirely. Rejected on data residency and on the self-hosting requirement: the control plane, its etcd and the API audit log would sit with a third party, and the organisation's position is that the platform is self-hosted in the EEA on its own hardware. OVH and Scaleway are EEA-hosted and remain the fallback if hardware failure makes self-hosting untenable; adopting one requires superseding this ADR. |

### Compliance impact

| Area | Impact |
| --- | --- |
| GDPR | Neutral. k3s stores no personal data itself; the etcd datastore holds Kubernetes objects, which include Secret material and therefore must be covered by the backup and encryption controls in INFRA-001. |
| Data residency | Positive. Everything runs on ViaVitae hardware in the EEA. No control plane, telemetry endpoint or managed-service API is involved. |
| Special category data (Art. 9) | Neutral at this layer. Tenant namespaces carry workloads that may process Art. 9 data; isolation between them is a network-policy and RBAC concern (see `k8s/policies/`), not a distribution concern. |
| Breach exposure, Art. 33 | A compromised k3s control plane exposes every tenant Secret in etcd. Mitigated by encryption at rest for Secrets, which is enabled in `ansible/roles/k3s` and verified by the hardening role. |
| Licensing | k3s and Kubernetes are Apache-2.0. See ADR-009. |
| New processors | None. |
| DPIA | Covered by INFRA-001 in `docs/DPIA-template.md`. |

---

## ADR-002: Ceph vs ZFS for Proxmox storage

| Field | Value |
| --- | --- |
| **Status** | Accepted with conditions |
| **Owner** | `@Via-Vitae/architects` |
| **Date** | 2026-09-06 |
| **Deciders** | Architects, Platform, Security |
| **Consulted** | Compliance, Finance |
| **Supersedes** | — |
| **Superseded by** | — |

### Context

Two Proxmox VE nodes are available in the pilot. Guest disks must survive the loss of one
node, and the storage layer must not require an appliance, a support contract or a third
physical machine.

Ceph (via `pveceph`) provides distributed, synchronously replicated block storage with
live migration between nodes. It requires a minimum of three nodes for a usable CRUSH map
with `size = 2, min_size = 1`; on two nodes a Ceph monitor cluster has no quorum, and
Proxmox's own documentation does not support a two-node Ceph deployment.

ZFS with Proxmox's built-in **ZFS replication** (`pvesr`) provides asynchronous block
replication of a zvol to a second node. It works on two nodes because it does not need
quorum — it needs a target.

### Decision

Use **ZFS with Proxmox ZFS replication** on the two pilot nodes, with the following
conditions, which are the reason the status is "Accepted with conditions":

1. **Replication is asynchronous.** The default `pvesr` interval is 15 minutes. A node
   failure can therefore lose up to one replication interval of guest disk writes. The RPO
   for VM disks is documented as 24 hours because `vzdump` daily snapshots are the recovery
   source of record, not the ZFS replica; the replica is a warm spare that shortens RTO, not
   a guarantee.
2. **ZFS replication is not high availability.** A replicated VM does not start
   automatically on the surviving node. Failover is a documented manual procedure
   (`docs/runbooks/proxmox-node-failure.md`) with a target RTO of 15 minutes.
3. **A two-node cluster needs a quorum device.** Corosync on two nodes splits brain when
   the link between them fails, because neither side has a majority. A `qdevice` running on
   a third, small machine — a Raspberry Pi or a VM on unrelated hardware is sufficient — is
   a prerequisite for enabling Proxmox HA, and is not optional. It is recorded in
   `docs/network-topology.md` as infrastructure, not as a suggestion.
4. **The three-control-plane decision in ADR-001 is not achievable on two nodes.** Three
   etcd members placed on two hosts are distributed 2 + 1 by the pigeonhole principle, so
   the failure of either host always removes at least two members and always loses quorum.
   A configuration that is described as HA and cannot survive the failure it is designed
   for is worse than one that is described accurately. Therefore:
   - while the cluster has two nodes, `prod` runs **one** control-plane VM with Proxmox HA
     enabled, and the availability SLO is 99.5 %, not 99.9 %;
   - `terraform/modules/k3s-node` and `terraform/envs/prod` carry a validation that
     **rejects `control_plane_count = 3` unless three distinct target nodes are declared**,
     so the impossible configuration cannot be applied by accident;
   - the third Proxmox node is the single trigger for switching `control_plane_count` to 3
     and raising the SLO. That trigger is listed in `docs/capacity-plan.md`.
5. **Scrubs are scheduled**, monthly, and a scrub failure is a page, not a ticket: silent
   corruption in a replicated zvol is copied to the replica at the next sync.
6. **ARC is capped** on each node to leave headroom for guest RAM. ZFS will otherwise take
   all available memory and the OOM killer decides which VM dies.

### Consequences

**Positive**

- Works on the two nodes that exist, with no third machine other than the qdevice.
- No Ceph monitor, OSD or manager daemons to operate, and no CRUSH map to reason about.
- ZFS gives checksummed data, so silent corruption is detected rather than served, and
  snapshot/rollback is instant and cheap.
- Compression (`lz4`) and thin provisioning reduce the effective storage purchase, which
  matters at pilot scale.

**Negative and accepted**

- Asynchronous replication means a real RPO gap at the VM-disk layer. Accepted because the
  database — the only component with an RPO that matters — is protected by WAL-G continuous
  archiving at 5 minutes, independently of the hypervisor.
- No live migration between nodes without shared storage. Maintenance on a node means a
  shutdown-and-restart of its guests, not a migration. Accepted; it makes the maintenance
  window in `CONTRIBUTING.md` a real requirement rather than a formality.
- Memory overhead: ZFS ARC plus guest RAM on the same host needs the cap in condition 6, and
  getting it wrong presents as random VM kills under memory pressure.
- Rebuilding onto a replacement node is a full replication seed, which for a full pool takes
  hours and saturates the replication link. Documented in the node-failure runbook.

### Alternatives considered

| Alternative | Why rejected |
| --- | --- |
| Ceph on two nodes | Not supported: no monitor quorum, and `min_size = 1` on a two-node cluster means a single failure leaves the pool unwritable or, worse, writable with one copy. Running it anyway converts a survivable failure into data loss. |
| Ceph on three nodes | The right answer at three nodes, and the intended destination if the estate grows. Rejected for the pilot because the third node does not exist and Ceph also wants dedicated disks and a dedicated network to behave predictably. |
| NFS or iSCSI to a separate storage host | Adds a single point of failure and a third machine to buy, power and patch, which is exactly what the two-node budget excludes. |
| Shared LVM on a SAN | No SAN exists. |
| Local storage with `vzdump` backup only, no replication | Cheapest, and honest about being so. Rejected because RTO becomes a full restore from backup (4 hours) for every node failure, and the pilot has committed to a 15-minute RTO for the platform. The ZFS replica is what buys that. |

### Compliance impact

| Area | Impact |
| --- | --- |
| GDPR, Art. 32 | Encryption at rest is provided by ZFS native encryption on the guest-disk datasets, with keys held in SOPS. Without it, a physically stolen or decommissioned disk is a personal-data breach. |
| Data residency | Positive. All storage is on ViaVitae hardware in the EEA; the offsite copy is also in the EEA (see `backup/offsite/replication.md`). |
| Breach exposure, Art. 33 | A lost or improperly destroyed disk is a notifiable breach. ZFS encryption plus a documented destruction procedure in the node-failure runbook is the control. |
| Availability of processing, Art. 32(1)(b) | This ADR is the record that the availability control is **asynchronous replication with manual failover**, not HA. The limitation is stated rather than implied, which is what an auditor needs. |
| DPIA | INFRA-001 §Backups and storage. |

---

## ADR-003: Schema-per-tenant PostgreSQL

| Field | Value |
| --- | --- |
| **Status** | Accepted |
| **Owner** | `@Via-Vitae/architects` |
| **Date** | 2026-09-06 |
| **Deciders** | Architects, Platform, Security, DPO |
| **Consulted** | Finance |
| **Supersedes** | — |
| **Superseded by** | — |

### Context

Each client tenant needs its own data, its own retention period, its own export and its own
erasure path, while the pilot can afford one PostgreSQL instance rather than one per tenant.
Three models were considered: database-per-tenant, schema-per-tenant, and shared tables with
a `tenant_id` discriminator column.

The deciding requirements are GDPR-mechanical rather than performance-related: erasure of one
tenant must be complete and provable, export of one tenant must not include another's rows,
and a query bug must not become a cross-tenant disclosure.

### Decision

**Schema-per-tenant** on a single PostgreSQL instance per environment, with these rules:

1. One PostgreSQL schema per tenant, named exactly `t_<slug>` where `<slug>` matches
   `^[a-z][a-z0-9]{1,30}$` and is unique across the organisation. The `t_` prefix keeps
   tenant schemas out of the way of extension schemas (`public`, `extensions`, `wal_g`).
2. One PostgreSQL **role** per tenant application, named `app_<slug>`, with
   `NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT LOGIN`, `search_path = t_<slug>, public`
   set as a role default, and privileges granted only on `t_<slug>`. A tenant's role cannot
   read another tenant's schema, and cannot `SET ROLE` to one that can.
3. **Terraform creates the schema, the grants and the DNS record. Terraform never creates a
   credential.** A value passed as a resource argument is written to state in plaintext, and
   state is readable by anyone with bucket access. The role's password is generated outside
   Terraform, stored SOPS-encrypted in the tenant's repository, and applied by the
   `ansible/roles/postgres` role. This is why `terraform/modules/tenant` has no password
   input and no password output.
4. Migrations run **per schema**, driven by the application's migration tool with
   `search_path` set to the tenant schema, in a single ordered pass over all tenants. A
   migration that fails on tenant 7 of 25 stops the pass; the remaining tenants are not
   migrated. That is deliberate: a half-migrated estate with two schema versions is worse
   than a stopped rollout.
5. Connection pooling: `pgbouncer` in **transaction** mode is the only supported pooling
   configuration for tenant workloads, because session-mode pooling would pin one connection
   per tenant and exhaust `max_connections` at around 100 tenants. Transaction mode requires
   that no session-level state be relied upon — no `SET` outside a transaction, no prepared
   statements with binary parameters, no temporary tables, no advisory locks. These
   restrictions are recorded here because they are the ones that break first and break
   silently.
6. **Erasure** is `DROP SCHEMA t_<slug> CASCADE` plus `DROP ROLE app_<slug>`, followed by a
   WAL-G restore-point record so the erasure can be evidenced. Note the residual exposure:
   the dropped data remains in existing base backups and WAL archives until they age out of
   retention (35 days). That is documented in INFRA-001 and is the reason the retention
   period is part of the tenant contract, not an implementation detail.
7. **Export** is `pg_dump --schema=t_<slug>`, which cannot include another tenant's data
   because the role performing it has no privileges outside the schema.

### Consequences

8. **The `dev` environment is an explicit exception: its PostgreSQL runs in-cluster as a
   StatefulSet.** A dev database holds generated fixtures, and a 2 vCPU / 8 GiB VM to hold
   data nobody would miss is 8 GiB the estate does not have — `docs/capacity-plan.md` shows
   89 % of the memory budget already committed. Losing the dev database when the dev node is
   destroyed is the intended behaviour, not a failure. The exception is recorded here rather
   than left implicit in `terraform/envs/dev/main.tf`, because an exception nobody wrote down
   is the pattern somebody copies into `staging`, where the data is rehearsal data and the
   DR drill depends on it being real. `staging` and `prod` use an external PostgreSQL VM with
   WAL-G archiving and no exception.

**Positive**

- Erasure and export are single, provable operations rather than filtered queries whose
  `WHERE` clause is the only thing between two tenants' data.
- A missing `WHERE tenant_id = ...` — the single most common cause of cross-tenant
  disclosure in a shared-table design — is not merely avoided but impossible: the role
  cannot see the other schema.
- One instance to patch, back up, monitor and tune, which is what the pilot can afford.
- Per-tenant resource accounting is possible through `pg_stat_statements` keyed by role.

**Negative and accepted**

- Migration fan-out: N tenants means N schema migrations per release, and the release time
  grows linearly. At 25 tenants with a 3-second migration this is invisible; at 250 it is a
  deployment window. The trigger to move to database-per-tenant is 50 tenants or 500 GB,
  recorded in `docs/capacity-plan.md`.
- One instance is one blast radius: a bad configuration change, an exhausted connection
  pool or a runaway query affects every tenant simultaneously. Mitigated by per-role
  `statement_timeout` and `connection_limit`, both set by the postgres role.
- Backups are instance-wide. Restoring a single tenant requires a scratch restore of the
  whole instance followed by a schema-level dump and load, which is slow and is exactly what
  the quarterly DR drill rehearses (`backup/drills/dr-drill-quarterly.sh`).
- `pgbouncer` transaction mode rules out prepared statements and session state, which
  constrains the application's database access patterns. Accepted, and recorded here because
  the constraint is invisible until it fails.
- Cross-tenant reporting is impossible without a separate read path. Accepted: analytics are
  produced from per-tenant exports, not from a cross-schema query.

### Alternatives considered

| Alternative | Why rejected |
| --- | --- |
| Shared tables with a `tenant_id` column | Cheapest to operate and the only model that supports cross-tenant analytics natively. Rejected because isolation depends on every query being written correctly, forever, by every contributor; one omitted predicate is a reportable cross-tenant disclosure. Row-level security was considered as the mitigation, but RLS policies must be enabled per table, are bypassed by superuser and by `BYPASSRLS` roles, and are not enforced for a table someone forgot — the failure mode is silent. |
| Database-per-tenant | The strongest isolation, with per-tenant backup, restore, retention and resource limits all natural. Rejected for the pilot on cost: N databases means N connection pools, N WAL streams and N sets of statistics, and `max_connections` plus RAM become the binding constraint at roughly 40 tenants on the hardware in `docs/capacity-plan.md`. This is the destination model, not a rejected one — it is what the 50-tenant trigger moves to. |
| PostgreSQL instance per tenant on its own VM | Cleanest, and unaffordable: at 4 GB per instance the pilot's RAM budget covers six tenants. |
| A managed database service | Rejected on residency and on the self-hosting requirement, as in ADR-001. |

### Compliance impact

| Area | Impact |
| --- | --- |
| GDPR, Art. 17 (erasure) | Positive. Erasure is one DDL statement plus role drop, and it is evidenced by the migration log and the WAL-G record rather than by an assertion. |
| GDPR, Art. 20 (portability) | Positive. `pg_dump --schema` produces a tenant's data and nothing else. |
| GDPR, Art. 5(1)(f) integrity and confidentiality | Positive. Isolation is enforced by the database's own privilege system rather than by application code. |
| Residual exposure after erasure | Data remains in base backups and WAL archives for up to 35 days. Recorded in INFRA-001 and in the tenant contract; a supervisory-authority question about this has a written answer. |
| Special category data (Art. 9) | Tenant schemas will hold Art. 9 data (religious belief, pastoral notes). Encryption at rest covers the whole instance, so the schema model does not change the Art. 9 posture — but it does mean one instance compromise exposes every tenant's Art. 9 data, which is why the instance is not reachable from the `dmz` VLAN. |
| DPIA | INFRA-001 §Tenancy and isolation; the application-level DPIA for each tenant's data is raised in `viavitae-api`. |

---

## ADR-004: GitOps via Argo CD, pull not push

| Field | Value |
| --- | --- |
| **Status** | Accepted |
| **Owner** | `@Via-Vitae/platform` |
| **Date** | 2026-09-06 |
| **Deciders** | Platform, Architects, Security |
| **Consulted** | Compliance |
| **Supersedes** | — |
| **Superseded by** | — |

### Context

Kubernetes objects have to reach three clusters (`dev`, `staging`, `prod`) and one namespace
per tenant, from four source repositories (`viavitae-web`, `viavitae-api`, `viavitae-demos`,
`viavitae-clients`). Two delivery models are available:

- **Push**: CI builds a manifest or image, then runs `kubectl apply` or `argocd app sync`
  against the cluster with a cluster-admin credential held in CI.
- **Pull**: an in-cluster agent (Argo CD) watches Git, compares desired to actual, and
  reconciles. CI's only write action is a commit.

### Decision

**Pull, with Argo CD, and CI never writes to a cluster.** Specifically:

1. Argo CD runs in the `argocd` namespace of each cluster and reconciles on a 3-minute
   interval plus webhook-triggered refresh. Git is the only source of desired state.
2. `deploy.yml` contains **no `argocd app sync` and no `kubectl apply`**. The workflow the
   generated spec asked for included an Argo CD sync step; it was removed, because a sync
   issued from CI creates a second writer for cluster state. With two writers, the cluster
   can be in a condition that no Git commit describes, which is precisely the drift GitOps
   exists to eliminate — and it means a CI credential holder can force-apply without a
   commit, without a review and without an audit trail in Git.
3. One `AppProject` per environment boundary: `staging.yaml` allows the four ViaVitae
   repositories and the `staging` destination; `prod.yaml` allows only `Via-Vitae`
   repositories, requires a commit SHA rather than a branch as `targetRevision`, and
   requires signed images.
4. Tenant applications are generated, not written: the `clients` ApplicationSet uses a Git
   directory generator over `clients/<slug>` in `viavitae-clients`, so adding a tenant is a
   merged pull request in that repository and nothing else. This is the single mechanism for
   tenant Kubernetes objects — see consequence 3 below.
5. Platform applications (namespaces, policies, ingress issuers, monitoring) are generated by
   the `platform` ApplicationSet from this repository.
6. `root-app.yaml` is the app-of-apps entry point. It is applied once by hand during
   bootstrap; everything after that is pulled.
7. Automated sync with `prune: false` and `selfHeal: true` outside `prod`. In `prod`,
   `prune` and `selfHeal` are enabled only for the platform projects and disabled for
   tenant applications, because a self-healing prune on a tenant namespace is an automated
   deletion of a customer's workload triggered by a bad commit.

### Consequences

**Positive**

- The cluster credential lives in the cluster. CI holds no kubeconfig for any environment,
  which removes the single most valuable credential from the CI secret store.
- Every change to a running cluster corresponds to a merged commit, so `git log` is the
  change record an ISO 27001 or SOC 2 auditor asks for.
- Rollback is `git revert` plus a sync, and it is the same mechanism in every environment.
- Drift is detected continuously rather than at deploy time, and the Argo CD UI shows it per
  application.

**Negative and accepted**

1. **Bootstrap is a chicken-and-egg problem.** Argo CD must be installed by hand before
   anything can be pulled. Documented in `k8s/argocd/install/README.md`, and the manual step
   is recorded in the environment build checklist in `README.md` rather than hidden.
2. **CI cannot tell a developer whether their manifest is valid in the cluster.** The
   feedback loop is a red Argo CD application after merge, not a failing check before it.
   Mitigated by the manifest checks in `ci.yml` and by the Kyverno policy tests, which
   evaluate admission policy against committed fixtures without a cluster.
3. **Two mechanisms for one object is drift by construction.** The generated spec had
   `terraform/modules/tenant` creating the namespace, quota and Argo CD application *and*
   the `clients` ApplicationSet creating one application per tenant folder. The Terraform
   side was **removed**, not disabled: a flag that defaults to `false` is a flag that gets
   set to `true` during an incident, and the `hashicorp/kubernetes` provider would have put
   a cluster-admin kubeconfig into the CI credential set for a code path nobody intends to
   use. The module now owns exactly what Git cannot do — the PostgreSQL schema, the login
   role and the DNS record — and has no Kubernetes provider at all.
4. **Sync waves and ordering are our problem.** Namespaces and policies must exist before
   the workloads that land in them. Handled with `argocd.argoproj.io/sync-wave` annotations
   rather than by hoping Argo CD's apply order is favourable.
5. **Argo CD is itself an attack surface** with cluster-admin privileges. Mitigated by SSO
   through Keycloak, RBAC that gives no human `admin` outside a break-glass account, and a
   network policy that restricts the `argocd` namespace to the API server and the
   repositories it reads.

### Alternatives considered

| Alternative | Why rejected |
| --- | --- |
| Push from CI with a cluster-admin kubeconfig | Simpler to start and gives pre-merge feedback. Rejected because it places a cluster-admin credential in CI, makes the cluster state a function of which workflow ran last rather than of Git, and produces no change record that an auditor can follow. |
| Flux CD | Equivalent capability, and the GitOps Toolkit's separation of source, kustomization and helm releases is arguably cleaner. Rejected on ApplicationSet maturity: the tenant generator in consequence 3 above is one ApplicationSet in Argo CD and a `GitRepository` plus `Kustomization` per generator dimension in Flux. Revisit if Argo CD's CVE history becomes a burden. |
| `kubectl apply` from a cron job on a management VM | No Git reconciliation, no drift detection, no UI, and a credential on a VM. Rejected. |
| Helm-only, no GitOps operator | `helm upgrade` from CI is the push model with extra steps. |

### Compliance impact

| Area | Impact |
| --- | --- |
| GDPR | Positive. Fewer systems hold personal data: CI holds no cluster credential and therefore no access to tenant Secrets. |
| Auditability, ISO 27001 A.8.32 | Positive. Change management is evidenced by Git history and Argo CD's sync history, both immutable and both timestamped. |
| Data residency | Positive. Argo CD reads from GitHub (already the SCM) and writes to the cluster in the EEA. No new processor. |
| Breach exposure | Reduced. The credential that would expose every tenant Secret is not in CI. |
| DPIA | INFRA-001 §Delivery pipeline. |

---

## ADR-005: Secrets with SOPS and age, not Vault, in the pilot

| Field | Value |
| --- | --- |
| **Status** | Accepted |
| **Owner** | `@Via-Vitae/security` |
| **Date** | 2026-09-06 |
| **Deciders** | Security, Architects, Platform |
| **Consulted** | Compliance, DPO |
| **Supersedes** | — |
| **Superseded by** | — |

### Context

Encrypted values are needed in four places: Ansible inventory variables, Kubernetes Secrets,
WAL-G storage credentials, and the offsite backup key. The estate is two Proxmox nodes with
no HA (ADR-002) and a team of two to four.

HashiCorp Vault would provide dynamic credentials, an audit log of every secret access,
lease-based rotation and a proper unseal procedure. It would also require a three-node
integrated-storage cluster for HA — which ADR-002 says the hardware cannot support — plus
unseal key custody, a PKI backend, and continuous operation by someone.

### Decision

**SOPS with age encryption**, committed to Git, with these controls:

1. **age, not PGP.** An age key is a single line, has no expiry, has no web-of-trust to
   manage, and decryption is not dependent on a keyring that lives on one engineer's laptop.
   Recipients are declared in `.sops.yaml` at the repository root, which holds **public keys only**
   and is committed. SOPS walks up from each encrypted file to find this configuration, which
   is why it must live at the root rather than under `k8s/secrets/`. The `.gitignore` re-includes
   `k8s/secrets/sops/` and `k8s/secrets/external-secrets/` for the *Kubernetes-side* SOPS
   configuration (ClusterSecretStore, namespace manifests) — not for `.sops.yaml` itself.
2. **Two age identities**, not one: a human custodian key and a CI key. The CI key can
   decrypt only the paths its `creation_rules` allow, and it is held as a `prod`-scoped
   GitHub Environment secret. Losing one does not require re-encrypting everything with a
   single remaining key.
3. **The private key never touches a runner's disk outside the job**, and never reaches a
   GitHub-hosted runner at all (ADR-008). Offline custody: the custodian key is held by two
   people, on hardware tokens or in the organisation's password manager, with a sealed paper
   copy in the safe. This is stated because a single custodian is a bus-factor of one for
   every encrypted value in the repository.
4. **Ansible reads SOPS through the `community.sops` vars plugin**, configured in
   `ansible/ansible.cfg`. Ansible Vault is **not** used, and `vault_password_file` is not
   set. The generated spec described inventory values as "vaulted values via SOPS" while
   `ansible.cfg` was to carry "vault config" — two secret systems for one set of values is
   how a plaintext copy survives in the one nobody rotates. One system, named here.
5. **Rotation** is manual and scheduled: every 180 days, and immediately on any suspicion of
   exposure. The procedure is in `docs/runbooks/backup-restore.md` §Key rotation, because a
   procedure that is not written down is a procedure that will be improvised at 02:00.
6. **No secret is ever produced by Terraform.** See ADR-003 consequence 3: anything passed as
   a resource argument is written to state in plaintext.

### Consequences

**Positive**

- Nothing to operate. There is no server, no unseal, no HA question, no upgrade track, and
  no fourth thing to monitor on a two-node cluster.
- Encrypted values are in Git, so a secret change is a reviewed commit with an author, a
  timestamp and a diff — an audit trail Vault would provide, obtained for free.
- Decryption works offline, which means a total loss of the platform does not also mean a
  loss of access to the credentials needed to rebuild it.

**Negative and accepted**

1. **No access audit log.** SOPS cannot tell us who decrypted what, or when. Accepted, with
   the compensating control that decryption requires the private key, whose custody is
   limited to two named people and one CI identity. This is the single largest gap versus
   Vault, and it is the reason the review trigger below exists.
2. **No dynamic or short-lived credentials.** Every credential is static until rotated.
   Accepted; rotation is scheduled rather than automatic.
3. **Rotation is a manual re-encrypt of every file.** At the current file count this is
   minutes; at 200 files it is a project. The `sops updatekeys` command handles recipient
   changes but not passphrase-style rotation of the underlying credential.
4. **The ciphertext is public within the organisation.** Security rests entirely on the age
   private keys. A key leak is a full compromise with no detection mechanism — which is why
   Gitleaks scans for age private key material specifically, and why the key is never
   committed even in encrypted form.
5. **Kubernetes Secrets are still base64 in etcd** unless encryption at rest is enabled. It
   is enabled in `ansible/roles/k3s`; this ADR does not make it optional.

**Review trigger.** Supersede this ADR and adopt Vault (or Infisical, or an external KMS)
when any of these happens: tenant count exceeds 25, a third Proxmox node exists so Vault HA
is possible, an auditor requires secret-access logging as a control, or the estate needs
short-lived database credentials.

### Alternatives considered

| Alternative | Why rejected |
| --- | --- |
| HashiCorp Vault | The right answer at a scale this pilot does not have. Requires three nodes for HA that ADR-002 says the hardware cannot provide, plus unseal custody and continuous operation. Adopting it now would mean running a single-node Vault, which is a secret store with no availability and an extra thing to lose — worse than not having it. |
| Vault in Dev mode / single node | Explicitly rejected: a single-node Vault loses everything on storage failure and provides none of the availability that justifies Vault in the first place. |
| Sealed Secrets (Bitnami) | Complements rather than replaces: it solves Kubernetes Secrets only, not Ansible inventory or WAL-G configuration, and it requires the controller's private key to be backed up with the same rigour as an age key. SOPS covers all four consumers with one mechanism. |
| Ansible Vault alone | Covers Ansible only, uses a shared symmetric passphrase (one value, every consumer, no per-file recipients), and would leave Kubernetes Secrets and WAL-G credentials to a second mechanism. |
| External Secrets Operator against a cloud KMS | Rejected on residency and on the self-hosting requirement; the `k8s/secrets/external-secrets/` directory holds the configuration shape for the day a self-hosted store exists, and is documented as not yet in use. |
| Plain environment variables in CI | No encryption, no review, no revocation path, and secrets in the CI secret store are readable by anyone who can run a workflow that echoes them. |

### Compliance impact

| Area | Impact |
| --- | --- |
| GDPR, Art. 32 | Encryption at rest for every committed secret, with modern cryptography (X25519 via age) and per-recipient access control. The absence of an access log is a gap against Art. 32(1)(d)'s "ability to restore" only in the sense of auditability, not of protection. |
| Auditability | Weaker than Vault. Compensated by Git history for changes and by two-custodian key control. Recorded as an accepted limitation with a review trigger. |
| Data residency | Positive. Keys are held in the EEA; decryption is local; nothing is sent to a key-management service. |
| Breach exposure, Art. 33 | A committed age private key is a notifiable breach affecting every encrypted value in the repository. The Gitleaks gate scans for exactly this pattern. |
| DPIA | INFRA-001 §Secrets and key custody. |

---

## ADR-006: IaC security scanner consolidation

| Field | Value |
| --- | --- |
| **Status** | Accepted |
| **Owner** | `@Via-Vitae/security` |
| **Date** | 2026-09-06 |
| **Deciders** | Security, Platform |
| **Consulted** | Architects, Compliance |
| **Supersedes** | — |
| **Superseded by** | — |

### Context

The generated specification for `compliance-check.yml` listed four scanners: Gitleaks,
tfsec, Checkov and KICS. Three of those four scan the same artefacts — Terraform, Kubernetes
manifests and Dockerfiles — for the same class of finding: misconfiguration.

Three problems follow from that list as written:

1. **tfsec is end of life.** The project was merged into Trivy in 2023 and the standalone
   binary is no longer maintained. Installing an archived binary in CI, from a repository
   that no longer receives security fixes, is a supply-chain liability dressed as a control.
2. **Checkov and KICS overlap almost completely** at the severities a gate is set to. The
   practical outcome of three overlapping scanners is not three times the coverage; it is
   three times the triage, duplicate findings under different identifiers, and — after about
   a month — all three being ignored or the gate being disabled. A disabled gate is worse
   than no gate, because it still reports green.
3. **`gitleaks/gitleaks-action` is not usable here.** Since v2.0.0 the action is under a
   commercial licence rather than MIT, requires a `GITLEAKS_LICENSE` for any repository owned
   by an organisation, and sends the repository owner, repository name and licence key to
   keygen.sh — a third-party service outside the EEA. That conflicts with the licence
   allow-list in ADR-009, with the residency rule, and with INFRA-001, which would have to
   record a processor nobody approved.

### Decision

Run **two** IaC scanners and the **gitleaks CLI**:

1. **Trivy `config`** replaces tfsec — same lineage, same rule families, maintained, and
   already present in the organisation's CI baseline as the dependency scanner. Gating
   severity is `CRITICAL` and `HIGH`. A separate non-gating step reports every severity so
   MEDIUM and LOW findings remain visible and are triaged monthly.
2. **Checkov** is retained. Its Kubernetes and Ansible coverage is stronger than Trivy's, and
   its check identifiers are already referenced in the organisation's audit evidence.
3. **KICS is not included.** If it is later wanted, it is added as a non-gating advisory job
   with a burn-down target and an explicit statement of which finding families it catches
   that Trivy and Checkov do not. Adding it as a fourth gate is not the way to do that.
4. **Gitleaks runs as a pinned CLI binary**, downloaded by version with a SHA-256 recorded in
   the workflow and verified before extraction. It runs with `--redact` so the CI log does
   not itself become the leak, and `--log-opts=--all` so the scan covers history rather than
   the diff.
5. **Suppressions are inline**, in the file, naming the approver and the review date. No
   `.trivyignore` and no `--skip-check` in a workflow: a suppression that lives in CI config
   is invisible to the person reading the Terraform it excuses.

### Consequences

**Positive**

- Two scanners, two finding streams, one triage queue. Each has a stated reason to exist.
- No end-of-life binary in the pipeline, and no commercial-licence action sending repository
  metadata to a US service.
- Checksum-pinned binaries mean a compromised release cannot substitute a scanner.

**Negative and accepted**

- Coverage is the union of Trivy and Checkov, not of Trivy, Checkov and KICS. Some KICS-only
  queries will not run. Accepted: no evidence was produced that any of them catches a finding
  class the other two miss at `CRITICAL` or `HIGH`, and the burden of proving that lies with
  whoever wants a third scanner.
- Trivy's misconfiguration bundle is fetched from `ghcr.io`, a US-hosted registry, on the
  first run of each day. The request carries no repository content. Recorded in INFRA-001.
- Two scanners still produce duplicate findings for the same underlying issue, under
  different identifiers. Triage deduplicates by resource address, not by identifier.

### Alternatives considered

| Alternative | Why rejected |
| --- | --- |
| Keep tfsec | Unmaintained. Installing it requires a download from an archived repository, and a finding it reports can never be fixed by an upstream rule update. |
| Keep all four | See context point 2. The cost is not compute, it is attention. |
| OPA/conftest instead of a scanner | Complementary rather than substitutive: conftest tests *our* policies against *our* files, and does not ship the several hundred built-in misconfiguration rules. The policy-testing role is filled here by the Kyverno CLI in `ci.yml`, which tests the policies that actually enforce in the cluster. Adding conftest would create a third policy language for no new enforcement point. |
| Snyk or a commercial IaC scanner | Requires a SaaS account, an upload of the repository to a non-EEA processor, and a per-seat cost. Rejected on residency and on ADR-008's principle that CI does not gain new processors. |

### Compliance impact

| Area | Impact |
| --- | --- |
| GDPR, Art. 32 | Positive. Removes an unapproved third-party data flow (keygen.sh) from the pipeline. |
| Supply chain | Positive. Checksum-pinned binaries; no archived software. |
| Licensing | Positive. gitleaks CLI is MIT; the action is not. See ADR-009. |
| Auditability | Neutral to positive: two documented scanners with stated severities are easier to evidence than four with unexplained overlap. |

---

## ADR-007: Bitrix24 on-premises isolation and vendor risk

| Field | Value |
| --- | --- |
| **Status** | Accepted with conditions |
| **Owner** | `@Via-Vitae/security` |
| **Date** | 2026-09-06 |
| **Deciders** | Security, Architects, Legal |
| **Consulted** | Compliance, DPO, Platform |
| **Supersedes** | — |
| **Superseded by** | — |

### Context

The business requires a Bitrix24 on-premises Enterprise box: a closed-source LAMP
application used for internal CRM, task management and document handling. It will hold
personal data about employees and about clients of ViaVitae.

Four properties of this component are unlike everything else in the estate:

1. **The source is not available.** It cannot be reviewed, cannot be rebuilt, and cannot be
   patched by us. Every other component here is open source with a published CVE feed.
2. **The vendor performs licence validation over the internet.** The box contacts
   `www.bitrix24.com` and related endpoints. This is an outbound data flow from a system
   holding personal data, to a vendor whose corporate origin (1C-Bitrix) brings sanctions and
   data-sovereignty questions that Legal, not Engineering, has to answer.
3. **It is a monolithic PHP application** with a historically poor vulnerability record and a
   large attack surface (file upload, webdav, REST, a bundled XMPP/XMPP-like service).
4. **It is not a container workload.** It does not fit the k3s and Argo CD model in ADR-001
   and ADR-004, and forcing it into a container would produce an unsupported configuration.

### Decision

Run Bitrix24 as a **dedicated virtual machine, treated as untrusted**, with these conditions:

1. **Placement: the `dmz` VLAN (40)**, not `prod`. It is reachable from the internet through
   HAProxy on 443 only, and it is not reachable from the `mgmt` VLAN except by the Ansible
   control path.
2. **Egress is allow-listed.** Default-deny outbound from the Bitrix24 VM, with explicit
   allowances for the vendor's licence-validation endpoints, the NTP servers and the
   internal Keycloak and PostgreSQL hosts. The allow-list is in
   `docs/network-topology.md` and any addition is a security-reviewed change. This is the
   control that makes the phone-home acceptable: it can talk to what it must and to nothing
   else, so an exfiltration path has to be opened deliberately rather than existing by
   default.
3. **No route to the `prod` VLAN** except to the two services it legitimately consumes, and
   those are exposed through the HAProxy internal listener, not by direct pod addressing.
4. **Its database is on the Bitrix24 VM or on a dedicated PostgreSQL VM in the `dmz`**, not
   on the tenant PostgreSQL instance in ADR-003. One untrusted application does not share a
   database server with every tenant's data.
5. **Single sign-on through Keycloak** (OIDC), so credentials are not stored in Bitrix24 and
   so leaving the organisation actually removes access. Local admin accounts are limited to
   two break-glass identities whose passwords are in SOPS.
6. **Backups are encrypted and stored separately** from the tenant database backups, because
   a restore of one must not be able to overwrite the other.
7. **Legal review is a condition of this ADR, not a follow-up.** The vendor's data-processing
   terms, the jurisdiction of the licence agreement, the sanctions position and the transfer
   implications of licence validation must be answered in writing by Legal and referenced
   here before the VM is created in `prod`. Until that reference exists, this ADR's status is
   "Accepted with conditions" and `prod` deployment is blocked.
8. **A DPIA is required** for the personal data Bitrix24 processes, raised in this
   repository's DPIA register as INFRA-002, because the processing is new and the vendor is a
   new processor.

### Consequences

**Positive**

- A compromise of Bitrix24 — historically the most likely single point of entry in an estate
  like this one — lands in a VLAN with no route to tenant data and no route to the management
  plane, and with egress limited to a short allow-list.
- The phone-home behaviour becomes a documented, bounded, monitored flow rather than an
  unknown.
- SSO means access reviews cover it, which a locally-authenticated vendor application never
  is.

**Negative and accepted**

- The isolation is only as good as the allow-list, and vendor endpoints change without
  notice. A licence-validation failure presents as a degraded or locked application, and the
  fix is a firewall change under time pressure — which is how allow-lists get widened
  permanently. The runbook requires the change to be temporary and reviewed.
- We cannot audit the code, cannot reproduce the binary and cannot verify what it sends.
  This is an irreducible trust decision, and it is recorded as such rather than mitigated
  into invisibility.
- Operating a LAMP monolith alongside a Kubernetes estate means a second patching cadence,
  second monitoring agent configuration and second backup format. Real ongoing cost.
- PHP tuning for Bitrix24 (`opcache`, `memory_limit`, `max_execution_time`, `pm.max_children`)
  is vendor-prescribed and conflicts with generic hardening baselines in
  `ansible/roles/hardening`. The conflicts are resolved per-parameter in
  `ansible/roles/bitrix24` and each deviation is commented there.

### Alternatives considered

| Alternative | Why rejected |
| --- | --- |
| Do not run Bitrix24; use an open-source CRM (EspoCRM, Twenty, Odoo Community) | The right answer on every technical and compliance axis, and rejected because the requirement is a business one: the organisation's existing processes, integrations and user familiarity are Bitrix24. Replacing an ERP-adjacent system is a business project, not an infrastructure decision. This alternative should be re-raised at contract renewal. |
| Bitrix24 cloud | Places employee and client personal data with a vendor-hosted service outside our control, with a transfer question we cannot answer. Rejected on residency. |
| Run it in a container on k3s | Unsupported by the vendor, breaks the licensing and update mechanism, and would put an untrusted monolith in the same cluster as every tenant workload. |
| Run it in `prod` alongside the platform | Cheaper and simpler. Rejected because a compromise then has a route to the tenant database and to the cluster API. |
| Block egress entirely | Breaks licence validation, which the vendor uses to enforce the subscription. Blocking it produces a locked application and an emergency firewall change. The allow-list is the honest version of the same control. |

### Compliance impact

| Area | Impact |
| --- | --- |
| GDPR, Art. 28 | A new processor. A DPA and the vendor's Art. 30 record are required before `prod` deployment; condition 7 makes this a blocker rather than a follow-up. |
| GDPR, Art. 44-49 transfers | Licence validation is an outbound call to a vendor endpoint. What it carries must be established and recorded in INFRA-002. If it carries personal data, a transfer impact assessment is required. |
| Art. 32 security of processing | Isolation, allow-listed egress, SSO and separate encrypted backups are the compensating controls for an unauditable closed-source component. |
| Art. 30 records of processing | INFRA-002 is the record for this processing activity. |
| Sanctions and supplier risk | Referred to Legal by condition 7. Engineering does not decide this and this ADR does not pretend to. |
| DPIA | Required. INFRA-002. |

---

## ADR-008: CI control plane and runner residency

| Field | Value |
| --- | --- |
| **Status** | Accepted |
| **Owner** | `@Via-Vitae/platform` |
| **Date** | 2026-09-06 |
| **Deciders** | Platform, Security, Architects |
| **Consulted** | Compliance, DPO |
| **Supersedes** | — |
| **Superseded by** | — |

### Context

The platform is described as 100 % self-hosted and EU-resident, and `CONTRIBUTING.md` states
that "storage, backups, processors and CI runners stay in the EEA". At the same time the
source code, the issue tracker, the pull-request review record and the Actions control plane
are GitHub — a US service.

Those two facts have to be reconciled explicitly, because the alternative is a repository
that claims self-hosting while quietly running `terraform plan` with a Proxmox API token on a
GitHub-hosted runner in a US data centre.

What actually crosses the boundary matters more than where the label says the compute is:

| Data | Where it goes | Is it personal data? |
| --- | --- | --- |
| Source code, commit metadata, review comments | GitHub (US) | No |
| `terraform plan` text output | GitHub, as a pull-request comment | No, but it contains internal hostnames, IP ranges and VMIDs |
| `terraform plan` **binary** | Nowhere — deleted on the runner (see `deploy.yml`) | Would contain sensitive attribute values |
| Proxmox API token, state-bucket key, apply token | Self-hosted runner only | No, but they are credentials |
| kubeconfig, age private key | Self-hosted runner only, and only in `deploy.yml` | No |
| Logs and metrics produced by a CI run | Runner, then discarded | Potentially — a failed run can echo a hostname |
| Trivy check bundle, Terraform provider binaries, Helm charts | Downloaded to the runner from US-hosted registries | No |

### Decision

1. **GitHub remains the SCM and the CI control plane.** Replacing it with a self-hosted
   Forgejo plus Woodpecker or Drone is the technically consistent answer and is not taken
   now, because it would move the review record, CODEOWNERS enforcement, environment
   protection rules and Dependabot into systems nobody is operating. That is a larger
   compliance risk than the one it removes.
2. **Every job in every workflow runs on the self-hosted EEA runner pool.** `runs-on` is
   `fromJSON(vars.RUNNER_LABELS || '["self-hosted","linux","x64","eu-infra"]')`. There is no
   `ubuntu-latest` fallback anywhere: if the pool is unavailable the run fails with "no
   runner available", which is visible, rather than silently migrating to US compute.
3. **Credentials exist only in `deploy.yml`,** scoped per environment, with a read-only token
   for `plan` and a write token for `apply`. `ci.yml`, `compliance-check.yml` and
   `codeql.yml` receive none, and the `action-pinning` job in `compliance-check.yml` fails
   the build if any other workflow names an infrastructure credential.
4. **Plan binaries never leave the runner.** Only Terraform's own redacted text output is
   posted or uploaded. The reason and the mechanism are documented at the top of
   `deploy.yml`.
5. **Runner image is versioned and reproducible.** The pool runs a Debian 12 VM built by
   `ansible/playbooks/proxmox-base.yml` plus a runner role, on the `mgmt` VLAN, with egress
   limited to GitHub, the Terraform registry, the Helm repositories and the state bucket. A
   runner with unrestricted egress that holds production credentials is a lateral-movement
   path, not a build machine.
6. **The pool is a prerequisite, not an optimisation.** Provisioning two runner VMs is step 0
   of the environment build checklist in `README.md`. Until they exist, no workflow in this
   repository can run — which is the intended fail-closed behaviour and the reason the
   default label has no hosted fallback.

### Consequences

**Positive**

- The residency claim is true for compute: no build artefact, plan output or credential is
  processed on non-EEA hardware.
- Credential blast radius is one workflow, and the two-token split means a compromised
  pull-request run cannot destroy infrastructure.
- Runner egress restriction means a malicious action or a poisoned provider cannot exfiltrate
  to an arbitrary host.

**Negative and accepted**

1. **Source code, review history and plan text are still processed in the US.** Accepted and
   recorded in INFRA-001. It is not personal data, but it is confidential intellectual
   property and it does include internal network topology in plan output. The compensating
   control is that plan output is capped and reviewed before posting.
2. **The runner pool is now infrastructure we operate.** Two more VMs to patch, monitor and
   capacity-plan, and a CI outage when they are down. Accepted: it is the cost of the claim.
3. **Self-hosted runners on public repositories are dangerous** (a pull request from anyone
   executes code on our machine). This repository is private, and it must stay private; that
   constraint is recorded here because making it public would silently turn CI into remote
   code execution for any GitHub user.
4. **Tool downloads still traverse US infrastructure** (registry.terraform.io, ghcr.io,
   get.helm.sh, GitHub releases). Mitigated by SHA-pinning every action, SHA-256-verifying
   every downloaded binary, and committing `.terraform.lock.hcl` so provider hashes are
   checked. A mirror inside the EEA is the eventual answer and is listed in
   `docs/capacity-plan.md` as a growth item.
5. **Dependabot, CodeQL and secret scanning are GitHub SaaS features.** Using them means
   GitHub processes the repository. Accepted, and consistent with decision 1.

### Alternatives considered

| Alternative | Why rejected |
| --- | --- |
| GitHub-hosted runners (`ubuntu-latest`) | Directly violates the residency rule for CI runners, and would execute `terraform plan` holding a Proxmox API token on US infrastructure. Rejected. |
| GitHub-hosted runners for static checks only, self-hosted for deploy | Reduces the operational burden and keeps credentials in the EEA. Rejected because the split is not stable: the first time a static check needs to reach the API to produce a better error message, the boundary moves. One rule that never needs interpreting beats two that do. |
| Self-hosted Forgejo plus Woodpecker/Drone | The consistent answer, and the direction of travel if GitHub's terms, pricing or jurisdiction become unacceptable. Not taken now because it moves branch protection, CODEOWNERS, environment approvals, Dependabot and code scanning into systems with no operator. Superseding this ADR is the mechanism for revisiting it. |
| Larger self-hosted GitHub Enterprise Server | Licence cost plus an entire application to operate, for a team of two to four. |
| No CI, apply by hand | Rejected: the review record, the plan attachment and the approval gate are what make an infrastructure change auditable. Manual applies produce no evidence. |

### Compliance impact

| Area | Impact |
| --- | --- |
| GDPR, Art. 44-49 | Source code and plan text are transferred to a US processor under GitHub's standard contractual terms. Recorded as a transfer in INFRA-001 with the observation that no personal data is included. A transfer impact assessment is required and is referenced from INFRA-001. |
| GDPR, Art. 32 | Positive: credentials never reach shared multi-tenant compute, and runner egress is restricted. |
| Data residency of personal data | Positive: no personal data is processed by CI. The one exception is a CI log that echoes a hostname containing a client slug, which is why the plan-summary cap and the redaction rule exist. |
| Auditability | Positive: environment protection rules give an approval record per apply. |
| DPIA | INFRA-001 §CI control plane. |

---

## ADR-009: Licence position for the infrastructure stack

| Field | Value |
| --- | --- |
| **Status** | Accepted with conditions |
| **Owner** | `@Via-Vitae/legal` |
| **Date** | 2026-09-06 |
| **Deciders** | Legal, Security, Architects |
| **Consulted** | Compliance, Finance |
| **Supersedes** | — |
| **Superseded by** | — |

### Context

The organisation's licence allow-list, defined in `viavitae-template` and enforced by
`compliance-check.yml`, is **MIT, Apache-2.0, BSD, CC0 and Proprietary**. An infrastructure
stack cannot be built from that list alone:

- Every Terraform provider, including HashiCorp's own, is **MPL-2.0**.
- The Terraform CLI has been **BUSL-1.1** since version 1.6, which is not an open-source
  licence at all.
- `ansible-core` and nearly every Ansible collection is **GPL-3.0-or-later**.
- Grafana and Loki are **AGPL-3.0-only**.
- HAProxy is **GPL-2.0-or-later** with an LGPL exception for its libraries.
- PostgreSQL uses the **PostgreSQL Licence**.

Applying the baseline allow-list unchanged would fail every one of these at the compliance
gate. Silently widening the allow-list in this repository would be worse: the gate would pass
while nobody had decided anything. So the position is stated here, per component, with a
rationale, and the CI gate reads this table.

### Decision

1. The allow-list for this repository is the organisation baseline **plus** MPL-2.0,
   BUSL-1.1, GPL-3.0-or-later, GPL-2.0-or-later, LGPL-2.1-or-later, PostgreSQL, AGPL-3.0-only
   and EPL-2.0. The additions are encoded in the `licences` job of `compliance-check.yml`;
   removing one there without updating this ADR fails the gate, and vice versa.
2. The additions are justified by the **use context**: ViaVitae operates this software
   internally to provide a service. It does not distribute it, does not link its own
   proprietary code into it, and does not offer it as a competing managed service.
   - **MPL-2.0** is file-based copyleft. Obligations attach to modifications of MPL files,
     which we do not make. Providers are invoked as separate processes over a plugin
     protocol, so no proprietary code is combined with them.
   - **GPL-3.0/GPL-2.0** obligations are triggered by *conveying* the software. Running
     Ansible on our own machines and HAProxy on our own load balancer conveys nothing. Our
     playbooks and configurations are separate works, not derivatives.
   - **AGPL-3.0** is the one that matters, because §13 reaches network use. Grafana and Loki
     are offered to internal staff and, in some dashboards, to tenant administrators. The
     obligation is to offer those users the corresponding source of the program they are
     interacting with. We do not modify Grafana or Loki, and the unmodified source is publicly
     available at a stable URL, so the obligation is satisfiable — **but it is an obligation,
     and it is why condition 3 below exists.**
   - **BUSL-1.1** permits production use and forbids offering the software as a commercially
     competitive managed service. We do neither offer Terraform as a service nor resell it.
     The restriction that matters is temporal: each version converts to Apache-2.0 four years
     after release, so the exposure shrinks on its own.
3. **AGPL components carry an explicit review condition.** Legal confirms in writing, before
   `prod` go-live, that (a) no tenant-facing use of Grafana or Loki constitutes providing the
   program to third parties in a way that triggers obligations we are not meeting, and (b) no
   modification, plugin or patched build is deployed. If either confirmation cannot be given,
   the Apache-2.0 replacements are named below and this ADR is superseded.
4. **Bitrix24 is Proprietary** and is covered by ADR-007, including the Legal review
   condition there.
5. **The base operating system is not inventoried as a component.** Debian 12 is a
   distribution of several thousand packages under many OSI-approved licences, and the
   obligations that come with it are the distribution's, not ours: we do not redistribute it,
   we install it from its own repositories, and we do not modify it. Listing it as one row
   with one licence would be a false precision, so it appears here rather than in the table.
6. **No copyleft component is linked with ViaVitae proprietary code.** Terraform providers are
   separate processes; Ansible runs our playbooks as data; Grafana and Loki are network
   services. The one place this could change is a custom Grafana plugin or a custom Ansible
   module written in this repository, and doing either requires a new ADR.

### Component licence inventory

This table is the licence record for the stack. The `licences` job in
`.github/workflows/compliance-check.yml` parses it: every component this repository deploys
must appear, every licence must be on the allow-list in decision 1, and every status must be
an approval. A status of anything else fails the build.

| Component | Licence | Status | Condition or reference |
| --- | --- | --- | --- |
| Terraform CLI | `BUSL-1.1` | Approved with conditions | Production use permitted; not offered as a service. Converts to Apache-2.0 four years after each release. OpenTofu (`MPL-2.0`) is the named fallback if the BUSL terms change. |
| bpg/proxmox provider | `MPL-2.0` | Approved | Invoked as a separate process; no modification. |
| hashicorp/random provider | `MPL-2.0` | Approved | Invoked as a separate process; no modification. |
| hashicorp/dns provider | `MPL-2.0` | Approved | RFC 2136 updates against the self-hosted authoritative DNS. |
| cyrilgdn/postgresql provider | `MIT` | Approved | — |
| ansible-core | `GPL-3.0-or-later` | Approved | Executed on our own machines; nothing conveyed. |
| community.general collection | `GPL-3.0-or-later` | Approved | Playbooks and roles in this repository are separate works, not derivatives. |
| community.sops collection | `GPL-3.0-or-later` | Approved | As above; required by ADR-005 decision 4. |
| ansible.posix collection | `GPL-3.0-or-later` | Approved | As above. |
| k3s | `Apache-2.0` | Approved | — |
| Kubernetes | `Apache-2.0` | Approved | — |
| containerd | `Apache-2.0` | Approved | Bundled with k3s. |
| Traefik | `MIT` | Approved | Bundled with k3s as the in-cluster ingress controller (ADR-001 decision 4). |
| CoreDNS | `Apache-2.0` | Approved | Bundled with k3s. |
| Argo CD | `Apache-2.0` | Approved | — |
| Kyverno | `Apache-2.0` | Approved | — |
| Kyverno CLI | `Apache-2.0` | Approved | Downloaded by version with a SHA-256 recorded in `ci.yml`. |
| cert-manager | `Apache-2.0` | Approved | — |
| kube-prometheus-stack chart | `Apache-2.0` | Approved | Chart version pinned in `ci.yml` and in the matching Argo CD Application. |
| Prometheus | `Apache-2.0` | Approved | — |
| Alertmanager | `Apache-2.0` | Approved | — |
| node_exporter | `Apache-2.0` | Approved | — |
| Grafana | `AGPL-3.0-only` | Approved with conditions | ADR-009 condition 3: Legal confirmation before prod go-live, and no modified or patched build may be deployed. There is no Apache-2.0 dashboarding equivalent with the same ecosystem; the named fallback is to withdraw tenant-facing dashboards and keep Grafana internal-only, which removes the network-use question. |
| Loki | `AGPL-3.0-only` | Approved with conditions | ADR-009 condition 3. Apache-2.0 fallback: VictoriaLogs. |
| Grafana Alloy | `AGPL-3.0-only` | Approved with conditions | ADR-009 condition 3, same licensor and licence as Grafana and Loki. Runs on every host as the log agent; performs redaction at the source (INFRA-001 control M3). Not tenant-facing. Apache-2.0 fallback: Promtail (deprecated by Grafana Labs, MIT/Apache-2.0). |
| Uptime Kuma | `MIT` | Approved | Deployed from manifests in `monitoring/uptime-kuma/`, not from a third-party chart. |
| PostgreSQL | `PostgreSQL` | Approved | Permissive, BSD-like; no obligation beyond attribution. |
| pgbouncer | `ISC` | Approved | — |
| WAL-G | `Apache-2.0` | Approved | — |
| Keycloak | `Apache-2.0` | Approved | — |
| Bitrix24 | `Proprietary` | Approved with conditions | Commercial on-premises licence; ADR-007 conditions 1 to 8 apply, including the Legal review blocker. |
| HAProxy | `GPL-2.0-or-later` | Approved | Run unmodified on our own load-balancer VMs; configuration files are separate works. |
| keepalived | `GPL-2.0-or-later` | Approved | Run unmodified; no conveyance. |
| SOPS | `Apache-2.0` | Approved | — |
| age | `Apache-2.0` | Approved | — |
| Gitleaks | `MIT` | Approved | The CLI binary, not `gitleaks-action`, which is under a commercial licence — see ADR-006. |
| Trivy | `Apache-2.0` | Approved | — |
| Checkov | `Apache-2.0` | Approved | — |
| jq | `MIT` | Approved | Used in workflow scripts. |

### Consequences

**Positive**

- The licence position is written down per component instead of being assumed, and it is
  mechanically checked: adding a component without a row fails CI.
- The AGPL exposure — the only licence in the stack with a network-use clause — is named,
  bounded and has a written confirmation gate before production.
- BUSL-1.1 is acknowledged rather than glossed as "open source", and OpenTofu is named as the
  fallback, so the migration decision has a starting point.

**Negative and accepted**

- This repository's allow-list is wider than the organisation's. That is deliberate and is the
  reason the table exists: a reviewer can see exactly what was widened and why, rather than
  finding a silently edited constant in a workflow.
- The inventory is maintained by hand. A component added to a Helm values file without a row
  here fails CI, which is the control — but the row's *accuracy* is not verifiable
  mechanically, and a wrong licence in the table is worse than a missing one because it reads
  as checked.
- Legal review of AGPL and BUSL is a dependency for `prod` go-live and is not in Engineering's
  control.

### Alternatives considered

| Alternative | Why rejected |
| --- | --- |
| Restrict the stack to MIT/Apache-2.0/BSD only | Would require OpenTofu instead of Terraform (MPL-2.0 either way, so this does not even solve the provider problem), no Ansible, no HAProxy, no Grafana, no Loki and no PostgreSQL. It is not a stack. |
| Widen the allow-list silently in the workflow | The gate would pass with no decision behind it, and the next repository to copy the workflow would inherit a widened list nobody approved. |
| Replace Grafana and Loki with Apache-2.0 alternatives now | VictoriaMetrics and VictoriaLogs are credible and would remove the AGPL question entirely. Not taken because Grafana's dashboard ecosystem and the team's familiarity are worth more than the licence risk in the pilot, and because condition 3 gives Legal the decision with a named fallback rather than Engineering pre-empting it. |
| Ignore the question | This is what an allow-list gate that passes on an empty scan looks like. |

### Compliance impact

| Area | Impact |
| --- | --- |
| Licensing | This ADR is the record. It widens the allow-list for one repository, with a per-component rationale and a mechanical check. |
| GDPR | None directly. |
| Supplier risk | Bitrix24 and the HashiCorp BUSL change are both supplier-risk items and are tracked here rather than in a spreadsheet. |
| Auditability | Positive: an auditor asking "what open-source obligations do you carry" gets a table. |

---

## ADR template

Copy everything below the line into a new section at the end of this file, assign the next
number from the index, and add the index row in the same pull request.

```markdown
## ADR-NNN: <short title in sentence case>

| Field | Value |
| --- | --- |
| **Status** | Proposed |
| **Owner** | <team handle, for example @Via-Vitae/architects> |
| **Date** | <YYYY-MM-DD> |
| **Deciders** | <roles and teams that agreed> |
| **Consulted** | <roles and teams whose input was sought> |
| **Supersedes** | <ADR-NNN or —> |
| **Superseded by** | <ADR-NNN or —> |

### Context

<The situation and the forces acting on it. What is true today, what constraint applies,
and why a decision is needed now. State the problem, not the preferred answer. Name the
regulatory, operational and technical constraints explicitly — GDPR, WCAG 2.2 AA, EEA data
residency, self-hosted Proxmox, the two-node limit from ADR-002, existing contracts.
Include the cost of doing nothing.>

### Decision

<The decision, in the active voice, specific enough to be implemented without further
interpretation. Number the constituent parts where there is more than one. A reader should
be able to tell whether an implementation conforms to this decision.>

### Consequences

<What becomes easier, what becomes harder, and what risk is knowingly accepted. Include the
negative consequences — an ADR that lists only benefits has not been thought through. State
migration cost, operational burden, the trigger that would reopen the decision, and what
has to be undone if it is reversed.>

### Alternatives considered

<Each rejected alternative and the reason for rejection, as a table. Recording why an option
was declined prevents the same debate recurring when the person who declined it has left.>

### Compliance impact

<Effects on GDPR, lawful basis, special category data, data residency and transfers,
retention, breach exposure, accessibility, licensing and auditability. Whether a DPIA is
required, and its reference if one exists. Whether a new processor is introduced and whether
a DPA is in place. State "none" explicitly where there is genuinely no impact — a blank
section is ambiguous.>
```
