# OPNSense VM Module
# Provisions an OPNSense firewall/router VM on Proxmox VE
#
# This module creates:
# - Downloads the OPNSense ISO
# - Creates a VM with 2 NICs (WAN + LAN)
# - Attaches ISO for initial installation
#
# After terraform apply, you must:
# 1. Access Proxmox console for the VM
# 2. Complete OPNSense installation wizard
# 3. Configure VLANs and firewall rules via OPNSense web UI
# See docs/04-opnsense.md for detailed configuration steps

terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.78.0"
    }
  }
}

# Download OPNSense ISO
resource "proxmox_virtual_environment_download_file" "opnsense_iso" {
  content_type            = "iso"
  datastore_id            = var.iso_datastore_id
  node_name               = var.proxmox_node
  url                     = var.opnsense_iso_url
  file_name               = var.opnsense_iso_filename
  decompression_algorithm = "bz2"

  overwrite = false

  lifecycle {
    # Don't re-download if file exists
    ignore_changes = [url]
  }
}

# OPNSense VM
resource "proxmox_virtual_environment_vm" "opnsense" {
  node_name   = var.proxmox_node
  name        = var.vm_name
  vm_id       = var.vm_id
  description = "OPNSense Firewall/Router - manages VLANs and inter-environment routing"

  on_boot = var.start_on_boot
  started = var.start_vm

  # Machine type - q35 supports PCIe passthrough if needed later
  machine = "q35"

  # BIOS - OVMF (UEFI) for modern boot
  bios = "ovmf"

  # EFI disk for UEFI boot
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

  # No QEMU agent until OPNSense is installed and agent package added
  agent {
    enabled = false
  }

  # Boot order: CD-ROM first for initial install, then disk
  boot_order = [for device in split(",", var.boot_order) : trimspace(device)]

  # CD-ROM with OPNSense ISO
  cdrom {
    file_id = proxmox_virtual_environment_download_file.opnsense_iso.id
  }

  # Boot disk
  disk {
    datastore_id = var.datastore_id
    interface    = "virtio0"
    size         = var.disk_size_gb
    file_format  = "raw"
    iothread     = true
    discard      = "on"
  }

  # WAN interface - connects to ISP router
  network_device {
    bridge  = var.wan_bridge
    model   = "virtio"
    vlan_id = var.wan_vlan_id
  }

  # LAN interface - VLAN trunk for prod/dev networks
  # OPNSense will create VLAN sub-interfaces on this
  network_device {
    bridge  = var.lan_bridge
    model   = "virtio"
    vlan_id = var.lan_vlan_id
  }

  # Serial console for troubleshooting
  serial_device {}

  # VGA for console access during installation
  vga {
    type = "std"
  }

  lifecycle {
    ignore_changes = [
      # Ignore CD-ROM changes after initial creation
      # (will be detached after installation)
      cdrom,
      # Ignore boot order changes after install
      boot_order,
    ]
  }
}
