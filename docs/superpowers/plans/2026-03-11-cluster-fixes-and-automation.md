# Cluster Fixes & Platform Automation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix critical issues found by expert review, then automate the full bootstrap so `terraform apply` provisions the cluster AND installs the platform stack (Cilium + ArgoCD), with ArgoCD managing everything else via GitOps.

**Architecture:** Terraform provisions VMs + Talos cluster + Cilium (via Helm provider) + ArgoCD (via Helm provider). ArgoCD then manages Longhorn, future apps, and even Cilium upgrades via app-of-apps with sync waves. No manual `helm install` commands. One `terraform apply` from bare metal to GitOps-managed cluster.

**Tech Stack:** Terraform (bpg/proxmox, siderolabs/talos, hashicorp/helm), Talos Linux v1.11.3, K8s 1.32.1, Cilium 1.16.5, Longhorn 1.7.2, ArgoCD 7.7.10

---

## File Structure

### Files to modify:
- `core/terraform/modules/talos-cluster/main.tf` — fix Longhorn disk config, extract shared patches to locals
- `core/terraform/modules/talos-cluster/variables.tf` — add lifecycle protection, tighten defaults
- `core/terraform/modules/talos-cluster/outputs.tf` — add machine_secrets backup output, kubeconfig components for Helm provider
- `environments/prod/terraform/main.tf` — add Helm + kubectl providers, helm_release for Cilium + ArgoCD, root Application
- `environments/prod/terraform/variables.tf` — add platform stack variables
- `core/charts/platform/cilium/values.yaml` — add k8sServiceHost/Port, MTU config
- `core/charts/platform/longhorn/values.yaml` — fix defaultDataPath
- `core/charts/platform/argocd/values.yaml` — add repo config, bump resource limits

### Files to create:
- `core/manifests/argocd/root-app.yaml` — production root Application (replaces template)
- `core/manifests/argocd/apps/cilium.yaml` — Cilium ArgoCD Application (wave 1)
- `core/manifests/argocd/apps/longhorn.yaml` — Longhorn ArgoCD Application (wave 2)
- `core/manifests/argocd/apps/argocd.yaml` — ArgoCD self-management Application (wave 3)

### Files NOT changed (documented why):
- `core/terraform/modules/proxmox-vm/main.tf` — no changes needed, boot_order already fixed
- `environments/prod/terraform/terraform.tfvars` — no changes needed, values are correct
- Ansible playbooks — superseded by Terraform Helm provider approach

---

## Chunk 1: Fix Critical Terraform & Talos Issues

### Task 1: Fix Longhorn Disk Config (machine.disks instead of UserVolumeConfig)

The `UserVolumeConfig` in worker config patches is not a valid machine config patch format for Talos v1.11.3. It's being silently ignored. Workers have no data disk provisioned for Longhorn.

**Files:**
- Modify: `core/terraform/modules/talos-cluster/main.tf:156-202`

- [ ] **Step 1: Replace UserVolumeConfig with machine.disks in worker config patches**

Replace the entire worker `config_patches` block. The new config uses `machine.disks` (proper Talos v1.11.3 machine config format) instead of the invalid `UserVolumeConfig` resource document.

```hcl
  config_patches = [
    yamlencode({
      machine = {
        network = {
          nameservers = var.nameservers
        }
        disks = [
          {
            device = "/dev/vdb"
            partitions = [
              {
                mountpoint = var.longhorn_mount_path
              }
            ]
          }
        ]
        kubelet = {
          extraMounts = [
            {
              destination = var.longhorn_mount_path
              type        = "bind"
              source      = var.longhorn_mount_path
              options     = ["bind", "rshared", "rw"]
            }
          ]
        }
      }
      cluster = {
        network = {
          cni = {
            name = "none"
          }
        }
        proxy = {
          disabled = true
        }
      }
    })
  ]
```

Note: This replaces the previous 3 separate `yamlencode()` blocks with a single consolidated one. The `machine.disks` block tells Talos to partition /dev/vdb and mount it at the longhorn path. The `kubelet.extraMounts` block makes it available to Longhorn pods.

