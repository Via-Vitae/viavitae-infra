# Network topology

Authoritative record of how the ViaVitae platform is segmented, addressed and firewalled.
Owned by `@Via-Vitae/security` and `@Via-Vitae/platform` (see `.github/CODEOWNERS`).

**A firewall or VLAN change is a pull request against this file first and against
configuration second.** If the table below and the running configuration disagree, one of
them is wrong and the drift job in `.github/workflows/deploy.yml` is not going to tell you
which — segmentation is configured partly in Proxmox, partly in the guest and partly in
Kubernetes network policy, and no single tool sees all three.

---

## Design principles

1. **Default deny between VLANs.** Nothing is reachable across a boundary unless a rule below
   says so. A new service does not become reachable by being deployed; it becomes reachable
   by a reviewed change to this file.
2. **Management is one-directional.** The `mgmt` VLAN can reach every other VLAN. No other
   VLAN can reach `mgmt`. This is the invariant that stops a compromised public-facing
   Bitrix24 box from becoming a route into the hypervisor, and it is checked by the
   `network-policies` job and by the quarterly DR drill.
3. **One writer per layer.** Proxmox owns the bridge and the VLAN tag on the vNIC; the guest
   owns its own host firewall; Kubernetes owns pod-to-pod policy. Overlapping rules at two
   layers are how an allow rule gets added in one place and silently negated in another.
4. **The tenant boundary is a namespace, not a VLAN.** Tenants share the `prod` VLAN and are
   separated by Kubernetes NetworkPolicy and RBAC, not by IP. Adding a VLAN per tenant does
   not scale past a handful and is not attempted.
5. **No inbound from the internet except through the `dmz` VIP.** There is no port-forward to
   a `prod` or `mgmt` address, ever, including "temporarily for a demo".

## VLAN plan

| VLAN | Name | Subnet | Gateway | Purpose | Internet | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| 10 | `mgmt` | 10.10.10.0/24 | 10.10.10.1 | Proxmox API, SSH to every VM, runner VMs, Keycloak admin console, backup appliance, qdevice | No | Reachable only from the office VPN and from the runner VMs. This is the only VLAN with a route to every other VLAN. |
| 20 | `prod` | 10.10.20.0/24 | 10.10.20.1 | Production k3s nodes, PostgreSQL, Keycloak, monitoring | No | Receives traffic only from the `dmz` VIP and from `mgmt`. |
| 30 | `staging` | 10.10.30.0/24 | 10.10.30.1 | Staging k3s nodes and staging platform services | No | Mirrors `prod` at reduced scale; the DR rehearsal target. |
| 40 | `dmz` | 10.10.40.0/24 | 10.10.40.1 | HAProxy LB pair, Bitrix24, any internet-exposed service | **Yes** | The only VLAN with an internet route. Egress is allow-listed per host, not open. |
| 50 | `dev` | 10.10.50.0/24 | 10.10.50.1 | Disposable single-node k3s, developer sandboxes | No | Added by this repository. See the correction note below. |
| 99 | *native/untagged* | — | — | **Prohibited.** No VM, no bridge port, no container is placed untagged. | — | An untagged port on a trunk bridge lands in the hypervisor's own management context. This is the single most common Proxmox misconfiguration and it is checked by the `common` role. |

> **Correction to the generated design.** The original plan listed four VLANs — mgmt, prod,
> staging, dmz — while the environment list included a disposable `dev` environment. With no
> VLAN of its own, `dev` would have been placed in `staging`, putting a deliberately
> throwaway, unhardened, anyone-can-deploy-to workload in the same broadcast domain as the
> pre-production copy of the platform. VLAN 50 exists to close that gap. It costs one
> subnet and no hardware.

## Addressing and VMID allocation

VMIDs are cluster-global in Proxmox (100 to 999999) and are allocated from non-overlapping
blocks so that two environments can never claim the same ID, even when their Terraform states
are applied out of order or by different people.

