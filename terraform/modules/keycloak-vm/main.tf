# modules/keycloak-vm — the identity provider as a Proxmox guest.
#
# Installs nothing. Writes the facts ansible/roles/keycloak needs and enforces the
# placement invariants that keep the admin console off the internet and the
# identity store away from tenant data.

locals {
  provisioning_files = {
    "/etc/viavitae/keycloak-public-hostname" = "${var.public_hostname}\n"
    "/etc/viavitae/keycloak-db-host"         = "${var.database_host}\n"
    "/etc/viavitae/keycloak-heap-mb"         = "${floor(var.memory_dedicated_mb * 0.6)}\n"
    "/etc/viavitae/environment"              = "${var.environment_name}\n"
    # The admin console is bound to the management path only. Ansible enforces it
    # by binding a separate HTTPS listener and by the VLAN rules in
    # docs/network-topology.md; this file exists so the intent is on the machine
    # and auditable, not only in a runbook.
    "/etc/viavitae/keycloak-admin-console-restricted" = "true\n"
  }

  tags = ["keycloak", var.environment_name, "identity", "backup-daily"]
}

module "vm" {
  source = "../proxmox-vm"

  name        = var.name
  description = "Keycloak identity provider for ${var.environment_name}. Owner: platform. Public name ${var.public_hostname}. Holds authentication records — INFRA-001 F4."
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
  vlan_id         = var.vlan_id
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

  depends_on = [terraform_data.keycloak_invariants]
}

resource "terraform_data" "keycloak_invariants" {
  input = {
    vlan     = var.vlan_id
    hostname = var.public_hostname
    db_host  = var.database_host
  }

  lifecycle {
    # Never in the dmz. Public SSO traffic reaches Keycloak through HAProxy
    # (rule X2 into prod); the administrative console must be reachable only from
    # the mgmt VLAN, which follows from rule X1. A Keycloak VM on VLAN 40 would put
    # its admin console one firewall mistake away from the internet, and the
    # console is a credential-stuffing target with a known URL.
    precondition {
      condition     = contains([20, 30], var.vlan_id)
      error_message = "vlan_id must be 20 (prod) or 30 (staging). Keycloak is never placed in the dmz: public traffic arrives through HAProxy, and the admin console stays reachable only from mgmt."
    }

    # The public hostname must be the one HAProxy routes and cert-manager issues
    # for. A mismatch yields a valid authentication followed by a failed redirect,
    # and neither Keycloak nor the client logs an error that says so.
    precondition {
      condition     = !endswith(var.public_hostname, ".internal") && !contains(split(".", var.public_hostname), "internal")
      error_message = "public_hostname must be an externally resolvable name, not an internal one. Keycloak derives its issuer URL from it, and an internal issuer breaks every external client."
    }

    precondition {
      condition     = var.database_host != var.public_hostname && var.database_host != ""
      error_message = "database_host must be the address of the keycloak-purpose PostgreSQL instance and must not be empty."
    }
  }
}
