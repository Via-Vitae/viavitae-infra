# backup/offsite — Offsite backup replication

INFRA-001 F8: the offsite replica is a copy of the encrypted backup set, stored
at a second EEA location, physically separate from the primary.

## Architecture

The primary backup storage is the Proxmox backup storage on `backup-01` (vzdump
archives) and the EU S3-compatible object store (WAL-G archives). The offsite
replica is a second S3-compatible bucket at a different provider, in a different
data centre, in the EEA.

Replication is unidirectional: primary → offsite. The offsite bucket is
write-once from the replication host; it cannot be modified or deleted by the
replication process. This is a deliberate asymmetry: if the primary is
compromised, the attacker cannot reach the offsite copy through the replication
channel.

## Encryption

All data in the offsite bucket is encrypted with age. The encryption keys are
held separately from the data: the private keys are on offline media, in the
possession of two custodians. The replication host has only the public key.

This means a compromise of the replication host exposes ciphertext, not
plaintext. A compromise of both the replication host and one custodian's key
material exposes ciphertext that can be decrypted only with the second
custodian's key.

## Disposal

INFRA-001 M2: backup media disposal. When a backup expires (35 days for WAL-G,
56 days for vzdump), the offsite copy expires with it. The offsite bucket has
a lifecycle rule that deletes objects after the retention period. No manual
disposal is required.

If a backup medium (a disk, a tape, a USB stick) is decommissioned, it is
disposed of according to the witnessed disposal procedure. The disposal record
includes the medium's serial number, the date, the witnesses, and the method
(degauss, shred, cryptographic erasure).

## Testing

The offsite replica is tested as part of the quarterly DR drill
(backup/drills/dr-drill-quarterly.sh). Phase 3 of the drill restores from the
offsite bucket, not from the primary, to prove the replica is usable.
