resource "talos_machine_secrets" "machine_secrets" {}

data "talos_client_configuration" "talosconfig" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  endpoints            = [var.talos_cp_01_ip_addr]
}

# ----------------------------
# Control plane (no disk tweaks)
# ----------------------------
data "talos_machine_configuration" "machineconfig_cp" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.talos_cp_01_ip_addr}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.machine_secrets.machine_secrets
}

resource "talos_machine_configuration_apply" "cp_config_apply" {
  depends_on                  = [proxmox_virtual_environment_vm.talos_cp_01]
  client_configuration        = talos_machine_secrets.machine_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.machineconfig_cp.machine_configuration
  count                       = 1
  node                        = var.talos_cp_01_ip_addr
}

# ----------------------------
# Workers (disk + kubelet mount + iscsi-tools)
# ----------------------------
data "talos_machine_configuration" "machineconfig_worker" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.talos_cp_01_ip_addr}:6443"
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.machine_secrets.machine_secrets
}

resource "talos_machine_configuration_apply" "worker_1_config_apply" {
  depends_on                  = [proxmox_virtual_environment_vm.talos_worker_01]
  client_configuration        = talos_machine_secrets.machine_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.machineconfig_worker.machine_configuration
  count                       = 1
  node                        = var.talos_worker_01_ip_addr

  # JSON6902 patch — Talos v1.7: no `filesystem:` key under partitions; only `mountpoint`.
  config_patches = [
    <<EOT
- op: add
  path: /machine/disks
  value: []
- op: add
  path: /machine/disks/-
  value:
    device: /dev/vdb
    partitions:
      - size: 0
        mountpoint: /var/mnt/longhorn

# Bind-mount to make it visible to workloads via kubelet (for Longhorn filesystem disk)
- op: add
  path: /machine/kubelet
  value: {}
- op: add
  path: /machine/kubelet/extraMounts
  value: []
- op: add
  path: /machine/kubelet/extraMounts/-
  value:
    destination: /var/mnt/longhorn
    type: bind
    source: /var/mnt/longhorn
    options: [bind, rshared, rw]

# iSCSI tools required by Longhorn
- op: add
  path: /machine/install
  value: {}
- op: add
  path: /machine/install/extensions
  value: []
- op: add
  path: /machine/install/extensions/-
  value:
    image: ghcr.io/siderolabs/extensions/iscsi-tools:latest
EOT
  ]
}

resource "talos_machine_configuration_apply" "worker_2_config_apply" {
  depends_on                  = [proxmox_virtual_environment_vm.talos_worker_02]
  client_configuration        = talos_machine_secrets.machine_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.machineconfig_worker.machine_configuration
  count                       = 1
  node                        = var.talos_worker_02_ip_addr

  config_patches = [
    <<EOT
- op: add
  path: /machine/disks
  value: []
- op: add
  path: /machine/disks/-
  value:
    device: /dev/vdb
    partitions:
      - size: 0
        mountpoint: /var/mnt/longhorn

- op: add
  path: /machine/kubelet
  value: {}
- op: add
  path: /machine/kubelet/extraMounts
  value: []
- op: add
  path: /machine/kubelet/extraMounts/-
  value:
    destination: /var/mnt/longhorn
    type: bind
    source: /var/mnt/longhorn
    options: [bind, rshared, rw]

- op: add
  path: /machine/install
  value: {}
- op: add
  path: /machine/install/extensions
  value: []
- op: add
  path: /machine/install/extensions/-
  value:
    image: ghcr.io/siderolabs/extensions/iscsi-tools:latest
EOT
  ]
}

# ----------------------------
# Bootstrap / health / kubeconfig / outputs
# ----------------------------
resource "talos_machine_bootstrap" "bootstrap" {
  depends_on           = [talos_machine_configuration_apply.cp_config_apply]
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  node                 = var.talos_cp_01_ip_addr
}

data "talos_cluster_health" "health" {
  depends_on = [
    talos_machine_configuration_apply.cp_config_apply,
    talos_machine_configuration_apply.worker_1_config_apply,
    talos_machine_configuration_apply.worker_2_config_apply
  ]
  client_configuration = data.talos_client_configuration.talosconfig.client_configuration
  control_plane_nodes  = [var.talos_cp_01_ip_addr]
  worker_nodes         = [var.talos_worker_01_ip_addr, var.talos_worker_02_ip_addr]
  endpoints            = data.talos_client_configuration.talosconfig.endpoints
}

data "talos_cluster_kubeconfig" "kubeconfig" {
  depends_on           = [talos_machine_bootstrap.bootstrap, data.talos_cluster_health.health]
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  node                 = var.talos_cp_01_ip_addr
}

output "talosconfig" {
  value     = data.talos_client_configuration.talosconfig.talos_config
  sensitive = true
}

output "kubeconfig" {
  value     = data.talos_cluster_kubeconfig.kubeconfig.kubeconfig_raw
  sensitive = true
}
