# Capacity plan

Sizing, growth assumptions and the tenant density model for the ViaVitae platform, together
with the trigger points at which hardware has to be bought. Owned by
`@Via-Vitae/architects` and `@Via-Vitae/platform`.

The numbers here are the inputs to `tools/cost-estimate.py`. If you change one, change it
there too — a capacity plan and a cost model that disagree produce a price that is wrong in
a direction nobody checks.

Reviewed quarterly, and immediately after any DR drill, because a drill is the only moment
the N-1 assumption is actually tested.

---

## Hardware baseline

The pilot estate, as procured.

| Item | Specification | Quantity | Purchase price | Amortisation |
| --- | --- | --- | --- | --- |
| Proxmox node | 2 × 16-core (32 cores / 64 threads per node), 256 GB ECC RAM, 2 × 1.92 TB NVMe in ZFS mirror (VM disks), 2 × 8 TB HDD in ZFS mirror (local backup staging), 2 × 10 GbE | 2 | €9,000 each | 60 months |
| Backup appliance | 4 cores, 8 GB RAM, 8 × 8 TB HDD ZFS raidz2 (48 TB usable), 10 GbE | 1 | €3,000 | 60 months |
| Network | 2 × 24-port 10 GbE switch, 1 × firewall/router appliance, cabling, SFPs | 1 set | €2,000 | 60 months |
| Offsite replica | Encrypted copy in a second EEA location, 2 TB committed | 1 | — | €40/month |
| Connectivity | Symmetric 1 Gbit/s, static IPv4 block including 203.0.113.0/24 | 1 | — | €60/month |
| Power | €0.25/kWh, measured at the PDU | — | — | see §Fixed cost |

Amortisation is straight-line over 60 months with no residual value. Hardware is replaced on
failure after month 48, not on schedule, and the amortisation is the accounting view rather
than a replacement plan.

**Usable capacity per node.**

| Resource | Raw | Reserved for hypervisor and ZFS | Available to guests |
| --- | --- | --- | --- |
| vCPU | 64 threads | 4 threads | 60 threads, and 120 vCPU at the 2:1 overcommit ratio below |
| RAM | 256 GB | 16 GB host + 48 GB ARC cap | 192 GB |
| NVMe | 1.92 TB mirrored = 1.92 TB usable | 20 % ZFS free-space headroom (a pool above 80 % full degrades badly and cannot resilver) | 1.53 TB |
| HDD | 16 TB mirrored = 16 TB usable | 20 % headroom | 12.8 TB |

**Overcommit policy: 2:1 for vCPU, 1:1 for RAM.** CPU overcommit is safe because k3s
workloads here are I/O-bound and bursty; RAM overcommit is not safe at all, because the
guest kernel's OOM killer chooses the victim and PostgreSQL is a large, attractive target.
The ARC cap of 48 GB is what makes 1:1 RAM honest — without it ZFS takes memory that the
guest budget already allocated, and the shortfall appears as random VM kills under load.

**Cluster totals, both nodes healthy:** 240 vCPU, 384 GB guest RAM, 3.06 TB NVMe.

## Committed allocation

Everything Terraform provisions, at the target state described in `README.md`.

