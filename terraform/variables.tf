# ---------- Proxmox API (secrets come from TF_VAR_* / runtime.auto.tfvars.json) ----------
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

# SSH target used by null_resource/remote-exec, etc.
variable "pm_ssh_host" {
  type      = string
  sensitive = true     # e.g. "root@REDACTED_IP"
}

# Talos image URL in Proxmox content (template or raw image)
variable "talos_image_url" {
  type = string
  # no default; supply via TF_VAR_talos_image_url or tfvars
}

# Optional: prebuilt cloud-init/cidata ISO locations (vm_name -> storage:path)
variable "config_isos" {
  type    = map(string)
  default = {}
}

# --- Talos template metadata (used by null_resource and clones) ---
variable "template_vmid" {
  description = "Numeric VMID to use for the Talos template in Proxmox (e.g., 9000)"
  type        = number
}

variable "template_name" {
  description = "Name of the Talos template VM to create/clone (e.g., talos-tpl)"
  type        = string
}

# --- Simple cluster shape: map of nodes keyed by VM name ---
variable "nodes" {
  description = "Map of nodes to create (key = VM name)"
  type = map(object({
    memory    = number         # MB
    cores     = number
    os_disk   = string         # e.g., "20G"
    data_disk = string         # e.g., "100G"; use null for none
  }))
  default = {}                 # empty = create nothing
}
