variable "pm_node" {
  type = string
}

variable "datastore_id" {
  type = string
}

variable "talos_image_url" {
  type = string
}

variable "talos_image_file_name" {
  type = string
}

variable "pm_file_store_id" {
  description = "File-based storage (dir/nfs) to stage downloads"
  type        = string
  default     = "local"
}

variable "pm_block_store_id" {
  description = "Block storage for VM disks (lvmthin/zfs)"
  type        = string
  default     = "local-lvm"
}

variable "PROXMOX_DIR_STORAGE" {
  type = string
  description = "Name of the directory storage in Proxmox (e.g., local)"
}

variable "cluster_name" {
  type    = string
  default = "homelab"
}

variable "default_gateway" {
  type    = string
  default = "192.168.1.1"
}

variable "talos_cp_01_ip_addr" {
  type    = string
  default = "REDACTED_IP0"
}

variable "talos_worker_01_ip_addr" {
  type    = string
  default = "REDACTED_IP1"
}

variable "talos_worker_02_ip_addr" {
  type    = string
  default = "REDACTED_IP2"
}

variable "skip_cluster_health" {
  description = "Skip Talos cluster health checks (useful during destroy)"
  type        = bool
  default     = false
}
