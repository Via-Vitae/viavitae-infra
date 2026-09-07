# modules/k3s-node

A Kubernetes node as a Proxmox guest. Wraps [`../proxmox-vm`](../proxmox-vm/README.md).

This module declares the k3s version and does not install it. The version is
written to `/etc/viavitae/k3s-version` at first boot; `ansible/roles/k3s` reads
that file and installs exactly it, failing if the file is absent.

## Why the version lives in Terraform and the installer lives in Ansible

One declaration, one installer. The alternatives are both worse:

- **Ansible declares and installs.** Simple, but then the version is a role
  default, and a role default is invisible in the plan that a reviewer approves.
  Upgrading k3s across `prod` becomes a change to a defaults file with no plan
  output and no environment-level gating.
- **cloud-init installs.** Then the install is not idempotent, not `--check`-able,
  runs before hardening, and cannot be re-run without rebuilding the VM.

Writing a fact and having a different tool act on it keeps the version in the plan
— where an upgrade is visible, reviewable and environment-gated — while keeping
installation in the tool that can retry, verify and roll back.

## ADR-002 quorum invariant

`control_plane_count = 3` is rejected unless `control_plane_nodes` lists three
**distinct** Proxmox node names. Three control-plane VMs on two nodes always loses
etcd quorum when one node fails: by the pigeonhole principle at least two of the
three share a node, so that failure removes two of three members, which is more
than half. The cluster then cannot elect a leader and the API server stops
accepting writes — worse than one control plane, which at least restarts under
Proxmox HA.

The check is a `terraform_data` resource with `lifecycle.precondition` rather than
a variable validation, because Terraform does not support `lifecycle` on a module
block and the condition needs to compare two variables.

A second precondition requires this VM's `node_name` to appear in
`control_plane_nodes`, so the declared placement cannot drift from the real one
and quietly invalidate the check.

## What is fixed here

| Fixed | Control plane | Worker | Reason |
| --- | --- | --- | --- |
| vCPU | 2 | 8 | etcd wants consistent disk latency, not cores |
| Memory | 4 GiB | 32 GiB | Workers are what `docs/capacity-plan.md` sizes the estate from |
| Disk | 60 GiB | 100 GiB | Image garbage collection dominates worker disk use |
| `backup-*` tag | `backup-daily` | `backup-weekly` | Control planes hold etcd, the cluster's only irreplaceable state. Workers hold no persistent tenant data and are rebuilt from Git |
| `protect_deletion` | `true` | `false` | Destroying a control plane destroys an etcd member; a worker is rebuilt in minutes, and protecting it would make a legitimate scale-down require an override |
| `ha_group` | required | optional | With one control plane in the pilot, HA is the only thing that brings it back |
| `memory_ballooning` | `false` | `false` | A kubelet that loses memory evicts pods; an etcd member that swaps out misses its heartbeat deadline and is removed from the cluster |
| `discard` | on | on | Without it a zvol grows forever while the guest believes it has free space |

## Files written at first boot

| Path | Content |
| --- | --- |
| `/etc/viavitae/k3s-version` | Pinned release, e.g. `v1.36.4+k3s1` |
| `/etc/viavitae/k3s-role` | `control_plane` or `worker` |
| `/etc/viavitae/k3s-api-vip` | kube-vip address, only for a multi-control-plane cluster |
| `/etc/viavitae/environment` | Environment label |

`k3s_version` must match `^v\d+\.\d+\.\d+\+k3s\d+$`. A branch (`v1.36`) or a
channel (`stable`) resolves to whatever is newest at install time, which makes a
rebuild non-reproducible and an upgrade unreviewed.
