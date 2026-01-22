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

output "next_steps" {
  description = "Instructions for completing OPNSense setup"
  value       = module.opnsense.next_steps
}