| Block | Environment / role | Range | Examples |
| --- | --- | --- | --- |
| 900–999 | Shared infrastructure | `global` state | 900 HAProxy LB-1, 901 HAProxy LB-2, 910 monitoring, 920 Keycloak, 930 PostgreSQL prod, 940 Bitrix24, 990 qdevice |
| 1000–1099 | `dev` | disposable | 1000 dev-k3s-0 |
| 1100–1199 | `staging` | persistent | 1100 stg-cp-0, 1110 stg-worker-0, 1120 stg-db-0 |
| 1200–1399 | `prod` | persistent | 1200–1202 prod-cp-0..2, 1210–1229 prod-worker-0..19, 1230 prod-db-0, 1231 prod-db-1 |

Rules:

- A VMID is **never reused**, including after a VM is destroyed. Reuse makes backup archives,
  audit logs and monitoring history ambiguous, and a restore can silently overwrite the wrong
  guest. The allocation table above is append-only; the `global` Terraform state holds the
  block assignments and validates them.
- The block is enforced by a `validation` block in `terraform/modules/proxmox-vm`, not by
  review discipline.
- Hostnames follow `<env>-<role>-<n>.<vlan-domain>`, for example
  `prod-cp-0.prod.viavitae.internal`. The hostname is derived from the VM name in the module,
  so it cannot drift from the VMID block.

## Request path

```
Internet
   │  443/tcp, 80/tcp (redirect only)
   ▼
keepalived VIP 203.0.113.10  (dmz, VLAN 40)
   │  held by haproxy-lb-1 or haproxy-lb-2
   ▼
HAProxy — layer 4, SNI passthrough, TCP health checks, no TLS termination
   │  forwards 10.10.40.11:443 → 10.10.20.0/24 node ports
   ▼
k3s ServiceLB (klipper-lb) NodePort on every prod node
   ▼
Traefik (bundled with k3s) — TLS termination, certificates from cert-manager
   ▼
Pod (namespace web / api / demos / tenant-<slug>)
```

**Why TLS terminates in Traefik and not in HAProxy.** One place renews certificates. If
HAProxy terminated TLS, the cert-manager-issued secret would have to be exported from the
cluster to a VM on every renewal — a cross-boundary secret copy, on a 60-day cycle, with a
second expiry to monitor and a second failure mode. HAProxy does SNI-based passthrough
instead, which needs no certificate at all and therefore has no expiry. The cost is that
HAProxy cannot route on HTTP path or header; it routes on SNI hostname only, which is
sufficient for this estate and is stated here so nobody adds a path-based rule to it later
and wonders why it does nothing.

Public hostnames:

| Hostname | Serves | VLAN | Certificate issuer |
| --- | --- | --- | --- |
| `www.viavitae.com`, `viavitae.com` | `viavitae-web` | prod, via dmz | Let's Encrypt, DNS-01 |
| `api.viavitae.com` | `viavitae-api` | prod, via dmz | Let's Encrypt, DNS-01 |
| `<slug>.viavitae.com` | tenant workload | prod, via dmz | Let's Encrypt, DNS-01 |
| `status.viavitae.com` | Uptime Kuma | prod, via dmz | Let's Encrypt, DNS-01 |
| `sso.viavitae.com` | Keycloak, tenant-facing SSO | prod, via dmz | Let's Encrypt, DNS-01 |
| `crm.viavitae.com` | Bitrix24 | dmz directly | Let's Encrypt, DNS-01 |
| `*.viavitae.internal` | Argo CD, Grafana, Proxmox, everything else | mgmt | Internal CA (`k8s/ingress/cert-manager`) |

`DNS-01` is required rather than `HTTP-01` for every public certificate: HTTP-01 needs an
internet-reachable endpoint per name, which for `<slug>.viavitae.com` means opening the dmz
to a challenge on a path served by a tenant workload. DNS-01 keeps the challenge inside our
own zone and lets one wildcard-capable issuer cover the tenant subdomains. Let's Encrypt is a
non-EU trust anchor; certificate validation transfers no personal data, and the position is
recorded in `README.md` (accepted risk 6).

