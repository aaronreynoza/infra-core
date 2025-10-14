resource "proxmox_vm_qemu" "talos_nodes" {
  for_each = local.all_nodes

  depends_on = [null_resource.talos_template]

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

  # Attach Talos machine config ISO (per node) as a CD-ROM (ide2)
  # Provide the path via var.config_isos["<vmname>"] = "local:iso/<vm>-cidata.iso"
  # If missing, Terraform will error (which is good — you must supply configs).
  ide2 = "${var.config_isos[each.key]},media=cdrom"

  network {
    model  = "virtio"
    bridge = var.bridge
  }

  # Resize OS disk if you want bigger than the template’s imported size
  disk {
    type    = "scsi"
    storage = var.vm_storage
    size    = each.value.os_disk
    # This ensures scsi0 is present (the clone already has one); provider will handle grow
  }

  # Worker-only: attach a second disk for Longhorn data (e.g., /dev/sdb or /dev/vdb)
  dynamic "disk" {
    for_each = each.value.data_disk == null ? [] : [each.value.data_disk]
    content {
      type     = "scsi"
      storage  = var.vm_storage
      size     = disk.value
      iothread = true
      ssd      = true
      # Provider will assign next available slot (e.g., scsi1)
    }
  }
}
