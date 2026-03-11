# Prod Talos Cluster Deployment Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy a production Talos K8s cluster on daytona with Longhorn on HDD-backed storage, then bootstrap the platform stack (Cilium, Longhorn, ArgoCD) and configure Pangolin/Newt for public ingress.

**Architecture:** Single Proxmox host (daytona) running 1 control plane + 2 worker VMs on PROD VLAN 10. Boot disks on SSD (local-lvm), Longhorn data disks on HDD (hdd-mirror). Cilium as CNI (replaces kube-proxy), Longhorn for PVs, ArgoCD for GitOps. Pangolin+Newt for public access.

**Tech Stack:** Terraform (bpg/proxmox + siderolabs/talos providers), Talos Linux v1.11.3, Cilium v1.16.5, Longhorn v1.7.2, ArgoCD v7.7.10, Pangolin/Newt

---

## Chunk 1: Terraform Config & Cluster Provisioning

### Task 1: Fix Proxmox Auth in Prod Main.tf

The prod `main.tf` uses `ssh { agent = true }` but lacks API token auth. The network module fetches credentials from AWS Secrets Manager — prod needs the same pattern.

**Files:**
- Modify: `environments/prod/terraform/main.tf`

- [ ] **Step 1: Add AWS provider and secrets lookup to prod main.tf**

Add the AWS provider and secrets manager data source (matching the pattern in `core/terraform/live/network/main.tf`):

```hcl
# After the required_providers block, add aws provider:
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

# Add aws provider block:
provider "aws" {
  region = "us-east-1"
}

# Add secrets fetch:
data "aws_secretsmanager_secret_version" "proxmox" {
  secret_id = "homelab/proxmox"
}

locals {
  proxmox_creds = jsondecode(data.aws_secretsmanager_secret_version.proxmox.secret_string)
}

# Update proxmox provider to use api_token:
provider "proxmox" {
  endpoint  = "https://${var.proxmox_host}:8006/"
  insecure  = var.proxmox_insecure
  api_token = "${local.proxmox_creds.api_token_id}=${local.proxmox_creds.api_token_secret}"

  ssh {
    agent    = true
    username = var.proxmox_ssh_user
  }
}
```

- [ ] **Step 2: Add missing variable for proxmox_ssh_user**

Add to `environments/prod/terraform/variables.tf`:

```hcl
variable "proxmox_ssh_user" {
  description = "SSH username for Proxmox host"
  type        = string
  default     = "root"
}
```

- [ ] **Step 3: Commit**

```bash
git add environments/prod/terraform/main.tf environments/prod/terraform/variables.tf
git commit -m "feat(prod): add AWS secrets manager auth for Proxmox provider"
```

### Task 2: Create Prod Backend Config

**Files:**
- Create: `environments/prod/backend.hcl`

- [ ] **Step 1: Create backend.hcl**

```hcl
bucket         = "homelab-terraform-state-REDACTED_AWS_ACCOUNT"
key            = "prod/infra.tfstate"
region         = "us-east-1"
dynamodb_table = "homelab-terraform-locks"
encrypt        = true
```

- [ ] **Step 2: Commit**

```bash
git add environments/prod/backend.hcl
git commit -m "feat(prod): add S3 backend config"
```

Note: `environments/` is gitignored. This commit is local/private only.

### Task 3: Create Prod Terraform Tfvars

Sized for single-host (daytona). 1 CP + 2 workers. Data disks on hdd-mirror.

**Files:**
- Create: `environments/prod/terraform/terraform.tfvars`

- [ ] **Step 1: Create terraform.tfvars**