| VM | Env | Count | vCPU each | RAM each | Disk each | Total vCPU | Total RAM |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `prod-cp-N` (k3s control plane) | prod | 3 | 2 | 4 GB | 60 GB | 6 | 12 GB |
| `prod-worker-N` (k3s worker) | prod | 4 | 8 | 32 GB | 100 GB | 32 | 128 GB |
| `db-01`, `db-02` (PostgreSQL) | prod | 2 | 8 | 32 GB | 500 GB | 16 | 64 GB |
| `sso-01` (Keycloak) | prod | 1 | 4 | 8 GB | 60 GB | 4 | 8 GB |
| `mon-01` (MinIO object store for Loki and Prometheus, plus the external prober) | prod | 1 | 8 | 24 GB | 430 GB | 8 | 24 GB |
| `lb-01`, `lb-02` (HAProxy + keepalived) | dmz | 2 | 2 | 2 GB | 20 GB | 4 | 4 GB |
| `crm-01` (Bitrix24) | dmz | 1 | 8 | 16 GB | 200 GB | 8 | 16 GB |
| `crm-db-01` (Bitrix24 database) | dmz | 1 | 4 | 8 GB | 150 GB | 4 | 8 GB |
| `runner-01`, `runner-02` (CI) | mgmt | 2 | 4 | 8 GB | 100 GB | 8 | 16 GB |
| `backup-01` | mgmt | 1 | 4 | 8 GB | 48 TB HDD | 4 | 8 GB |
| `qdevice-01` | mgmt | 1 | 1 | 0.5 GB | 4 GB | 1 | 0.5 GB |
| `stg-cp-0` | staging | 1 | 4 | 8 GB | 60 GB | 4 | 8 GB |
| `stg-worker-0` | staging | 1 | 4 | 16 GB | 100 GB | 4 | 16 GB |
| `stg-db-0`, `stg-sso-0` | staging | 2 | 2 | 6 GB avg | 100 GB | 4 | 12 GB |
| `dev-k3s-0` | dev | 1 | 4 | 16 GB | 100 GB | 4 | 16 GB |
| **Committed total** | | **27** | | | | **115** | **340.5 GB** |

| Resource | Committed | Available (both nodes) | Utilisation | Headroom |
| --- | --- | --- | --- | --- |
| vCPU | 115 | 240 | 48 % | 125 vCPU |
| RAM | 340.5 GB | 384 GB | **89 %** | **43.5 GB** |
| NVMe | 2.5 TB | 3.06 TB | **82 %** | 0.56 TB |

**RAM and NVMe are the binding constraints, and both are already tight.** vCPU has room
because it is overcommitted; RAM is not, and NVMe is at the ZFS degradation threshold. This
is the honest starting position, and it is why the trigger table below starts at values that
look small.

The pilot differs from the table in two places: one `prod-cp` VM at 4 vCPU / 8 GB instead of
three at 2 vCPU / 4 GB (ADR-002), and no `db-02` standby. That frees 6 vCPU and 36 GB RAM,
which is what makes the pilot fit at all.

## N-1: what happens when a node fails

With two nodes there is no N-1 capacity. The surviving node has 120 vCPU and 192 GB guest
RAM, and 340.5 GB is committed. **Not everything can run.** This is not a contingency to be
written; it is arithmetic, and pretending otherwise produces a runbook that fails on the
first real failure.

The surviving node therefore runs a defined subset, in this order, and Proxmox HA start
priorities are set to match (`ansible/roles/common` writes them):

| Priority | Starts on the surviving node | RAM | Why this order |
| --- | --- | --- | --- |
| 1 | `qdevice-01` | 0.5 GB | Without quorum nothing else may start, and fencing becomes unsafe |
| 2 | `lb-01` or `lb-02` (whichever lost the VIP) | 2 GB | The public entry point. Without it, nothing is reachable at all |
| 3 | `db-01` | 32 GB | Tenant data. Everything else is a cache of Git or of this |
| 4 | `sso-01` | 8 GB | Without authentication no administrator can log in to fix anything, including this |
| 5 | `prod-cp-0` | 4 GB | Single control plane; the cluster runs degraded but runs |
| 6 | `prod-worker-0`, `prod-worker-1` | 64 GB | Two of four workers. Tenant workloads run at reduced capacity and the `tenant-quota` alert fires |
| 7 | `mon-01` | 24 GB | Alerting and dashboards. Deliberately below the workloads it monitors, because a monitoring stack that prevents recovery is worse than recovering blind — but above `dev`, because the incident needs evidence |
| 8 | `runner-01` | 8 GB | One CI runner, so a fix can be built and applied during the incident |
| 9 | `backup-01` | 8 GB | Backups must continue during an incident, not pause for it |
| **Subtotal, priority 1–9** | | **142.5 GB** | Fits in 192 GB with 49.5 GB for ARC and burst |
| — | **Does not start:** `db-02`, `prod-worker-2..3`, `crm-01`, `crm-db-01`, all of `staging`, all of `dev`, `runner-02` | 198 GB | Recovered after the node returns, in reverse priority order |

