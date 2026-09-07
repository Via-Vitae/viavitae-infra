# monitoring/grafana/dashboards

Grafana dashboard JSON files. Each dashboard is mounted as a ConfigMap by Argo CD
and appears in the Platform folder in Grafana.

## Rules

1. Every Loki query carries a namespace selector (INFRA-001 M6). A dashboard that
   queries Loki without a namespace selector is a dashboard that can leak one
   tenant's logs into another tenant's administrator's view.
2. Dashboard review is part of the pull-request checklist. A new dashboard or a
   change to an existing one must be reviewed by a platform engineer and, if it
   touches tenant-visible data, by the DPO.
3. No dashboard is organisation-wide public. Per-tenant dashboards go in
   per-tenant folders with Viewer access for the tenant administrator.

## Naming convention

`<component>-<purpose>.json`, e.g. `platform-overview.json`,
`tenant-assessment-latency.json`.