- [ ] **Step 2: Extract shared config patches to locals block**

The control plane and worker configs share the nameservers, CNI, and proxy patches. Extract to a locals block to DRY it up. Add this in `main.tf` before the `talos_machine_configuration_apply` resources (around line 115):

```hcl
locals {
  # Shared config patches for all nodes (CP + workers)
  common_config_patch = yamlencode({
    machine = {
      network = {
        nameservers = var.nameservers
      }
    }
    cluster = {
      network = {
        cni = {
          name = "none"
        }
      }
      proxy = {
        disabled = true
      }
    }
  })

  # Worker-specific config patch (Longhorn data disk)
  worker_config_patch = yamlencode({
    machine = {
      disks = [
        {
          device = "/dev/vdb"
          partitions = [
            {
              mountpoint = var.longhorn_mount_path
            }
          ]
        }
      ]
      kubelet = {
        extraMounts = [
          {
            destination = var.longhorn_mount_path
            type        = "bind"
            source      = var.longhorn_mount_path
            options     = ["bind", "rshared", "rw"]
          }
        ]
      }
    }
  })
}
```

Then update the control plane resource:
```hcl
resource "talos_machine_configuration_apply" "control_plane" {
  ...
  config_patches = [local.common_config_patch]
}
```

And the worker resource:
```hcl
resource "talos_machine_configuration_apply" "worker" {
  ...
  config_patches = [local.common_config_patch, local.worker_config_patch]
}
```

- [ ] **Step 3: Verify with terraform plan**

```bash
cd environments/prod/terraform
terraform plan -var="skip_health_check=true"
```

Expected: Shows changes to `talos_machine_configuration_apply` for all 3 nodes. The worker patches should show the new `machine.disks` block instead of `UserVolumeConfig`.

- [ ] **Step 4: Commit**

```bash
git add core/terraform/modules/talos-cluster/main.tf
git commit -m "fix(talos): use machine.disks for Longhorn storage instead of UserVolumeConfig"
```

### Task 2: Fix Longhorn Data Path Mismatch

Terraform mounts the disk at `/var/mnt/u-longhorn` but Longhorn values.yaml looks at `/var/mnt/longhorn` (missing `u-` prefix).

**Files:**
- Modify: `core/charts/platform/longhorn/values.yaml`

- [ ] **Step 1: Fix the defaultDataPath**

Change line 4 from:
```yaml
  defaultDataPath: "/var/mnt/longhorn"
```
To:
```yaml
  defaultDataPath: "/var/mnt/u-longhorn"
```

- [ ] **Step 2: Commit**

```bash
git add core/charts/platform/longhorn/values.yaml
git commit -m "fix(longhorn): align defaultDataPath with Talos mount path /var/mnt/u-longhorn"
```

### Task 3: Fix Cilium Config for Talos (k8sServiceHost + MTU)

With kube-proxy disabled, Cilium must know the API server address. Also add MTU config to prevent VLAN encapsulation issues that caused slow image pulls.

**Files:**
- Modify: `core/charts/platform/cilium/values.yaml`

- [ ] **Step 1: Add k8sServiceHost, k8sServicePort, and MTU config**

Replace the entire file with:

```yaml
# Cilium CNI Configuration for Talos Linux
# Talos disables kube-proxy, so Cilium must handle service proxying.

ipam:
  mode: kubernetes

# kube-proxy replacement — requires k8sServiceHost/Port
kubeProxyReplacement: true
k8sServiceHost: "REDACTED_K8S_API"
k8sServicePort: "6443"

# BPF masquerade (required when replacing kube-proxy)
bpf:
  masquerade: true

# MTU — account for VLAN 802.1Q overhead (4 bytes)
# Set to 1450 to guarantee no fragmentation across any path
MTU: 1450

# Routing — native mode for flat L2 VLAN network (avoids double encapsulation)
routingMode: native
autoDirectNodeRoutes: true
ipv4NativeRoutingCIDR: "10.244.0.0/16"

# Security context required for Talos
securityContext:
  capabilities:
    ciliumAgent:
      - CHOWN
      - KILL
      - NET_ADMIN
      - NET_RAW
      - IPC_LOCK
      - SYS_ADMIN
      - SYS_RESOURCE
      - DAC_OVERRIDE
      - FOWNER
      - SETGID
      - SETUID

# Hubble observability
hubble:
  enabled: true
  relay:
    enabled: true
  ui:
    enabled: true

# Talos mounts cgroupv2
cgroup:
  autoMount:
    enabled: true
  hostRoot: /sys/fs/cgroup

# Single-node operator (resource constrained)
operator:
  replicas: 1
```

