output "vm_names" {
  value = keys(local.all_nodes)
}

output "vm_config_iso_map" {
  value = var.config_isos
}
