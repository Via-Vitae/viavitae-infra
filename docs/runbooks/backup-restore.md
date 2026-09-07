# Runbook: backup and restore

**Audience.** On-call platform engineer. **Read this before you need it.** A restore
performed by someone reading it for the first time takes three times as long, and the
difference is the RTO.

**Authoritative here.** `viavitae-docs` links to this file; it does not copy it. Two copies of
a runbook drift, and the one that is wrong is always the one being followed.

| Field | Value |
| --- | --- |
| Owner | `@Via-Vitae/platform`, with `@Via-Vitae/security` for key rotation and erasure |
| Last verified by a real restore | See `backup/drills/last-drill-report.md` |
| Verification cadence | Quarterly, `docs/runbooks/dr-drill.md` |
| Related | [dr-drill.md](dr-drill.md), [proxmox-node-failure.md](proxmox-node-failure.md), `backup/`, ADR-002, ADR-003, ADR-005 |
| DPIA reference | INFRA-001, flows F7, F8, F9; risks R1, R7; controls M1, M2, M13, M14, M19 |

---

## What is backed up, and what is not

| Data | Mechanism | Frequency | Retention | Recovery granularity | RPO | RTO |
| --- | --- | --- | --- | --- | --- | --- |
| PostgreSQL, all environments | WAL-G continuous archiving to the EU S3 bucket | Continuous, `archive_timeout = 300` | 35 days | Point-in-time, any second in the window; or per-schema via `pg_dump --schema` | ≤ 5 min | 1 h |
| VM disks and configuration (`prod`) | Proxmox `vzdump`, ZFS snapshot mode, to `backup-01` | Daily 02:00 Europe/Vilnius | 14 daily, 8 weekly | Whole VM | ≤ 24 h | 4 h |
| VM disks and configuration (`staging`, `dev`) | `vzdump` | Weekly, Sunday 03:00 | 4 weekly | Whole VM | ≤ 7 d | 8 h |
| Kubernetes objects | **Not backed up.** Git is the backup; Argo CD rebuilds the cluster from it | Continuous | Git history | Per commit | 0 | 15 min |
| Secrets | SOPS-encrypted in Git; the age **private** key is held offline by two custodians | On change | Git history plus an offline sealed copy | Per file | 0 | 30 min |
| Terraform state | S3 bucket versioning | On every write | 90 days of versions | Per version | 0 | 15 min |
| Grafana dashboards | In Git (`monitoring/grafana/dashboards/`) | On change | Git history | Per commit | 0 | 15 min |
| Loki logs | **Not backed up.** Retention 30 days, then deleted | — | — | — | — | — |
| Prometheus metrics | **Not backed up.** A monitoring history loss is an inconvenience, not an incident | — | — | — | — | — |
| Bitrix24 and its database | `vzdump` of `crm-01` and `crm-db-01`, daily | Daily | 14 daily | Whole VM | ≤ 24 h | 4 h |
| Keycloak database | Inside the PostgreSQL backup (schema `keycloak`) | Continuous | 35 days | Point-in-time | ≤ 5 min | 1 h |

Two things on this list are deliberately not backed up, and both decisions are recorded
because "we don't back up logs" reads as an oversight unless the reason is written down:
logs are the highest-volume, lowest-value-per-byte data in the estate and contain personal
data whose retention is capped at 30 days by INFRA-001; metrics are an aggregate of the same.

**A backup of Kubernetes objects would be a second source of truth.** Restoring one over a
cluster that Argo CD is reconciling produces a fight, not a recovery. Rebuild the cluster and
let Argo CD pull.

## Verification: what "backed up" means

A backup that has not been restored is an untested hypothesis. Three levels of verification
exist here and only the third counts as evidence.

| Level | What it proves | How | Frequency |
| --- | --- | --- | --- |
| 1. Job success | The job ran and exited 0 | `backup-failed.yml` alert on any non-zero `vzdump` task or WAL-G archive failure | Continuous |
| 2. Artefact exists and is intact | The file is present, the right size and passes its checksum | `backup/proxmox/snapshot-prune.sh --verify-only` and `wal-g backup-list` | Weekly, from the `backup.yml` playbook |
| 3. **Restored data is correct** | A restore produces a database whose row counts and checksums match the source | `backup/drills/dr-drill-quarterly.sh` | Quarterly |

Level 1 is what most organisations call a backup check and it is the one that passes during a
real failure. Level 3 is the only one that has ever caught a defect here: an encryption key
that rotated without a re-encrypt, a WAL archive path that pointed at a bucket with a
lifecycle rule, and a `vzdump` snapshot of a running database with no `fsync` — all three
produced successful jobs and unrestorable data.