Two consequences that are stated here because they are unwelcome and therefore get omitted:

1. **Bitrix24 does not survive a node failure** in the pilot. It is priority 10 and there is
   no capacity for it. If it is business-critical, it needs dedicated capacity, which is a
   third node or a smaller worker pool. That is a business decision, recorded here rather
   than discovered during an incident.
2. **Staging is unavailable during a node failure**, which means the DR rehearsal target is
   gone at exactly the moment a rehearsal would be most useful. The quarterly drill is
   therefore run against a **restored copy on the surviving node with dev and staging
   deliberately shut down first** — see `docs/runbooks/dr-drill.md`.

## Growth assumptions

| Driver | Assumption | Source | Confidence |
| --- | --- | --- | --- |
| Tenant count | 11 today, 25 by month 6, 50 by month 18, 100 by month 36 | Sales pipeline, `viavitae-clients` | Medium — the only input with a commercial rather than technical origin |
| Data per tenant | 2 GB at onboarding, growing 150 MB/month, 20 GB by month 36 | Measured on the three tenants running in `staging` | Medium |
| Log volume | 400 MB/tenant/day raw, 90 MB after redaction and drop rules | Measured, `monitoring/loki/values.yaml` | High |
| Metric series | 8,000/tenant, of which 6,000 are kube-state-metrics and exporter noise | Measured | High |
| Request rate | 0.5 req/s average, 8 req/s peak per tenant | Measured on demo traffic; **not** validated against real tenant load | Low — the weakest number in this document |
| Peak concurrency | 5 % of a tenant's end users simultaneously | Industry norm for a CRM-adjacent product | Low |
| Backup growth | 1.4 × live data (base plus WAL plus `vzdump` copies at the retention in `backup/`) | Computed from the retention table | High |

The two low-confidence numbers are the reason the trigger table has a "measured, not
forecast" column: growth is watched against measurement, and the forecast is used only for
procurement lead time.

## Tenant density model

One tenant consumes, at steady state:

| Resource | Quota | Rationale |
| --- | --- | --- |
| Namespace CPU limit | 2 vCPU | `k8s/namespaces/` template; enforced by ResourceQuota and LimitRange, not by convention |
| Namespace memory limit | 4 GB | Same |
| Persistent storage | 10 GB | Same |
| PostgreSQL schema | 2 GB average, 20 GB at month 36 | ADR-003 |
| WAL archive share | 0.5 GB/day of the instance-wide stream, attributed pro rata | `backup/wal-g/` |
| Log storage | 90 MB/day × 30 days = 2.7 GB | INFRA-001 F1 |
| Metric series | 8,000 active | `monitoring/prometheus/values.yaml` cardinality budget |
| Backup share | 1.4 × schema size, at 35-day WAL and 14-day `vzdump` retention | `backup/` |

**Density per worker VM.** A `prod-worker` at 8 vCPU / 32 GB hosts 4 tenants at quota
(4 × 2 vCPU = 8, 4 × 4 GB = 16 GB, leaving 16 GB for system pods, the kubelet and burst).
Quota is a ceiling, not a reservation, so real density is higher — measured at 6 tenants per
worker at 35 % average utilisation. **Planning uses 4, not 6**: a quota that is only
satisfiable when everyone is idle is not a quota.

| Tenants | prod workers needed | RAM for workers | Total cluster RAM committed | Fits two nodes? |
| --- | --- | --- | --- | --- |
| 11 (today) | 3 | 96 GB | 304.5 GB | Yes, 79 % |
| 25 | 7 | 224 GB | 432.5 GB | **No** |
| 50 | 13 | 416 GB | 624.5 GB | **No** |
| 100 | 25 | 800 GB | 1,008.5 GB | **No** |

