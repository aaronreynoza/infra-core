# Initial Setup Runbook

**Purpose**: Manual steps to set up the homelab infrastructure from scratch.

---

## Prerequisites

- AWS CLI configured (`aws configure`)
- SSH key for Proxmox access
- Proxmox API token created

---

## 1. Verify Prerequisites

```bash
# Check AWS CLI
aws sts get-caller-identity

# Check SSH agent has key loaded
ssh-add -l

# If no key loaded:
ssh-add ~/.ssh/id_ed25519

# Verify Proxmox is reachable
curl -sk https://<PROXMOX_IP>:8006/api2/json/version
# 401 = reachable (auth required, expected)
```

---

## 2. Create Terraform Backend (One-Time)

```bash
cd core/terraform/bootstrap
terraform init
terraform apply
```

This creates:
- S3 bucket: `homelab-terraform-state-<account-id>`
- DynamoDB table: `homelab-terraform-locks`

State is automatically migrated to S3 (see `terraform-backend-setup.md`).

---

## 3. Create Proxmox API Token

In Proxmox UI (`https://<PROXMOX_IP>:8006`):

1. Go to **Datacenter → Permissions → API Tokens**
2. Click **Add**
3. Fill in:
   - **User**: `root@pam`
   - **Token ID**: `terraform`
   - **Privilege Separation**: **Uncheck** (full permissions)
4. Click **Add**
5. **Copy the token secret** (shown only once!)

Token format: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`

---

## 4. Store Credentials in AWS Secrets Manager

```bash
# Create the secret (first time only)
aws secretsmanager create-secret \
  --name "homelab/proxmox" \
  --description "Proxmox VE API credentials" \
  --secret-string '{"api_token_id": "root@pam!terraform", "api_token_secret": "YOUR_TOKEN_HERE"}' \
  --region us-east-1

# Update existing secret (if already created)
aws secretsmanager put-secret-value \
  --secret-id "homelab/proxmox" \
  --secret-string '{"api_token_id": "root@pam!terraform", "api_token_secret": "YOUR_TOKEN_HERE"}' \
  --region us-east-1

# Verify secret exists
aws secretsmanager get-secret-value --secret-id "homelab/proxmox" --region us-east-1
```

---

## 5. Deploy Network Infrastructure (OPNSense)

```bash
cd core/terraform/live/network

# Initialize
terraform init

# Plan (verify what will be created)
terraform plan -var-file=../../../../environments/network/terraform.tfvars

# Apply
terraform apply -var-file=../../../../environments/network/terraform.tfvars
```

After apply, complete OPNSense installation manually (see `docs/04-opnsense.md`).

---

## 6. Verify Deployment

```bash
# Check S3 has state files
aws s3 ls s3://homelab-terraform-state-<account-id>/ --recursive

# Expected:
# bootstrap/terraform.tfstate
# network/terraform.tfstate
```

---

## Environment-Specific tfvars

Configuration files are in `environments/<env>/terraform.tfvars`:

| Environment | File | Purpose |
|-------------|------|---------|
| network | `environments/network/terraform.tfvars` | OPNSense firewall |
| prod | `environments/prod/terraform.tfvars` | Production K8s cluster |
| dev | `environments/dev/terraform.tfvars` | Development K8s cluster |

---

## Quick Reference Commands

```bash
# Check AWS identity
aws sts get-caller-identity

# List secrets
aws secretsmanager list-secrets --region us-east-1

# Check terraform state in S3
aws s3 ls s3://homelab-terraform-state-<account-id>/ --recursive

# SSH to Proxmox
ssh root@<PROXMOX_IP>

# Check Proxmox bridges
ssh root@<PROXMOX_IP> "grep vmbr /etc/network/interfaces"
```
