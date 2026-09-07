# Runbook: Proxmox node failure

**Audience.** On-call platform engineer, at any hour. **Read the first two sections now, not
during the incident.** The rest is reference.

| Field | Value |
| --- | --- |
| Owner | `@Via-Vitae/platform` |
| Expected RTO | 15 min to a degraded-but-serving platform; 4 h to full capacity |
| Expected RPO | ≤ 5 min for PostgreSQL (WAL-G), ≤ 15 min for other VM disks (ZFS replication interval), ≤ 24 h for anything not replicated |
| Related | [backup-restore.md](backup-restore.md), [dr-drill.md](dr-drill.md), ADR-002, `docs/network-topology.md`, `docs/capacity-plan.md` |
| Drilled | Quarterly, Q3 scenario |

> **The single most important fact.** With two nodes, a node failure is not a failover. It is
> a **capacity reduction**: the surviving node has 192 GB of guest RAM and 340.5 GB is
> committed, so roughly 40 % of the estate cannot run. ADR-002 records why, and
> `docs/capacity-plan.md` §N-1 records the priority order. Deciding that order during the
> incident, under pressure, at 03:00, is how the wrong VMs get started.

---

## Phase 0 — Triage (first 5 minutes)

Do these before anything else, in this order, and say the answers out loud or in `#incidents`.
Writing them down is what stops a 03:00 incident from becoming a 06:00 one.

```bash
# 1. Which node, and is it dead or unreachable? These have different procedures.
pvesh get /nodes --output-format json | jq -r '.[] | "\(.node) status=\(.status) uptime=\(.uptime)"'
ping -c 3 -W 2 10.10.10.2 ; ping -c 3 -W 2 10.10.10.3

# 2. Is quorum intact? Without it, HA will not act and fencing is unsafe.
pvecm status
systemctl status corosync pve-ha-lrm pve-ha-crm

# 3. What was on the failed node?
qm list --output-format json | jq -r '.[] | select(.node=="pve-01") | "\(.vmid) \(.name) \(.status)"'

# 4. Is the surviving node going to fit what matters? Free RAM is the whole question.
ssh 10.10.10.3 'free -g; zfs list -o name,used,avail,compressratio -t filesystem | head'

# 5. Is the public entry point alive? If the VIP did not move, nothing else matters.
arping -c 3 -I vmbr1 203.0.113.10 2>/dev/null || true
curl -sS -o /dev/null -w '%{http_code}\n' --resolve www.viavitae.com:443:203.0.113.10 \
  https://www.viavitae.com/
```

**Classify the failure.** The rest of this runbook branches on it, and misclassifying is the
most common error.

| Class | Evidence | Go to |
| --- | --- | --- |
| A. Node is dead — no ping, no IPMI response, no power | `pvesh` shows `unknown`, ping fails, IPMI unreachable | Phase 1A |
| B. Node is up but the cluster thinks it is down — network partition | Ping succeeds, `pvecm status` shows it unjoined, corosync errors | Phase 1B — **this is the dangerous one** |
| C. Node is up, cluster is fine, VMs are failing | `pvesh` shows `online`, individual `qm status` is `stopped` | Not a node failure. Go to Phase 3 and treat it as a guest problem |
| D. Storage failure on a live node | ZFS pool `DEGRADED` or `FAULTED`, VMs I/O-erroring | Phase 1D |

Announce in `#incidents`: class, node, time, and who is driving. Then page the second on-call —
this runbook assumes two people, because Phase 2 involves a decision about fencing and one
person should not make it alone.

## Phase 1A — Node is dead