**Note:** `k8sServiceHost` is hardcoded to `REDACTED_K8S_API` (the prod control plane IP). For a reusable config across environments, this could be templated. For now it matches the prod deployment.

- [ ] **Step 2: Commit**

```bash
git add core/charts/platform/cilium/values.yaml
git commit -m "fix(cilium): add k8sServiceHost/Port, MTU, native routing for Talos"
```

### Task 4: Pin Provider Versions & Protect Machine Secrets

The `>= 0.8.0` Talos provider constraint already caused 2 schema mismatches. Machine secrets have no destroy protection.

**Files:**
- Modify: `environments/prod/terraform/main.tf:17-24`
- Modify: `core/terraform/modules/talos-cluster/main.tf:88`
- Modify: `core/terraform/modules/talos-cluster/outputs.tf`

- [ ] **Step 1: Pin provider versions in prod main.tf**

Change the `required_providers` block in `environments/prod/terraform/main.tf`:

```hcl
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.98.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.10.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.35.0"
    }
```

- [ ] **Step 2: Add lifecycle protection to machine secrets**

In `core/terraform/modules/talos-cluster/main.tf`, change:

```hcl
resource "talos_machine_secrets" "this" {}
```

To:

```hcl
resource "talos_machine_secrets" "this" {
  lifecycle {
    prevent_destroy = true
  }
}
```

- [ ] **Step 3: Add machine_secrets output for backup**

Add to `core/terraform/modules/talos-cluster/outputs.tf`:

```hcl
output "machine_secrets" {
  description = "Talos machine secrets for backup (store in AWS Secrets Manager)"
  value       = talos_machine_secrets.this.machine_secrets
  sensitive   = true
}
```

- [ ] **Step 4: Add kubeconfig components output for Helm provider**

Add to `core/terraform/modules/talos-cluster/outputs.tf`:

```hcl
output "kubeconfig_raw" {
  description = "Raw kubeconfig for Helm/kubectl provider configuration"
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}
```

- [ ] **Step 5: Verify with terraform plan**

```bash
cd environments/prod/terraform
terraform plan -var="skip_health_check=true"
```

Expected: No changes to infrastructure (just provider constraint tightening and output additions).

- [ ] **Step 6: Commit**

```bash
git add core/terraform/modules/talos-cluster/main.tf core/terraform/modules/talos-cluster/outputs.tf environments/prod/terraform/main.tf
git commit -m "fix(terraform): pin provider versions, protect machine secrets, add backup outputs"
```

---

## Chunk 2: ArgoCD App-of-Apps Manifests

### Task 5: Create ArgoCD Application Manifests

The current root-app-template.yaml points to a nonexistent path. No child Application manifests exist. We need the complete app-of-apps tree.

**Files:**
- Create: `core/manifests/argocd/root-app.yaml`
- Create: `core/manifests/argocd/apps/cilium.yaml`
- Create: `core/manifests/argocd/apps/longhorn.yaml`
- Create: `core/manifests/argocd/apps/argocd.yaml`

- [ ] **Step 1: Create root Application**

This replaces the broken `root-app-template.yaml`. It points to the `core/manifests/argocd/apps/` directory where child Applications live.

