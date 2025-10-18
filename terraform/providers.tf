terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "~> 2.9"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# terraform/providers.tf
provider "proxmox" {
  pm_api_url          = var.proxmox_api_url
  pm_api_token_id     = "packer@pve!packer"       # user@realm!token
  pm_api_token_secret = var.proxmox_api_token_secret

  pm_tls_insecure = true
  pm_parallel     = 2

  # TEMP: debug
  pm_log_enable = true
  pm_log_file   = "proxmox-provider.log"
  pm_debug      = true
}
