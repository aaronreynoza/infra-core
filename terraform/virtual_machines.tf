############################################
# VM definitions (clone from talos template)
############################################

locals {
  vm_names = ["w1", "w2"]
}

# Assumes these vars already exist in variables.tf:
# - var.pm_node
# - var.vm_storage
# - var.bridge
# - var.template_name  # e.g. "talos-template"

resource "proxmox_vm_qemu" "talos_nodes" {
  for_each = toset(local.vm_names)

  name        = each.key
  target_node = var.pm_node

  # Clone from an existing template. Do NOT set `iso` here (it conflicts).
  clone      = var.template_name
  full_clone = true

  # General behavior
  automatic_reboot       = true
  additional_wait        = 5
  clone_wait             = 10
  preprovision           = true
  oncreate               = true
  onboot                 = true
  tablet                 = true
  kvm                    = true
  define_connection_info = true

  # Firmware/boot
  bios = "seabios"
  boot = "order=scsi0"

  # CPU & RAM
  cpu     = "host"
  sockets = 1
  cores   = 4
  memory  = 8192

  scsihw  = "virtio-scsi-single"
  hotplug = "network,disk,usb"

  #####################
  # Root system disk
  #####################
  disk {
    type    = "scsi"
    storage = var.vm_storage
    size    = "20G"
    cache   = "none"

    # The Telmate provider expects numeric flags, not TF bools/strings.
    iothread = 0
    ssd      = 0
    backup   = true

    # Keep throttling fields numeric to avoid provider panics
    iops                = 0
    iops_max            = 0
    iops_max_length     = 0
    iops_rd             = 0
    iops_rd_max         = 0
    iops_rd_max_length  = 0
    iops_wr             = 0
    iops_wr_max         = 0
    iops_wr_max_length  = 0
    mbps                = 0
    mbps_rd             = 0
    mbps_rd_max         = 0
    mbps_wr             = 0
    mbps_wr_max         = 0
    replicate           = 0
  }

  #####################
  # Data disk (optional)
  #####################
  disk {
    type    = "scsi"
    storage = var.vm_storage
    size    = "500G"
    cache   = "none"

    iothread = 1
    ssd      = 1
    backup   = true

    iops                = 0
    iops_max            = 0
    iops_max_length     = 0
    iops_rd             = 0
    iops_rd_max         = 0
    iops_rd_max_length  = 0
    iops_wr             = 0
    iops_wr_max         = 0
    iops_wr_max_length  = 0
    mbps                = 0
    mbps_rd             = 0
    mbps_rd_max         = 0
    mbps_wr             = 0
    mbps_wr_max         = 0
    replicate           = 0
  }

  #####################
  # Network
  #####################
  network {
    model     = "virtio"
    bridge    = var.bridge
    firewall  = false
    link_down = false
    tag       = -1
  }
}
