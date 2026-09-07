# ansible/roles/k3s

Installs the k3s version that Terraform declared, verifies it against the published
checksum, writes the node configuration and starts the service.

## The version is not a role default

It is read from `/etc/viavitae/k3s-version`, which Terraform wrote at first boot from
`terraform/envs/<env>/terraform.tfvars`. The role **fails** when that file is missing.

A default here would be a second source of truth, and the two would disagree on the
first upgrade — silently, because the role would keep working. Keeping the declaration
in Terraform puts the version in the plan a reviewer approves and behind the
environment gate; keeping the installation here makes it idempotent, `--check`-able and
rollback-able. ADR-001 decision 3.

## Pinned binary, verified twice

`get_url` fetches `sha256sum.txt` and the binary from the release for that exact
version, and a subsequent task re-verifies the binary against the published checksum
for the matching filename. Downloading a binary and a checksum from the same place is
not verification on its own, so `k3s_release_checksum` exists to pin the checksum file
itself from the inventory, where the value is compared against the release notes at
review time.

This is also what satisfies the checksum-pinning gate in
`.github/workflows/compliance-check.yml`: a workflow or a role that downloads a binary
must pin it.

## What is kept and what is disabled

Nothing is disabled. ADR-001 keeps the bundled Traefik (the only ingress controller),
ServiceLB (the NodePorts HAProxy forwards to), CoreDNS and metrics-server. Replacing
any of them means running two implementations of one function, and two load-balancer
implementations on one cluster is a source of IP-allocation conflicts.

`etcd-snapshot-schedule-cron` is set to every six hours with eight generations
retained. Git holds the manifests; etcd holds the state, and a cluster rebuilt from Git
alone loses every Secret, every PVC binding and every Argo CD application status.

## The cluster token

`k3s_cluster_token` comes from `vault.sops.yml`. It authorises a machine to join the
cluster, and for a control plane that means to become an etcd member — so it is a
control-plane credential and is treated as one. `config.yaml` is mode `0600` for that
reason.

Rotation is a re-run of this role with a new value, which rewrites every node's config
in one pass. Rotating on one node at a time partitions the cluster instead.
