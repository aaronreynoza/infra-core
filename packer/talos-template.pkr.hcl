// Minimal Talos template build on Proxmox using the hashicorp/proxmox "clone" builder.
// This imports the Talos nocloud image, creates a VM, and converts it to a TEMPLATE.

packer {
  required_plugins {
    proxmox = {
      source  = "github.com/hashicorp/proxmox"
      version = ">= 1.2.0"
    }
  }
}

# ---------- Inputs ----------
variable "proxmox_url" {
  type = string
  # e.g. https://REDACTED_IP:8006/api2/json
}

variable "proxmox_username" {
  type = string
  # e.g. root@pam
}

variable "proxmox_password" {
  type      = string
  sensitive = true
}

variable "proxmox_node" {
  type = string
  # e.g. pve
}

variable "storage_pool" {
  type    = string
  default = "local-lvm"
}

variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "template_name" {
  type    = string
  default = "template-talos"
}

variable "talos_version" {
  type    = string
  default = "v1.7.4"
}

# Talos "nocloud" disk image (supports cloud-init). The builder imports this URL directly.
variable "talos_image_url" {
  type    = string
  default = "https://github.com/siderolabs/talos/releases/download/v1.7.4/nocloud-amd64.img.xz"
}

variable "vm_cores" {
  type    = number
  default = 2
}

variable "vm_memory" {
  type    = number
  default = 4096 # MB
}

variable "vm_disk_gb" {
  type    = number
  default = 8
}

# ---------- Builder ----------
# Use the "clone" builder. No ISO, no checksum—just import the Talos image and template it.
source "proxmox-clone" "talos" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  insecure_skip_tls_verify = true

  node    = var.proxmox_node
  vm_name = "${var.template_name}-${var.talos_version}"

  # Import Talos disk image directly from URL
  disk_image_url = var.talos_image_url

  # Primary disk created from imported image
  disks {
    type         = "scsi"
    storage_pool = var.storage_pool
    disk_size    = "${var.vm_disk_gb}G"
  }

  # Network
  network_adapters {
    model  = "virtio"
    bridge = var.network_bridge
  }

  # Hardware
  cores           = var.vm_cores
  memory          = var.vm_memory
  scsi_controller = "virtio-scsi-pci"
  bios            = "seabios"

  # Attach Cloud-Init drive so clones can inject Talos configs
  cloud_init              = true
  cloud_init_storage_pool = var.storage_pool

  # Convert to Proxmox template when done (matches the blog flow)
  convert_to_template = true

  # Talos installer has no SSH for packer to use
  communicator = "none"
}

build {
  name    = "talos-template"
  sources = ["source.proxmox-clone.talos"]
}
