# ansible/roles/monitoring-agent

Install the observability agent on every host.

The role installs:
- **node_exporter** (Apache-2.0) on every host; exposes host metrics on port 9100.
- **Grafana Alloy** (AGPL-3.0-only) on every host; performs log redaction at the source
  (INFRA-001 control M3) and ships to the Loki push NodePort of the host's own environment.
- **Prometheus in agent mode** on the hypervisors only; scrapes VLAN 10 hosts and
  remote-writes to the production Prometheus.

The role refuses to run without `host_log_endpoints` defined in the inventory, because an
agent that cannot ship is an agent that buffers to disk until the disk is full, and then
drops logs silently.

## What the role does not do

- It does not install the in-cluster monitoring stack (kube-prometheus-stack, Loki,
  Grafana, Alertmanager). That is deployed by Argo CD ApplicationSets from `monitoring/`.
- It does not configure alert routing. That is `monitoring/alertmanager/`.
- It does not configure dashboards. That is `monitoring/grafana/dashboards/`.
