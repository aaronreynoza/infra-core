variable "proxmox_api_url"          { type = string }
variable "proxmox_api_token_id"     { type = string }
variable "proxmox_api_token_secret" { type = string }

variable "pm_node"      { type = string  default = "pve" }
variable "vm_storage"   { type = string  default = "local-lvm" }
variable "iso_storage"  { type = string  default = "local" }
variable "bridge"       { type = string  default = "vmbr0" }

# Where Terraform can SSH into Proxmox to run qm commands
variable "pm_ssh_host" { type = string } # e.g. "root@pve"

# Talos factory *metal* image (.raw.xz), e.g.:
# https://factory.talos.dev/image/XXXXXXXX/metal-amd64.raw.xz
variable "talos_image_url" { type = string }

# Template settings
variable "template_vmid" { type = number default = 9000 }
variable "template_name" { type = string default = "talos-proxmox-template" }

# VM shapes
variable "controlplane" {
  type = object({
    name   = string
    memory = number
    cores  = number
    disk   = string  # OS disk size (e.g., "20G")
  })
  default = {
    name   = "cp1"
    memory = 4096
    cores  = 2
    disk   = "20G"
  }
}

variable "workers" {
  description = "Map of worker nodes with OS and data disk sizes"
  type = map(object({
    memory      = number
    cores       = number
    os_disk     = string  # e.g., "20G"
    data_disk   = string  # Longhorn data disk, e.g., "500G"
  }))
  default = {
    "w1" = { memory = 4096, cores = 4, os_disk = "20G", data_disk = "200G" }
    "w2" = { memory = 4096, cores = 4, os_disk = "20G", data_disk = "200G" }
  }
}

# Per-node Talos cidata ISOs you will upload to `local:iso/…`
# e.g. { cp1 = "local:iso/cp1-cidata.iso", w1 = "local:iso/w1-cidata.iso", w2 = "local:iso/w2-cidata.iso" }
variable "config_isos" {
  type        = map(string)
  description = "VM name -> Proxmox ISO path for Talos machine config"
  default     = {}
}

variable "proxmox_api_url"          { type = string, sensitive = true }
variable "proxmox_api_token_id"     { type = string, sensitive = true }
variable "proxmox_api_token_secret" { type = string, sensitive = true }
variable "pm_ssh_host"              { type = string, sensitive = true }  # e.g. root@pve