1. **Confirm the qdevice is alive.** `pvecm status` should show 3 votes (2 nodes + qdevice)
   with quorum on the survivor. If the qdevice is also down, the cluster has **no quorum** and
   HA cannot act:
   ```bash
   # Expected:Votes 3, Expected votes 3, Quorum 2 (or 1 if one node is gone)
   pvecm status
   # If quorum is lost, and ONLY after confirming the failed node is physically dead
   # (IPMI power state, or someone in front of it), set the expected-votes override:
   pvecm expected 2
   ```
   `pvecm expected` is the command that causes data loss when used wrongly: it tells corosync
   to accept a smaller membership, so if the "dead" node is actually alive and writing to a
   replicated zvol, both sides now accept writes. **It requires two people and physical
   confirmation of power state.** Record who confirmed it.

2. **Check what HA did.** With quorum intact, `pve-ha-crm` should have started the HA-managed
   guests on the survivor, in priority order.
   ```bash
   ha-manager status
   journalctl -u pve-ha-crm -u pve-ha-lrm --since "-30 min" | tail -60
   ```
   If HA-managed guests are in `fenced` or `error` state, they did not move. Fencing on a
   two-node cluster without a working qdevice is where this goes wrong; see step 1.

3. **Apply the N-1 priority order manually for anything HA did not start**, from
   `docs/capacity-plan.md`: qdevice → LB → `db-01` → `sso-01` → `prod-cp-0` →
   `prod-worker-0..1` → `mon-01` → `runner-01` → `backup-01`. Start in that order and check
   free RAM after each:
   ```bash
   qm start 930 && ssh 10.10.10.3 'free -g | head -2'
   ```
   **Stop starting VMs when available RAM drops below 40 GB.** The ZFS ARC needs it, and an
   OOM kill during recovery chooses its own victim.

4. **Confirm the public path.** The VIP should have moved with keepalived. If it did not:
   ```bash
   ssh 10.10.10.11 'ip addr show vmbr1 | grep 203.0.113.10'   # lb-02
   # If absent on both, force it on the survivor:
   ssh 10.10.10.11 'systemctl restart keepalived && sleep 5 && ip addr show vmbr1 | grep 203'
   arping -c 3 -U -I vmbr1 203.0.113.10    # gratuitous ARP so the switch learns the new port
   ```
   Then verify from **outside** the platform, not from a VM inside it:
   `curl -sS -o /dev/null -w '%{http_code}' https://www.viavitae.com/`.

5. **Set `status.viavitae.com` to a partial outage** and write what is degraded. Tenants
   discover a slow platform faster than they read a status page, but a status page that says
   nothing while the platform is degraded costs more trust than the degradation.

## Phase 1B — Network partition (the dangerous one)

The node is alive and may be **running VMs and writing to replicated storage** while the
cluster believes it is gone. Starting those VMs elsewhere creates two writers.

1. **Do not fence. Do not start anything that was on the partitioned node.**
2. Establish ground truth by a second path: IPMI/iDRAC/iLO console, a switch port status
   check, or a person physically at the machine.
   ```bash
   # IPMI, from the mgmt VLAN only
   ipmitool -I lanplus -H 10.10.10.102 -U <user> -P <pass> chassis power status
   ipmitool -I lanplus -H 10.10.10.102 -U <user> -P <pass> sol activate
   ```
3. If the node is running guests: fix the network, do not the cluster. Restart the interface
   or the switch port. Bringing the partition back is always safer than resolving it by force.
4. If the node is running but its guests are stopped, and the partition cannot be repaired
   quickly: power the node **off** at IPMI, wait 60 seconds, confirm via `pvecm status` that
   the cluster sees one node with quorum, then proceed to Phase 1A step 3.
5. After the partition heals, **do not simply restart the node's guests**. ZFS replication may
   have diverged. Check before starting:
   ```bash
   pvesr status
   # Any guest showing 'failed' or with a stale last-sync must be reconciled manually:
   # the replica that was written to while partitioned is authoritative only if its VM was
   # serving traffic. If neither served traffic, prefer the primary.
   ```
6. Record the partition in the incident notes and open a `dr-finding` issue: a partition is a
   network defect, and the fix belongs in `docs/network-topology.md` (switch, cable, LACP
   configuration, or corosync on a separate VLAN).

## Phase 1D — Storage failure on a live node

