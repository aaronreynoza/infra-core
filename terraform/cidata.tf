# Single builder that creates all per-node ISOs in one shot
resource "null_resource" "cidata" {
  # change this trigger whenever inputs change so script re-runs
  triggers = {
    content_hash = sha1(join(",", sort(keys(var.nodes))))
    script_hash  = filesha1("${path.module}/scripts/build_cidata.sh")
  }

  provisioner "local-exec" {
    command = <<-EOT
      bash '${path.module}/scripts/build_cidata.sh' \
        '${var.pm_ssh_host}' \
        '${var.cluster_endpoint}' \
        '${var.cluster_name}'
    EOT
    interpreter = ["/usr/bin/bash", "-c"]
  }
}
