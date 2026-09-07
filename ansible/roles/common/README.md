# ansible/roles/common

Applies to every host, hypervisor and guest. It is the first role any playbook runs
and the only one that `playbooks/update.yml` reuses with upgrades enabled.

## What it owns

| Area | Detail |
| --- | --- |
| Packages | A base set including the diagnostics that are useless to install during an incident |
| Time | `systemd-timesyncd` against EEA pools; wrong clocks break TLS and log correlation |
| Logging | journald capped at 1 GiB and 90 days, compressed and sealed, not forwarded |
| Identity | The `viavitae` automation user, key-only, with passwordless sudo that logs input and output |
| ZFS (hosts only) | ARC capped at 48 GiB, monthly scrub cron, and an assertion that a scrub has actually completed |

## What it does not own

Hardening (`roles/hardening`), services (`roles/k3s`, `roles/postgres`, …), and
backups (`roles/wal-g`, `roles/backup-check`). The split matters because `common` runs
on every host including the hypervisors, and a role that installs services would then
install them there too.

## The ZFS ARC cap is the load-bearing task

`docs/capacity-plan.md` commits 192 GiB per node to guests out of 256 GiB, which
assumes the ARC is capped at 48 GiB. ZFS grows the ARC into free memory by default, so
without `/etc/modprobe.d/zfs.conf` the guest budget is a fiction and the failure mode is
VMs being killed under memory pressure — which reads as an application fault and sends
the investigation in the wrong direction entirely.

The cap is a module parameter and needs a reboot. The handler says so rather than
rebooting: an unattended reboot of a hypervisor is an outage, and tuning is not an
incident.

## The scrub assertion

A ZFS replica that has not been read end-to-end is a replica whose silent corruption is
undiscovered, and silent corruption is precisely what ZFS replication does **not**
detect — `pvesr` compares metadata, not every block. ADR-002 condition 4 requires
monthly scrubs; the assertion is what turns that condition into a failing run instead of
a checkbox nobody reads.
