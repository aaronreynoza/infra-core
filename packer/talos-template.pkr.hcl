// Build a Talos VM (powered off) on Proxmox using the hashicorp/proxmox plugin.
// We intentionally do NOT call "template" here because proxmox-iso (v1.2.3) doesn't
// support it. We'll convert to a template later from Terraform/Proxmox API.

packer {
  required_plugins {
    proxmox = {
      source  = "github.com/hashicorp/proxmox"
      version = ">= 1.2.0"
    }
  }
}

variable "proxmox_url" {
  type = string
}

variable "proxmox_username" {
  type = string
}

variable "proxmox_password" {
  type      = string
  sensitive = true
}

variable "proxmox_node" {
  type = string
}

variable "storage_pool" {
  type    = string
  default = "local-lvm"
}

variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "iso_storage_pool" {
  type    = string
  default = "local" // your directory store that holds ISO images
}

variable "template_name" {
  type    = string
  default = "template-talos"
}

variable "talos_version" {
  type    = string
  default = "v1.7.4"
}

# Talos ISO for the proxmox-iso builder
variable "talos_iso_url" {
  type    = string
  default = "https://github.com/siderolabs/talos/releases/download/v1.7.4/metal-amd64.iso"
}

# Optional checksum (leave empty to skip)
variable "talos_iso_checksum" {
  type    = string
  default = "" # e.g., "sha256:<hash>"
}

variable "vm_cores" {
  type    = number
  default = 2
}

variable "vm_memory" {
  type    = number
  default = 4096
}

variable "vm_disk_gb" {
  type    = number
  default = 8
}

source "proxmox-iso" "talos" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  insecure_skip_tls_verify = true

  node    = var.proxmox_node
  vm_name = "${var.template_name}-${var.talos_version}"

  # ISO boot (download to ISO storage, then mount)
  iso_url          = var.talos_iso_url
  iso_checksum     = length(var.talos_iso_checksum) > 0 ? var.talos_iso_checksum : null
  iso_storage_pool = var.iso_storage_pool
  unmount_iso      = true

  # Network
  network_adapters {
    model  = "virtio"
    bridge = var.network_bridge
  }

  # Disk (the "storage_pool" is valid ONLY inside this block)
  disks {
    type         = "scsi"
    storage_pool = var.storage_pool
    disk_size    = "${var.vm_disk_gb}G"
  }

  # Hardware
  cores           = var.vm_cores
  memory          = var.vm_memory
  scsi_controller = "virtio-scsi-pci"
  bios            = "seabios"

  # Cloud-Init drive for per-node configs later
  cloud_init              = true
  cloud_init_storage_pool = var.storage_pool

  # Talos has no SSH during ISO boot; no guest comms.
  communicator = "none"
  boot_wait    = "5s"
}

build {
  name    = "talos-template"
  sources = ["source.proxmox-iso.talos"]
}
