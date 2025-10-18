locals {
  talout_dir            = "${path.module}/.talout"              # talhelper writes here
  cidata_iso_dir        = "/var/lib/vz/template/iso"            # remote path
  cidata_storage_prefix = "local:iso"                           # attach prefix
}

resource "null_resource" "cidata" {
  for_each = var.nodes

  # Rebuild ISO when the machineconfig YAML changes
  triggers = {
    node_name   = each.key
    mc_hash     = filesha256("${local.talout_dir}/${each.key}.yaml")
    pm_ssh      = var.pm_ssh_host
  }

  provisioner "local-exec" {
    command = <<EOT
bash '${path.module}/scripts/make_cidata.sh' \
  '${var.pm_ssh_host}' \
  '${each.key}' \
  '${local.talout_dir}/${each.key}.yaml' \
  '${local.cidata_iso_dir}' \
  '${local.cidata_storage_prefix}'
EOT
  }
}
