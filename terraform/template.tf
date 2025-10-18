locals {
  talos_raw_url = var.talos_image_url != "" ?
    var.talos_image_url :
    "https://github.com/siderolabs/talos/releases/download/${var.talos_version}/metal-amd64.raw.xz"
}

resource "null_resource" "talos_template" {
  triggers = {
    talos_raw_url = local.talos_raw_url
    vmid          = tostring(var.template_vmid)
    name          = var.template_name
    vm_storage    = var.vm_storage
    bridge        = var.bridge
    pm_ssh        = var.pm_ssh_host
  }

  provisioner "local-exec" {
    # Use a heredoc so we don't have to worry about quoting/escaping
    command = <<-EOT
      bash '${path.module}/scripts/build_talos_template.sh' \
        '${var.pm_ssh_host}' \
        '${local.talos_raw_url}' \
        '${var.template_vmid}' \
        '${var.template_name}' \
        '${var.vm_storage}' \
        '${var.bridge}'
    EOT

    # Ensure we run the heredoc string through bash
    interpreter = ["/usr/bin/bash", "-c"]
  }
}
