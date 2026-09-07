# monitoring/uptime-kuma

Uptime Kuma runs on `mon-01` (10.10.20.10) as a Docker container managed by
`docker-compose`. It is the external prober: it monitors the public endpoints
the way a customer does, from outside the infrastructure (INFRA-001 X15).

Uptime Kuma is deployed from manifests in this directory, not from a third-party
chart (ADR-009 licence inventory: MIT, approved).

## What is configured here

- Docker Compose file for Uptime Kuma.
- Tag and monitor definitions (exported from the Uptime Kuma API).

## What is not configured here

- Alert notifications. Those go through Alertmanager's webhook relay.
- The monitors themselves. Those are configured in the Uptime Kuma UI and
  exported to `monitors.json` by the backup script.