**The pilot hardware cannot reach 25 tenants.** It reaches roughly 16 (four workers, 128 GB,
total 336.5 GB committed, 88 % of 384 GB) before RAM becomes unavailable, and roughly 14
before NVMe does. Everything above that requires procurement, and the lead time — not the
installation — is the schedule risk.

## Trigger points

Each trigger has an action, an owner and a lead time. A trigger that is noticed after it is
crossed is a capacity plan that was not read.

| Trigger | Measured, not forecast | Action | Lead time | Owner |
| --- | --- | --- | --- | --- |
| Cluster RAM committed > 80 % | Prometheus `cluster_ram_committed_ratio` > 0.80 for 7 days | Order node 3. This is also the ADR-002 trigger that unlocks a 3-node k3s control plane and a 99.9 % SLO | 6–8 weeks | Platform |
| ZFS pool > 75 % used | `node_zfs_pool_used_ratio` > 0.75 | Order NVMe, or migrate cold tenant schemas to the HDD tier | 4 weeks | Platform |
| Tenant count ≥ 14 | `tenant_count` gauge | Order node 3 if not already ordered | 6–8 weeks | Architects |
| Tenant count ≥ 40 | `tenant_count` gauge | Supersede ADR-003: move to database-per-tenant on dedicated DB VMs | One quarter of design work | Architects |
| PostgreSQL instance > 500 GB | `pg_database_size_bytes` sum | Same as above | One quarter | Architects |
| p95 API latency > 300 ms for 3 days | SLO dashboard | Add a worker VM (needs RAM headroom first) | 1 day if headroom exists | Platform |
| Loki ingest > 6 GB/day | `loki_distributor_bytes_received_total` rate | Tighten drop rules before buying disk; log volume growth is almost always a debug statement left in | 1 day | Platform |
| Prometheus active series > 400,000 | `prometheus_tsdb_head_series` | Enforce the cardinality budget; add a recording rule for the expensive query, not more RAM | 1 week | Platform |
| Backup window > 6 h | `vzdump` task duration | Move to incremental `vzdump` (`--mode snapshot` with changed-block tracking) or add a second backup target | 2 weeks | Platform |
| DR drill RTO > 15 min | `backup/drills/last-drill-report.md` | Investigate before adding hardware; an RTO miss is usually a procedure defect, not a capacity one | One drill cycle | Platform |
| Any single node > 90 % RAM for 24 h | `node_memory_MemAvailable_bytes` | Immediate: stop `dev`, then `staging`, per the N-1 order above | Immediate | On-call |

## Fixed and marginal cost

These constants are the inputs to `tools/cost-estimate.py` and are duplicated there
deliberately, with a test that fails if they diverge.

**Fixed platform cost, per month.**

| Component | Calculation | Monthly |
| --- | --- | --- |
| Compute hardware | 2 × €9,000 / 60 | €300.00 |
| Backup appliance | €3,000 / 60 | €50.00 |
| Network | €2,000 / 60 | €33.33 |
| Power | 0.85 kW continuous × 730 h × €0.25 | €155.13 |
| Offsite replica | 2 TB committed | €40.00 |
| Connectivity | 1 Gbit/s symmetric | €60.00 |
| **Total fixed** | | **€638.46** |

Power is measured at the PDU, not estimated from datasheets: an idle 2-socket node with 256 GB
of ECC RAM draws roughly 350 W, which is close to the datasheet figure only because the
memory is populated. An under-populated node draws less, and the model uses the measured
value.

**Marginal cost per tenant, per month.**

| Component | Calculation | Monthly |
| --- | --- | --- |
| Power share | 4 GB of 512 GB across 2 nodes × 0.7 kW × 730 h × €0.25 | €1.07 |
| Block storage | 10 GB × €0.02 | €0.20 |
| Backup and WAL share | 2.8 GB × €0.02 × 1.4 | €0.08 |
| Log and metric share | 2.7 GB Loki + 8,000 series | €0.65 |
| **Total marginal** | | **€2.00** |

**Break-even against the €30–50 monthly ceiling.**