```hcl
# Proxmox Configuration
proxmox_host     = "REDACTED_PVE_IP"
proxmox_node     = "daytona"
proxmox_ssh_user = "root"

# Talos Image — generate schematic at https://factory.talos.dev
# Include extensions: siderolabs/qemu-guest-agent, siderolabs/iscsi-tools
# For Newt (Pangolin agent), add when ready: ghcr.io/fosrl/newt/newt:latest
talos_image_url = "https://factory.talos.dev/image/SCHEMATIC_ID/v1.11.3/nocloud-amd64.raw.xz"

# Cluster
cluster_name = "homelab-prod"

# Single control plane (single-host, no HA needed)
control_planes = [
  {
    name       = "prod-cp-01"
    vm_id      = 500
    ip_address = "REDACTED_K8S_API"
  }
]

# Two workers for Longhorn replication
workers = [
  {
    name       = "prod-wk-01"
    vm_id      = 510
    ip_address = "10.10.10.20"
  },
  {
    name       = "prod-wk-02"
    vm_id      = 511
    ip_address = "10.10.10.21"
  }
]

# Resource Sizing — fit within daytona's budget
# Total: 4+8+8=20 CPU, 4+16+16=36 GB RAM (of 56 CPU / 120 GB free)
control_plane_cpu_cores    = 4
control_plane_memory_mb    = 4096
control_plane_boot_disk_gb = 20

worker_cpu_cores    = 8
worker_memory_mb    = 16384
worker_boot_disk_gb = 20
worker_data_disk_gb = 1500  # ~1.5TB each from hdd-mirror (3.6TB total)

# Storage — boot on SSD, data on HDD
image_datastore_id = "local"
boot_datastore_id  = "local-lvm"
data_datastore_id  = "hdd-mirror"

# Network — PROD VLAN
network_bridge = "vmbr0"
network_cidr   = 16
gateway        = "10.10.10.1"
vlan_id        = 10

# Longhorn — use most of the data disk
longhorn_min_size_gib = 1000
longhorn_mount_path   = "/var/mnt/u-longhorn"
```

- [ ] **Step 2: Generate Talos schematic ID**

Go to https://factory.talos.dev and create a schematic with:
- **Talos version**: v1.11.3
- **Platform**: nocloud
- **Architecture**: amd64
- **Extensions**: `siderolabs/qemu-guest-agent`, `siderolabs/iscsi-tools`

Copy the schematic ID and update `talos_image_url` in the tfvars.

- [ ] **Step 3: Commit (local only — environments/ is gitignored)**

### Task 4: Initialize and Apply Terraform

**Prerequisites:**
- AWS credentials configured (`aws sts get-caller-identity` must work)
- SSH agent running with Proxmox host key (`ssh-add`)
- OPNSense running (VLAN 10 gateway at 10.10.10.1)

- [ ] **Step 1: Terraform init**

```bash
cd environments/prod/terraform
terraform init -backend-config=../../prod/backend.hcl
```

Expected: Successful init, S3 backend configured.

- [ ] **Step 2: Terraform plan**

```bash
terraform plan
```

Expected: Plan shows creation of ~8 resources (image download, 3 VMs, Talos configs, bootstrap).
Review: Check VM IDs, IPs, disk sizes, datastore assignments (data on hdd-mirror).

- [ ] **Step 3: Terraform apply**

```bash
terraform apply
```

Expected: Takes 5-15 minutes. Creates VMs, downloads Talos image, applies machine configs, bootstraps cluster. Outputs kubeconfig and talosconfig.

- [ ] **Step 4: Save kubeconfig and talosconfig**

```bash
terraform output -raw kubeconfig > ../kubeconfig
terraform output -raw talosconfig > ../talosconfig
```

- [ ] **Step 5: Verify cluster is up**

```bash
export KUBECONFIG=$(pwd)/../kubeconfig
kubectl get nodes
```

Expected: 3 nodes (1 control plane, 2 workers) in Ready state.

```bash
export TALOSCONFIG=$(pwd)/../talosconfig
talosctl health --nodes REDACTED_K8S_API
```

- [ ] **Step 6: Verify Longhorn mount on workers**

