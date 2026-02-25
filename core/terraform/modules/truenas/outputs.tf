# TrueNAS Module Outputs

output "vm_id" {
  description = "The VM ID of the TrueNAS instance"
  value       = proxmox_virtual_environment_vm.truenas.vm_id
}

output "vm_name" {
  description = "The name of the TrueNAS VM"
  value       = proxmox_virtual_environment_vm.truenas.name
}

output "mac_address" {
  description = "MAC address of the network interface"
  value       = proxmox_virtual_environment_vm.truenas.network_device[0].mac_address
}

output "passthrough_disk_count" {
  description = "Number of physical disks passed through for ZFS"
  value       = length(var.passthrough_disks)
}

output "next_steps" {
  description = "Instructions for completing TrueNAS setup"
  value       = <<-EOT
    TrueNAS VM has been created. Complete these manual steps:

    1. Open Proxmox console for VM '${var.vm_name}' (ID: ${var.vm_id})
    2. Boot and install TrueNAS to the boot disk (scsi0, ${var.boot_disk_size_gb} GB)
       DO NOT install to the passthrough disks (scsi1, scsi2, etc.)
    3. After install, reboot and access TrueNAS web UI
    4. Set a static IP on VLAN ${var.vlan_id}
    5. Create a ZFS mirror pool from the passthrough disks
    6. Create datasets: tank/media, tank/downloads, tank/backups
    7. Configure NFS shares for Kubernetes access
    8. Configure SMB shares for desktop access

    After installation, update boot_order to "scsi0" (disk only) and remove ISO.

    See docs/decisions/002-truenas-storage.md for the full storage plan.
  EOT
}