| Price point | Tenants to cover fixed cost | Cost per tenant at 25 tenants | Margin at 25 tenants |
| --- | --- | --- | --- |
| €30/month | 638.46 / (30 − 2.00) = **23 tenants** | (638.46 + 50.00) / 25 = **€27.54** | **€2.46 (8.2 %)** |
| €40/month | 638.46 / 38 = **17 tenants** | €27.54 | €12.46 (31 %) |
| €50/month | 638.46 / 48 = **14 tenants** | €27.54 | €22.46 (45 %) |

**This is the finding the capacity plan exists to surface.** At 11 tenants — the number
running today — the infrastructure cost per tenant is (638.46 + 22.00) / 11 = **€59.99**,
which exceeds the *upper* end of the €30–50 ceiling. The €30 tier does not cover its own
infrastructure below 23 tenants, and at 25 tenants it returns 8.2 % before support, payment
processing, VAT, engineering time or any allowance for the hardware that has to be bought at
14 tenants anyway.

The implications are commercial and are stated here rather than left in a spreadsheet:

1. **The €30 tier is a volume product.** Selling it below 23 tenants loses money on
   infrastructure alone. Either the floor price rises, or a minimum tenant count is a
   condition of offering it.
2. **Node 3 is not optional and is not far away.** It is triggered at 14 tenants by RAM and
   at roughly the same point by NVMe, with a 6–8 week lead time. Procurement must start at
   tenant 11, which is now.
3. **Cost per tenant falls with density, and density is capped by the quota model.** Raising
   the per-tenant quota raises revenue per tenant and lowers density; lowering it does the
   opposite. Both are pricing decisions with an infrastructure consequence, and
   `tools/cost-estimate.py --tenants N --quota-cpu X --quota-ram Y` exists so the two can be
   evaluated together rather than argued about separately.

## Growth items not yet funded

Recorded so they are not rediscovered as emergencies.

| Item | Why | Rough cost | Blocking? |
| --- | --- | --- | --- |
| Third Proxmox node | Unlocks 3-node k3s control-plane HA (ADR-002) and 25 tenants | €9,000 | Yes, at 14 tenants |
| Internal container registry (Harbor) | Removes `registry-1.docker.io` and `ghcr.io` from the egress allow-list (E2), removes pull rate limits, and makes image digests an internal supply-chain control. Also a prerequisite for the signed-image requirement in `k8s/argocd/projects/prod.yaml`, which cannot be met from a registry we do not control | €0 software, 1 VM at 4 vCPU / 8 GB / 500 GB | Yes, for the signed-image policy |
| Internal Debian and Helm mirror | Same egress argument; also makes a node rebuild possible during an internet outage | 1 VM at 2 vCPU / 4 GB / 1 TB | No, but E2 depends on it for offline recovery |
| Second backup target in a different EEA facility | The current 3-2-1 relies on two locations, one of which is the same building as the primary for the `vzdump` copies | €40/month | Yes, for the DR drill to be meaningful |
| Dedicated Bitrix24 capacity | Currently priority 10 in the N-1 order, i.e. it does not survive a node failure | 8 vCPU / 24 GB | Only if Bitrix24 becomes business-critical |
| Hardware security module or TPM-backed key custody | age keys are currently software-held by two custodians (ADR-005) | €300 | No, until tenant count or auditor pressure requires it |

## What invalidates this plan

- A tenant with a workload profile unlike the current eleven — batch processing, file
  conversion, video, or an AI inference endpoint. The density model assumes I/O-bound
  request/response work at 35 % average utilisation. One CPU-saturated tenant consumes a
  worker that the model says holds four.
- Real traffic data replacing the low-confidence request-rate assumption. If peak per-tenant
  load is 5× the estimate, worker count is the binding constraint rather than RAM, and the
  table above changes shape rather than scale.
- A change to the €30–50 price ceiling, which moves every break-even number.
- Availability of a genuinely EU-sovereign object store at better than €0.02/GB, which
  changes both the marginal cost and the offsite replication design.