## Host addressing

Static addresses, allocated once and recorded here. DHCP is used only for workstations on the
office network; every server address is static, because a server whose address changes breaks
firewall rules, TLS SANs, backup targets and monitoring discovery simultaneously and in ways
that look like four unrelated faults.

| Address | VLAN | VMID | Host | Role |
| --- | --- | --- | --- | --- |
| 10.10.10.1 | mgmt | — | gateway | Router and firewall |
| 10.10.10.2, 10.10.10.3 | mgmt | — | `pve-01`, `pve-02` | Proxmox hypervisors, API on 8006 |
| 10.10.10.5 | mgmt | 990 | `qdevice-01` | Corosync quorum device |
| 10.10.10.10, 10.10.10.11 | mgmt | 900, 901 | `lb-01`, `lb-02` | HAProxy control and SSH; the data path is on the dmz VLAN |
| 10.10.10.15 | mgmt | 991 | `runner-01` | Self-hosted GitHub Actions runner |
| 10.10.10.16 | mgmt | 992 | `runner-02` | Second runner; one is a maintenance window, not an outage |
| 10.10.10.20 | mgmt | — | `backup-01` | Backup appliance, Proxmox Backup Server |
| 10.10.20.10 | prod | 910 | `mon-01` | MinIO object store for Loki and Prometheus, plus the Uptime Kuma external prober. The monitoring stack itself runs in the cluster |
| 10.10.20.20 | prod | 920 | `sso-01` | Keycloak |
| 10.10.20.30 | prod | 930 | `db-01` | PostgreSQL primary, all tenant schemas |
| 10.10.20.31 | prod | 931 | `db-02` | PostgreSQL standby (Patroni-ready, see ADR-003) |
| 10.10.20.40–42 | prod | 1200–1202 | `prod-cp-0..2` | k3s control plane — target state only, see ADR-002 |
| 10.10.20.50–69 | prod | 1210–1229 | `prod-worker-N` | k3s workers |
| 10.10.30.10 | staging | 1120 | `stg-db-0` | Staging PostgreSQL |
| 10.10.30.20 | staging | 1121 | `stg-sso-0` | Staging Keycloak |
| 10.10.30.30 | staging | 1100 | `stg-cp-0` | Staging k3s control plane |
| 10.10.30.40 | staging | 1110 | `stg-worker-0` | Staging k3s worker |
| 203.0.113.10 | *public* | — | VIP | Public virtual IP, held by keepalived on `lb-01`/`lb-02` and announced on the dmz segment. It is not a 10.10.40.x address: it is the address the internet sees |
| 10.10.40.11 | dmz | 900 | `lb-01` | HAProxy data path, active |
| 10.10.40.12 | dmz | 901 | `lb-02` | HAProxy data path, passive |
| 10.10.40.40 | dmz | 940 | `crm-01` | Bitrix24 |
| 10.10.40.41 | dmz | 941 | `crm-db-01` | Bitrix24 MySQL/MariaDB, isolated from the tenant database |
| 10.10.50.10 | dev | 1000 | `dev-k3s-0` | Single-node disposable cluster |

Two hosts appear twice — the load balancers on `mgmt` and on `dmz` — because they are
dual-homed by design: administered on VLAN 10, serving traffic on VLAN 40. No other host is
dual-homed. A dual-homed host is a route between segments, and the load balancers are the only
place where such a route is intended.

**Keycloak and PostgreSQL live in `prod` (VLAN 20), not in `mgmt`.** Their *administrative
consoles* are reachable only from `mgmt`, which follows from X1 and needs no rule of its own.
Placing the services themselves in `mgmt` would require an exception to X11 — the invariant
that nothing reaches the management VLAN — and an exception to an invariant is how the
invariant dies.

## Firewall rules

Direction is always **from → to**. Everything not listed is denied.

### Inbound from the internet (dmz only)