Create `core/manifests/argocd/root-app.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/aaronreynoza/homelab.git
    targetRevision: main
    path: core/manifests/argocd/apps
    directory:
      recurse: false
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: false
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**Note:** `prune: false` for prod safety — ArgoCD won't delete resources removed from Git without manual confirmation. `selfHeal: true` restores drift.

- [ ] **Step 2: Create Cilium ArgoCD Application (wave 1)**

Create `core/manifests/argocd/apps/cilium.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cilium
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://helm.cilium.io/
    chart: cilium
    targetRevision: 1.16.5
    helm:
      valueFiles: []
      values: |
        ipam:
          mode: kubernetes
        kubeProxyReplacement: true
        k8sServiceHost: "REDACTED_K8S_API"
        k8sServicePort: "6443"
        bpf:
          masquerade: true
        MTU: 1450
        routingMode: native
        autoDirectNodeRoutes: true
        ipv4NativeRoutingCIDR: "10.244.0.0/16"
        securityContext:
          capabilities:
            ciliumAgent:
              - CHOWN
              - KILL
              - NET_ADMIN
              - NET_RAW
              - IPC_LOCK
              - SYS_ADMIN
              - SYS_RESOURCE
              - DAC_OVERRIDE
              - FOWNER
              - SETGID
              - SETUID
        hubble:
          enabled: true
          relay:
            enabled: true
          ui:
            enabled: true
        cgroup:
          autoMount:
            enabled: true
          hostRoot: /sys/fs/cgroup
        operator:
          replicas: 1
  destination:
    server: https://kubernetes.default.svc
    namespace: cilium
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

**Note:** Values are inline because ArgoCD can't reference local files from a Helm chart source. `ServerSideApply=true` prevents conflicts with the initial Terraform Helm install. No automated sync — Cilium upgrades are manual in prod.

- [ ] **Step 3: Create Longhorn ArgoCD Application (wave 2)**

Create `core/manifests/argocd/apps/longhorn.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: longhorn
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "2"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://charts.longhorn.io
    chart: longhorn
    targetRevision: 1.7.2
    helm:
      values: |
        defaultSettings:
          defaultReplicaCount: 1
          storageMinimalAvailablePercentage: 1
          defaultDataPath: "/var/mnt/u-longhorn"
  destination:
    server: https://kubernetes.default.svc
    namespace: longhorn-system
  syncPolicy:
    automated:
      prune: false
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

- [ ] **Step 4: Create ArgoCD self-management Application (wave 3)**

Create `core/manifests/argocd/apps/argocd.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "3"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://argoproj.github.io/argo-helm
    chart: argo-cd
    targetRevision: 7.7.10
    helm:
      values: |
        server:
          extraArgs:
            - --insecure
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
        controller:
          resources:
            requests:
              cpu: 250m
              memory: 256Mi
            limits:
              cpu: 1000m
              memory: 1Gi
        repoServer:
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
        applicationSet:
          enabled: true
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 250m
              memory: 256Mi
        notifications:
          enabled: false
        redis-ha:
          enabled: false
        dex:
          enabled: false
        configs:
          ssh:
            knownHosts: |
              github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
              github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

- [ ] **Step 5: Commit**

```bash
git add core/manifests/argocd/root-app.yaml core/manifests/argocd/apps/
git commit -m "feat(argocd): create app-of-apps manifests with sync waves (Cilium→Longhorn→ArgoCD)"
```

### Task 6: Update ArgoCD Values (resource limits + repo config)

**Files:**
- Modify: `core/charts/platform/argocd/values.yaml`

- [ ] **Step 1: Bump resource limits and add repo config**

Replace the entire file with:

```yaml
# ArgoCD Configuration
# Used for initial Helm install via Terraform. Once running, ArgoCD self-manages
# via the ArgoCD Application in core/manifests/argocd/apps/argocd.yaml.

server:
  extraArgs:
    - --insecure
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

controller:
  resources:
    requests:
      cpu: 250m
      memory: 256Mi
    limits:
      cpu: 1000m
      memory: 1Gi

repoServer:
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

applicationSet:
  enabled: true
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 250m
      memory: 256Mi

notifications:
  enabled: false

redis-ha:
  enabled: false

dex:
  enabled: false

configs:
  ssh:
    knownHosts: |
      github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
      github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
```

- [ ] **Step 2: Commit**

```bash
git add core/charts/platform/argocd/values.yaml
git commit -m "fix(argocd): bump controller limits to 1Gi, update resource requests"
```

---

