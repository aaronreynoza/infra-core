locals {
  # A single control-plane + map of workers
  all_nodes = merge(
    { (var.controlplane.name) = {
        role      = "controlplane"
        memory    = var.controlplane.memory
        cores     = var.controlplane.cores
        os_disk   = var.controlplane.disk
        data_disk = null
      }
    },
    { for k, v in var.workers :
      k => {
        role      = "worker"
        memory    = v.memory
        cores     = v.cores
        os_disk   = v.os_disk
        data_disk = v.data_disk
      }
    }
  )
}