## Restore procedures

### R1 — Restore a single tenant schema (most common, least destructive)

Use when one tenant's data is wrong, corrupted or must be rolled back, and everyone else is
fine. **Do not restore the whole instance for one tenant.**

```bash
# 0. Establish what you are restoring to, and say it out loud. A point-in-time target
#    written down now is the only defence against restoring to the wrong second.
TARGET_TIME="2026-09-06 14:22:00+03"
TENANT=acme            # slug, from clients/<slug> in viavitae-clients
SCRATCH=db-restore-$(date +%Y%m%d-%H%M)

# 1. Create a scratch VM from the most recent vzdump of db-01. Never restore onto db-01.
#    VMID from the 900-999 shared block; 950-959 are reserved for restore scratch.
qm restore 950 /mnt/pve-backup/dump/vzdump-qemu-930-2026_09_06-02_00_15.vma.zst \
   --storage local-zfs --force
qm set 950 --name "${SCRATCH}" --net0 virtio,bridge=vmbr1,tag=20
qm start 950

# 2. Wait for PostgreSQL, then confirm it is the scratch and not the primary.
ssh debian@10.10.20.50 'pg_isready -h 127.0.0.1' 
ssh debian@10.10.20.50 "psql -Atc \"select inet_server_addr(), current_setting('port')\""
#    If the address is 10.10.20.30 you are on the primary. Stop.

# 3. Point-in-time recover to TARGET_TIME using WAL-G.
ssh debian@10.10.20.50 "sudo -u postgres wal-g backup-list | tail -5"
ssh debian@10.10.20.50 "sudo -u postgres bash -c '
  cat >> /etc/postgresql/17/main/postgresql.conf <<EOF
restore_command = \x27wal-g wal-fetch %f %p\x27
recovery_target_time = \x27${TARGET_TIME}\x27
recovery_target_action = promote
EOF
  touch /var/lib/postgresql/17/main/recovery.signal
  systemctl restart postgresql'"

# 4. Verify before touching production. Row count and a checksum, not "it looks right".
ssh debian@10.10.20.50 "psql -d viavitae -Atc \
  \"select count(*) from t_${TENANT}.assessment\""
ssh debian@10.10.20.50 "psql -d viavitae -Atc \
  \"select md5(string_agg(id::text || updated_at::text, ',' order by id)) from t_${TENANT}.assessment\""

# 5. Export the schema and load it into production inside a transaction.
ssh debian@10.10.20.50 "pg_dump -d viavitae --schema=t_${TENANT} --no-owner --no-privileges" \
  > "/tmp/${TENANT}-${SCRATCH}.sql"
#    Review the dump. Confirm it contains only t_${TENANT} and no other tenant's rows.
grep -c 'CREATE TABLE' "/tmp/${TENANT}-${SCRATCH}.sql"
grep -o 't_[a-z0-9_]*' "/tmp/${TENANT}-${SCRATCH}.sql" | sort -u   # must list one schema

# 6. Rename the live schema aside rather than dropping it. Dropping is irreversible and
#    you are not yet certain the restore is correct.
psql -h 10.10.20.30 -U postgres -d viavitae -c \
  "ALTER SCHEMA t_${TENANT} RENAME TO t_${TENANT}_pre_restore_$(date +%s)"
psql -h 10.10.20.30 -U postgres -d viavitae -f "/tmp/${TENANT}-${SCRATCH}.sql"
psql -h 10.10.20.30 -U postgres -d viavitae -c \
  "GRANT USAGE ON SCHEMA t_${TENANT} TO app_${TENANT}"

# 7. Confirm with the tenant, then delete the renamed schema after 7 days, not before.
# 8. Destroy the scratch VM. It holds a full copy of every tenant's data.
qm stop 950 && qm destroy 950 --purge
shred -u "/tmp/${TENANT}-${SCRATCH}.sql"
```

**Stop conditions.** If step 4's checksum does not match a known-good value, if step 5's
`sort -u` lists more than one schema, or if the scratch VM's address is the primary's: stop,
and escalate to `@Via-Vitae/platform` before doing anything else.

### R2 — Restore the whole PostgreSQL instance

Use when the instance is corrupt, the disk is lost, or a migration was applied to every
tenant and must be undone.

1. Announce it. This is an outage for every tenant: post in `#incidents`, page the second
   on-call, and set `status.viavitae.com` to a major outage.
