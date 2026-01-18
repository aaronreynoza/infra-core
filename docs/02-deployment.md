# Initial Deployment Process

This document outlines the step-by-step process to deploy the homelab infrastructure from scratch.

## Prerequisites

### Hardware Requirements

- Proxmox VE host(s) with sufficient resources
- Network switch with VLAN support (e.g., NETGEAR GS308EP)
- Router/Firewall capable of VLAN routing (OPNSense VM or dedicated device)

### Software Requirements

- Terraform >= 1.9.0
- Ansible >= 2.15
- talosctl (Talos CLI)
- kubectl
- AWS CLI (for state backend)

### Accounts & Credentials

- Proxmox API token with VM provisioning permissions
- AWS account with S3/DynamoDB access (for Terraform state)
- SSH key pair for Proxmox access

## Deployment Steps

### Phase 1: AWS Backend Setup

Set up the Terraform state backend in AWS.

```bash
# Navigate to runner setup directory
cd runner

# Run the AWS setup script
./aws-setup.sh

# This creates:
# - S3 bucket for state storage
# - DynamoDB table for state locking
# - IAM role for OIDC authentication
```

**Manual Alternative:**
```bash
# Create S3 bucket
aws s3api create-bucket \
  --bucket homelab-terraform-state \
  --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket homelab-terraform-state \
  --versioning-configuration Status=Enabled

# Create DynamoDB table
aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

### Phase 2: Network Configuration

Before deploying VMs, configure the network infrastructure.

#### 2.1 Proxmox Network

Create a VLAN-aware bridge in Proxmox:

```bash
# Edit /etc/network/interfaces on Proxmox host
auto vmbr0
iface vmbr0 inet static
    address 192.168.1.100/24
    gateway 192.168.1.1
    bridge-ports eno1
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids 2-4094
```

#### 2.2 Switch Configuration

Configure VLANs on your managed switch:
- VLAN 10: Production (10.10.10.0/16)
- VLAN 11: Development (10.11.10.0/16)

See [04-opnsense.md](./04-opnsense.md) for detailed VLAN configuration.

### Phase 3: Environment Configuration

#### 3.1 Create terraform.tfvars

```bash
# For production
cd environments/prod/terraform
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
vim terraform.tfvars
```

**Example terraform.tfvars:**
```hcl
# Proxmox Configuration
proxmox_host = "192.168.1.100"
proxmox_node = "pve"

# Talos Image (get from factory.talos.dev)
talos_image_url = "https://factory.talos.dev/image/YOUR_SCHEMATIC/v1.11.3/nocloud-amd64.raw.xz"

# Optional overrides
# cluster_name = "homelab-prod"
# gateway = "10.10.10.1"
# vlan_id = 10
```

#### 3.2 Set Environment Variables

```bash
# Proxmox credentials
export PROXMOX_VE_ENDPOINT="https://192.168.1.100:8006/api2/json"
export PROXMOX_VE_API_TOKEN="terraform@pve!terraform=your-token-secret"
export PROXMOX_VE_INSECURE="true"  # If using self-signed cert

# AWS credentials (if not using OIDC)
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_REGION="us-east-1"
```

### Phase 4: Deploy Infrastructure

#### 4.1 Initialize Terraform

```bash
cd environments/prod/terraform

# Initialize with backend configuration
terraform init \
  -backend-config="bucket=homelab-terraform-state" \
  -backend-config="key=prod/infra.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=terraform-locks" \
  -backend-config="encrypt=true"
```

#### 4.2 Plan and Apply

```bash
# Review the plan
terraform plan

# Apply (creates VMs and bootstraps cluster)
terraform apply
```

This will:
1. Download Talos image to Proxmox
2. Create control plane VMs
3. Create worker VMs
4. Generate Talos machine secrets
5. Apply Talos configuration to all nodes
6. Bootstrap the Kubernetes cluster
7. Wait for cluster health

#### 4.3 Export Configurations

```bash
# Export kubeconfig
terraform output -raw kubeconfig > kubeconfig.yaml
export KUBECONFIG=$(pwd)/kubeconfig.yaml

