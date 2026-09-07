# modules/bitrix24-vm

Bitrix24 on-premises, isolated by construction. Wraps
[`../proxmox-vm`](../proxmox-vm/README.md) and installs nothing;
`ansible/playbooks/bitrix24.yml` does.

ADR-007 accepts this component **with eight conditions**, because it is
closed-source software with an outbound flow that cannot be inspected, processing
employee and client personal data. Four of those conditions are properties of a VM
and are enforced here as plan failures rather than left to review:

| ADR-007 condition | Enforced by |
| --- | --- |
| 1 — dmz VLAN only | `vlan_id = 40` hard-coded, plus a precondition that the address is inside `10.10.40.0/24` |
| 2 — egress allow-listed | `egress_allow_list` with no wildcards permitted, written to `/etc/viavitae/bitrix-egress-hosts`, implemented as rule E6 |
| 4 — separate database | `database_host` must be a dmz address; `postgres-vm` refuses a `bitrix24` purpose outside VLAN 40 |
| 5 — Keycloak SSO | `/etc/viavitae/bitrix-sso-required = true`, consumed by `ansible/roles/bitrix24`, which disables the vendor's local password store |
| 7 — Legal review | `legal_review_approved` **and** `legal_review_reference`, both required in `prod` |
| 8 — DPIA INFRA-002 | `dpia_infra_002_approved` **and** `dpia_reference`, both required in `prod` |

Conditions 3 (no route to `prod` except through the HAProxy internal listener) and
6 (separate encrypted backups) are firewall and backup-schedule properties, owned by
`docs/network-topology.md` rule X14 and by `backup/` respectively.

## Two gates for one decision

`ansible/playbooks/bitrix24.yml` refuses to run against a `prod` inventory unless
the same two approvals are present there. Terraform can be bypassed by creating a
VM by hand; Ansible can be bypassed by installing the vendor package by hand; both
at once is not a mistake, it is a decision, and it will be visible in two places.

## Approvals are recorded, not just checked

An approval with no reference is an assertion. Both flags therefore require a
companion reference string, and the `approvals` output puts the whole tuple into
state and into the plan output — which is where an auditor will look, and which is
attached to the pull request that enabled it.

## Priority in a node failure

This VM is priority 10 in the N-1 start order (`docs/capacity-plan.md`) and will
**not** fit on the surviving node in the two-node pilot. It is still HA-managed:
Proxmox will attempt to start it, fail for want of memory, and record the attempt.
That is preferable to the alternative, which is a CRM that silently never returns
and a business that discovers it during the incident rather than before.

If Bitrix24 becomes business-critical it needs dedicated capacity — a third node or
a smaller worker pool. That is a commercial decision recorded in
`docs/capacity-plan.md` §Growth items, not something to discover at 03:00.
