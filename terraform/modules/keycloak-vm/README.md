# modules/keycloak-vm

The identity provider as a Proxmox guest. Wraps
[`../proxmox-vm`](../proxmox-vm/README.md) and installs nothing;
`ansible/playbooks/keycloak.yml` does.

Keycloak is priority 4 in the N-1 start order (`docs/capacity-plan.md`), above the
workloads it authenticates, because without it no administrator can log in to fix
anything — including an outage of Keycloak.

## Invariants

| Invariant | Reason |
| --- | --- |
| `vlan_id` is 20 or 30, never 40 | Public SSO traffic arrives through HAProxy (rule X2). The administrative console stays reachable only from `mgmt` (rule X1). On VLAN 40 the console would be one firewall mistake from the internet, and it is a credential-stuffing target with a predictable URL. |
| `public_hostname` must not be an internal name | Keycloak derives its issuer URL, redirect allow-list and cookie domain from it. An internal issuer breaks every external client, and the failure looks like a client misconfiguration. |
| `protect_deletion = true` | INFRA-001 F4: the identity store is personal data, and losing it loses every group membership that authorisation depends on. |
| `ha_group` required | Authentication is a dependency of recovery itself. |
| `memory_ballooning = false` | A JVM whose heap is reclaimed under it does not degrade gracefully; it stalls, then dies. |
| Separate database instance | A Keycloak database reachable from a tenant query is a privilege boundary that does not exist. Enforced by `instance_purpose` in [`../postgres-vm`](../postgres-vm/README.md). |

## Files written at first boot

| Path | Content |
| --- | --- |
| `/etc/viavitae/keycloak-public-hostname` | External name |
| `/etc/viavitae/keycloak-db-host` | keycloak-purpose database address |
| `/etc/viavitae/keycloak-heap-mb` | 60 % of committed memory; the rest is for metaspace, thread stacks, the OS page cache and the margin that prevents an OOM kill |
| `/etc/viavitae/keycloak-admin-console-restricted` | `true`, so the restriction is auditable on the machine and not only in a runbook |
| `/etc/viavitae/environment` | Environment label |

## Not managed here

Realms, clients, groups, MFA policy, brute-force detection and the LDAP-free
user directory are configured by `ansible/roles/keycloak` from the SOPS-encrypted
inventory. The bootstrap administrator password is generated there and never
passes through Terraform, which is why this module has no credential input at all.