```bash
talosctl -n 10.10.10.20 mounts | grep longhorn
```

Expected: `/var/mnt/u-longhorn` mounted from the data disk.

---

## Chunk 2: Platform Stack (Cilium, Longhorn, ArgoCD)

### Task 5: Install Cilium CNI

Cilium is configured in the Talos machine config (kube-proxy disabled). But the actual Cilium pods need to be deployed.

**Files:**
- Reference: `core/charts/platform/cilium/values.yaml`
- Reference: `environments/prod/apps/cilium.yaml`

- [ ] **Step 1: Install Cilium via Helm (bootstrap — before ArgoCD manages it)**

```bash
export KUBECONFIG=environments/prod/kubeconfig

helm repo add cilium https://helm.cilium.io/
helm repo update

helm install cilium cilium/cilium \
  --version 1.16.5 \
  --namespace cilium \
  --create-namespace \
  -f core/charts/platform/cilium/values.yaml
```

- [ ] **Step 2: Verify Cilium is running**

```bash
kubectl -n cilium get pods
kubectl -n cilium exec ds/cilium -- cilium status
```

Expected: All cilium pods Running, connectivity healthy.

- [ ] **Step 3: Verify pod networking works**

```bash
kubectl run test-net --image=busybox:1.36 --rm -it --restart=Never -- wget -qO- ifconfig.me
```

Expected: Returns an IP (proves pods can reach internet via OPNSense NAT).

### Task 6: Install Longhorn

**Files:**
- Reference: `core/charts/platform/longhorn/values.yaml`

- [ ] **Step 1: Install Longhorn via Helm**

```bash
helm repo add longhorn https://charts.longhorn.io
helm repo update

helm install longhorn longhorn/longhorn \
  --version 1.7.2 \
  --namespace longhorn-system \
  --create-namespace \
  -f core/charts/platform/longhorn/values.yaml
```

- [ ] **Step 2: Verify Longhorn is running**

```bash
kubectl -n longhorn-system get pods
```

Expected: All pods Running (manager, driver, UI, etc.)

- [ ] **Step 3: Verify Longhorn sees the HDD-backed storage**

```bash
kubectl -n longhorn-system get nodes.longhorn.io -o wide
```

Expected: Worker nodes show available storage from `/var/mnt/u-longhorn`.

- [ ] **Step 4: Test PVC creation**

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
EOF

kubectl get pvc test-pvc
```

Expected: PVC bound within 30 seconds.

- [ ] **Step 5: Clean up test PVC**

```bash
kubectl delete pvc test-pvc
```

### Task 7: Install ArgoCD

**Files:**
- Reference: `core/charts/platform/argocd/values.yaml`
- Reference: `core/ansible/playbooks/install-argocd.yml`

- [ ] **Step 1: Install ArgoCD via Helm**

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm install argocd argo/argo-cd \
  --version 7.7.10 \
  --namespace argocd \
  --create-namespace \
  -f core/charts/platform/argocd/values.yaml
```

- [ ] **Step 2: Verify ArgoCD is running**

```bash
kubectl -n argocd get pods
```

Expected: All pods Running.

- [ ] **Step 3: Get ArgoCD admin password**

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

- [ ] **Step 4: Access ArgoCD UI**

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open https://localhost:8080, login with `admin` and the password from step 3.

- [ ] **Step 5: Apply root ArgoCD application (GitOps bootstrap)**

Review and apply the root app that points to the prod apps directory:

```bash
kubectl apply -f environments/prod/apps/root.yaml
```

Expected: ArgoCD picks up the app definitions in `environments/prod/apps/` and starts syncing.

---

## Chunk 3: Pangolin/Newt & App Deployment

### Task 8: Configure Pangolin/Newt for Public Ingress

Pangolin is already deployed on a Vultr VPS. Newt is the agent that runs inside the cluster and establishes a WireGuard tunnel to Pangolin.

