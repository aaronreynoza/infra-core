# Network Infrastructure Variables
# Values provided via environments/network/terraform.tfvars

# Proxmox connection
variable "proxmox_host" {
  description = "Proxmox host IP or hostname"
  type        = string
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
}

variable "proxmox_insecure" {
  description = "Skip TLS verification for Proxmox API"
  type        = bool
  default     = true
}

variable "proxmox_ssh_user" {
  description = "SSH user for Proxmox operations"
  type        = string
  default     = "root"
}

# OPNSense VM configuration
variable "opnsense_vm_id" {
  description = "VM ID for OPNSense"
  type        = number
  default     = 100
}

variable "opnsense_vm_name" {
  description = "Name of the OPNSense VM"
  type        = string
  default     = "opnsense"
}

variable "opnsense_cpu_cores" {
  description = "Number of CPU cores for OPNSense"
  type        = number
  default     = 2
}

variable "opnsense_memory_mb" {
  description = "Memory in MB for OPNSense"
  type        = number
  default     = 4096
}

variable "opnsense_disk_size_gb" {
  description = "Disk size in GB for OPNSense"
  type        = number
  default     = 32
}

# Storage
variable "datastore_id" {
  description = "Datastore ID for VM disk"
  type        = string
  default     = "local-lvm"
}

variable "iso_datastore_id" {
  description = "Datastore ID for ISO storage"
  type        = string
  default     = "local"
}

# Network bridges
variable "wan_bridge" {
  description = "Network bridge for WAN interface"
  type        = string
  default     = "vmbr0"
}

variable "lan_bridge" {
  description = "Network bridge for LAN interface (VLAN trunk)"
  type        = string
  default     = "vmbr0"
}

# OPNSense ISO
variable "opnsense_iso_url" {
  description = "URL to download OPNSense ISO"
  type        = string
  default     = "https://mirror.ams1.nl.leaseweb.net/opnsense/releases/24.7/OPNsense-24.7-dvd-amd64.iso.bz2"
}

variable "opnsense_iso_filename" {
  description = "Filename for the OPNSense ISO"
  type        = string
  default     = "OPNsense-24.7-dvd-amd64.iso"
}

variable "boot_order" {
  description = "Boot order for OPNSense VM (comma-separated device IDs, e.g. 'ide3,virtio0' for CD-ROM install, 'virtio0' for disk-only after install)"
  type        = string
  default     = "ide3,virtio0"
}

# TrueNAS VM configuration
variable "truenas_vm_id" {
  description = "VM ID for TrueNAS"
  type        = number
  default     = 101
}

variable "truenas_vm_name" {
  description = "Name of the TrueNAS VM"
  type        = string
  default     = "truenas"
}

variable "truenas_cpu_cores" {
  description = "Number of CPU cores for TrueNAS"
  type        = number
  default     = 4
}

variable "truenas_memory_mb" {
  description = "Memory in MB for TrueNAS (16384 recommended for ZFS)"
  type        = number
  default     = 16384
}

variable "truenas_boot_disk_size_gb" {
  description = "Boot disk size in GB for TrueNAS (OS only)"
  type        = number
  default     = 32
}

variable "truenas_passthrough_disks" {
  description = "Physical disk paths (/dev/disk/by-id/...) to pass through for ZFS pool"
  type        = list(string)
  default     = []
}

variable "truenas_vlan_id" {
  description = "VLAN ID for TrueNAS network"
  type        = number
  default     = 10
}

variable "truenas_iso_url" {
  description = "URL to download TrueNAS SCALE ISO"
  type        = string
  default     = "https://download.truenas.com/TrueNAS-SCALE-Goldeye/25.10.1/TrueNAS-SCALE-25.10.1.iso"
}

variable "truenas_iso_filename" {
  description = "Filename for the TrueNAS ISO"
  type        = string
  default     = "TrueNAS-SCALE-25.10.1.iso"
}

variable "truenas_boot_order" {
  description = "Boot order for TrueNAS VM (e.g. 'ide3,scsi0' for CD-ROM install, 'scsi0' for disk-only after install)"
  type        = string
  default     = "ide3,scsi0"
}
