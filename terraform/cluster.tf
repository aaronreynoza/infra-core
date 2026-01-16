resource "talos_machine_secrets" "machine_secrets" {}

data "talos_client_configuration" "talosconfig" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  endpoints            = [var.talos_cp_01_ip_addr]
}

data "talos_machine_configuration" "machineconfig_cp" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.talos_cp_01_ip_addr}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.machine_secrets.machine_secrets
}

resource "talos_machine_configuration_apply" "cp_config_apply" {
  depends_on                  = [proxmox_virtual_environment_vm.control_planes]
  client_configuration        = talos_machine_secrets.machine_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.machineconfig_cp.machine_configuration
  count                       = 1
  node                        = var.talos_cp_01_ip_addr

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
    })
  ]
}

data "talos_machine_configuration" "machineconfig_worker_1" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.talos_cp_01_ip_addr}:6443"
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.machine_secrets.machine_secrets
}

data "talos_machine_configuration" "machineconfig_worker_2" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.talos_cp_01_ip_addr}:6443"
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.machine_secrets.machine_secrets
}

resource "talos_machine_configuration_apply" "worker_1_config_apply" {
  depends_on                  = [proxmox_virtual_environment_vm.workers]
  client_configuration        = talos_machine_secrets.machine_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.machineconfig_worker_1.machine_configuration
  node                        = var.talos_worker_01_ip_addr

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
    yamlencode({
      apiVersion   = "v1alpha1"
      kind         = "UserVolumeConfig"
      name         = "longhorn"
      provisioning = {
        diskSelector = {
          match = "disk.dev_path == '/dev/vdb' && !system_disk"
        }
        minSize = "300GiB"
        grow    = true
      }
    }),
    yamlencode({
      machine = {
        kubelet = {
          extraMounts = [
            {
              destination = "/var/mnt/u-longhorn"
              type        = "bind"
              source      = "/var/mnt/u-longhorn"
              options     = ["bind","rshared","rw"]
            }
          ]
        }
      }
    })
  ]
}


resource "talos_machine_configuration_apply" "worker_2_config_apply" {
  depends_on                  = [proxmox_virtual_environment_vm.workers]
  client_configuration        = talos_machine_secrets.machine_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.machineconfig_worker_2.machine_configuration
  count                       = 1
  node                        = var.talos_worker_01_ip_addr
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
    yamlencode({
      apiVersion   = "v1alpha1"
      kind         = "UserVolumeConfig"
      name         = "longhorn"
      provisioning = {
        diskSelector = {
          match = "disk.dev_path == '/dev/vdb' && !system_disk"
        }
        minSize = "300GiB"
        grow    = true
      }
    }),
    yamlencode({
      machine = {
        kubelet = {
          extraMounts = [
            {
              destination = "/var/mnt/u-longhorn"
              type        = "bind"
              source      = "/var/mnt/u-longhorn"
              options     = ["bind","rshared","rw"]
            }
          ]
        }
      }
    })
  ]
}

resource "talos_machine_bootstrap" "bootstrap" {
  depends_on           = [ talos_machine_configuration_apply.cp_config_apply ]
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  node                 = var.talos_cp_01_ip_addr
}

data "talos_cluster_health" "health" {
  count                = var.skip_cluster_health ? 0 : 1
  depends_on           = [ talos_machine_configuration_apply.cp_config_apply, talos_machine_configuration_apply.worker_1_config_apply, talos_machine_configuration_apply.worker_2_config_apply ]
  client_configuration = data.talos_client_configuration.talosconfig.client_configuration
  control_plane_nodes  = [ var.talos_cp_01_ip_addr ]
  worker_nodes         = [ var.talos_worker_01_ip_addr ]
  endpoints            = data.talos_client_configuration.talosconfig.endpoints
}

resource "talos_cluster_kubeconfig" "kubeconfig" {
  depends_on = [
    talos_machine_bootstrap.bootstrap,
    talos_machine_configuration_apply.cp_config_apply,
    talos_machine_configuration_apply.worker_1_config_apply,
    talos_machine_configuration_apply.worker_2_config_apply,
  ]
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  node                 = var.talos_cp_01_ip_addr
}

output "talosconfig" {
  value = data.talos_client_configuration.talosconfig.talos_config
  sensitive = true
}

output "kubeconfig" {
  value = resource.talos_cluster_kubeconfig.kubeconfig.kubeconfig_raw
  sensitive = true
}
