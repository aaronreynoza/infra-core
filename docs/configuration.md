# Configuration Guide

This repo is a **library** of reusable Terraform modules, Helm charts, and documentation. Your environment-specific configuration (IPs, hostnames, secrets, backend config) lives in a separate private `environments/` directory.

## Architecture

```
homelab/              (this repo — public, reusable)
├── core/             # Terraform modules, Helm charts, Ansible
├── docs/             # Documentation
└── .gitignore        # Excludes environments/

environments/         (your private config — gitignored, eventually its own repo)
├── .sops.yaml            # SOPS encryption rules + age public key
├── bootstrap/
│   ├── backend.hcl
│   └── terraform.tfvars
├── network/
│   ├── backend.hcl
│   ├── terraform.tfvars
│   ├── opnsense-backups/
│   └── docs/             # Private runbooks with real IPs
├── prod/
│   ├── backend.hcl
│   ├── terraform.tfvars
│   └── secrets/          # SOPS-encrypted secret files
│       ├── proxmox-creds.yaml
│       └── newt-credentials.yaml
└── dev/
    ├── backend.hcl
    ├── terraform.tfvars
    └── secrets/          # SOPS-encrypted secret files
```

---

## Setting Up Your Environments

### 1. Create the directory structure

```bash
mkdir -p environments/{bootstrap,network,prod,dev}
```

### 2. Configure Terraform backends

Each environment needs a `backend.hcl` file for S3 remote state. Create one per environment:

**`environments/network/backend.hcl`**
```hcl
bucket         = "your-terraform-state-bucket"
key            = "network/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "your-terraform-locks-table"
encrypt        = true
```

**`environments/bootstrap/backend.hcl`**
```hcl
bucket         = "your-terraform-state-bucket"
key            = "bootstrap/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "your-terraform-locks-table"
encrypt        = true
```

Repeat for `prod/` and `dev/` with unique `key` values.

### 3. Configure Terraform variables

Each environment needs a `terraform.tfvars` file. Below are the variables for each configuration.

---

## Network Environment (`environments/network/terraform.tfvars`)

Deploys the OPNSense firewall/router VM.

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `proxmox_host` | string | — | Proxmox host IP or hostname |
| `proxmox_node` | string | — | Proxmox node name |
| `proxmox_insecure` | bool | `true` | Skip TLS verification for Proxmox API |
| `proxmox_ssh_user` | string | `"root"` | SSH user for Proxmox operations |
| `opnsense_vm_id` | number | `100` | VM ID for OPNSense |
| `opnsense_vm_name` | string | `"opnsense"` | Name of the OPNSense VM |
| `opnsense_cpu_cores` | number | `2` | CPU cores for OPNSense |
| `opnsense_memory_mb` | number | `4096` | Memory in MB for OPNSense |
| `opnsense_disk_size_gb` | number | `32` | Disk size in GB |
| `datastore_id` | string | `"local-lvm"` | Proxmox datastore for VM disk |
| `iso_datastore_id` | string | `"local"` | Proxmox datastore for ISO storage |
| `wan_bridge` | string | `"vmbr0"` | Network bridge for WAN interface |
| `lan_bridge` | string | `"vmbr0"` | Network bridge for LAN interface (VLAN trunk) |
| `opnsense_iso_url` | string | *(24.7 mirror)* | URL to download OPNSense ISO |
| `opnsense_iso_filename` | string | `"OPNsense-24.7-dvd-amd64.iso"` | Filename for the OPNSense ISO |
| `boot_order` | string | `"ide3,virtio0"` | Boot device order (use `"virtio0"` after install) |

**Example:**
```hcl
proxmox_host     = "REDACTED_MGMT_IP0"
proxmox_node     = "pve"
proxmox_insecure = true
proxmox_ssh_user = "root"

opnsense_vm_id        = 100
opnsense_vm_name      = "opnsense"
opnsense_cpu_cores    = 2
opnsense_memory_mb    = 4096
opnsense_disk_size_gb = 32

datastore_id     = "local-lvm"
iso_datastore_id = "local"

wan_bridge = "vmbr1"
lan_bridge = "vmbr0"
```

