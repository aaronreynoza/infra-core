output "vms" {
  description = "Map of created VMs with their details"
  value = {
    for name, vm in proxmox_virtual_environment_vm.vm : name => {
      id         = vm.id
      vm_id      = vm.vm_id
      name       = vm.name
      node       = vm.node_name
      ip_address = var.vms[index(var.vms.*.name, name)].ip_address
    }
  }
}

output "vm_ids" {
  description = "Map of VM names to their Proxmox VM IDs"
  value       = { for name, vm in proxmox_virtual_environment_vm.vm : name => vm.vm_id }
}

output "ip_addresses" {
  description = "Map of VM names to their IP addresses"
  value       = { for vm in var.vms : vm.name => vm.ip_address }
}
