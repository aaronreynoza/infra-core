# Talos Cluster Module
# Provisions a Talos Linux Kubernetes cluster on Proxmox VE

terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.78.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = ">= 0.8.0"
    }
  }
}

# Download Talos image to Proxmox
resource "proxmox_virtual_environment_download_file" "talos_image" {
  content_type = "iso"
  datastore_id = var.image_datastore_id
  node_name    = var.proxmox_node
  url          = var.talos_image_url
  file_name    = local.talos_image_filename
}

# Control Plane VMs
module "control_planes" {
  source = "../proxmox-vm"

  proxmox_node      = var.proxmox_node
  boot_datastore_id = var.boot_datastore_id
  data_datastore_id = var.data_datastore_id
  boot_image_id     = proxmox_virtual_environment_download_file.talos_image.id
  network_bridge    = var.network_bridge
  network_cidr      = var.network_cidr
  gateway           = var.gateway

  vms = [
    for i, cp in var.control_planes : {
      name         = cp.name
      vm_id        = cp.vm_id
      ip_address   = cp.ip_address
      cpu_cores    = var.control_plane_cpu_cores
      memory_mb    = var.control_plane_memory_mb
      boot_disk_gb = var.control_plane_boot_disk_gb
      data_disk_gb = null
      vlan_id      = var.vlan_id
    }
  ]
}

# Worker VMs
module "workers" {
  source     = "../proxmox-vm"
  depends_on = [module.control_planes]

  proxmox_node      = var.proxmox_node
  boot_datastore_id = var.boot_datastore_id
  data_datastore_id = var.data_datastore_id
  boot_image_id     = proxmox_virtual_environment_download_file.talos_image.id
  network_bridge    = var.network_bridge
  network_cidr      = var.network_cidr
  gateway           = var.gateway

  vms = [
    for i, worker in var.workers : {
      name         = worker.name
      vm_id        = worker.vm_id
      ip_address   = worker.ip_address
      cpu_cores    = var.worker_cpu_cores
      memory_mb    = var.worker_memory_mb
      boot_disk_gb = var.worker_boot_disk_gb
      data_disk_gb = var.worker_data_disk_gb
      vlan_id      = var.vlan_id
    }
  ]
}

# Talos Machine Secrets
resource "talos_machine_secrets" "this" {}

# Talos Client Configuration
data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [for cp in var.control_planes : cp.ip_address]
}

# Control Plane Machine Configuration
data "talos_machine_configuration" "control_plane" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.control_planes[0].ip_address}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
}

# Worker Machine Configuration
data "talos_machine_configuration" "worker" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.control_planes[0].ip_address}:6443"
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
}

# Apply configuration to control planes
resource "talos_machine_configuration_apply" "control_plane" {
  for_each   = { for cp in var.control_planes : cp.name => cp }
  depends_on = [module.control_planes]

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.control_plane.machine_configuration
  node                        = each.value.ip_address

  config_patches = [
    yamlencode({
      cluster = {
        network = {
          cni = {
            name = "none" # Use Cilium instead
          }
        }
        proxy = {
          disabled = true # Cilium handles kube-proxy
        }
      }
    })
  ]
}

# Apply configuration to workers
resource "talos_machine_configuration_apply" "worker" {
  for_each   = { for worker in var.workers : worker.name => worker }
  depends_on = [module.workers, talos_machine_configuration_apply.control_plane]

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = each.value.ip_address

  config_patches = [
    yamlencode({
      cluster = {
        network = {
          cni = {
            name = "none"
          }
        }
        proxy = {
          disabled = true
        }
      }
    }),
    # Longhorn volume configuration
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "UserVolumeConfig"
      name       = "longhorn"
      provisioning = {
        diskSelector = {
          match = "disk.dev_path == '/dev/vdb' && !system_disk"
        }
        minSize = "${var.longhorn_min_size_gib}GiB"
        grow    = true
      }
    }),
    yamlencode({
      machine = {
        kubelet = {
          extraMounts = [
            {
              destination = var.longhorn_mount_path
              type        = "bind"
              source      = var.longhorn_mount_path
              options     = ["bind", "rshared", "rw"]
            }
          ]
        }
      }
    })
  ]
}

# Bootstrap the cluster
resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.control_plane]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.control_planes[0].ip_address
}

# Health check
data "talos_cluster_health" "this" {
  count      = var.skip_health_check ? 0 : 1
  depends_on = [talos_machine_configuration_apply.control_plane, talos_machine_configuration_apply.worker]

  client_configuration = data.talos_client_configuration.this.client_configuration
  control_plane_nodes  = [for cp in var.control_planes : cp.ip_address]
  worker_nodes         = [for worker in var.workers : worker.ip_address]
  endpoints            = data.talos_client_configuration.this.endpoints
}

# Get kubeconfig
resource "talos_cluster_kubeconfig" "this" {
  depends_on = [
    talos_machine_bootstrap.this,
    talos_machine_configuration_apply.control_plane,
    talos_machine_configuration_apply.worker,
  ]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.control_planes[0].ip_address
}
