# Proxmox VM Module
# Generic module for provisioning VMs on Proxmox VE

terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.78.0"
    }
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  for_each = { for vm in var.vms : vm.name => vm }

  node_name = var.proxmox_node
  name      = each.value.name
  vm_id     = each.value.vm_id
  on_boot   = var.start_on_boot

  cpu {
    sockets = var.cpu_sockets
    cores   = each.value.cpu_cores
    type    = var.cpu_type
  }

  memory {
    dedicated = each.value.memory_mb
  }

  agent {
    enabled = var.qemu_agent_enabled
  }

  # Explicitly boot from the virtio0 disk to avoid iPXE/network boot fallback
  boot_order = ["virtio0"]

  network_device {
    bridge  = var.network_bridge
    vlan_id = each.value.vlan_id
  }

  # Boot disk
  disk {
    datastore_id = var.boot_datastore_id
    file_id      = var.boot_image_id
    file_format  = "raw"
    interface    = "virtio0"
    size         = each.value.boot_disk_gb
  }

  # Data disk (optional)
  dynamic "disk" {
    for_each = each.value.data_disk_gb != null ? [1] : []
    content {
      datastore_id = var.data_datastore_id
      interface    = "virtio1"
      size         = each.value.data_disk_gb
      iothread     = true
    }
  }

  initialization {
    datastore_id = var.boot_datastore_id
    ip_config {
      ipv4 {
        address = "${each.value.ip_address}/${var.network_cidr}"
        gateway = var.gateway
      }
    }
  }

  lifecycle {
    ignore_changes = [
      # Ignore changes to disk file_id after initial creation
      # This prevents recreation when image is updated
      disk[0].file_id,
    ]
  }
}