## Bootstrap Environment (`environments/bootstrap/terraform.tfvars`)

Creates AWS resources for Terraform state management (S3 bucket + DynamoDB table).

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `aws_region` | string | `"us-east-1"` | AWS region for resources |
| `bucket_name` | string | — | S3 bucket name for Terraform state |
| `dynamodb_table_name` | string | `"homelab-terraform-locks"` | DynamoDB table for state locking |
| `tags` | map(string) | *(project defaults)* | Tags to apply to AWS resources |

**Example:**
```hcl
bucket_name         = "mylab-terraform-state"
dynamodb_table_name = "mylab-terraform-locks"
```

---

## Running Terraform

### Initialize with backend config

```bash
# Network
cd core/terraform/live/network
terraform init -backend-config=../../../../environments/network/backend.hcl

# Bootstrap
cd core/terraform/bootstrap
terraform init -backend-config=../../../environments/bootstrap/backend.hcl
```

### Plan and apply with variable file

```bash
# Network
cd core/terraform/live/network
terraform plan -var-file=../../../../environments/network/terraform.tfvars
terraform apply -var-file=../../../../environments/network/terraform.tfvars

# Bootstrap
cd core/terraform/bootstrap
terraform plan -var-file=../../../environments/bootstrap/terraform.tfvars
terraform apply -var-file=../../../environments/bootstrap/terraform.tfvars
```

---

## Secrets Management (SOPS + age)

Secrets are encrypted with [SOPS](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age) and stored in `environments/<env>/secrets/`. See [ADR-004](decisions/004-sops-secrets-management.md) for rationale.

### Setup

```bash
# Install tools
brew install sops age

# Generate age keypair (one-time)
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt

# Add to shell profile (~/.zshrc)
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
```

Copy the public key from the keygen output into `environments/.sops.yaml`.

### Usage

```bash
cd environments

# Encrypt a new secret file
sops -e -i prod/secrets/my-secret.yaml

# Edit an encrypted file (decrypts in $EDITOR, re-encrypts on save)
sops prod/secrets/my-secret.yaml

# View decrypted contents
sops -d prod/secrets/my-secret.yaml
```

### How Terraform uses secrets

Terraform reads encrypted files via the `carlpett/sops` provider:

```hcl
data "sops_file" "proxmox_creds" {
  source_file = "${path.module}/../secrets/proxmox-creds.yaml"
}

# Use: data.sops_file.proxmox_creds.data["api_token_id"]
```

For Kubernetes secrets, Terraform creates them directly:

```hcl
resource "kubernetes_secret" "newt_credentials" {
  metadata {
    name      = "newt-credentials"
    namespace = "newt"
  }
  data = {
    NEWT_ID     = data.sops_file.newt_creds.data["NEWT_ID"]
    NEWT_SECRET = data.sops_file.newt_creds.data["NEWT_SECRET"]
  }
}
```

ArgoCD apps reference the pre-existing secret via `existingSecretName`.

### Key backup

Back up `~/.config/sops/age/keys.txt` securely (password manager, USB drive). If lost, secrets cannot be decrypted.

---

## Prerequisites

- **SOPS + age** installed and configured (see above)
- **AWS credentials** configured (`aws configure`) for S3 backend only
- **Proxmox** host accessible from your workstation
- **Terraform** >= 1.9.0

---

## Splitting into a Separate Repo

Eventually, `environments/` can become its own private Git repository:

```bash
cd environments
git init
git remote add origin git@github.com:youruser/homelab-config.git
git add -A && git commit -m "Initial environments config"
git push -u origin main
```

Then clone it alongside this repo and symlink or reference via relative paths.