**Files:**
- Reference: `docs/decisions/003-pangolin-controld-architecture.md`

- [ ] **Step 1: Create Newt site in Pangolin dashboard**

Go to the Pangolin dashboard and create a new site for the prod cluster. Note the:
- Site ID
- Auth token
- Pangolin endpoint URL

- [ ] **Step 2: Deploy Newt as a K8s deployment**

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: newt
---
apiVersion: v1
kind: Secret
metadata:
  name: newt-config
  namespace: newt
stringData:
  PANGOLIN_ENDPOINT: "https://YOUR_PANGOLIN_VPS:443"
  NEWT_ID: "YOUR_SITE_ID"
  NEWT_SECRET: "YOUR_AUTH_TOKEN"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: newt
  namespace: newt
spec:
  replicas: 1
  selector:
    matchLabels:
      app: newt
  template:
    metadata:
      labels:
        app: newt
    spec:
      containers:
        - name: newt
          image: ghcr.io/fosrl/newt:latest
          envFrom:
            - secretRef:
                name: newt-config
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 256Mi
EOF
```

- [ ] **Step 3: Verify Newt connects to Pangolin**

```bash
kubectl -n newt logs deploy/newt
```

Expected: Logs show successful WireGuard tunnel establishment to Pangolin VPS.

- [ ] **Step 4: Verify tunnel in Pangolin dashboard**

Check the Pangolin dashboard — the site should show as "connected".

- [ ] **Step 5: Create a test resource in Pangolin**

Add a resource pointing to a service inside the cluster (e.g., ArgoCD at `argocd-server.argocd.svc.cluster.local:443`). Test that it's accessible via the public Pangolin URL.

- [ ] **Step 6: Save Newt manifests to Git**

Move the Newt deployment to a proper manifest:

Create: `core/manifests/newt/deployment.yaml` (the manifest without secrets)
Create: `environments/prod/apps/newt.yaml` (ArgoCD Application pointing to the manifest)

```bash
git add core/manifests/newt/
git commit -m "feat: add Newt deployment manifest for Pangolin ingress"
```

### Task 9: Deploy First Application

Pick a simple app to validate the full pipeline: Git → ArgoCD → K8s → Pangolin → Public.

- [ ] **Step 1: Choose an app from existing charts**

Available in `core/charts/apps/`: jellyfin, harbor, grafana-stack, zitadel, forgejo.

For a quick validation, use a simple nginx or the user's race telemetry app.

- [ ] **Step 2: Create ArgoCD Application manifest**

Create in `environments/prod/apps/<app-name>.yaml` following the pattern of cilium.yaml.

- [ ] **Step 3: Apply and verify**

```bash
kubectl apply -f environments/prod/apps/<app-name>.yaml
```

Verify in ArgoCD UI that the app syncs and pods are running.

- [ ] **Step 4: Create Pangolin resource for public access**

Add a resource in Pangolin dashboard pointing to the app's K8s service.

- [ ] **Step 5: Verify public access**

Access the app via the Pangolin public URL. Confirm end-to-end: public internet → Pangolin VPS → WireGuard → Newt → K8s service → pod.

---

## Resource Budget Summary

| VM | CPU | RAM | Boot (SSD) | Data (HDD) |
|----|-----|-----|------------|------------|
| OPNSense (100) | 2 | 4 GB | 32 GB | — |
| Talos CP (500) | 4 | 4 GB | 20 GB | — |
| Talos WK (510) | 8 | 16 GB | 20 GB | 1.5 TB |
| Talos WK (511) | 8 | 16 GB | 20 GB | 1.5 TB |
| **Total** | **22** | **40 GB** | **92 GB** | **3.0 TB** |
| **Available** | **56** | **125 GB** | **240 GB** | **3.6 TB** |
| **Remaining** | **34** | **85 GB** | **148 GB** | **0.6 TB** |

Plenty of headroom for additional workloads.
