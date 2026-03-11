output "kubeconfig" {
  description = "Kubernetes kubeconfig for the cluster (deprecated: use kubeconfig_raw)"
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}

output "talosconfig" {
  description = "Talos client configuration"
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "cluster_name" {
  description = "Name of the cluster"
  value       = var.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = "https://${var.control_planes[0].ip_address}:6443"
}

output "control_plane_ips" {
  description = "IP addresses of control plane nodes"
  value       = [for cp in var.control_planes : cp.ip_address]
}

output "worker_ips" {
  description = "IP addresses of worker nodes"
  value       = [for worker in var.workers : worker.ip_address]
}

output "talos_image_id" {
  description = "ID of the Talos image in Proxmox"
  value       = proxmox_virtual_environment_download_file.talos_image.id
}

output "machine_secrets" {
  description = "Talos machine secrets for backup (store in AWS Secrets Manager)"
  value       = talos_machine_secrets.this.machine_secrets
  sensitive   = true
}

output "kubeconfig_raw" {
  description = "Raw kubeconfig for Helm/kubectl provider configuration"
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}
