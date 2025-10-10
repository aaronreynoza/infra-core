# Terraform Backend + AWS OIDC (GitHub Actions)

This repo uses **AWS S3** for Terraform state, **DynamoDB** for state locks, and **GitHub OIDC** for short-lived AWS creds in CI (no static keys on the runner).

Nothing here hardcodes your AWS Account ID, bucket, or repo—`runner/aws-setup.sh` discovers them at runtime and renders IAM policies from templates in this folder.

## Repo configuration

### Repository **Variables** (non-secret)
- `AWS_REGION` — e.g., `us-east-2`
- `TF_BACKEND_BUCKET` — e.g., `myorg-homelab-tfstate-<rand>`
- `TF_BACKEND_TABLE` — e.g., `tfstate-locks`
- `TF_BACKEND_PREFIX` — e.g., `lab`
- `AWS_ROLE_ARN` — set **after** running `runner/aws-setup.sh` (the script prints it)

### Repository **Secrets** (Proxmox auth)
- `PROXMOX_URL` — e.g., `https://<pve-host>:8006/api2/json`
- `PROXMOX_USERNAME` — e.g., `root@pam`
- `PROXMOX_PASSWORD`
- `PROXMOX_NODE` — e.g., `pve`
- Optional: `PROXMOX_STORAGE` (default `local-lvm`), `PROXMOX_BRIDGE` (default `vmbr0`)

> No AWS secrets are needed when using OIDC.

## One-time AWS bootstrap

Run on any machine with AWS CLI auth (MFA/session recommended):

```bash
export ORG="your-github-org-or-user"
export REPO="your-repo-name"
export REGION="us-east-2"
# optionally:
# export BUCKET="myorg-homelab-tfstate-abc123"
# export TABLE="tfstate-locks"
# export ROLE_NAME="github-oidc-terraform"

bash runner/aws-setup.sh
