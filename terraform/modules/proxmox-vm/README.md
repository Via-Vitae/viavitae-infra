# modules/proxmox-vm

One Proxmox guest, created by cloning a cloud-init template. Every VM in every
environment goes through this module; nothing creates a `proxmox_virtual_environment_vm`
directly.

**Why a single path.** The invariants that matter are enforced here once instead
of being remembered per call site: VMID inside its allocated block, no password
anywhere, no balloon device on a stateful guest, a tagged VLAN, an EFI disk
present exactly when EFI firmware is selected, and HA membership wherever deletion
protection is asserted.

## What this module does and does not do

| Does | Does not |
| --- | --- |
| Clone the template, resize disks, set CPU and memory | Install or configure any software |
| Write hostname, SSH keys, timezone and static networking via cloud-init | Patch the guest (Ansible, gated maintenance window) |
| Tag the VM for backup selection | Create a backup job (Ansible `backup` role) |
| Register HA membership | Create the HA group (environment root module) |
| Enforce allocation and safety invariants | Decide node placement policy (the caller passes `node_name`) |
| — | Create a ZFS replication job (Ansible `common` role) |
| — | Create any credential (see below) |

## No credential ever enters this module

`ssh_public_keys` takes **public** keys only, and the validation rejects anything
that is not an OpenSSH public key line. There is no variable for a password, and
adding one would be a regression rather than a feature:

- cloud-init `user_account.password` is written into Terraform state in plaintext;
- it appears in the plan file, which `deploy.yml` attaches to the pull request as
  redacted text — redaction depends on Terraform knowing the value is sensitive;
- it is written into the Proxmox VM configuration, where it is visible to anyone
  with API read access, which is a wider audience than the guest itself.

Database credentials are created inside the guest by Ansible from SOPS-encrypted
inventory, per ADR-003 decision 3. If you find yourself wanting to pass a password
to this module, the design is wrong at a higher level.

## `ignore_changes = [initialization]` is deliberate

Cloud-init reads its snippets once, on first boot. After that the file identifier
is history. Without the ignore, a one-line edit to `user-data.yaml.tftpl` changes
the uploaded snippet's identifier, which changes the VM's `initialization` block,
which the provider resolves by **replacing the VM** — destroying a database
because someone fixed a typo in a comment.

The consequence is that editing the templates does **not** update running guests,
and that is correct: cloud-init is not a configuration management system. To
change an existing guest, use Ansible. To change first-boot behaviour for new
guests, edit the template. To re-run cloud-init on an existing guest, destroy and
recreate it deliberately, with a plan attached.

## Invariants enforced

| Invariant | Where | Failure it prevents |
| --- | --- | --- |
| `vm_id` inside `vmid_block` | `lifecycle.precondition` | Two environments claiming one cluster-global identifier; ambiguous `vzdump` archives |
| EFI disk present iff `bios = "ovmf"` | `lifecycle.precondition` | A VM that powers on, shows nothing, and logs nothing |
| No ballooning on protected guests | `lifecycle.precondition` | Guest OOM killer choosing PostgreSQL under memory pressure |
| Protected guests are HA-managed | `lifecycle.precondition` | "Protected" data that stays down after a node failure until someone notices |
| `on_boot` and HA are not both authoritative | `lifecycle.precondition` | State that depends on which mechanism acted last |
| VLAN tag is one of 10/20/30/40/50 | `variable.vlan_id` validation | An untagged guest landing in the hypervisor's management context |
| At least two resolvers | `variable.dns_servers` validation | Single point of failure for every name lookup on the machine |
| Public-key format | `variable.ssh_public_keys` validation | A private key committed to state |
| Disk cache is a known value | `variable.disks` validation | `writeback` on a ZFS zvol, which is a data-loss setting |
| Tags exclude the bare word `terraform` | `variable.tags` validation | Collision with the provider's own tag, breaking tag-based backup selection |

## Prerequisites on the Proxmox side

These are manual, one-time, and are the reason a first `apply` fails more often
than any other step:

1. **A cloud-init template** at `template_vm_id`, with `qemu-guest-agent`
   installed and enabled, and cloud-init present. Built by Ansible
   (`ansible/roles/common`, documented in that role's README). One template per
   Debian release per environment.
2. **`snippets` content type enabled** on `snippets_datastore_id`
   (Datacenter → Storage → Content). Not enabled by default on new Proxmox
   installations, and the failure message when it is missing does not mention
   snippets.
3. **Provider SSH access** for snippet upload: `PM_SSH_USERNAME` and
   `PM_SSH_PRIVATE_KEY`. Required at **apply** time only — `terraform plan` never
   needs it, which is what keeps the read-only plan credential free of node SSH
   access. See `.github/workflows/deploy.yml`.
4. **An HA group** named by `ha_group`, created in the environment root module.
5. **A corosync qdevice** on a third machine, without which HA will not act on a
   two-node cluster. See `docs/network-topology.md`.

## Example

```hcl
module "prod_cp_0" {
  source = "../modules/proxmox-vm"

  name          = "prod-cp-0"
  description   = "k3s control plane 0 — prod. Owner: platform."
  node_name     = "pve-01"
  vm_id         = 1200
  vmid_block    = data.terraform_remote_state.global.outputs.vmid_blocks["prod"]
  pool_id       = data.terraform_remote_state.global.outputs.pool_ids["prod"]

  template_vm_id        = 9000
  template_node_name    = "pve-01"
  snippets_datastore_id = "local"

  cpu_cores           = 2
  memory_dedicated_mb = 4096

  disks = [{
    interface    = "scsi"
    size_gb      = 60
    datastore_id = "local-zfs"
    iothread     = true
    ssd          = true
    discard      = true
    backup       = true
    replicate    = true
    cache        = "none"
  }]

  vlan_id      = 20
  ipv4_address = "10.10.20.40/24"
  ipv4_gateway = "10.10.20.1"
  dns_servers  = ["10.10.10.1", "10.10.10.2"]

  ssh_public_keys = var.ssh_public_keys

  bios                  = "ovmf"
  efi_disk_datastore_id = "local-zfs"

  ha_group         = "viavitae-prod-ha"
  protect_deletion = true
  tags             = ["k3s", "control-plane", "backup-daily"]
}
```

`k3s-node`, `postgres-vm`, `keycloak-vm`, `bitrix24-vm` and `monitoring-vm` are
thin wrappers around this module that fix the sizing, tagging and HA policy for
their role. Call the wrapper, not this module, unless you are creating a genuinely
new role — and then add a wrapper, because the next person will otherwise copy
your call site and the invariants that live in your head will not travel with it.
