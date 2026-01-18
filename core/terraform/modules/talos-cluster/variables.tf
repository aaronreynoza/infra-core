variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
  default     = "homelab"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.cluster_name))
    error_message = "Cluster name must start with a letter, be lowercase alphanumeric with hyphens, and max 63 characters."
  }
}

variable "proxmox_node" {
  description = "Name of the Proxmox node to deploy to"
  type        = string
}

variable "talos_image_url" {
  description = "URL to download Talos Linux image from"
  type        = string

  validation {
    condition     = can(regex("^https?://", var.talos_image_url))
    error_message = "Talos image URL must be a valid HTTP(S) URL."
  }
}

variable "control_planes" {
  description = "List of control plane nodes"
  type = list(object({
    name       = string
    vm_id      = number
    ip_address = string
  }))

  validation {
    condition     = length(var.control_planes) >= 1
    error_message = "At least one control plane node is required."
  }
}

variable "workers" {
  description = "List of worker nodes"
  type = list(object({
    name       = string
    vm_id      = number
    ip_address = string
  }))

  validation {
    condition     = length(var.workers) >= 1
    error_message = "At least one worker node is required."
  }
}

# Resource sizing
variable "control_plane_cpu_cores" {
  description = "CPU cores for control plane nodes"
  type        = number
  default     = 2
}

variable "control_plane_memory_mb" {
  description = "Memory in MB for control plane nodes"
  type        = number
  default     = 4096
}

variable "control_plane_boot_disk_gb" {
  description = "Boot disk size in GB for control plane nodes"
  type        = number
  default     = 50
}

variable "worker_cpu_cores" {
  description = "CPU cores for worker nodes"
  type        = number
  default     = 4
}

variable "worker_memory_mb" {
  description = "Memory in MB for worker nodes"
  type        = number
  default     = 16384
}

variable "worker_boot_disk_gb" {
  description = "Boot disk size in GB for worker nodes"
  type        = number
  default     = 50
}

variable "worker_data_disk_gb" {
  description = "Data disk size in GB for worker nodes (for Longhorn)"
  type        = number
  default     = 500
}

# Storage
variable "image_datastore_id" {
  description = "Datastore ID for storing the Talos image"
  type        = string
  default     = "local"
}

variable "boot_datastore_id" {
  description = "Datastore ID for VM boot disks"
  type        = string
  default     = "local-lvm"
}

variable "data_datastore_id" {
  description = "Datastore ID for VM data disks"
  type        = string
  default     = "local-lvm"
}

# Network
variable "network_bridge" {
  description = "Proxmox network bridge"
  type        = string
  default     = "vmbr0"
}

variable "network_cidr" {
  description = "Network CIDR prefix length"
  type        = number
  default     = 24
}

variable "gateway" {
  description = "Network gateway IP address"
  type        = string
}

variable "vlan_id" {
  description = "VLAN ID for the cluster network (null for untagged)"
  type        = number
  default     = null
}

# Longhorn configuration
variable "longhorn_min_size_gib" {
  description = "Minimum size for Longhorn volumes in GiB"
  type        = number
  default     = 300
}

variable "longhorn_mount_path" {
  description = "Mount path for Longhorn volumes"
  type        = string
  default     = "/var/mnt/u-longhorn"
}

# Health check
variable "skip_health_check" {
  description = "Skip cluster health check (useful during destroy)"
  type        = bool
  default     = false
}