2. Stop the API so nothing writes during the restore: scale `viavitae-api` to zero replicas
   via Argo CD (`spec.source.targetRevision` to a commit with `replicas: 0`), **not** via
   `kubectl scale`. Argo CD's self-heal will undo a `kubectl scale` within three minutes,
   mid-restore.
3. Restore `db-01` from `vzdump` per R1 step 1, or rebuild the VM from Terraform and restore
   the data with WAL-G if the VM itself is intact.
4. Recover to the last known-good time with WAL-G, then verify with a full checksum run:
   `backup/drills/dr-drill-quarterly.sh --source restored --verify-only`.
5. Promote, re-point `db-02`, and confirm replication lag is zero before re-enabling traffic.
6. Scale the API back up through Argo CD. Watch the error budget burn rate; a restore that
   succeeded at the database layer can still fail at the application layer if a migration was
   half-applied.
7. Write the incident record. If personal data was exposed or lost, this is an Art. 33
   candidate: notify `security@viavitae.com` and `dpo@viavitae.com` **immediately**, not at
   the end of the restore. The 72-hour clock runs from awareness, which was step 1.

### R3 — Restore a VM from `vzdump`

```bash
# List what exists. Do not guess the filename from the date.
ls -la /mnt/pve-backup/dump/ | grep "qemu-${VMID}"

# Confirm the archive is intact before you need it, not after the restore fails.
vzdump --recover --dry-run 2>/dev/null || true
sha256sum "/mnt/pve-backup/dump/vzdump-qemu-${VMID}-<timestamp>.vma.zst"
grep "<filename>" /mnt/pve-backup/dump/vzdump-qemu-${VMID}-<timestamp>.log

# Restore to a NEW VMID, never over the original, until the original is confirmed dead.
qm restore <NEW_VMID> /mnt/pve-backup/dump/vzdump-qemu-${VMID}-<timestamp>.vma.zst \
  --storage local-zfs
qm start <NEW_VMID>
```

Restoring over the original VMID is what you do *after* the new VM is verified and the
original is confirmed unrecoverable. Doing it first turns a recovery into a data-loss event
when the archive is bad.

**Terraform will fight you.** A VM restored outside Terraform has attributes that do not
match state, and the next `terraform plan` will propose to correct them — potentially by
replacing the VM. After any manual restore, run `terraform plan` for the environment and
either accept the drift deliberately or run `terraform apply -refresh-only` to adopt the
restored state. Record which, in the incident notes. Leaving it unadopted means the nightly
drift job goes red and nobody can tell whether that red is the restore or a new problem.

### R4 — Restore the cluster from Git

There is no cluster backup. The procedure is:

1. Provision VMs: `terraform -chdir=terraform/envs/<env> apply`.
2. Bootstrap the OS and k3s: `ansible-playbook -i ansible/inventories/<env>/hosts.yml
   ansible/playbooks/{proxmox-base,hardening,k3s-bootstrap,k3s-nodes}.yml`.
3. Install Argo CD: `helm upgrade --install argocd argo/argo-cd -n argocd
   -f k8s/argocd/install/values.yaml`.
4. Apply the root app: `kubectl apply -f k8s/argocd/root-app.yaml`.
5. Wait. Argo CD pulls everything else — namespaces, policies, ingress, monitoring,
   applications, tenants. Do not `kubectl apply` anything from `k8s/`; that creates objects
   Argo CD does not know it owns, and the next prune removes them.
6. Restore the databases per R2, in parallel with steps 3–5. The cluster without data is a
   shell; the data without the cluster is a file.

Expected time from bare metal to serving traffic: **3 h 40 min**, measured at the last drill.
The RTO of 4 h in `README.md` is that measurement plus 20 minutes, not a target chosen
because it looked reasonable.

### R5 — Restore Terraform state

```bash
aws s3api list-object-versions --bucket viavitae-infra-tfstate \
  --prefix envs/prod/terraform.tfstate --query 'Versions[0:5].[VersionId,LastModified]'
aws s3api get-object --bucket viavitae-infra-tfstate \
  --key envs/prod/terraform.tfstate --version-id <VersionId> /tmp/restored.tfstate

# Diff against the live state BEFORE overwriting anything.
terraform show -json /tmp/restored.tfstate | jq -r '.values.root_module' > /tmp/restored.json
terraform -chdir=terraform/envs/prod show -json | jq -r '.values.root_module' > /tmp/current.json
diff <(jq -S . /tmp/current.json) <(jq -S . /tmp/restored.json)
```

Then push with `terraform state push /tmp/restored.tfstate -force` **only** after the diff is
understood. `-force` is required because the serial is lower, and the serial check exists
precisely to stop you doing this by accident. A state rollback that does not match reality
makes every subsequent plan a work of fiction; if the infrastructure has moved on, adopt it
with `terraform import` resource by resource instead.

