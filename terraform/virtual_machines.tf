locals {
  control_plane_names = ["talos-cp-01"]
  worker_names        = ["talos-worker-01", "talos-worker-02"]

  cpu_cores  = 4
  memory_mb  = 8192
  scsihw     = "virtio-scsi-single"

  talos_upload_name = replace(replace(var.talos_image_file_name, ".raw.xz", ".img"), ".xz", ".img")
  boot_disk_gb      = 20
  data_disk_gb      = 1000
}

resource "proxmox_virtual_environment_vm" "control_planes" {
  for_each  = toset(local.control_plane_names)
  node_name = var.pm_node
  name      = each.key
  on_boot   = true
  tags      = ["tofu"]

  cpu {
    sockets = 1
    cores   = local.cpu_cores
    type    = "host"
  }

  memory {
    dedicated = local.memory_mb
  }

  scsi_hardware = local.scsihw
  hotplug       = ["network", "disk", "usb"]

  disk {
    datastore_id = var.datastore_id
    file_id      = "${var.PROXMOX_DIR_STORAGE}:iso/${local.talos_upload_name}"
    file_format  = "raw"
    interface    = "virtio0"
    size         = local.boot_disk_gb
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "virtio1"
    size         = local.data_disk_gb
    iothread     = true
  }
}

resource "proxmox_virtual_environment_vm" "workers" {
  for_each  = toset(local.worker_names)
  node_name = var.pm_node
  name      = each.key
  on_boot   = true
  tags      = ["tofu"]

  cpu {
    sockets = 1
    cores   = local.cpu_cores
    type    = "host"
  }

  memory {
    dedicated = local.memory_mb
  }

  scsi_hardware = local.scsihw
  hotplug       = ["network", "disk", "usb"]

  disk {
    datastore_id = var.datastore_id
    file_id      = "${var.PROXMOX_DIR_STORAGE}:iso/${local.talos_upload_name}"
    file_format  = "raw"
    interface    = "virtio0"
    size         = local.boot_disk_gb
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "virtio1"
    size         = local.data_disk_gb
    iothread     = true
  }
}
