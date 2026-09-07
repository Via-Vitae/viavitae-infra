# Inputs for modules/k3s-node.
#
# A k3s node is a proxmox-vm with a role, a pinned k3s version and a set of
# invariants that come from ADR-001 and ADR-002. This module does not install k3s:
# it declares the version, writes it to the guest at first boot, and Ansible's k3s
# role reads it back and installs exactly that.

variable "name" {
  type        = string
  description = "Node name, e.g. prod-cp-0 or prod-worker-3. Becomes the guest hostname and the Kubernetes node name."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,62}$", var.name))
    error_message = "name must be a lowercase DNS label."
  }
}

variable "role" {
  type        = string
  description = "k3s role. `control_plane` runs the API server, scheduler, controller-manager and embedded etcd; `worker` runs kubelet and workloads only."

  validation {
    condition     = contains(["control_plane", "worker"], var.role)
    error_message = "role must be control_plane or worker."
  }
}

variable "k3s_version" {
  type        = string
  description = <<-EOT
    Pinned k3s release, e.g. v1.36.4+k3s1. Declared here and nowhere else in the
    repository. It reaches the guest as /etc/viavitae/k3s-version via cloud-init,
    and ansible/roles/k3s reads that file and fails if it is missing rather than
    falling back to a default — a silent default would be a second source of truth
    and the two would drift on the first upgrade.
  EOT

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+\\+k3s[0-9]+$", var.k3s_version))
    error_message = "k3s_version must be a full pinned release such as v1.36.4+k3s1. A branch like v1.36 or a channel like stable resolves to whatever is newest at install time, which makes a rebuild non-reproducible and an upgrade unreviewed."
  }
}

variable "control_plane_count" {
  type        = number
  description = "How many control-plane VMs this environment declares. Used with control_plane_nodes to enforce the ADR-002 quorum rule."
}

variable "control_plane_nodes" {
  type        = list(string)
  description = <<-EOT
    The Proxmox node name each control-plane VM is placed on, in VMID order. Its
    length must equal control_plane_count. This exists so that the quorum
    constraint can be checked mechanically: three control-plane VMs on two
    Proxmox nodes always loses etcd quorum when one node fails, because at least
    two of the three share a node (pigeonhole), and losing two of three members is
    losing the majority.
  EOT
}

variable "api_vip_address" {
  type        = string
  default     = ""
  description = <<-EOT
    Virtual IP for the Kubernetes API, held by kube-vip across the control-plane
    VMs. Required when control_plane_count is greater than 1: without a stable API
    address, every kubeconfig and every worker's server URL points at one
    control-plane VM and losing that VM takes the cluster's control path with it.
  EOT
}

variable "node_name" {
  type        = string
  description = "Proxmox node hosting this VM."
}

variable "vm_id" {
  type        = number
  description = "VMID from this environment's allocated block."
}

variable "vmid_block" {
  type = object({
    start = number
    end   = number
  })
  description = "Allocated VMID block, from the global root module."
}

variable "pool_id" {
  type        = string
  description = "Proxmox resource pool for this environment."
}

variable "ha_group" {
  type        = string
  default     = null
  description = <<-EOT
    HA group for this VM. Required for control-plane VMs in a two-node pilot: with
    one control plane, HA is the only thing that brings it back after a node
    failure, and without it a node failure is a cluster outage that waits for a
    human.
  EOT
}

variable "cpu_cores" {
  type        = number
  default     = null
  description = "Override the role default (control_plane 2, worker 8)."
}

variable "memory_dedicated_mb" {
  type        = number
  default     = null
  description = "Override the role default (control_plane 4096, worker 32768)."
}

variable "disk_size_gb" {
  type        = number
  default     = null
  description = "Override the role default (control_plane 60, worker 100)."
}

variable "datastore_id" {
  type        = string
  description = "ZFS pool datastore for the root disk."
}

variable "snippets_datastore_id" {
  type        = string
  description = "Snippets-enabled datastore for cloud-init, on the same node."
}

variable "template_vm_id" {
  type        = number
  description = "Cloud-init template VMID for this environment."
}

variable "template_node_name" {
  type        = string
  default     = ""
  description = "Node holding the template; empty to let the provider locate it."
}

variable "vlan_id" {
  type        = number
  description = "VLAN for the node's primary interface."
}

variable "ipv4_address" {
  type        = string
  description = "Static address in CIDR notation, from docs/network-topology.md."
}

variable "ipv4_gateway" {
  type        = string
  description = "Gateway for that VLAN."
}

variable "dns_domain" {
  type        = string
  default     = "viavitae.internal"
  description = "DNS search domain."
}

variable "dns_servers" {
  type        = list(string)
  description = "Recursive resolvers reachable from the node's VLAN."
}

variable "ssh_public_keys" {
  type        = list(string)
  description = "SSH public keys for the automation user. Ansible authenticates with these."
}

variable "started" {
  type        = bool
  default     = true
  description = "Whether the VM should be running after apply."
}

variable "environment_name" {
  type        = string
  description = "Environment label used in tags and in the files written to /etc/viavitae/, so a node can say which environment it belongs to without being asked."
}