## Key rotation

age keys encrypt WAL-G archives, the offsite replica and every SOPS file. Rotation is a
180-day schedule (ADR-005) and an immediate action on any suspicion of exposure.

```bash
# 1. Generate the new keypair OFFLINE. Never on a runner, never on a hypervisor.
age-keygen -o /media/offline/age-key-2.txt
age -R /media/offline/age-key-2.txt   # prints the public key

# 2. Add the new recipient to k8s/secrets/sops/.sops.yaml WITHOUT removing the old one.
#    Both recipients must be present during the transition, or a file encrypted to the old
#    key becomes undecryptable the moment you remove it.

# 3. Re-encrypt every SOPS file to both recipients.
sops updatekeys --yes k8s/secrets/sops/*.sops.yaml
find ansible/inventories -name '*.sops.yml' -exec sops updatekeys --yes {} \;

# 4. WAL-G: update the archive encryption recipient, then note the cutover timestamp.
#    Archives written before it can only be decrypted with the OLD key. This is why the
#    old key is retired after the retention window, not immediately.

# 5. Verify decryption with the NEW key on a copy, in a scratch directory.
sops --decrypt k8s/secrets/sops/<file>.sops.yaml > /dev/null && echo "new key OK"

# 6. Commit .sops.yaml and the re-encrypted files. They are ciphertext; committing them is
#    correct and is why .gitignore re-includes k8s/secrets/.

# 7. After the retention window (35 days for WAL-G, 90 days for state), remove the old
#    recipient, run `sops updatekeys` again, and shred the old private key material:
#    two custodians, witnessed, recorded in the incident log with the key fingerprint.
```

**Do not skip step 2.** Removing the old recipient before re-encrypting is unrecoverable:
SOPS has no recovery path, and the only remaining copy of the plaintext is in a backup you
cannot decrypt.

## Erasure (Art. 17)

A tenant's erasure request or an individual's erasure request against infrastructure-held
data. The honest answer has two parts, and giving only the first one is a compliance defect.

1. **Live erasure.** `DROP SCHEMA t_<slug> CASCADE; DROP ROLE app_<slug>;` — ADR-003
   decision 6. Record the timestamp and the executing role.
2. **Residual copies.** The data remains in: WAL archives and base backups for up to 35 days,
   `vzdump` archives for up to 56 days (14 daily plus 8 weekly), the offsite replica for the
   same period, and Terraform state until the next apply. State which of these still hold the
   data and the date each expires.
3. **The response says so.** Art. 17 does not require retroactive destruction of backups; it
   requires that the data not be *processed*. The correct response states that the live copy
   is erased, that backups are encrypted and access-controlled, that they expire on the dates
   given, and that the data will not be restored. A response claiming complete erasure is
   false and is worse than the residual exposure it hides.
4. **Block restoration.** Add the tenant slug to the restore-block list in
   `backup/wal-g/schedules/erasure-blocklist.txt` so a routine restore does not resurrect
   erased data. Check that list at R1 step 5 and at R2 step 4 — both procedures say "verify",
   and this is part of verifying.
5. Notify `dpo@viavitae.com` with the record. It is the DPO's response to the data subject,
   not the platform team's.

## Failure modes seen here

Recorded because each one produced a green backup job.

| Failure | Symptom | Detection that caught it | Fix |
| --- | --- | --- | --- |
| WAL archive path pointed at a bucket with a 7-day lifecycle rule | Archives vanished; `wal-g backup-list` still showed the base backups | Drill: point-in-time recovery to T−10 days failed | Lifecycle rule removed; the drill now tests T−30 days, not T−7 |
| age key rotated without re-encrypting | New archives fine, old archives undecryptable | Drill | Procedure step 2 above, and `sops updatekeys` added to the rotation checklist |
| `vzdump` of a running PostgreSQL with no freeze | Archive restored, database refused to start, crash recovery found torn pages | Drill | Snapshot mode plus `archive_mode` reliance: the `vzdump` copy is a fallback, WAL-G is the recovery path |
| Backup appliance full, jobs silently writing to a secondary mount that was not replicated | Offsite copy stopped 11 days earlier | `backup-failed.yml` staleness series, not the job alert | Alert on *age of the newest offsite copy*, not on job success |
| Restored VM kept its old MAC address, and the DHCP reservation gave the primary's IP to the scratch | Split-brain DNS for 20 minutes | Manual | R1 step 1 now sets a new NIC without a MAC; scratch VMs use `.50` addresses |