## Chunk 3: Terraform Platform Automation

### Task 7: Add Helm Provider and Platform Stack to Terraform

This is the main automation task. After this, `terraform apply` creates the cluster AND installs Cilium + ArgoCD + applies the root Application. No manual helm commands.

**Files:**
- Modify: `environments/prod/terraform/main.tf`
- Modify: `environments/prod/terraform/variables.tf`

- [ ] **Step 1: Add Helm and kubectl providers to required_providers**

In `environments/prod/terraform/main.tf`, add to the `required_providers` block:

```hcl
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.19.0"
    }
```

- [ ] **Step 2: Add provider configurations after the module block**

Add after the `module "cluster"` block (after line 94):

```hcl
# Helm provider — uses kubeconfig from the cluster module
provider "helm" {
  kubernetes {
    host                   = module.cluster.cluster_endpoint
    client_certificate     = base64decode(yamldecode(module.cluster.kubeconfig_raw).users[0].user["client-certificate-data"])
    client_key             = base64decode(yamldecode(module.cluster.kubeconfig_raw).users[0].user["client-key-data"])
    cluster_ca_certificate = base64decode(yamldecode(module.cluster.kubeconfig_raw).clusters[0].cluster["certificate-authority-data"])
  }
}

# kubectl provider — for applying raw manifests (root Application)
provider "kubectl" {
  host                   = module.cluster.cluster_endpoint
  client_certificate     = base64decode(yamldecode(module.cluster.kubeconfig_raw).users[0].user["client-certificate-data"])
  client_key             = base64decode(yamldecode(module.cluster.kubeconfig_raw).users[0].user["client-key-data"])
  cluster_ca_certificate = base64decode(yamldecode(module.cluster.kubeconfig_raw).clusters[0].cluster["certificate-authority-data"])
  load_config_file       = false
}
```

- [ ] **Step 3: Add Cilium helm_release**

```hcl
# Install Cilium CNI — must be first, nodes are NotReady without it
resource "helm_release" "cilium" {
  depends_on = [module.cluster]

  name             = "cilium"
  repository       = "https://helm.cilium.io/"
  chart            = "cilium"
  version          = "1.16.5"
  namespace        = "cilium"
  create_namespace = true

  values = [file("${path.module}/../../../core/charts/platform/cilium/values.yaml")]

  # Wait for Cilium to be ready before proceeding
  wait    = true
  timeout = 600
}
```

- [ ] **Step 4: Add ArgoCD helm_release**

```hcl
# Install ArgoCD — depends on Cilium (needs CNI for pods)
resource "helm_release" "argocd" {
  depends_on = [helm_release.cilium]

  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.7.10"
  namespace        = "argocd"
  create_namespace = true

  values = [file("${path.module}/../../../core/charts/platform/argocd/values.yaml")]

  wait    = true
  timeout = 600
}
```

- [ ] **Step 5: Add root Application manifest**

```hcl
# Apply the root ArgoCD Application (triggers app-of-apps: Longhorn, etc.)
resource "kubectl_manifest" "argocd_root_app" {
  depends_on = [helm_release.argocd]

  yaml_body = file("${path.module}/../../../core/manifests/argocd/root-app.yaml")
}
```

- [ ] **Step 6: Add outputs for platform stack status**

Add to `environments/prod/terraform/main.tf`:

```hcl
output "cluster_endpoint" {
  value = module.cluster.cluster_endpoint
}

output "argocd_namespace" {
  value = helm_release.argocd.namespace
}

output "platform_stack" {
  value = "Cilium ${helm_release.cilium.version} + ArgoCD ${helm_release.argocd.version} installed. Root Application applied."
}
```

- [ ] **Step 7: Run terraform init to fetch new providers**

```bash
cd environments/prod/terraform
terraform init -backend-config=../backend.hcl
```

Expected: Downloads hashicorp/helm and gavinbunney/kubectl providers.

- [ ] **Step 8: Run terraform plan**

```bash
terraform plan -var="skip_health_check=true"
```

Expected: Shows creation of `helm_release.cilium`, `helm_release.argocd`, `kubectl_manifest.argocd_root_app`, plus the Talos config changes from Tasks 1-4.

