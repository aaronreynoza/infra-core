############################################
# Build & upload CIData ISO on Proxmox host
############################################

# Triggers replace when the script or inputs change
locals {
  cidata_script_path = "${path.module}/scripts/build_cidata.sh"
  # Use the same values you were already passing; names below are examples:
  pm_ssh_host   = var.pm_ssh_host                   # e.g. "***@REDACTED_IP"
  api_server    = var.cluster_api_endpoint          # e.g. "https://192.168.100.101:6443"
  cluster_name  = coalesce(try(var.cluster_name, null), "talos")
}

resource "null_resource" "cidata" {
  triggers = {
    script_hash  = filesha1(local.cidata_script_path)
    pm_ssh_host  = local.pm_ssh_host
    api_server   = local.api_server
    cluster_name = local.cluster_name
  }

  provisioner "local-exec" {
    # Use flags (but the script also accepts the old positional style).
    command = join(" ", [
      "bash", "'${local.cidata_script_path}'",
      "--pm-ssh",      "'${local.pm_ssh_host}'",
      "--api-server",  "'${local.api_server}'",
      "--cluster-name","'${local.cluster_name}'",
    ])
  }
}
