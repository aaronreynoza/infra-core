# Infrastructure and Terraform

This document explains the infrastructure architecture and how Terraform is used to provision and manage the homelab environment.

## Overview

The homelab infrastructure runs on Proxmox VE and uses Talos Linux as the Kubernetes cluster operating system. Terraform provisions all virtual machines and bootstraps the Kubernetes clusters.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Proxmox VE Host                          │
│                                                                 │
│  ┌─────────────────────────┐  ┌─────────────────────────┐      │
│  │   VLAN 10 (Production)  │  │   VLAN 11 (Development) │      │
│  │      10.10.10.0/16      │  │      10.11.10.0/16      │      │
│  │                         │  │                         │      │
│  │  ┌─────────────────┐    │  │  ┌─────────────────┐    │      │
│  │  │ prod-cp-01      │    │  │  │ dev-cp-01       │    │      │
│  │  │ prod-cp-02      │    │  │  │ dev-cp-02       │    │      │
│  │  │ (Control Plane) │    │  │  │ (Control Plane) │    │      │
│  │  └─────────────────┘    │  │  └─────────────────┘    │      │
│  │                         │  │                         │      │
│  │  ┌─────────────────┐    │  │  ┌─────────────────┐    │      │
│  │  │ prod-wk-01      │    │  │  │ dev-wk-01       │    │      │
│  │  │ prod-wk-02      │    │  │  │ dev-wk-02       │    │      │
│  │  │ (Workers)       │    │  │  │ (Workers)       │    │      │
│  │  └─────────────────┘    │  │  └─────────────────┘    │      │
│  └─────────────────────────┘  └─────────────────────────┘      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Terraform Structure

### Directory Layout

```
homelab/
├── core/terraform/modules/      # Reusable modules
│   ├── talos-cluster/          # Complete Talos K8s cluster
│   ├── proxmox-vm/             # Generic VM provisioning
│   └── aws-backend/            # S3 + DynamoDB for state
│
└── environments/
    ├── prod/terraform/         # Production configuration
    └── dev/terraform/          # Development configuration
```

### Modules

#### talos-cluster

The main module that provisions a complete Talos Linux Kubernetes cluster.

**Features:**
- Downloads Talos image to Proxmox automatically
- Creates control plane and worker VMs
- Configures Talos machine secrets
- Applies machine configurations with patches
- Bootstraps the cluster
- Exports kubeconfig and talosconfig

**Key Variables:**
```hcl
variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
}

variable "control_planes" {
  description = "List of control plane nodes"
  type = list(object({
    name       = string
    vm_id      = number
    ip_address = string
  }))
}

variable "workers" {
  description = "List of worker nodes"
  type = list(object({
    name       = string
    vm_id      = number
    ip_address = string
  }))
}
```

**Outputs:**
- `kubeconfig` - Kubernetes configuration (sensitive)
- `talosconfig` - Talos client configuration (sensitive)
- `cluster_endpoint` - Kubernetes API endpoint
- `control_plane_ips` - List of control plane IPs
- `worker_ips` - List of worker IPs

#### proxmox-vm

A generic module for provisioning VMs on Proxmox VE.

**Features:**
- Creates multiple VMs using `for_each`
- Supports VLAN tagging
- Configurable CPU, memory, and disk sizes
- Optional data disk for storage workloads
- Static IP configuration via cloud-init

**Usage:**
```hcl
module "workers" {
  source = "../proxmox-vm"

  proxmox_node      = "pve"
  boot_datastore_id = "local-lvm"
  boot_image_id     = proxmox_virtual_environment_download_file.talos_image.id
  network_bridge    = "vmbr0"
  gateway           = "10.10.10.1"

  vms = [
    {
      name         = "prod-wk-01"
      vm_id        = 510
      ip_address   = "10.10.10.20"
      cpu_cores    = 8
      memory_mb    = 32768
      boot_disk_gb = 50
      data_disk_gb = 500
      vlan_id      = 10
    }
  ]
}
```

#### aws-backend

Creates AWS resources for Terraform state management.

**Resources Created:**
- S3 bucket with versioning and encryption
- DynamoDB table for state locking
- Public access blocking on S3

## Environment Configuration

Each environment (prod/dev) has its own Terraform configuration that consumes the core modules.

### Production Example

```hcl
# environments/prod/terraform/main.tf

module "cluster" {
  source = "../../../core/terraform/modules/talos-cluster"

  cluster_name    = "homelab-prod"
  proxmox_node    = "pve"
  talos_image_url = "https://factory.talos.dev/image/..."

  control_planes = [
    { name = "prod-cp-01", vm_id = 500, ip_address = "10.10.10.10" },
    { name = "prod-cp-02", vm_id = 501, ip_address = "10.10.10.11" }
  ]

  workers = [
    { name = "prod-wk-01", vm_id = 510, ip_address = "10.10.10.20" },
    { name = "prod-wk-02", vm_id = 511, ip_address = "10.10.10.21" }
  ]

  gateway = "10.10.10.1"
  vlan_id = 10
}
```

### State Management

Terraform state is stored in AWS S3 with DynamoDB locking:

```hcl
terraform {
  backend "s3" {
    bucket         = "homelab-terraform-state"
    key            = "prod/infra.tfstate"  # or "dev/infra.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

**Benefits:**
- Remote state enables team collaboration
- State locking prevents concurrent modifications
- Versioning allows state recovery
- Encryption protects sensitive data

## Resource Specifications

### Control Plane Nodes

| Resource | Production | Development |
|----------|------------|-------------|
| CPU Cores | 4 | 4 |
| Memory | 8 GB | 8 GB |
| Boot Disk | 50 GB | 50 GB |
| Count | 2 | 2 |

### Worker Nodes

| Resource | Production | Development |
|----------|------------|-------------|
| CPU Cores | 8 | 8 |
| Memory | 32 GB | 32 GB |
| Boot Disk | 50 GB | 50 GB |
| Data Disk | 500 GB | 500 GB |
| Count | 2 | 2 |

## Talos Linux Configuration

Talos is configured with patches applied during provisioning:

### CNI Configuration
```yaml
cluster:
  network:
    cni:
      name: none  # Cilium will be installed via ArgoCD
  proxy:
    disabled: true  # Cilium replaces kube-proxy
```

### Longhorn Storage
```yaml
apiVersion: v1alpha1
kind: UserVolumeConfig
name: longhorn
provisioning:
  diskSelector:
    match: "disk.dev_path == '/dev/vdb' && !system_disk"
  minSize: "300GiB"
  grow: true
```

## Commands

```bash
# Initialize Terraform (first time)
cd environments/prod/terraform
terraform init

# Plan changes
terraform plan

# Apply changes
terraform apply

# Export kubeconfig
terraform output -raw kubeconfig > ~/.kube/config

# Export talosconfig
terraform output -raw talosconfig > ~/.talos/config

# Destroy environment (use with caution)
terraform destroy
```

## Best Practices

1. **Always plan before apply** - Review changes before applying
2. **Use workspaces or separate state** - Keep prod and dev state separate
3. **Pin provider versions** - Avoid unexpected breaking changes
4. **Protect sensitive outputs** - Mark kubeconfig/talosconfig as sensitive
5. **Use variables** - Don't hardcode values in modules
6. **Validate inputs** - Add validation blocks to catch errors early