```bash
zpool status -x
zpool status local-zfs -v
# Degraded (one disk failed, resilvering) is an urgent ticket, not an incident.
# FAULTED or UNAVAIL is an incident: guests on that pool are down and cannot be started.
```

- **DEGRADED**: replace the disk, let it resilver, and **do not touch the second disk**.
  Resilvering stresses the surviving disks; a second failure during resilver is a pool loss.
  `zpool status` progress and `zpool iostat -v 5` tell you how long. Book the maintenance
  window for after the resilver completes, not before.
- **FAULTED / UNAVAIL**: guests on that pool are unavailable. Start their replicas on the
  other node from Phase 1A step 3. Do not attempt `zpool clear` more than once; repeated
  clear attempts on a genuinely failed pool waste the time the RTO is measured in.
- Check the scrub history before assuming the pool was healthy:
  `zpool status -v | grep -A2 scan`. A pool that has not scrubbed in over a month may have
  silent corruption that a disk failure exposed. Scrub scheduling is in
  `ansible/roles/common`.

## Phase 2 — The fencing decision

Fencing means forcing the failed node's guests to be started elsewhere, accepting that if the
node is actually alive, two copies are running.

**Fence only when all four are true**, and record that all four were checked:

1. The node is confirmed unreachable by a second path (IPMI, physical, switch), not only by
   corosync.
2. Quorum is intact, or `pvecm expected` has been set with two people present and physical
   confirmation of power state.
3. The guests in question are not writable by anyone else — specifically, `db-01` must not be
   running anywhere. Check with `psql -h <every candidate address> -c 'select pg_is_in_recovery()'`
   rather than assuming.
4. The business impact of *not* fencing exceeds the risk of split-brain. For `db-01` at 03:00
   with no traffic, waiting until 07:00 for a second engineer is often the correct call. Say
   so and record it.

If any of the four is not established: **do not fence.** Serve degraded, or serve nothing, and
wait. Data loss from a double-started PostgreSQL is a breach; an outage is not.

## Phase 3 — Restore service, degraded

| Component | Degraded state | What tenants experience | Action |
| --- | --- | --- | --- |
| k3s | One control plane, two of four workers | Slower, occasional pod evictions under load | Raise the `tenant-quota` alert threshold temporarily so the alert does not fire continuously; **remove the override when the node returns**, and record that you added it |
| PostgreSQL | `db-01` only, no standby | Normal, with no database-level redundancy | This is the highest-risk state in the incident: a second failure now means restore-from-backup. Prioritise the node's return over everything else |
| Keycloak | Single instance | Sessions survive; new logins may be slow | None, unless `sso-01` failed to start — then start it before the workers |
| Monitoring | `mon-01` may be last in the start order | Dashboards have a gap for the incident | Export the gap afterwards; the incident timeline will need it |
| Bitrix24 | **Not started.** Priority 10 | CRM unavailable | Tell the business explicitly. Do not let this be discovered by someone who needed it |
| Staging, dev | Not started | Nothing | Leave them down until production is stable. Starting them competes for the RAM production needs |
| CI | One runner | Slower pipelines, and any fix you need to ship queues behind them | If a fix is needed urgently, run it locally and paste the output into the incident channel; do not add a third runner mid-incident |

## Phase 4 — Node returns

Bringing the node back is not the end, and doing it wrong re-breaks the platform.

1. **Do not let it start its old guests automatically.** Disable HA-managed start for them
   first, or the node will boot into a state that assumes it still owns `db-01`.
   ```bash
   ha-manager disable <vmid>   # for each guest that was on the failed node
   ```
2. Repair the hardware, then check the pool **before** the cluster:
   ```bash
   zpool import -a ; zpool status -x
   zpool scrub local-zfs        # and wait. Booting guests onto an unscrubbed pool after an
                                # unclean shutdown is how corruption is discovered twice.
   ```
