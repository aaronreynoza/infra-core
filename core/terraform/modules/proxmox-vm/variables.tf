variable "proxmox_node" {
  description = "Name of the Proxmox node to create VMs on"
  type        = string
}

variable "vms" {
  description = "List of VMs to create"
  type = list(object({
    name         = string
    vm_id        = number
    ip_address   = string
    cpu_cores    = number
    memory_mb    = number
    boot_disk_gb = number
    data_disk_gb = optional(number)
    vlan_id      = optional(number)
  }))

  validation {
    condition     = length(var.vms) > 0
    error_message = "At least one VM must be specified."
  }

  validation {
    condition     = alltrue([for vm in var.vms : vm.vm_id >= 100 && vm.vm_id <= 999999999])
    error_message = "VM IDs must be between 100 and 999999999."
  }

  validation {
    condition     = alltrue([for vm in var.vms : vm.cpu_cores >= 1 && vm.cpu_cores <= 128])
    error_message = "CPU cores must be between 1 and 128."
  }

  validation {
    condition     = alltrue([for vm in var.vms : vm.memory_mb >= 512])
    error_message = "Memory must be at least 512 MB."
  }
}

variable "boot_datastore_id" {
  description = "Datastore ID for boot disks (block storage like LVM-thin or ZFS)"
  type        = string
  default     = "local-lvm"
}

variable "data_datastore_id" {
  description = "Datastore ID for data disks"
  type        = string
  default     = "local-lvm"
}

variable "boot_image_id" {
  description = "ID of the boot image (e.g., from proxmox_virtual_environment_download_file)"
  type        = string
}

variable "network_bridge" {
  description = "Network bridge to attach VMs to"
  type        = string
  default     = "vmbr0"
}

variable "network_cidr" {
  description = "Network CIDR prefix length (e.g., 24 for /24)"
  type        = number
  default     = 24

  validation {
    condition     = var.network_cidr >= 8 && var.network_cidr <= 32
    error_message = "Network CIDR must be between 8 and 32."
  }
}

variable "gateway" {
  description = "Default gateway IP address"
  type        = string

  validation {
    condition     = can(regex("^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$", var.gateway))
    error_message = "Gateway must be a valid IPv4 address."
  }
}

variable "cpu_sockets" {
  description = "Number of CPU sockets"
  type        = number
  default     = 1
}

variable "cpu_type" {
  description = "CPU type (e.g., host, kvm64)"
  type        = string
  default     = "host"
}

variable "qemu_agent_enabled" {
  description = "Enable QEMU guest agent"
  type        = bool
  default     = true
}

variable "start_on_boot" {
  description = "Start VM when Proxmox host boots"
  type        = bool
  default     = true
}
