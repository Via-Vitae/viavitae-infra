# Runbook: quarterly disaster-recovery drill

**Purpose.** Prove that recovery works, and produce evidence that it does. The drill is not a
test of the backups; it is a test of *this document*, of the people following it, and of the
assumptions in `docs/capacity-plan.md`. A drill that only runs scripts proves the scripts run.

| Field | Value |
| --- | --- |
| Owner | `@Via-Vitae/platform`, observed by `@Via-Vitae/security` and `@Via-Vitae/compliance` |
| Frequency | Quarterly: first Tuesday of January, April, July, October, 09:00–15:00 Europe/Vilnius |
| Duration | 6 hours booked, 4 hours expected. If it takes longer, that is a finding. |
| Evidence produced | `backup/drills/reports/<date>-<scope>.md` plus an updated `backup/drills/last-drill-report.md` |
| Audit purpose | ISO 27001 A.5.29/A.5.30 (ICT readiness for business continuity, testing), A.8.13 (backup), SOC 2 CC9.1 and A1.2 |
| Related | [backup-restore.md](backup-restore.md), [proxmox-node-failure.md](proxmox-node-failure.md), ADR-002 |

---

## Rules of the drill

1. **It is a drill, not a change window.** Production is not touched. Every restore targets a
   scratch VM in the VMID 950–959 range on the `prod` VLAN, and every destructive command in
   this document has already been checked against that constraint.
2. **The person running it must not be the person who wrote the automation.** A drill run by
   the author tests the author's memory. Rotate: platform engineers take turns, and the
   security observer is present every time.
3. **The runbook is followed literally.** Where it is wrong, ambiguous or missing a step, that
   is recorded as a finding and the drill continues with the workaround noted. Fixing the
   runbook mid-drill invalidates the evidence that it needed fixing.
4. **Failures are the output.** A drill in which everything worked and no finding was raised
   is a drill that was not run honestly, or was scoped too narrowly. Two findings minimum is
   the expectation; zero is investigated.
5. **Timings are measured, not estimated.** Every step has a start and end timestamp in the
   report. The RTO figures in `README.md` come from these measurements.

## Prerequisites, checked the day before

```bash
# Runner and tooling
command -v terraform tflint ansible ansible-playbook wal-g qm pvesh sops age jq sha256sum
terraform version && ansible --version | head -1

# Capacity: a drill needs one spare 8 vCPU / 32 GB slot on the node NOT hosting db-01.
pvesh get /nodes --output-format json | jq -r '.[] | "\(.node) cpu=\(.cpu) mem=\(.mem)"'

# Backups are current. Drilling against a 9-day-old archive measures the wrong thing.
ls -lt /mnt/pve-backup/dump/ | head -20
wal-g backup-list | tail -5

# The scratch VMID range is free.
for id in $(seq 950 959); do qm status $id 2>/dev/null | grep -q . && echo "$id IN USE"; done

# Nobody is mid-change.
git -C ~/viavitae-infra fetch && git -C ~/viavitae-infra status
```

If capacity is not available, **shut down `dev` and `staging` first**, per the N-1 priority
order in `docs/capacity-plan.md`. This is deliberate: the drill rehearses the degraded state,
so the degraded state is what it runs in. A drill performed with both nodes empty proves
nothing about a real failure, which happens when the estate is full.

## Scenario rotation

One scenario per quarter, in order. All four are run within a year, and the rotation is fixed
so that a scenario is not quietly dropped because it is the hard one.

| Quarter | Scenario | Primary objective |
| --- | --- | --- |
| Q1 | Single tenant data loss (R1) | Point-in-time recovery of one schema, with the other 24 untouched |
| Q2 | Full database instance loss (R2) | Rebuild the instance, measure RPO and RTO honestly |
| Q3 | Proxmox node failure ([proxmox-node-failure.md](proxmox-node-failure.md)) | N-1 degraded operation, fencing, ZFS replication failover |
| Q4 | Cluster rebuild from Git (R4) plus state rollback (R5) | Bare metal to serving traffic |

## Procedure

### Phase 1 — Scope and announce (09:00–09:30)

1. Post in `#incidents`: "DR drill in progress, <scenario>, 09:00–15:00, lead <name>". A drill
   that is not announced gets investigated as an outage by someone else, and that person's
   time is the cost of skipping this step.
2. Set the drill flag so alerting does not page: add `drill: "true"` to the Alertmanager
   silence for the affected VMs — `amtool silence add --comment "DR drill" node="db-restore-*"
   --duration 6h`. Record the silence ID; forgetting to remove it is a finding that has
   happened.
3. Note the start timestamp.

### Phase 2 — Execute (09:30–13:00)

Run the scenario's procedure from [backup-restore.md](backup-restore.md) or
[proxmox-node-failure.md](proxmox-node-failure.md), literally, timing each step.

`backup/drills/dr-drill-quarterly.sh` automates the Q1 and Q2 verification path. It requires
`--confirm` and refuses to run against a production target; read its `--help` before the
drill, not during it.

```bash
./backup/drills/dr-drill-quarterly.sh \
  --scenario q1-single-tenant \
  --tenant acme \
  --target-time "$(date -d '2 hours ago' '+%Y-%m-%d %H:%M:%S%z')" \
  --scratch-vmid 950 \
  --confirm
```

