output "vm_names" {
  value = keys(var.nodes)
}

output "vm_config_iso_map" {
  value = var.config_isos
}

output "generated_cidata_isos" {
  value = { for k, _ in var.nodes : k => "local:iso/${k}-cidata.iso" }
}