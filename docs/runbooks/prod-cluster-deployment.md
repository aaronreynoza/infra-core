# Production Talos Cluster Deployment Runbook

This runbook documents the complete deployment of the production Talos Linux Kubernetes cluster on Proxmox VE. It covers every step from pre-requisites through a running cluster, including all issues encountered and their fixes. Use this as the definitive reference for rebuilding or troubleshooting the prod cluster.

**Date deployed:** 2026-03-11
**Talos version:** v1.11.3
**Kubernetes version:** 1.32.1
**Proxmox host:** daytona
**Network:** PROD VLAN 10 (10.10.10.0/16)

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Pre-requisites](#pre-requisites)
3. [Step 1: Prepare Environment Config Files](#step-1-prepare-environment-config-files)
4. [Step 2: Generate Talos Image Schematic](#step-2-generate-talos-image-schematic)
5. [Step 3: Terraform Init and Apply](#step-3-terraform-init-and-apply)
6. [Step 4: Management-to-VLAN Routing](#step-4-management-to-vlan-routing)
7. [Step 5: Save Credentials](#step-5-save-credentials)
8. [Step 6: Verify Cluster](#step-6-verify-cluster)
9. [Step 7: Install Platform Stack](#step-7-install-platform-stack)
10. [Issues Encountered and Fixes](#issues-encountered-and-fixes)
11. [Manual Steps That Should Be Automated](#manual-steps-that-should-be-automated)
12. [Current State](#current-state)
13. [Resource Budget](#resource-budget)

---

## Architecture Overview

```
Proxmox Host: daytona (REDACTED_PVE_IP)
├── OPNSense VM (100) — WAN: REDACTED_OPNSENSE_IP, PROD: 10.10.10.1
├── prod-cp-01 (500) — Control Plane — REDACTED_K8S_API
├── prod-wk-01 (510) — Worker — 10.10.10.20
└── prod-wk-02 (511) — Worker — 10.10.10.21

Network: VLAN 10 on vmbr0 (VLAN-aware bridge)
Gateway: 10.10.10.1 (OPNSense PROD interface)
CIDR: /16

Storage:
  Boot disks: local-lvm (SSD)
  Data disks: hdd-mirror (2x WD Gold 3.6TB ZFS mirror)
  Talos image: local (ISO storage)
```

All three VMs run on a single Proxmox host (daytona). The control plane has no data disk. Workers each have a 1.5TB data disk on the HDD mirror pool for Longhorn persistent volumes.

---

## Pre-requisites

Before starting, ensure all of the following are in place:

### Infrastructure

- [ ] Proxmox VE running on daytona with `local-lvm` (SSD) and `hdd-mirror` (HDD) datastores
- [ ] `vmbr0` bridge is VLAN-aware (configured in Proxmox network settings)
- [ ] OPNSense VM running with PROD VLAN 10 interface at 10.10.10.1 and DHCP/NAT working
- [ ] OPNSense has internet-bound NAT configured for PROD subnet

### Credentials and Tools

- [ ] AWS CLI configured (`aws sts get-caller-identity` must succeed)
- [ ] Proxmox API token stored in AWS Secrets Manager at `homelab/proxmox` with keys `api_token_id` and `api_token_secret`
- [ ] SSH agent running with the Proxmox host key loaded (`ssh-add -l` shows the key)
- [ ] `terraform` >= 1.9.0 installed
- [ ] `talosctl` installed (matching Talos version v1.11.3)
- [ ] `kubectl` installed
- [ ] `helm` installed

### Verify Proxmox API access

```bash
# Test SSH to Proxmox
ssh root@REDACTED_PVE_IP 'hostname'
# Expected: daytona

# Test AWS credentials
aws sts get-caller-identity
# Expected: shows account REDACTED_AWS_ACCOUNT
```

---

## Step 1: Prepare Environment Config Files

The prod environment lives in `environments/prod/` (gitignored, private). Three files are needed.

### 1a. Backend config (`environments/prod/backend.hcl`)

```hcl
bucket         = "homelab-terraform-state-REDACTED_AWS_ACCOUNT"
key            = "prod/infra.tfstate"
region         = "us-east-1"
dynamodb_table = "homelab-terraform-locks"
encrypt        = true
```

### 1b. Main terraform config (`environments/prod/terraform/main.tf`)

This file wires up the Proxmox and Talos providers and calls the `talos-cluster` module. Key design decisions:

- Proxmox credentials are fetched from AWS Secrets Manager (not hardcoded)
- S3 backend for remote state (no local tfstate files)
- The module source points to `../../../core/terraform/modules/talos-cluster`

```hcl
terraform {
  required_version = ">= 1.9.0"

  backend "s3" {}

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.78.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = ">= 0.8.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_secretsmanager_secret_version" "proxmox" {
  secret_id = "homelab/proxmox"
}

locals {
  proxmox_creds = jsondecode(
    data.aws_secretsmanager_secret_version.proxmox.secret_string
  )
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

module "cluster" {
  source = "../../../core/terraform/modules/talos-cluster"

  cluster_name    = var.cluster_name
  proxmox_node    = var.proxmox_node
  talos_image_url = var.talos_image_url

  control_planes = var.control_planes
  workers        = var.workers

  control_plane_cpu_cores    = var.control_plane_cpu_cores
  control_plane_memory_mb    = var.control_plane_memory_mb
  control_plane_boot_disk_gb = var.control_plane_boot_disk_gb

  worker_cpu_cores    = var.worker_cpu_cores
  worker_memory_mb    = var.worker_memory_mb
  worker_boot_disk_gb = var.worker_boot_disk_gb
  worker_data_disk_gb = var.worker_data_disk_gb

  image_datastore_id = var.image_datastore_id
  boot_datastore_id  = var.boot_datastore_id
  data_datastore_id  = var.data_datastore_id

  network_bridge = var.network_bridge
  network_cidr   = var.network_cidr
  gateway        = var.gateway
  vlan_id        = var.vlan_id

  longhorn_min_size_gib = var.longhorn_min_size_gib
  longhorn_mount_path   = var.longhorn_mount_path

  skip_health_check = var.skip_health_check
}
```

### 1c. Terraform variables (`environments/prod/terraform/terraform.tfvars`)

```hcl
# Proxmox
proxmox_host     = "REDACTED_PVE_IP"
proxmox_node     = "daytona"
proxmox_ssh_user = "root"

# Talos image — .raw.zst format (NOT .raw.xz — see Issue #1 below)
talos_image_url = "https://factory.talos.dev/image/<SCHEMATIC_ID>/v1.11.3/nocloud-amd64.raw.zst"

# Cluster
cluster_name = "homelab-prod"

# 1 control plane (single host, no HA)
control_planes = [
  {
    name       = "prod-cp-01"
    vm_id      = 500
    ip_address = "REDACTED_K8S_API"
  }
]

# 2 workers for Longhorn replication
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

# Sizing (total: 20 CPU, 36GB RAM)
control_plane_cpu_cores    = 4
control_plane_memory_mb    = 4096
control_plane_boot_disk_gb = 20

worker_cpu_cores    = 8
worker_memory_mb    = 16384
worker_boot_disk_gb = 20
worker_data_disk_gb = 1500

# Storage — boot on SSD, data on HDD mirror
image_datastore_id = "local"
boot_datastore_id  = "local-lvm"
data_datastore_id  = "hdd-mirror"

# Network — PROD VLAN
network_bridge = "vmbr0"
network_cidr   = 16
gateway        = "10.10.10.1"
vlan_id        = 10

# Longhorn
longhorn_min_size_gib = 1000
longhorn_mount_path   = "/var/mnt/u-longhorn"
```

---

## Step 2: Generate Talos Image Schematic

The Talos image must include system extensions for QEMU guest agent and iSCSI (required by Longhorn).

1. Go to https://factory.talos.dev
2. Select:
   - **Talos version**: v1.11.3
   - **Platform**: nocloud
   - **Architecture**: amd64
3. Add extensions:
   - `siderolabs/qemu-guest-agent`
   - `siderolabs/iscsi-tools`
4. (Optional, for later) Add `ghcr.io/fosrl/newt/newt:latest` for Pangolin agent
5. Copy the schematic ID
6. Update `talos_image_url` in `terraform.tfvars` with the schematic ID
7. **CRITICAL**: Use `.raw.zst` suffix, NOT `.raw.xz` (see [Issue #1](#issue-1-talos-image-format-rawxz-vs-rawzst))

The resulting URL should look like:
```
https://factory.talos.dev/image/b15572a23ba3e735d0be57b006a5740f56bab22727abc87a89135a274658e2db/v1.11.3/nocloud-amd64.raw.zst
```

---

## Step 3: Terraform Init and Apply

### 3a. Initialize terraform

```bash
cd environments/prod/terraform

terraform init -backend-config=../backend.hcl
```

Expected output: "Terraform has been successfully initialized!" with S3 backend configured.

### 3b. Plan

```bash
terraform plan
```

Review the plan carefully. Expected resources:
- 1x `proxmox_virtual_environment_download_file` (Talos image)
- 3x `proxmox_virtual_environment_vm` (1 CP + 2 workers)
- 1x `talos_machine_secrets`
- 3x `talos_machine_configuration_apply` (1 CP + 2 workers)
- 1x `talos_machine_bootstrap`
- 1x `talos_cluster_kubeconfig`

Verify:
- VM IDs match (500, 510, 511)
- IPs are correct (REDACTED_K8S_API, .20, .21)
- Boot disks on `local-lvm`, data disks on `hdd-mirror`
- VLAN ID is 10
- Image URL uses `.raw.zst`

### 3c. Apply

```bash
terraform apply
```

This takes 10-20 minutes. What happens in order:

1. Talos image downloads to Proxmox `local` datastore (~800MB)
2. Machine secrets are generated
3. Control plane VM is created and started
4. Worker VMs are created and started
5. Talos machine configs are applied to all nodes (with config patches for DNS, CNI=none, kube-proxy=disabled, Longhorn mounts)
6. Bootstrap runs on the first control plane node
7. Kubeconfig is retrieved

**If apply is interrupted:** You may get a stale DynamoDB lock. Fix with:
```bash
terraform force-unlock <LOCK_ID>
```
The lock ID is shown in the error message.

### 3d. Troubleshooting apply failures

If VMs boot but Talos config apply times out:
- Check that your machine can reach the VLAN (see Step 4)
- Check that VMs actually booted into Talos (not iPXE — see [Issue #2](#issue-2-vms-booting-into-ipxe))
- Check Proxmox console for the VM to see boot output

If bootstrap times out:
- The nodes may need DNS to pull etcd images (see [Issue #7](#issue-7-dns-resolution-failing-on-nodes))
- Try manually: `talosctl --talosconfig ../talosconfig bootstrap --nodes REDACTED_K8S_API`

---

## Step 4: Management-to-VLAN Routing

Your workstation (on the management network 192.168.1.0/24) needs to reach nodes on PROD VLAN 10 (10.10.10.0/16) through OPNSense. This does not work by default and requires several configuration changes.

**Full details:** See [mgmt-to-vlan-routing.md](mgmt-to-vlan-routing.md)

### Quick summary of required changes

#### On OPNSense:

1. **Firewall > Rules > WAN**: Add rule — Pass, Source: WAN net, Destination: PROD net (10.10.10.0/16)
2. **Firewall > NAT > Outbound**: Switch to Hybrid mode, add manual "Do not NAT" rule for Source 10.10.0.0/16 -> Destination 192.168.1.0/24
3. **Firewall > Settings > Advanced**: Check "Disable reply-to" (prevents pf from dropping routed return traffic)

#### On your Mac:

```bash
# Add static route for PROD VLAN via OPNSense WAN
sudo route add -net 10.10.0.0/16 REDACTED_OPNSENSE_IP

# Verify
ping REDACTED_K8S_API
nc -zv REDACTED_K8S_API 6443
```

**IMPORTANT**: This static route only works when your Mac is connected to the **office router** (same L2 segment as OPNSense WAN at REDACTED_OPNSENSE_IP). If you are on the room/home router, routing will fail. See [issue #007](../issues/007-multi-router-vlan-access.md) for details and workaround.

#### Verify connectivity

```bash
ping REDACTED_K8S_API     # Control plane
ping 10.10.10.20     # Worker 1
ping 10.10.10.21     # Worker 2
nc -zv REDACTED_K8S_API 50000   # Talos API
nc -zv REDACTED_K8S_API 6443    # Kubernetes API
```

---

## Step 5: Save Credentials

After a successful apply, extract the kubeconfig and talosconfig:

```bash
cd environments/prod/terraform

terraform output -raw kubeconfig > ../kubeconfig
terraform output -raw talosconfig > ../talosconfig
```

Set environment variables for subsequent commands:

```bash
export KUBECONFIG=$(realpath ../kubeconfig)
export TALOSCONFIG=$(realpath ../talosconfig)
```

These files are in `environments/prod/` which is gitignored. Do not commit them.

---

## Step 6: Verify Cluster

### 6a. Check Talos node status

```bash
talosctl --nodes REDACTED_K8S_API health
talosctl --nodes REDACTED_K8S_API get members
talosctl --nodes REDACTED_K8S_API services
```

Expected services running on control plane:
- `etcd` — Running
- `kubelet` — Running
- `apid` — Running
- `machined` — Running

### 6b. Check Kubernetes

```bash
kubectl get nodes
```

Expected output:
```
NAME         STATUS     ROLES           AGE   VERSION
prod-cp-01   NotReady   control-plane   Xm    v1.32.1
prod-wk-01   NotReady   <none>          Xm    v1.32.1
prod-wk-02   NotReady   <none>          Xm    v1.32.1
```

**Nodes will be NotReady** until CNI (Cilium) is installed. This is expected.

### 6c. Check system pods

```bash
kubectl get pods -n kube-system
```

Expected: `kube-apiserver`, `kube-controller-manager`, `kube-scheduler`, `etcd` pods running on the control plane. CoreDNS pods will be Pending (waiting for CNI).

### 6d. Verify Longhorn mount on workers

```bash
talosctl --nodes 10.10.10.20 mounts | grep longhorn
talosctl --nodes 10.10.10.21 mounts | grep longhorn
```

Expected: `/var/mnt/u-longhorn` mounted from the data disk (`/dev/vdb`).

---

## Step 7: Install Platform Stack

The platform stack must be installed in order: Cilium first (CNI, required for pod networking), then Longhorn (storage), then ArgoCD (GitOps).

### 7a. Install Cilium

```bash
helm repo add cilium https://helm.cilium.io/
helm repo update

helm install cilium cilium/cilium \
  --version 1.16.5 \
  --namespace cilium \
  --create-namespace \
  -f core/charts/platform/cilium/values.yaml
```

Verify:
```bash
# Wait for Cilium pods
kubectl -n cilium get pods -w

# Check Cilium status
kubectl -n cilium exec ds/cilium -- cilium status

# Nodes should transition to Ready
kubectl get nodes
```

After Cilium is running, all nodes should show `Ready`.

### 7b. Install Longhorn

```bash
helm repo add longhorn https://charts.longhorn.io
helm repo update

helm install longhorn longhorn/longhorn \
  --version 1.7.2 \
  --namespace longhorn-system \
  --create-namespace \
  -f core/charts/platform/longhorn/values.yaml
```

Verify:
```bash
kubectl -n longhorn-system get pods
kubectl -n longhorn-system get nodes.longhorn.io -o wide
```

Test PVC creation:
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

kubectl get pvc test-pvc   # Should be Bound within 30s
kubectl delete pvc test-pvc
```

### 7c. Install ArgoCD

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm install argocd argo/argo-cd \
  --version 7.7.10 \
  --namespace argocd \
  --create-namespace \
  -f core/charts/platform/argocd/values.yaml
```

Verify and access:
```bash
kubectl -n argocd get pods

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo

# Port forward to access UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open https://localhost:8080, login: admin / <password from above>
```

---

## Issues Encountered and Fixes

This section documents every issue hit during deployment, in the order they were encountered. Each fix is reflected in the current Terraform module code.

### Issue #1: Talos image format (.raw.xz vs .raw.zst)

**Problem:** The Talos factory generates download URLs ending in `.raw.xz` by default. The bpg/proxmox provider's `download_file` resource only supports `gz`, `lzo`, `zst`, and `bz2` decompression algorithms. It does **not** support `xz`. Terraform apply failed with a decompression error.

**Fix:** Changed the image URL from `.raw.xz` to `.raw.zst` (Talos factory provides both formats at the same URL path, just change the extension). Added `decompression_algorithm = "zst"` to the `proxmox_virtual_environment_download_file` resource. Added a validation rule on `talos_image_url` that rejects `.raw.xz` URLs with a helpful error message.

**Where:** `core/terraform/modules/talos-cluster/main.tf` (download_file resource), `core/terraform/modules/talos-cluster/variables.tf` (validation on talos_image_url)

### Issue #2: VMs booting into iPXE instead of Talos

**Problem:** After VMs were created and the Talos image was attached as a disk, the VMs booted into iPXE network boot instead of booting from the disk. The Proxmox console showed the iPXE prompt rather than Talos booting.

**Root cause:** The bpg/proxmox provider did not set an explicit boot order. Proxmox defaulted to network boot (PXE) before disk boot.

**Fix:** Added `boot_order = ["virtio0"]` to the `proxmox_virtual_environment_vm` resource in the proxmox-vm module, which tells Proxmox to boot from the first virtio disk.

**Where:** `core/terraform/modules/proxmox-vm/main.tf`

### Issue #3: Management-to-VLAN routing

**Problem:** After VMs booted on PROD VLAN (10.10.10.0/16), the Mac on the management network (192.168.1.0/24) could not reach them. `ping REDACTED_K8S_API` timed out, `nc -zv REDACTED_K8S_API 6443` returned "Can't assign requested address".

**Root cause:** Three interacting issues — outbound NAT rewriting return traffic, reply-to dropping asymmetric traffic, and missing WAN firewall rules.

**Fix:** Required changes on OPNSense (hybrid NAT with "Do not NAT" rule, disable reply-to, WAN pass rule) and a static route on the Mac. See [mgmt-to-vlan-routing.md](mgmt-to-vlan-routing.md) for full details.

**Additional caveat:** Only works from the office router (same L2 as OPNSense WAN). Room/home router requires static routes on the home router. See [issue #007](../issues/007-multi-router-vlan-access.md).

### Issue #4: Talos provider generating incompatible configs

**Problem:** `terraform apply` succeeded in applying machine configs, but the Talos nodes rejected the config with errors about unknown fields. Specifically, the config included `grubUseUKICmdline: true` which is not recognized by Talos v1.11.3.

**Root cause:** The `talos_machine_configuration` data source defaults to the latest Talos schema version if `talos_version` is not explicitly set. The latest schema included fields that are incompatible with v1.11.3.

**Fix:** Added `talos_version = var.talos_version` to both `data "talos_machine_configuration"` blocks (control_plane and worker) in the talos-cluster module. The variable defaults to `"v1.11.3"`.

**Where:** `core/terraform/modules/talos-cluster/main.tf` (both talos_machine_configuration data sources), `core/terraform/modules/talos-cluster/variables.tf` (talos_version variable)

### Issue #5: Kubernetes version too new

**Problem:** Similar to Issue #4 — the Talos provider defaulted to Kubernetes 1.35.0, which is not compatible with Talos v1.11.3. Kubelet failed to start.

**Fix:** Added `kubernetes_version = var.kubernetes_version` to both `data "talos_machine_configuration"` blocks. The variable defaults to `"1.32.1"`.

**Where:** Same files as Issue #4.

### Issue #6: Health check race condition

**Problem:** The `talos_cluster_health` data source started evaluating before the bootstrap completed, causing it to time out waiting for etcd to become healthy.

**Fix:** Two changes:
1. Added `talos_machine_bootstrap.this` to the `depends_on` list on `talos_cluster_health`
2. Defaulted `skip_health_check = true` because nodes stay NotReady until Cilium is installed (which happens outside Terraform, after apply). The health check would always fail in this architecture.

**Where:** `core/terraform/modules/talos-cluster/main.tf` (talos_cluster_health), `core/terraform/modules/talos-cluster/variables.tf` (skip_health_check default)

### Issue #7: DNS resolution failing on nodes

**Problem:** After bootstrap, etcd and kubelet failed to pull container images. Talos nodes could not resolve `gcr.io`, `ghcr.io`, or any external hostnames.

**Root cause:** No nameservers were configured in the Talos machine config. The nodes had no DNS resolver configured.

**Fix:** Added a config patch to both control plane and worker `talos_machine_configuration_apply` resources that sets `machine.network.nameservers` to `["8.8.8.8", "1.1.1.1"]`. This is now a variable (`nameservers`) with those values as defaults.

**Where:** `core/terraform/modules/talos-cluster/main.tf` (config_patches), `core/terraform/modules/talos-cluster/variables.tf` (nameservers variable)

### Issue #8: etcd image pull hanging

**Problem:** Even after DNS was working (nslookup succeeded), the automatic image pull for `gcr.io/etcd-development/etcd:v3.6.5` was extremely slow or hung indefinitely. The etcd service would not start.

**Root cause:** Unclear. Possibly slow path through OPNSense NAT, or rate limiting from gcr.io, or MTU issues on the VLAN.

**Workaround:** Manually pulled the image on the control plane node:

```bash
talosctl --nodes REDACTED_K8S_API image pull gcr.io/etcd-development/etcd:v3.6.5
```

This is not ideal and may need investigation if it recurs.

### Issue #9: etcd waiting for bootstrap after reboot

**Problem:** After rebooting the control plane node (during troubleshooting), etcd came back in a state where it was waiting for a bootstrap command. The cluster was stuck.

**Fix:** Re-ran the bootstrap command manually:

```bash
talosctl --nodes REDACTED_K8S_API bootstrap
```

**Note:** This should only be needed once (the initial bootstrap). If a node reboots and etcd doesn't rejoin automatically, check that the machine config is correctly applied and etcd data is intact.

### Issue #10: Terraform state lock stuck

**Problem:** Cancelling `terraform apply` (Ctrl+C) during a long operation left a stale DynamoDB lock. Subsequent terraform commands failed with "Error acquiring the state lock".

**Fix:**

```bash
terraform force-unlock <LOCK_ID>
```

The lock ID is printed in the error message. This is safe to run if you are sure no other terraform process is running against this state.

### Issue #11: Terraform re-downloading Talos image

**Problem:** The `overwrite = true` on the `download_file` resource causes Proxmox to compare the file size on every `terraform apply`. If the remote file size differs (or can't be checked), it re-downloads the entire image (~800MB).

**Impact:** Minor annoyance. Adds 2-5 minutes to every apply. Does not affect running VMs (disk is already imported).

**Mitigation:** Could set `overwrite = false` after initial deployment, but then image updates would require manual intervention.

---

## Manual Steps That Should Be Automated

The following steps were performed manually and should eventually be automated (via Terraform, Ansible, or ArgoCD):

| Step | Current Method | Target Automation |
|------|---------------|-------------------|
| Cilium install | `helm install` from workstation | ArgoCD Application (app-of-apps) |
| Longhorn install | `helm install` from workstation | ArgoCD Application |
| ArgoCD install | `helm install` from workstation | Ansible playbook (bootstrap) |
| DNS nameservers | Terraform config patch (now automated) | Already in Terraform |
| etcd bootstrap | Terraform (but reboot can reset) | Investigate why reboot resets bootstrap |
| Image pre-pulling | Manual `talosctl image pull` | Talos machine config `registries.mirrors` or pre-pull DaemonSet |
| Worker reboots after config changes | Manual `talosctl reboot` | Terraform provisioner or null_resource |
| Static route on Mac | Manual `sudo route add` | Script in repo, or home router static route |

---

## Current State

As of 2026-03-11:

| Component | Status |
|-----------|--------|
| prod-cp-01 (REDACTED_K8S_API) | Running, control-plane |
| prod-wk-01 (10.10.10.20) | Running, worker |
| prod-wk-02 (10.10.10.21) | Running, worker |
| Kubernetes API | Accessible at https://REDACTED_K8S_API:6443 |
| etcd | Running, healthy |
| kubelet | Running on all nodes |
| Node status | NotReady (no CNI) |
| Cilium | Not installed |
| Longhorn | Not installed |
| ArgoCD | Not installed |

### Next steps (in order)

1. Install Cilium (nodes become Ready)
2. Install Longhorn (persistent storage)
3. Install ArgoCD (GitOps)
4. Deploy Newt for Pangolin connectivity
5. Deploy first application

---

## Resource Budget

| VM | CPU | RAM | Boot (SSD) | Data (HDD) |
|----|-----|-----|------------|------------|
| OPNSense (100) | 2 | 4 GB | 32 GB | -- |
| prod-cp-01 (500) | 4 | 4 GB | 20 GB | -- |
| prod-wk-01 (510) | 8 | 16 GB | 20 GB | 1.5 TB |
| prod-wk-02 (511) | 8 | 16 GB | 20 GB | 1.5 TB |
| **Total** | **22** | **40 GB** | **92 GB** | **3.0 TB** |
| **Available (daytona)** | **56** | **125 GB** | **240 GB** | **3.6 TB** |
| **Remaining** | **34** | **85 GB** | **148 GB** | **0.6 TB** |

---

## Quick Reference: Useful Commands

```bash
# Set up environment
export KUBECONFIG=environments/prod/kubeconfig
export TALOSCONFIG=environments/prod/talosconfig

# Talos operations
talosctl --nodes REDACTED_K8S_API health
talosctl --nodes REDACTED_K8S_API services
talosctl --nodes REDACTED_K8S_API get members
talosctl --nodes REDACTED_K8S_API dmesg
talosctl --nodes REDACTED_K8S_API logs kubelet
talosctl --nodes REDACTED_K8S_API logs etcd

# Kubernetes operations
kubectl get nodes
kubectl get pods -A
kubectl get events -A --sort-by='.lastTimestamp'

# Terraform operations (from environments/prod/terraform/)
terraform plan
terraform apply
terraform output -raw kubeconfig > ../kubeconfig
terraform output -raw talosconfig > ../talosconfig

# Routing (run once per Mac reboot)
sudo route add -net 10.10.0.0/16 REDACTED_OPNSENSE_IP

# Emergency: force-unlock stale terraform lock
terraform force-unlock <LOCK_ID>
```

---

**Last Updated:** 2026-03-11
