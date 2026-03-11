# Network Infrastructure Outputs

output "opnsense_vm_id" {
  description = "The VM ID of the OPNSense instance"
  value       = module.opnsense.vm_id
}

output "opnsense_vm_name" {
  description = "The name of the OPNSense VM"
  value       = module.opnsense.vm_name
}

output "opnsense_mac_addresses" {
  description = "MAC addresses of OPNSense network interfaces"
  value       = module.opnsense.mac_addresses
}

output "opnsense_next_steps" {
  description = "Instructions for completing OPNSense setup"
  value       = module.opnsense.next_steps
}

# TrueNAS outputs
output "truenas_vm_id" {
  description = "The VM ID of the TrueNAS instance"
  value       = module.truenas.vm_id
}

output "truenas_vm_name" {
  description = "The name of the TrueNAS VM"
  value       = module.truenas.vm_name
}

output "truenas_mac_address" {
  description = "MAC address of TrueNAS network interface"
  value       = module.truenas.mac_address
}

output "truenas_next_steps" {
  description = "Instructions for completing TrueNAS setup"
  value       = module.truenas.next_steps
}
