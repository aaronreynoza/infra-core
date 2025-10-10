// Packer template to create a Talos VM template on Proxmox
// Uses the hashicorp/proxmox plugin. Requires a Talos nocloud image URL.
// The VM is converted to a reusable Proxmox template.

packer {
  required_plugins {
    proxmox = {
      source  = "github.com/hashicorp/proxmox"
      version = ">= 1.1.5"
    }
  }
}

variable "proxmox_url"          { type = string }
variable "proxmox_token_id"     { type = string }
variable "proxmox_token_secret" { type = string }
variable "proxmox_node"         { type = string }
variable "storage_pool"         { type = string   default = "local-lvm" }
variable "network_bridge"       { type = string   default = "vmbr0" }
variable "template_name"        { type = string   default = "template-talos" }
variable "talos_version"        { type = string   default = "v1.7.4" }
variable "talos_image_url"      { type = string   default = "https://github.com/siderolabs/talos/releases/download/v1.7.4/nocloud-amd64.img.xz" }
variable "vm_cores"             { type = number   default = 2 }
variable "vm_memory"            { type = number   default = 4096 }
variable "vm_disk_gb"           { type = number   default = 8 }

source "proxmox" "talos" {
  proxmox_url     = var.proxmox_url
  username        = var.proxmox_token_id
  token           = var.proxmox_token_secret
  insecure_skip_tls_verify = true

  node            = var.proxmox_node
  vm_name         = "${var.template_name}-${var.talos_version}"
  network_adapters {
    model  = "virtio"
    bridge = var.network_bridge
  }

  // Upload and use the Talos nocloud disk image directly
  // Packer will decompress .xz and upload the disk to the storage pool
  disks {
    type            = "scsi"
    storage_pool    = var.storage_pool
    disk_size       = "${var.vm_disk_gb}G"
    disk_image_url  = var.talos_image_url
  }

  cores           = var.vm_cores
  memory          = var.vm_memory
  scsi_controller = "virtio-scsi-pci"

  // Firmware (SeaBIOS) works; OVMF also works if you add an EFI disk.
  bios            = "seabios"

  // Add a Cloud-Init drive so clones can inject config later
  cloud_init              = true
  cloud_init_storage_pool = var.storage_pool

  // When build completes, convert the VM to a template
  convert_to_template = true
}

build {
  name    = "talos-template"
  sources = ["source.proxmox.talos"]

  provisioner "shell" {
    inline = ["echo Talos template ready"]
  }
}