# Export talosconfig
terraform output -raw talosconfig > talosconfig.yaml
export TALOSCONFIG=$(pwd)/talosconfig.yaml

# Verify cluster access
kubectl get nodes
talosctl health
```

### Phase 5: Deploy Platform Components

#### 5.1 Install ArgoCD

```bash
cd ../../../core/ansible

# Update inventory with kubeconfig path
vim inventories/local/hosts.ini

# Install ArgoCD
ansible-playbook -i inventories/local/hosts.ini playbooks/install-argocd.yml
```

#### 5.2 Deploy Applications via GitOps

```bash
# Apply the root application (app-of-apps pattern)
ansible-playbook -i inventories/local/hosts.ini playbooks/install-apps.yml

# This deploys:
# - Cilium (CNI)
# - Longhorn (Storage)
# - Any other enabled applications
```

#### 5.3 Verify Deployment

```bash
# Check ArgoCD applications
kubectl get applications -n argocd

# Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

### Phase 6: Post-Deployment Tasks

#### 6.1 Configure DNS

Add DNS records for your services (either in OPNSense or external DNS).

#### 6.2 Set Up Backups

Configure Velero for cluster backups (see [05-security.md](./05-security.md)).

#### 6.3 Enable Monitoring

Deploy the Grafana stack when ready:
1. Update `core/charts/defaults.yaml` to enable Grafana
2. Create ArgoCD Application for Grafana in your environment

## Deployment Order Summary

```
1. AWS Backend (S3 + DynamoDB)
2. Network (Proxmox bridge, Switch VLANs, OPNSense)
3. Terraform Configuration (terraform.tfvars)
4. Infrastructure (terraform apply)
5. ArgoCD Installation (Ansible)
6. Platform Applications (GitOps via ArgoCD)
7. Post-deployment (DNS, Backups, Monitoring)
```

## Deploying Development Environment

Repeat Phases 3-6 for the dev environment:

```bash
cd environments/dev/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with dev-specific values

terraform init \
  -backend-config="bucket=homelab-terraform-state" \
  -backend-config="key=dev/infra.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=terraform-locks"

terraform plan
terraform apply
```

## Troubleshooting

### Terraform Apply Fails

```bash
# Check Proxmox connectivity
curl -k https://192.168.1.100:8006/api2/json/version

# Verify API token
curl -k -H "Authorization: PVEAPIToken=terraform@pve!terraform=xxx" \
  https://192.168.1.100:8006/api2/json/version
```

### Talos Bootstrap Fails

```bash
# Check node status
talosctl -n 10.10.10.10 get members

# View logs
talosctl -n 10.10.10.10 logs controller-runtime

# Reset and retry
talosctl -n 10.10.10.10 reset --graceful=false
```

### Cluster Not Healthy

```bash
# Check all node health
talosctl health --nodes 10.10.10.10,10.10.10.11,10.10.10.20,10.10.10.21

# Check etcd status
talosctl -n 10.10.10.10 etcd status

# Check kubelet
talosctl -n 10.10.10.20 service kubelet
```

### ArgoCD Applications Not Syncing

```bash
# Check application status
kubectl get applications -n argocd

# View sync details
kubectl describe application cilium -n argocd

# Force sync
argocd app sync cilium
```

## Destroying the Environment

```bash
# Destroy infrastructure (WARNING: destructive)
cd environments/prod/terraform
terraform destroy

# Optionally clean up AWS backend
aws s3 rb s3://homelab-terraform-state --force
aws dynamodb delete-table --table-name terraform-locks
```

## Next Steps

After successful deployment:
1. Review [03-ansible.md](./03-ansible.md) for ongoing management
2. Configure OPNSense per [04-opnsense.md](./04-opnsense.md)
3. Review security considerations in [05-security.md](./05-security.md)
