# ---------- Proxmox API (use TF_VAR_* or a tfvars file) ----------
variable "proxmox_api_url" {
  type      = string
  sensitive = true
}
variable "proxmox_api_token_id" {
  type      = string
  sensitive = true
}
variable "proxmox_api_token_secret" {
  type      = string
  sensitive = true
}

# ---------- Proxmox node / infra settings ----------
variable "pm_node" {
  type    = string
  default = "pve"
}

variable "vm_storage" {
  type    = string
  default = "local-lvm"
}

variable "bridge" {
  type    = string
  default = "vmbr0"
}

# SSH target to run 'qm' commands for the template step (local-exec over ssh)
# e.g. "root@REDACTED_IP"
variable "pm_ssh_host" {
  type      = string
  sensitive = true
}

# Template VM info
variable "template_vmid" {
  type    = number
  default = 9000
}
variable "template_name" {
  type    = string
  default = "talos-template"
}

# Map of node name -> cidata ISO path in Proxmox (e.g. "local:iso/w1-cidata.iso")
variable "config_isos" {
  type    = map(string)
  default = {}
}

# Nodes definition: name -> { cores, memory (MiB), os_disk (e.g. "20G"), optional data_disk (e.g. "200G") }
variable "nodes" {
  type = map(object({
    cores     = number
    memory    = number
    os_disk   = string
    data_disk = optional(string) # present => create a 2nd disk for Longhorn
  }))
  default = {}
}

variable "talos_version" {
  description = "Talos release tag to use, e.g. v1.7.5"
  type        = string
  default     = "v1.8.2"
}

variable "talos_image_url" {
  description = "Override Talos metal image URL (raw.xz). Leave empty to use talos_version."
  type        = string
  default     = ""
}