3. Rejoin the cluster and confirm votes: `pvecm status` must show 3 votes and quorum 2.
4. **Re-sync ZFS replication before migrating anything back.** A replica that is 6 hours
   behind will be re-seeded in full, which saturates the replication link for hours and can
   starve the production network. Check the size first:
   ```bash
   pvesr status
   # For a full reseed, schedule it in the maintenance window, not now.
   ```
5. Migrate guests back in reverse priority order — `dev` first, `db-01` last — and only after
   each has been running cleanly on the survivor for at least 30 minutes.
   ```bash
   qm migrate 1000 pve-01 --online    # dev first: the cheapest thing to break
   ```
   Online migration needs shared storage or a replication that is caught up. With ZFS
   replication (ADR-002) there is no shared storage, so migration is **offline** for most
   guests: stop, migrate, start. Plan for the outage rather than discovering it.
6. Re-enable HA: `ha-manager enable <vmid>`.
7. Remove the Alertmanager silence from the drill/incident, remove any temporary alert
   threshold override from Phase 3, and confirm `status.viavitae.com` is green.
8. Run the nightly drift check by hand — `deploy.yml` on `workflow_dispatch` is not the way;
   instead:
   ```bash
   terraform -chdir=terraform/envs/prod plan -lock=false -detailed-exitcode -no-color
   # Exit 2 means the running infrastructure diverged during the incident. Reconcile it by
   # pull request, and record the divergence in the incident notes.
   ```

## Phase 5 — After

Within 48 hours, or the incident becomes folklore:

1. Incident record: timeline with timestamps, decisions taken, and **who confirmed what** —
   especially any `pvecm expected`, any fencing decision and any manual firewall change.
2. `dr-finding` issues for every defect found, with severity per
   [dr-drill.md](dr-drill.md) §Findings.
3. Art. 33 assessment: was personal data unavailable, altered, destroyed or disclosed? An
   availability loss **is** a personal-data breach under Art. 4(12) if it is significant.
   `dpo@viavitae.com` decides, not the platform team, and the clock started when Phase 0 was
   completed — not when this section is written.
4. Update this runbook with whatever was wrong in it. A runbook that is not edited after an
   incident is a runbook that will fail the same way next quarter.
5. Update `docs/capacity-plan.md` if the incident revealed a different N-1 picture than the
   one on paper. It usually does.

## Known traps

Each of these has happened here or in an equivalent estate, and each one looks like the right
thing to do at the time.

| Trap | Why it looks right | Why it is wrong |
| --- | --- | --- |
| Starting every failed VM on the survivor | "Get everything back up" | RAM exhaustion. The OOM killer picks the victim, and it picks PostgreSQL because it is the largest process. You convert a capacity problem into data loss |
| `pvecm expected 1` to restore quorum quickly | The cluster is stuck and this unblocks it | If the other node is alive, both sides now accept writes to replicated zvols. Unrecoverable divergence |
| Removing the failed node from the cluster (`pvecm delnode`) to clean up `pvesh` output | The node shows as `unknown` and clutters everything | `pvecm delnode` on a node that might return forces a full cluster rejoin and can invalidate the corosync config on the survivor. Do it only when the node is being decommissioned, never during an incident |
| Restoring `db-01` from backup because the replica is "probably stale" | A restore is a known-good state | The replica on the survivor is at most 15 minutes behind; the newest `vzdump` is up to 24 hours behind. Restoring throws away a day of tenant data to save ten minutes |
| Rebooting the survivor "to clear it up" | It is behaving strangely | It is the only node left. Rebooting it is a full outage plus a cold-start of everything, with no fallback |
| Fixing the network by moving the VIP to a third machine | Traffic must flow | The VIP is bound to the HAProxy pair by keepalived and to the `dmz` VLAN by the switch configuration in `docs/network-topology.md`. Moving it creates a path that no firewall rule describes |
| Skipping the status page because "it will be back soon" | Avoid alarming tenants | Tenants see the degradation before they see the page. A page that says nothing is read as either indifference or ignorance |
