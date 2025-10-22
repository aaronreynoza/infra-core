############################################
# virtual_machines.tf (bpg/proxmox)
# Edit locals.control_planes / locals.workers
############################################

locals {
  talos_upload_name = replace(replace(var.talos_image_file_name, ".raw.xz", ".img"), ".xz", ".img")
  control_planes = [
    "talos-cp-01",
  ]

  workers = [
    "talos-worker-01",
    "talos-worker-02",
  ]

  # Common sizing (override if you like)
  cpu_cores      = 4
  memory_mb      = 8192
  boot_disk_gb   = 20
  data_disk_gb   = 1000
}

# Expected vars (match your environment)
# variable "pm_node"        { type = string }            # e.g. "proxmox1"
# variable "datastore_id"   { type = string }            # e.g. "local-lvm"
# variable "talos_image_id" { type = string }            # If you prefer passing file_id directly
#
# If you're already using the download_file resource, keep using it:
# resource "proxmox_virtual_environment_download_file" "talos_nocloud_image" { ... }

########################
# Control-plane VMs
########################
resource "proxmox_virtual_environment_vm" "control_planes" {
  for_each = toset(local.control_planes)

  name        = each.value
  description = "Managed by Terraform"
  tags        = ["talos", "control-plane"]
  node_name   = var.pm_node
  on_boot     = true

  # CPU/RAM
  sockets = 1
  cores   = local.cpu_cores
  memory  = local.memory_mb

  # Disks
  disk {
    datastore_id = var.datastore_id
    file_id      = "${var.PROXMOX_DIR_STORAGE}:iso/${local.talos_upload_name}"
    file_format  = "raw"
    interface    = "virtio0"
    size         = local.boot_disk_gb
    ssd          = true
    discard      = "on"
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "virtio1"
    size         = local.data_disk_gb
    iothread     = true
    ssd          = true
    discard      = "on"
  }

  # Optional but nice to pin boot order
  boot_order = ["virtio0", "net0"]
}

########################
# Worker VMs
########################
resource "proxmox_virtual_environment_vm" "workers" {
  for_each = toset(local.workers)

  name        = each.value
  description = "Managed by Terraform"
  tags        = ["talos", "worker"]
  node_name   = var.pm_node
  on_boot     = true

  # CPU/RAM
  sockets = 1
  cores   = local.cpu_cores
  memory  = local.memory_mb

  # Disks
  disk {
    datastore_id = var.datastore_id
    # If you use the download_file resource, uncomment the next line and remove var.talos_image_id:
    # file_id      = proxmox_virtual_environment_download_file.talos_nocloud_image.id
    file_id      = "${var.PROXMOX_DIR_STORAGE}:iso/${local.talos_upload_name}"
    file_format  = "raw"
    interface    = "virtio0"
    size         = local.boot_disk_gb
    ssd          = true
    discard      = "on"
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "virtio1"
    size         = local.data_disk_gb
    iothread     = true
    ssd          = true
    discard      = "on"
  }

  boot_order = ["virtio0", "net0"]
}

########################
# Handy outputs
########################
output "control_plane_names" {
  value = keys(proxmox_virtual_environment_vm.control_planes)
}

output "worker_names" {
  value = keys(proxmox_virtual_environment_vm.workers)
}