| # | From | To | Port | Protocol | Purpose | Rule ID |
| --- | --- | --- | --- | --- | --- | --- |
| I1 | any | 203.0.113.10 (dmz VIP) | 443 | tcp | HTTPS to HAProxy | `dmz-in-443` |
| I2 | any | 203.0.113.10 (dmz VIP) | 80 | tcp | HTTP, redirects to 443 only; no service listens behind it | `dmz-in-80` |
| I3 | Let's Encrypt validation | — | — | — | **Not applicable.** DNS-01 uses outbound DNS only; no inbound rule exists for certificate issuance, which is the point of choosing it | — |

There are no other inbound rules. SSH, the Proxmox API, Keycloak administration, Grafana,
Argo CD and every database port are unreachable from the internet by construction, not by
omission.

### Between VLANs

| # | From | To | Port | Protocol | Purpose | Rule ID |
| --- | --- | --- | --- | --- | --- | --- |
| X1 | mgmt 10.10.10.0/24 | all VLANs | any | any | Administration, Ansible, monitoring scrape, administrative consoles | `mgmt-any` |
| X2 | dmz 10.10.40.11, 10.10.40.12 (HAProxy pair) | prod 10.10.20.0/24 | 30000-32767 | tcp | NodePort range for ServiceLB. Scoped to the two HAProxy addresses, not the whole dmz subnet, so a compromised Bitrix24 host cannot reach the cluster | `dmz-to-prod-nodeport` |
| X3 | prod 10.10.20.0/24 | 10.10.20.20 (Keycloak) | 8443 | tcp | OIDC token validation and SSO. Intra-VLAN, listed because the Kubernetes NetworkPolicy that permits it is not | `prod-to-sso` |
| X4 | prod 10.10.20.0/24 | 10.10.20.30, 10.10.20.31 (PostgreSQL) | 5432 | tcp | Tenant database access, restricted to the `api` namespace by NetworkPolicy | `prod-to-db` |
| X5 | staging 10.10.30.0/24 | staging hosts in the same VLAN | 5432, 8443 | tcp | Staging platform services live inside VLAN 30 | `staging-internal` |
| X6 | prod 10.10.20.0/24 | 10.10.20.10 (monitoring VM) | 9000 | tcp | S3 writes from in-cluster Loki and Prometheus to the object store | `prod-to-monitoring` |
| X7 | staging 10.10.30.0/24 | 10.10.20.10 (monitoring VM) | 9000 | tcp | Same, from staging. Cross-VLAN, therefore explicit | `staging-to-monitoring` |
| X8 | dev 10.10.50.0/24 | 10.10.20.10 (monitoring VM) | 9000 | tcp | Same, from dev. A disposable environment still reports, so that its disposal is visible | `dev-to-monitoring` |
| X9 | dmz 10.10.40.40 (Bitrix24) | dmz 10.10.40.41 (its database) | 3306 | tcp | Vendor LAMP stack, same VLAN only, single source address | `bitrix-to-db` |
| X10 | dev 10.10.50.0/24 | dev 10.10.50.0/24 | any | any | Intra-VLAN only | `dev-internal` |
| **X11** | **prod, staging, dev, dmz** | **mgmt 10.10.10.0/24** | **any** | **any** | **DENIED.** Explicitly denied, not merely absent, so the rule is visible in review | `deny-to-mgmt` |
| X12 | dev | prod, staging, dmz | any | any | **DENIED.** A disposable environment has no business addressing production | `deny-dev-egress` |
| X13 | staging | prod | any | any | **DENIED.** Staging may not reach production, including "just for a test" | `deny-staging-to-prod` |
| X14 | dmz (except HAProxy) | prod | any | any | **DENIED.** Bitrix24 has no path to the cluster, the database or Keycloak | `deny-dmz-to-prod` |
| X15 | prod 10.10.20.10 (prober) | 203.0.113.10 (public VIP) | 443 | tcp | External-path probing. Uptime Kuma must traverse the same route a customer does — HAProxy, then Traefik, then the pod — because probing the pod directly reports healthy while the public path is broken | `prod-to-vip-probe` |

