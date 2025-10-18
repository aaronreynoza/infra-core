resource "proxmox_vm_qemu" "talos_nodes" {
  for_each = var.nodes

  depends_on = [
    null_resource.talos_template,
    null_resource.cidata[each.key]
  ]

  name        = each.key
  target_node = var.pm_node
  clone       = var.template_name
  full_clone  = true

  agent   = 0
  sockets = 1
  cores   = each.value.cores
  memory  = each.value.memory
  onboot  = true

  scsihw = "virtio-scsi-single"
  boot   = "order=scsi0"

  # Attach the per-node ISO we just generated (IDE slot 2)
  ide {
    slot = 2
    iso  = "${local.cidata_storage_prefix}/${each.key}-cidata.iso"
  }

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
    for_each = try(each.value.data_disk, null) == null ? [] : [each.value.data_disk]
    content {
      type     = "scsi"
      storage  = var.vm_storage
      size     = disk.value
      iothread = true
      ssd      = true
    }
  }
}
