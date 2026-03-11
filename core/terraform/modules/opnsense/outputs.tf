# OPNSense Module Outputs

output "vm_id" {
  description = "The VM ID of the OPNSense instance"
  value       = proxmox_virtual_environment_vm.opnsense.vm_id
}

output "vm_name" {
  description = "The name of the OPNSense VM"
  value       = proxmox_virtual_environment_vm.opnsense.name
}

output "mac_addresses" {
  description = "MAC addresses of the network interfaces (WAN, LAN)"
  value = {
    wan = proxmox_virtual_environment_vm.opnsense.network_device[0].mac_address
    lan = proxmox_virtual_environment_vm.opnsense.network_device[1].mac_address
  }
}

output "iso_file_id" {
  description = "The file ID of the downloaded OPNSense ISO"
  value       = proxmox_virtual_environment_download_file.opnsense_iso.id
}

output "next_steps" {
  description = "Instructions for completing OPNSense setup"
  value       = <<-EOT
    OPNSense VM has been created. Complete these manual steps:

    1. Open Proxmox console for VM '${var.vm_name}' (ID: ${var.vm_id})
    2. Boot the VM and follow OPNSense installation wizard
    3. After install, access web UI at https://<WAN_IP> (default: root/opnsense)
    4. Configure interfaces:
       - WAN: vtnet0 (DHCP from ISP)
       - LAN: vtnet1 (create VLANs 10 and 11)
    5. See docs/04-opnsense.md for detailed VLAN and firewall configuration

    After installation, update boot_order to "virtio0" (disk only) and remove ISO.
  EOT
}
