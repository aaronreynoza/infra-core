locals {
  cidata_map = { for name, _ in var.nodes : name => "local:iso/${name}-cidata.iso" }
}

resource "proxmox_vm_qemu" "talos_nodes" {
  for_each = var.nodes
  depends_on = [null_resource.cidata]

  name        = each.key
  target_node = var.pm_node
  clone       = var.template_name
  full_clone  = true

  agent   = 0
  sockets = 1
  cores   = each.value.cores
  memory  = each.value.memory
  onboot  = true

  scsihw  = "virtio-scsi-single"
  boot    = "order=scsi0"

  iso = local.cidata_map[each.key]

  network {
    model  = "virtio"
    bridge = var.bridge
  }

  disk {
    type    = "scsi"
    storage = var.vm_storage
    size    = each.value.os_disk
  }

  dynamic "disk" {
    for_each = each.value.data_disk == null ? [] : [each.value.data_disk]
    content {
      type     = "scsi"
      storage  = var.vm_storage
      size     = disk.value
      iothread = 1
      ssd      = 1
    }
  }
}
