# TrueNAS VM Module
# Provisions a TrueNAS SCALE VM on Proxmox VE with raw disk passthrough
#
# This module creates:
# - Downloads the TrueNAS SCALE ISO
# - Creates a VM with boot disk on local-lvm
# - Passes through physical disks for ZFS pool
# - Attaches ISO for initial installation
#
# After terraform apply, you must:
# 1. Access Proxmox console for the VM
# 2. Complete TrueNAS installation wizard (install to the boot disk, NOT the passthrough disks)
# 3. Set a static IP, create ZFS pool, configure NFS/SMB shares
# See docs/decisions/002-truenas-storage.md for details

terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.78.0"
    }
  }
}

# Download TrueNAS SCALE ISO
resource "proxmox_virtual_environment_download_file" "truenas_iso" {
  content_type = "iso"
  datastore_id = var.iso_datastore_id
  node_name    = var.proxmox_node
  url          = var.truenas_iso_url
  file_name    = var.truenas_iso_filename
  overwrite    = true

  lifecycle {
    ignore_changes = [url]
  }
}

# TrueNAS VM
resource "proxmox_virtual_environment_vm" "truenas" {
  node_name   = var.proxmox_node
  name        = var.vm_name
  vm_id       = var.vm_id
  description = "TrueNAS SCALE - Media storage (NFS/SMB) with ZFS on passthrough disks"

  on_boot = var.start_on_boot
  started = var.start_vm

  machine = "q35"
  bios    = "ovmf"

  efi_disk {
    datastore_id = var.datastore_id
    type         = "4m"
  }

  cpu {
    sockets = 1
    cores   = var.cpu_cores
    type    = "host"
  }

  memory {
    dedicated = var.memory_mb
  }

  agent {
    enabled = true
  }

  boot_order = [for device in split(",", var.boot_order) : trimspace(device)]

  # CD-ROM with TrueNAS ISO
  cdrom {
    file_id = proxmox_virtual_environment_download_file.truenas_iso.id
  }

  # Boot disk (TrueNAS OS install target)
  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = var.boot_disk_size_gb
    file_format  = "raw"
    iothread     = true
    discard      = "on"
    ssd          = true
  }

  # Network interface on VLAN
  network_device {
    bridge  = var.network_bridge
    model   = "virtio"
    vlan_id = var.vlan_id
  }

  serial_device {}

  vga {
    type   = "virtio"
    memory = 32
  }

  scsi_hardware = "virtio-scsi-pci"

  lifecycle {
    ignore_changes = [
      cdrom,
      boot_order,
    ]
  }
}

# Attach passthrough disks via Proxmox CLI
# The bpg/proxmox provider does not natively support raw physical disk passthrough,
# so we use qm set after VM creation to attach /dev/disk/by-id/ paths.
resource "terraform_data" "passthrough_disks" {
  for_each = { for idx, disk in var.passthrough_disks : idx => disk }

  triggers_replace = [
    proxmox_virtual_environment_vm.truenas.vm_id,
    each.value,
  ]

  provisioner "local-exec" {
    command = "ssh -o StrictHostKeyChecking=accept-new ${var.proxmox_ssh_user}@${var.proxmox_host} 'qm set ${var.vm_id} --scsi${each.key + 1} ${each.value}'"
  }

  depends_on = [proxmox_virtual_environment_vm.truenas]
}