What the script does, and what it deliberately does not:

- Creates the scratch VM from the newest `vzdump` archive, recovers to `--target-time` with
  WAL-G, and compares row counts and per-table MD5 aggregates between the scratch and a
  read-only snapshot of the source.
- Writes the report to `backup/drills/reports/<date>-<scenario>.md` and refreshes
  `backup/drills/last-drill-report.md`.
- **Does not** touch `db-01`, `db-02`, any tenant namespace or any production VM. It exits
  non-zero rather than proceeding if the target resolves to a production address.
- **Does not** clean up automatically. The scratch VM stays up until Phase 4 so the observer
  can inspect it. Cleanup is a human step, because a script that destroys VMs on exit is a
  script that will one day destroy the wrong one.

### Phase 3 — Verify beyond the script (13:00–14:00)

The script verifies rows. Verification that stops there has missed every interesting failure
so far.

| Check | Command | Passes when |
| --- | --- | --- |
| Application can read the restored schema | Point a `staging` API pod at the scratch DB with a read-only DSN and run the smoke suite | All smoke tests pass, no migration error |
| Permissions survived | `psql -c "\dn+ t_acme"` on the scratch | `app_acme` has USAGE and the table grants match the live schema |
| No cross-tenant leakage | `psql -U app_acme -c "select count(*) from t_other.some_table"` | Fails with permission denied. If it succeeds, stop the drill and treat it as a security incident |
| Erasure block list honoured | `grep acme backup/wal-g/schedules/erasure-blocklist.txt` | Absent, unless the tenant was erased — in which case the restore must have been refused |
| Encryption actually applied | `wal-g backup-list --detail` and `age --decrypt` on a fetched WAL segment with the current key | Decrypts with the current recipient |
| Offsite copy exists and is current | Compare `wal-g backup-list` against the offsite bucket listing | Newest offsite object is less than 24 h old |
| Timing is inside the RTO | Sum of the phase-2 timestamps | ≤ 1 h for R1, ≤ 4 h for R2/R3 |

### Phase 4 — Clean up (14:00–14:30)

```bash
qm stop 950 && qm destroy 950 --purge
amtool silence expire <silence-id>
# The scratch VM held a full copy of every tenant's data. Confirm it is gone.
qm list | grep -c 950   # must print 0
find /tmp -name '*restore*' -newermt '-8 hours' -print -delete
```

Then confirm the estate is back to its pre-drill state: `terraform plan` for `prod` shows no
changes, Argo CD shows all applications `Synced` and `Healthy`, and no alert is firing.

### Phase 5 — Report (14:30–15:00)

Write `backup/drills/reports/<date>-<scope>.md` and update `backup/drills/last-drill-report.md`
to point at it. Both are committed in the same pull request, which is what makes the evidence
tamper-evident: the report is a commit with an author and a timestamp, and amending it later
is visible in history.

The report has exactly these sections, and a section with nothing to say says "none":

1. Scope, scenario, participants and their roles.
2. Timeline with a timestamp per step, and measured durations.
3. **Measured RPO and RTO** against the targets in `README.md`, with the variance explained.
4. Verification results from Phase 3, one row per check, pass or fail.
5. Findings, each with a severity, an owner and a due date. Findings are the deliverable.
6. Deviations from the runbook, and what the runbook should have said.
7. Attestation: the lead and the observer both sign, with the date. An unsigned report is not
   evidence.

Commit message: `docs(dr): drill report <date> — <scenario>, RTO <measured>`.

## Findings and their lifecycle

A finding without an owner and a due date is an observation. Findings are filed as issues with
the `dr-finding` label the same day, and:

| Severity | Meaning | Due |
| --- | --- | --- |
| Critical | Recovery would have failed in a real incident | Fix before the next drill; the drill is re-run for that scenario |
| High | Recovery succeeded but outside the RTO, or a control was absent | 30 days |
| Medium | Runbook defect, ambiguity or missing step | 90 days, i.e. before the next drill |
| Low | Tooling friction, cosmetic | Backlog |

Open critical or high findings from the previous drill are restated at the top of the next
report. A finding that has been open for three quarters is itself a critical finding, because
it means the drill process is not connected to the work process.

## What this drill does not cover

Stated so nobody assumes it does.

- **Simultaneous loss of both nodes.** That is a site disaster, not a node failure, and it
  requires the offsite replica and a hardware procurement lead time measured in weeks. It is
  covered by the annual continuity exercise, not by this quarterly drill.
- **Ransomware that also encrypts the backups.** Mitigated by the offsite copy being
  write-once for the retention window; verifying immutability requires the storage provider's
  object-lock API, which is tested annually, not quarterly.
- **Loss of both age key custodians.** Practically unrecoverable for encrypted archives, which
  is why ADR-005 requires a sealed offline copy and why the sealed copy's existence is checked
  in the Q4 drill.
- **A GitHub outage.** Would stop deployment but not operation; Argo CD keeps reconciling from
  its cache. Tested by simply observing behaviour during a real GitHub incident rather than by
  simulation.
- **Application-level recovery.** Migrations, data corruption introduced by application code
  and business-logic errors are `viavitae-api`'s concern. The drill provides the platform
  capability; the application team's own rehearsal consumes it.