- [ ] **Step 9: Commit**

```bash
git add environments/prod/terraform/main.tf environments/prod/terraform/variables.tf
git commit -m "feat(prod): automate platform stack via Terraform Helm provider (Cilium + ArgoCD + root app)"
```

---

## Chunk 4: Apply and Verify

### Task 8: Apply Everything and Verify

This is the execution task. One `terraform apply` should provision the updated configs AND install the platform stack.

- [ ] **Step 1: Apply terraform**

```bash
cd environments/prod/terraform
terraform apply -var="skip_health_check=true"
```

Expected sequence:
1. Talos config patches updated on all 3 nodes (nameservers, Longhorn disk fix)
2. Cilium installs (helm_release), nodes transition to Ready
3. ArgoCD installs (helm_release)
4. Root Application applied (kubectl_manifest)
5. ArgoCD picks up child apps: Longhorn (wave 2), ArgoCD self-management (wave 3)

- [ ] **Step 2: Verify nodes are Ready**

```bash
export KUBECONFIG=../kubeconfig
kubectl get nodes
```

Expected: All 3 nodes show `Ready` status.

- [ ] **Step 3: Verify Cilium**

```bash
kubectl -n cilium get pods
kubectl -n cilium exec ds/cilium -- cilium status --brief
```

Expected: All Cilium pods Running, connectivity OK.

- [ ] **Step 4: Verify ArgoCD**

```bash
kubectl -n argocd get pods
```

Expected: All ArgoCD pods Running.

- [ ] **Step 5: Get ArgoCD admin password**

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

- [ ] **Step 6: Port forward and check ArgoCD UI**

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open https://localhost:8080, login with `admin` + password from step 5. Verify:
- Root Application is Healthy/Synced
- Cilium Application exists (wave 1)
- Longhorn Application exists and syncing (wave 2)
- ArgoCD self-management Application exists (wave 3)

- [ ] **Step 7: Verify Longhorn (deployed by ArgoCD)**

```bash
kubectl -n longhorn-system get pods
kubectl -n longhorn-system get nodes.longhorn.io -o wide
```

Expected: Longhorn pods Running, worker nodes show available storage at `/var/mnt/u-longhorn`.

- [ ] **Step 8: Test PVC creation**

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
# Expected: Bound within 60 seconds
kubectl delete pvc test-pvc
```

- [ ] **Step 9: Reboot workers to pick up disk config changes**

The `machine.disks` config change may require a reboot on workers:

```bash
export TALOSCONFIG=../talosconfig
talosctl --nodes 10.10.10.20 reboot --wait=false
talosctl --nodes 10.10.10.21 reboot --wait=false
```

Wait 60 seconds, then verify mounts:

```bash
talosctl --nodes 10.10.10.20 mounts | grep longhorn
talosctl --nodes 10.10.10.21 mounts | grep longhorn
```

Expected: `/var/mnt/u-longhorn` mounted from `/dev/vdb1`.

- [ ] **Step 10: Commit any remaining changes and update runbook**

```bash
git add -A
git commit -m "docs: update runbook with automated platform stack deployment"
```

---

## Post-Deployment Notes

### What's automated now:
- `terraform apply` → VMs + Talos + Cilium + ArgoCD + root Application
- ArgoCD manages: Longhorn, ArgoCD self-management, future apps

### What's still manual:
- Talos image schematic generation (one-time, at factory.talos.dev)
- OPNSense firewall rules (WAN→PROD pass, NAT exceptions)
- Static route on Mac (`sudo route add -net 10.10.0.0/16 REDACTED_OPNSENSE_IP`)
- Worker reboot after first deploy (for disk partition changes)
- DHCP reservation for OPNSense WAN IP (needs router access)

### Next steps (not in this plan):
- Deploy Newt as Talos system extension for Pangolin connectivity
- Install ctrld on OPNSense, switch DNS from 8.8.8.8 to 10.10.10.1
- Deploy first application via ArgoCD
- Configure OPNSense WAN as static IP
- Switch outbound NAT to full manual mode
