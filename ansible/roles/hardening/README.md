# ansible/roles/hardening

CIS Level 1 for Debian 12, plus the controls this estate needs that the profile does
not mention. Depends on `common`.

## Why Level 1 and not Level 2

Level 2 items are listed in `defaults/main.yml` with the reason each is excluded. The
three that matter:

- **Separate `/tmp`, `/var`, `/home` partitions.** The guests are VMs with one zvol.
  Repartitioning means rebuilding every VM for a control that Kyverno already provides
  better, at the container level, with `readOnlyRootFilesystem`.
- **A host firewall on every interface.** Segmentation is at the router
  (`docs/network-topology.md`) and in Kubernetes NetworkPolicy. A third firewall layer
  means three places where an allow rule can be silently negated by a deny in another,
  which is how a service becomes unreachable with no error anywhere.
- **SELinux/AppArmor enforcing.** Debian ships AppArmor; k3s and ZFS zvol paths produce
  denials that are indistinguishable from application faults, and nobody here can own
  the policy. Revisit when that changes.

An excluded control that is written down with its reason is a decision. An excluded
control that is not written down is an omission, and the next auditor treats it as one.

## The SSH drop-in and the lockout risk

Configuration lands in `/etc/ssh/sshd_config.d/90-viavitae.conf`, not in the
distribution's file, so a package upgrade cannot silently revert it. The task that
writes it uses `validate: /usr/sbin/sshd -t -f %s`, which means a syntax error fails the
task rather than the next restart — the difference between a failed run and a host that
cannot be reached.

`playbooks/hardening.yml` additionally backs up `sshd_config` first, prints the backup
path, runs in batches of 20 %, and verifies SSH connectivity after each host. A
hardening run that locks out the automation user is unrecoverable remotely and needs
console access, which on a two-node cluster at 03:00 is a site visit.

## fail2ban and the management VLAN

`ignoreip` includes `10.10.10.0/24`. That is a deliberate trade: an administrator typing
a wrong passphrase five times is not locked out of the platform during an incident, and
it is acceptable because that VLAN is unreachable from every other segment (rule X11).
If that rule ever changes, this line has to change with it.