### Egress to the internet

| # | From | To | Port | Purpose | Rule ID |
| --- | --- | --- | --- | --- | --- |
| E1 | prod, staging nodes | NTP pool (EEA hosts) | 123/udp | Time synchronisation; wrong clocks break TLS, Kerberos and log correlation | `egress-ntp` |
| E2 | prod, staging, dev nodes | Debian repositories, `registry-1.docker.io`, `ghcr.io`, `quay.io` | 443 | Package and image pulls. **To be replaced by an internal mirror** — see `docs/capacity-plan.md` growth items | `egress-updates` |
| E3 | cert-manager (prod namespace) | `acme-v02.api.letsencrypt.org` | 443 | ACME account and order validation | `egress-acme` |
| E4 | DNS resolvers (mgmt) | Authoritative root and TLD servers | 53 | Resolution for E2, E3, E5, E6 | `egress-dns` |
| E5 | runner VMs (mgmt) | `github.com`, `objects.githubusercontent.com`, `api.github.com`, `registry.terraform.io`, `releases.hashicorp.com`, `*.github.io` Helm repos, `pypi.org`, `files.pythonhosted.org` | 443 | CI control plane and toolchain (ADR-008). The allow-list is deliberately explicit: a runner holding production credentials with open egress is an exfiltration path | `egress-ci` |
| E6 | Bitrix24 VM (dmz) | `www.bitrix24.com` and the vendor's licence-validation endpoints | 443 | Licence validation (ADR-007). Allow-listed, logged, and reviewed quarterly. Any addition is a security-reviewed change | `egress-bitrix` |
| E7 | monitoring VM | `alertmanager` webhook target, internal only | — | **No internet egress.** Alert routing terminates inside the EEA | — |
| **E8** | **any other host** | **internet** | **any** | **DENIED** by the VLAN default. A new egress path is a row in this table before it is a firewall rule | `deny-egress-default` |

## Observability paths

The monitoring stack runs **in-cluster** on every environment's own k3s cluster (kube-prometheus-stack,
Loki, Grafana, Alertmanager — deployed by Argo CD ApplicationSets from `monitoring/`). Long-term object
storage for TSDB blocks and Loki chunks is MinIO on `mon-01` (10.10.20.10). Uptime Kuma, the external
prober, also runs on `mon-01` because it must traverse the same path a customer does (X15).

The question this section answers is how the hypervisors, the load balancers and the CI runners — all on
VLAN 10, all unreachable from any other VLAN by invariant 1 — are observed, without weakening that
invariant.

### Metrics: agent-mode Prometheus on the hypervisors

Scraping the VLAN 10 hosts from the in-cluster Prometheus would require an exception to X11 — a flow
from `prod` into `mgmt`. An exception to an invariant is how the invariant dies, so the opposite
direction is used instead:

- A **Prometheus agent** runs on each hypervisor (pve-01, pve-02). Agent mode holds no local TSDB and
  has no query endpoint; it scrapes and remote-writes.
- The agent scrapes node_exporter on every VLAN 10 host: both hypervisors, both load balancers, both
  CI runners, and the backup appliance. All scrapes are **intra-VLAN 10** — no firewall rule needed.
- The agent remote-writes to the production Prometheus at `http://10.10.20.40:9090/api/v1/write`.
  That flow is **mgmt → prod**, which X1 already permits.
- External labels `cluster: prod, segment: mgmt` distinguish the remote-write stream from the
  in-cluster Prometheus's own scrapes. Prometheus deduplicates on the external labels.
- `node_exporter` on the hypervisors runs with `--no-collector.processes --no-collector.textfile
  --no-collector.systemd`, because those collectors expose command lines (which on a Proxmox node
  include API tokens passed to `pvesh`) and the contents of a directory any root process can write
  to, and the scrape crosses a VLAN boundary.

