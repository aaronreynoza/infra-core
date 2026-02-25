# TrueNAS Module Variables

variable "proxmox_node" {
  description = "Name of the Proxmox node to create the TrueNAS VM on"
  type        = string
}

variable "proxmox_host" {
  description = "Proxmox host IP or hostname (used for SSH to attach passthrough disks)"
  type        = string
}

variable "proxmox_ssh_user" {
  description = "SSH user for Proxmox host"
  type        = string
  default     = "root"
}

variable "vm_name" {
  description = "Name of the TrueNAS VM"
  type        = string
  default     = "truenas"
}

variable "vm_id" {
  description = "VM ID for TrueNAS"
  type        = number
  default     = 101

  validation {
    condition     = var.vm_id >= 100 && var.vm_id <= 999999999
    error_message = "VM ID must be between 100 and 999999999."
  }
}

variable "cpu_cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 4

  validation {
    condition     = var.cpu_cores >= 2 && var.cpu_cores <= 32
    error_message = "CPU cores must be between 2 and 32."
  }
}

variable "memory_mb" {
  description = "Memory in MB (16384 recommended minimum for ZFS)"
  type        = number
  default     = 16384

  validation {
    condition     = var.memory_mb >= 8192
    error_message = "Memory must be at least 8192 MB (8 GB) for TrueNAS with ZFS."
  }
}

variable "boot_disk_size_gb" {
  description = "Boot disk size in GB (TrueNAS OS only, not data)"
  type        = number
  default     = 32

  validation {
    condition     = var.boot_disk_size_gb >= 16
    error_message = "Boot disk must be at least 16 GB."
  }
}

variable "passthrough_disks" {
  description = "List of physical disk paths (/dev/disk/by-id/...) to pass through for ZFS pool"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for disk in var.passthrough_disks : can(regex("^/dev/disk/by-id/", disk))])
    error_message = "Passthrough disks must use /dev/disk/by-id/ paths for stability."
  }
}

# Storage
variable "datastore_id" {
  description = "Datastore ID for boot disk"
  type        = string
  default     = "local-lvm"
}

variable "iso_datastore_id" {
  description = "Datastore ID for ISO storage (must support ISO files)"
  type        = string
  default     = "local"
}

# ISO
variable "truenas_iso_url" {
  description = "URL to download TrueNAS SCALE ISO"
  type        = string
  default     = "https://download.truenas.com/TrueNAS-SCALE-Goldeye/25.10.1/TrueNAS-SCALE-25.10.1.iso"
}

variable "truenas_iso_filename" {
  description = "Filename for the downloaded TrueNAS ISO"
  type        = string
  default     = "TrueNAS-SCALE-25.10.1.iso"
}

# Network
variable "network_bridge" {
  description = "Network bridge for TrueNAS interface"
  type        = string
  default     = "vmbr0"
}

variable "vlan_id" {
  description = "VLAN ID for TrueNAS (e.g., 10 for prod)"
  type        = number

  validation {
    condition     = var.vlan_id >= 1 && var.vlan_id <= 4094
    error_message = "VLAN ID must be between 1 and 4094."
  }
}

# Lifecycle
variable "start_on_boot" {
  description = "Start VM when Proxmox host boots"
  type        = bool
  default     = true
}

variable "start_vm" {
  description = "Start the VM after creation"
  type        = bool
  default     = true
}

variable "boot_order" {
  description = "Boot order (comma-separated device IDs, e.g. 'ide3,scsi0' for CD-ROM install, 'scsi0' for disk-only after install)"
  type        = string
  default     = "ide3,scsi0"
}
