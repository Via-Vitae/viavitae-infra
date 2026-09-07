# modules/bitrix24-vm — the closed-source CRM, isolated by construction.
#
# ADR-007 accepts Bitrix24 with eight conditions. Four of them are properties of a
# VM and are therefore enforced here rather than left to review: dmz placement,
# allow-listed egress, a separate database, and the two approvals that gate `prod`.
#
# Installs nothing. ansible/playbooks/bitrix24.yml does, and that playbook refuses
# to run in prod unless the same two approvals are present in the inventory. Two
# gates for one decision is deliberate: Terraform can be bypassed by a manual VM
# and Ansible can be bypassed by a manual install, but not both at once.

locals {
  provisioning_files = merge(
    {
      "/etc/viavitae/bitrix-public-hostname" = "${var.public_hostname}\n"
      "/etc/viavitae/bitrix-db-host"         = "${var.database_host}\n"
      "/etc/viavitae/bitrix-egress-mode"     = length(var.egress_allow_list) == 0 ? "deny-all\n" : "allowlist\n"
      "/etc/viavitae/bitrix-egress-hosts"    = length(var.egress_allow_list) == 0 ? "" : join("\n", sort(var.egress_allow_list))
      "/etc/viavitae/environment"            = "${var.environment_name}\n"
      # Read by ansible/roles/bitrix24, which configures Keycloak as the only
      # authentication path and disables the vendor's local password store.
      "/etc/viavitae/bitrix-sso-required" = "true\n"
    },
  )

  tags = ["bitrix24", var.environment_name, "dmz", "backup-daily"]
}

module "vm" {
  source = "../proxmox-vm"

  name        = var.name
  description = "Bitrix24 CRM for ${var.environment_name}. Owner: platform. Closed-source, dmz-isolated, egress allow-listed — ADR-007. Public name ${var.public_hostname}."
  node_name   = var.node_name
  vm_id       = var.vm_id
  vmid_block  = var.vmid_block
  pool_id     = var.pool_id

  template_vm_id        = var.template_vm_id
  template_node_name    = var.template_node_name
  snippets_datastore_id = var.snippets_datastore_id

  cpu_cores           = var.cpu_cores
  memory_dedicated_mb = var.memory_dedicated_mb
  memory_ballooning   = false

  disks = [{
    interface    = "scsi"
    size_gb      = var.disk_size_gb
    datastore_id = var.datastore_id
    iothread     = true
    ssd          = true
    discard      = true
    backup       = true
    replicate    = true
    cache        = "none"
  }]

  bridge          = "vmbr1"
  vlan_id         = 40
  ipv4_address    = var.ipv4_address
  ipv4_gateway    = var.ipv4_gateway
  dns_domain      = var.dns_domain
  dns_servers     = var.dns_servers
  ssh_public_keys = var.ssh_public_keys

  bios                  = "ovmf"
  efi_disk_datastore_id = var.datastore_id

  protect_deletion = true
  ha_group         = var.ha_group
  on_boot          = true
  started          = var.started

  tags        = local.tags
  extra_files = local.provisioning_files

  depends_on = [terraform_data.bitrix24_invariants]
}

resource "terraform_data" "bitrix24_invariants" {
  input = {
    environment = var.environment_name
    legal       = var.legal_review_approved
    dpia        = var.dpia_infra_002_approved
    egress      = var.egress_allow_list
  }

  lifecycle {
    # ADR-007 condition 7 and condition 8, as a plan failure rather than a
    # checklist item.
    precondition {
      condition = var.environment_name == "prod" ? (
        var.legal_review_approved && var.dpia_infra_002_approved
      ) : true
      error_message = <<-EOT
        Bitrix24 in `prod` requires legal_review_approved and
        dpia_infra_002_approved to both be true. ADR-007 conditions 7 and 8, and
        INFRA-001 condition C5. This is closed-source software with an outbound
        flow that cannot be inspected, processing employee and client personal
        data; the approvals are what make that acceptable rather than merely
        documented.
      EOT
    }

    # An approval with no reference is an assertion. An auditor asking "who
    # approved this and where is it recorded" must get a location, not a boolean.
    precondition {
      condition     = var.legal_review_approved ? var.legal_review_reference != "" : true
      error_message = "legal_review_approved is true but legal_review_reference is empty. Record where the approval lives."
    }

    precondition {
      condition     = var.dpia_infra_002_approved ? var.dpia_reference != "" : true
      error_message = "dpia_infra_002_approved is true but dpia_reference is empty. Record the DPIA identifier."
    }

    # ADR-007 condition 1: dmz only. Hard-coded above rather than taken as input,
    # asserted here so that changing it is a two-file change with an error message.
    precondition {
      condition     = can(regex("^10\\.10\\.40\\.[0-9]{1,3}/24$", var.ipv4_address))
      error_message = "ipv4_address must be inside 10.10.40.0/24 (the dmz VLAN). Bitrix24 is never placed on prod, staging or mgmt."
    }

    # ADR-007 condition 2: allow-listed egress, explicitly decided.
    precondition {
      condition     = var.environment_name == "prod" ? length(var.egress_allow_list) > 0 : true
      error_message = "egress_allow_list is empty in prod. If licence validation is required, list the hostnames; if it is not, the VM must have no internet egress and that must be a recorded decision rather than a blank field."
    }

    # ADR-007 condition 4: its own database.
    precondition {
      condition     = var.database_host != "" && can(regex("^10\\.10\\.40\\.[0-9]{1,3}$", var.database_host))
      error_message = "database_host must be an address in the dmz VLAN. Bitrix24 never shares an instance with tenant data: a vendor workload compromise would otherwise be a tenant breach."
    }
  }
}
