# OPNSense Module Variables

variable "proxmox_node" {
  description = "Name of the Proxmox node to create the OPNSense VM on"
  type        = string
}

variable "vm_name" {
  description = "Name of the OPNSense VM"
  type        = string
  default     = "opnsense"
}

variable "vm_id" {
  description = "VM ID for OPNSense"
  type        = number
  default     = 100

  validation {
    condition     = var.vm_id >= 100 && var.vm_id <= 999999999
    error_message = "VM ID must be between 100 and 999999999."
  }
}

variable "cpu_cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 2

  validation {
    condition     = var.cpu_cores >= 1 && var.cpu_cores <= 16
    error_message = "CPU cores must be between 1 and 16."
  }
}

variable "memory_mb" {
  description = "Memory in MB"
  type        = number
  default     = 4096

  validation {
    condition     = var.memory_mb >= 1024
    error_message = "Memory must be at least 1024 MB."
  }
}

variable "disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 32

  validation {
    condition     = var.disk_size_gb >= 8
    error_message = "Disk size must be at least 8 GB."
  }
}

variable "datastore_id" {
  description = "Datastore ID for VM disk"
  type        = string
  default     = "local-lvm"
}

variable "iso_datastore_id" {
  description = "Datastore ID for ISO storage (must support ISO files)"
  type        = string
  default     = "local"
}

variable "opnsense_iso_url" {
  description = "URL to download OPNSense ISO"
  type        = string
  default     = "https://mirror.ams1.nl.leaseweb.net/opnsense/releases/24.7/OPNsense-24.7-dvd-amd64.iso.bz2"
}

variable "opnsense_iso_filename" {
  description = "Filename for the downloaded ISO"
  type        = string
  default     = "OPNsense-24.7-dvd-amd64.iso"
}

# Network configuration
variable "wan_bridge" {
  description = "Network bridge for WAN interface (connects to ISP)"
  type        = string
  default     = "vmbr0"
}

variable "wan_vlan_id" {
  description = "VLAN ID for WAN interface (null for untagged/native)"
  type        = number
  default     = null
}

variable "lan_bridge" {
  description = "Network bridge for LAN interface (VLAN trunk)"
  type        = string
  default     = "vmbr0"
}

variable "lan_vlan_id" {
  description = "VLAN ID for LAN interface (null for trunk mode - OPNSense handles VLAN tagging)"
  type        = number
  default     = null
}

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
  description = "Boot order (comma-separated device IDs, e.g. ide3,virtio0)"
  type        = string
  default     = "ide3,virtio0"
}
