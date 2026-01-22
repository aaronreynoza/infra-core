# Network Infrastructure
# Deploys OPNSense firewall/router for VLAN routing
#
# This should be deployed BEFORE prod/dev clusters.
# OPNSense provides VLAN gateway, DHCP, DNS, and firewall.
#
# Credentials are fetched from AWS Secrets Manager - no secrets in code.

terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket         = "homelab-terraform-state-REDACTED_ACCOUNT_ID"
    key            = "network/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "homelab-terraform-locks"
    encrypt        = true
  }

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.78.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# AWS provider for fetching secrets
provider "aws" {
  region = "us-east-1"
}

# Fetch Proxmox credentials from Secrets Manager
data "aws_secretsmanager_secret_version" "proxmox" {
  secret_id = "homelab/proxmox"
}

locals {
  proxmox_creds = jsondecode(data.aws_secretsmanager_secret_version.proxmox.secret_string)
}

provider "proxmox" {
  endpoint  = "https://${var.proxmox_host}:8006/"
  insecure  = var.proxmox_insecure
  api_token = "${local.proxmox_creds.api_token_id}=${local.proxmox_creds.api_token_secret}"

  ssh {
    agent    = true
    username = var.proxmox_ssh_user
  }
}

# OPNSense Firewall/Router
module "opnsense" {
  source = "../../modules/opnsense"

  proxmox_node = var.proxmox_node

  # VM configuration
  vm_id        = var.opnsense_vm_id
  vm_name      = var.opnsense_vm_name
  cpu_cores    = var.opnsense_cpu_cores
  memory_mb    = var.opnsense_memory_mb
  disk_size_gb = var.opnsense_disk_size_gb

  # Storage
  datastore_id     = var.datastore_id
  iso_datastore_id = var.iso_datastore_id

  # Network - both NICs on same bridge, OPNSense handles VLAN tagging
  wan_bridge = var.wan_bridge
  lan_bridge = var.lan_bridge

  # ISO
  opnsense_iso_url      = var.opnsense_iso_url
  opnsense_iso_filename = var.opnsense_iso_filename

  # Start VM after creation for installation
  start_vm      = true
  start_on_boot = true

  # Boot from CD-ROM first for initial installation
  boot_order = "cdn"
}