The result: the load balancers — the entry point of the entire platform — are observed, and X11 is
unchanged. No new firewall rule, no new exception, no new invariant violation.

### Logs: Grafana Alloy on every host

Every host runs **Grafana Alloy** (AGPL-3.0-only, same licensor and licence as Grafana and Loki).
Alloy performs log redaction on the host, before anything leaves the machine (INFRA-001 control M3),
and ships to the Loki push NodePort of the host's own environment:

| Host group | VLAN | Loki endpoints | Reachability |
| --- | --- | --- | --- |
| `viavitae` (prod guests) | 20 | `10.10.20.50..53:3100` | Intra-VLAN |
| `viavitae` (staging guests) | 30 | `10.10.30.40:3100` | Intra-VLAN |
| `viavitae` (dev guests) | 50 | `10.10.50.10:3100` | Intra-VLAN |
| `proxmox`, `loadbalancer`, `ci_runner` (VLAN 10) | 10 | `10.10.20.50..53:3100` | mgmt → prod (X1) |

Alloy is configured with multiple endpoints and fails over between them. A single endpoint would mean
a single node reboot silently stops log ingestion, and "the logs stopped" is indistinguishable from
"nothing happened".

### Why not a collection tier on `mon-01`

An alternative design places Prometheus and Loki on `mon-01` as systemd services, so that every
environment pushes to one stable address. It was rejected because:

1. `mon-01` is already the long-term storage target; adding the collection tier makes it a SPOF for
   both collection and storage, and a single machine failure removes observability at exactly the
   moment when it is most needed.
2. The in-cluster stack is GitOps-managed via Helm and Argo CD, which is the deployment mechanism
   for every other workload. A systemd service on a VM is a second mechanism, and two mechanisms for
   one function is how one of them stops being patched.
3. The licence inventory (ADR-009) already commits to kube-prometheus-stack; moving the collection
   tier off-cluster would require a second Prometheus deployment and a second Loki deployment,
   neither of which is covered by the existing licence assessment.

### Why not an exception to X11

The other alternative was to add a firewall rule permitting the in-cluster Prometheus to scrape VLAN 10
directly. It was rejected because:

1. X11 is the strongest invariant in this file. It is the control that makes a compromised runner
   survivable: a runner with no route to mgmt cannot reach the Proxmox API, the CI credentials or the
   backup appliance. Punching a hole — even a narrow one, even one port — weakens it.
2. The agent-mode approach achieves the same observability without weakening it. The flow is
   mgmt → prod, which is the permitted direction. The invariant holds exactly.
3. A narrow exception tends to widen. "Just one more port" is the most common firewall rule in any
   estate, and the rule that was added first is always the one cited as precedent for the second.

## Proxmox bridge and VLAN mapping

| Bridge | Tagged VLANs | Untagged | Used by |
| --- | --- | --- | --- |
| `vmbr0` | none | VLAN 10 (`mgmt`) | Hypervisor management, the only bridge the host itself uses |
| `vmbr1` | 20, 30, 40, 50 | **none** | All guest traffic. A VLAN-aware bridge with no native VLAN, so an untagged frame from a misconfigured guest goes nowhere |
| `vmbr2` | 10 | none | Runner VMs and the backup appliance, on a separate bridge so a guest flood cannot affect host management |

`vmbr1` has no untagged membership. This is deliberate and is the enforcement of the VLAN 99
prohibition: a guest that fails to tag gets no connectivity at all, which is a visible failure
during provisioning rather than a silent placement into the wrong segment.

## Cluster quorum and the qdevice

Proxmox HA on a two-node cluster requires a quorum device on a **third** machine. Without it,
losing the link between the two nodes gives each node zero votes out of two, both fence
nothing, and both believe they are alone — which is the split-brain case ZFS replication
handles worst, because both sides accept writes to the same replicated dataset.

