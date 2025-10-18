locals {
  vm_names = ["w1", "w2"]
}

variable "pm_node"        { type = string }
variable "vm_storage"     { type = string }
variable "bridge"         { type = string }
variable "template_name"  { type = string } # e.g. "talos-template"

provider "proxmox" {
  # Uses environment variables:
  # PM_API_URL, PM_API_TOKEN_ID, PM_API_TOKEN_SECRET (or your TF_VAR_* equivalents)
  pm_parallel      = 2
  timeout          = 600
  # If you use self-signed certs:
  insecure         = true
}

resource "proxmox_vm_qemu" "talos_nodes" {
  for_each = toset(local.vm_names)

  name            = each.key
  target_node     = var.pm_node
  clone           = var.template_name
  full_clone      = true

  # general
  automatic_reboot          = true
  additional_wait           = 5
  clone_wait                = 10
  preprovision              = true
  oncreate                  = true
  onboot                    = true
  tablet                    = true
  kvm                       = true
  define_connection_info    = true

  # firmware/boot
  bios   = "seabios"
  boot   = "order=scsi0"

  # cpu & ram
  cpu     = "host"
  sockets = 1
  cores   = 4
  memory  = 8192

  scsihw  = "virtio-scsi-single"
  hotplug = "network,disk,usb"

  # --------- DISKS ----------
  # IMPORTANT: provider expects numeric flags (0/1), not booleans
  disk {
    type         = "scsi"
    storage      = var.vm_storage
    size         = "20G"
    cache        = "none"
    iothread     = 0       # NOT true/false
    ssd          = 0       # NOT true/false
    backup       = true

    # Keep throttling fields numeric (avoid empty strings)
    iops             = 0
    iops_max         = 0
    iops_max_length  = 0
    iops_rd          = 0
    iops_rd_max      = 0
    iops_rd_max_length = 0
    iops_wr          = 0
    iops_wr_max      = 0
    iops_wr_max_length = 0
    mbps             = 0
    mbps_rd          = 0
    mbps_rd_max      = 0
    mbps_wr          = 0
    mbps_wr_max      = 0
    replicate        = 0
  }

  # Data disk (example 500G) – toggle as needed
  disk {
    type         = "scsi"
    storage      = var.vm_storage
    size         = "500G"
    cache        = "none"
    iothread     = 1
    ssd          = 1
    backup       = true

    iops             = 0
    iops_max         = 0
    iops_max_length  = 0
    iops_rd          = 0
    iops_rd_max      = 0
    iops_rd_max_length = 0
    iops_wr          = 0
    iops_wr_max      = 0
    iops_wr_max_length = 0
    mbps             = 0
    mbps_rd          = 0
    mbps_rd_max      = 0
    mbps_wr          = 0
    mbps_wr_max      = 0
    replicate        = 0
  }

  # --------- NETWORK ----------
  network {
    model = "virtio"
    bridge = var.bridge
    firewall  = false
    link_down = false
    tag       = -1
  }

  # DO NOT set `iso = ...` here if you are cloning — it conflicts with `clone`.
  # Attach your cloud-init/cidata iso with a separate step/null_resource if needed.
}
