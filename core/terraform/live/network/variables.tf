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