| Item | Value |
| --- | --- |
| qdevice host | VMID 990, or a physical Raspberry Pi on unrelated power and an unrelated switch — the point is that it must not share a failure domain |
| VLAN | 10 (`mgmt`) |
| Resources | 1 vCPU, 512 MB RAM, 4 GB disk. It votes; it stores nothing |
| Votes | 1 |
| Expected cluster votes | 2 nodes + 1 qdevice = 3; quorum = 2 |
| Survives | Loss of either node, or loss of one node link |
| Does not survive | Simultaneous loss of both nodes — that is a disaster, not a failure, and is handled by `docs/runbooks/dr-drill.md` |

The qdevice is provisioned outside Terraform (a one-line install, and putting it in the same
automation as the cluster it arbitrates means a Terraform failure can take quorum with it) but
is recorded here so its absence is a findable defect rather than a mystery.

## Kubernetes network policy

VLAN rules stop at the node. Inside the cluster, `k8s/policies/network-policies/` provides:

| Policy | Effect |
| --- | --- |
| `default-deny` per namespace | Denies all ingress and all egress. Applied to every platform namespace and every tenant namespace. A workload with no explicit allow rule is unreachable and cannot reach out — including to the internet, which is why E2 exists at node level for image pulls but not for pods. |
| `allow-ingress-from-haproxy` | Permits ingress from the node CIDR on the ServiceLB ports, which is the only path a public request takes. |
| `allow-egress-dns` | Permits UDP and TCP 53 to the `kube-dns` Service in `kube-system`. Without it every workload that resolves a name fails, and the failure looks like an application bug. |
| `allow-api-to-db` | Permits egress from the `api` namespace to the PostgreSQL Service on 5432, and nothing else. |
| `allow-web-to-api` | Permits ingress to `api` from the `web` namespace only. |
| `tenant-<slug>-isolated` | Permits ingress from the ingress controller and egress to DNS and to its own database only. Generated per tenant; hand-written per-tenant policy is how one tenant ends up able to reach another. |
| `monitoring-scrape` | Permits ingress from the `monitoring` namespace to metrics ports. Scoped to the port, not to the pod, so a scrape cannot become a general ingress path. |
| `deny-cross-tenant` | An explicit deny for pod-to-pod traffic between tenant namespaces, layered on the default deny so that removing one policy does not open the path. |

Pod Security Standards are set to `restricted` on every namespace
(`k8s/policies/pod-security/`), and `k8s/policies/kyverno/` enforces that the labels are
actually present, so a namespace created by a new ApplicationSet cannot arrive unlabelled.

## Invariants

These are asserted by the quarterly DR drill and by review, and violating one is a security
incident, not a configuration preference.

1. No route from `dmz`, `prod`, `staging` or `dev` to `mgmt` (X11), and no route
   from `dmz` to `prod` other than X2 (X14).
2. No inbound internet rule other than I1 and I2.
3. No untagged guest on `vmbr1`.
4. No VMID reuse, ever.
5. Bitrix24 egress is exactly E6 and nothing more.
6. Tenant pods have no internet egress; `default-deny` plus `allow-egress-dns` is the whole
   of their outbound world.
7. The Proxmox API is reachable only from VLAN 10 and only with a scoped API token — never
   `root@pam` with a password.
8. The state bucket and the backup bucket are different buckets with different credentials.

## Change procedure

1. Open an issue describing the path that is needed and why the existing rules do not cover it.
2. Add or amend the row in the table above, in the same pull request as the configuration
   change. A configuration change with no table change is returned in review.
3. Security approval is required for any change to X11, X12, X13, X14, E5, E6, E8, or to
   any row in
   the "Inbound from the internet" table. `CODEOWNERS` requests it for
   `docs/network-topology.md` and for `k8s/policies/`.
4. Apply, then verify from the outside: `nmap` or `nc` from a host in the source VLAN, not
   from the host itself. A rule that appears correct in the Proxmox UI and is shadowed by a
   guest `iptables` rule is the common failure, and only an external probe distinguishes them.
5. Record the verification output in the pull request.
