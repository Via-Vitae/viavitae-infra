# modules/monitoring-vm

The VM behind the observability stack — **not** the stack itself. Prometheus,
Grafana, Loki and Alertmanager run in the cluster, deployed by Argo CD from
`monitoring/*/values.yaml`. This module provisions the two things that cannot run
in the cluster:

1. **The object store** those components write to. An in-cluster MinIO would store
   the logs of the cluster inside the cluster it is logging, so the failure that
   matters destroys the evidence of itself. Loki has no local-disk mode that
   survives a node failure.
2. **The external prober** (Uptime Kuma). A monitor running inside the thing it
   monitors reports healthy until the moment there is nobody left to report
   anything.

## Invariants

| Invariant | Reason |
| --- | --- |
| Address inside `10.10.20.0/24` | Rules X6, X7 and X8 describe paths to this address. On `mgmt` it would be unreachable from the cluster without an exception to the no-route-to-mgmt invariant |
| `loki_bucket != metrics_bucket` | Logs are personal data with a 30-day cap (INFRA-001 F1); metric blocks are aggregates with a one-year downsampled retention. One bucket cannot carry two retention rules |
| Bucket disk excluded from `vzdump`, included in replication | The buckets have their own lifecycle and their own offsite replication. Copying 400 GB of chunks into a VM archive nightly doubles the backup window to protect data already protected twice — while replication still gives a node-failure copy |
| `protect_deletion = true` | Loki chunks are personal data (INFRA-001 R2), so this is a protected host despite holding no tenant database |
| Log retention written to `/etc/viavitae/minio-loki-retention-days = 30` | A lifecycle rule that outlives the DPIA is a retention breach nobody decided to make. The value is on the machine, so an audit can compare it against INFRA-001 without reading Terraform state |
| HA group required | Priority 7 in the N-1 order: above `dev`, below the workloads. An incident without evidence is an incident that repeats |

## Files written at first boot

| Path | Content |
| --- | --- |
| `/etc/viavitae/minio-loki-bucket` | Loki bucket name |
| `/etc/viavitae/minio-metrics-bucket` | Metrics bucket name |
| `/etc/viavitae/minio-region` | `eu-central-1` |
| `/etc/viavitae/minio-loki-retention-days` | `30` |
| `/etc/viavitae/uptime-hostname` | Public status page name |
| `/etc/viavitae/environment` | Environment label |

## Sizing

8 vCPU, 24 GiB, 30 GiB root plus 400 GiB bucket volume — the numbers in
`docs/capacity-plan.md`. The bucket volume is sized from the retention model, not
from disk price: 25 tenants × 90 MB/day after redaction × 30 days ≈ 70 GB for Loki,
plus roughly 100 GB of long-term metric blocks at the cardinality budget. 400 GB is
about four times that, which is the headroom the `ZFS pool > 75 %` trigger assumes.

## Not managed here

MinIO credentials, bucket policies and TLS are applied by
`ansible/roles/monitoring-agent` from the SOPS-encrypted inventory. The Uptime Kuma
monitor list is desired-state in `monitoring/uptime-kuma/monitors.yaml` and applied
by the same role — a monitor added by hand on the box is a monitor that disappears
at the next run and, worse, one that nobody reviewed.
