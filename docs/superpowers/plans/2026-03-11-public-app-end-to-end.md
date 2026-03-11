# Public App End-to-End Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One `terraform apply` from bare metal to a publicly accessible app through Pangolin, with zero manual steps between apply and verification.

**Architecture:** Terraform provisions VMs + Talos cluster, installs Cilium + ArgoCD via Helm provider, waits for workers to be ready (disk partitioning), then ArgoCD deploys Longhorn + future apps. Newt system extension establishes a WireGuard tunnel to the Pangolin VPS for public ingress. A test nginx app validates the full traffic path.

**Tech Stack:** Terraform (bpg/proxmox, siderolabs/talos, hashicorp/helm, gavinbunney/kubectl), Talos Linux v1.11.3, Cilium 1.16.5, ArgoCD 7.7.10, Longhorn 1.7.2, Newt (Talos system extension), Pangolin (Vultr VPS)

---

## File Structure

### Files to modify:
- `environments/prod/terraform/main.tf` — add local_file, null_resource wait, null/local providers, pass Newt vars
- `environments/prod/terraform/variables.tf` — add Newt variables for prod
- `environments/prod/terraform/terraform.tfvars` — update Talos image URL with Newt schematic, add Newt creds
- `core/terraform/modules/talos-cluster/main.tf` — add Newt config patch locals
- `core/terraform/modules/talos-cluster/variables.tf` — add Newt variables

### Files to create:
- `core/terraform/modules/talos-cluster/scripts/wait-for-nodes.sh` — wait for nodes Ready after Cilium
- `core/manifests/argocd/apps/nginx-test.yaml` — test app to validate full traffic path
- `docs/issues/backlog.md` — documented future tasks (deferred work)

### Files NOT changed (documented why):
- `core/charts/platform/cilium/values.yaml` — already fixed in prior plan
- OPNSense config — already working, firewall rules in place

---

## Chunk 1: Worker Readiness + Newt Extension

### Task 1: Add Worker Readiness Wait to Terraform

After `terraform apply` updates worker machine configs and Cilium is installed, the workers may need a reboot for `machine.disks` to partition `/dev/vdb`. We need Terraform to wait for nodes to actually be Ready before ArgoCD tries to deploy Longhorn.

**Files:**
- Create: `core/terraform/modules/talos-cluster/scripts/wait-for-nodes.sh`
- Modify: `core/terraform/modules/talos-cluster/main.tf:200-221`
- Modify: `core/terraform/modules/talos-cluster/outputs.tf`

- [ ] **Step 1: Create the wait-for-nodes script**

Create `core/terraform/modules/talos-cluster/scripts/wait-for-nodes.sh`:

```bash
#!/usr/bin/env bash
# Wait for all cluster nodes to be Ready.
# Called by Terraform null_resource after Cilium is installed.
# Usage: wait-for-nodes.sh <kubeconfig-path> <expected-node-count> <timeout-seconds>
set -euo pipefail

KUBECONFIG_PATH="$1"
EXPECTED_NODES="${2:-3}"
TIMEOUT="${3:-300}"

echo "Waiting for $EXPECTED_NODES nodes to be Ready (timeout: ${TIMEOUT}s)..."

start=$(date +%s)
while true; do
  ready_count=$(KUBECONFIG="$KUBECONFIG_PATH" kubectl get nodes --no-headers 2>/dev/null \
    | grep -c ' Ready' || echo "0")

  if [ "$ready_count" -ge "$EXPECTED_NODES" ]; then
    echo "All $ready_count/$EXPECTED_NODES nodes are Ready."
    exit 0
  fi

  elapsed=$(( $(date +%s) - start ))
  if [ "$elapsed" -ge "$TIMEOUT" ]; then
    echo "ERROR: Timed out after ${TIMEOUT}s. Only $ready_count/$EXPECTED_NODES nodes Ready."
    KUBECONFIG="$KUBECONFIG_PATH" kubectl get nodes 2>/dev/null || true
    exit 1
  fi

  echo "  $ready_count/$EXPECTED_NODES Ready (${elapsed}s elapsed)..."
  sleep 10
done
```

- [ ] **Step 2: Make the script executable**

```bash
chmod +x core/terraform/modules/talos-cluster/scripts/wait-for-nodes.sh
```

- [ ] **Step 3: Add kubeconfig file output and talosconfig output to the module**

In `core/terraform/modules/talos-cluster/outputs.tf`, add:

```hcl
output "talosconfig" {
  description = "Talos client configuration for talosctl"
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}
```

Note: `talosconfig` output may already exist — check first. If it does, skip this step.

- [ ] **Step 4: Add null_resource for writing kubeconfig to disk + waiting**

**Prerequisite:** `kubectl` must be installed on the machine running `terraform apply`. This is already the case for any machine with `talosctl` and Helm CLI.

In `environments/prod/terraform/main.tf`, add after `helm_release.cilium` but before `helm_release.argocd`:

```hcl
# Write kubeconfig to temp file for scripts
resource "local_file" "kubeconfig" {
  depends_on = [module.cluster]

  content         = module.cluster.kubeconfig_raw
  filename        = "${path.module}/.kubeconfig"
  file_permission = "0600"
}

# Wait for all nodes to be Ready after Cilium installs
resource "null_resource" "wait_for_nodes" {
  depends_on = [helm_release.cilium, local_file.kubeconfig]

  provisioner "local-exec" {
    command = "${path.module}/../../../core/terraform/modules/talos-cluster/scripts/wait-for-nodes.sh ${local_file.kubeconfig.filename} ${length(var.control_planes) + length(var.workers)} 300"
  }
}
```

Then update `helm_release.argocd` to depend on the wait:

```hcl
resource "helm_release" "argocd" {
  depends_on = [null_resource.wait_for_nodes]
  # ... rest unchanged
}
```

Also add `local` and `null` to required_providers in `environments/prod/terraform/main.tf`:

```hcl
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.0"
    }
```

- [ ] **Step 5: Add .kubeconfig to .gitignore**

Add to `environments/prod/terraform/.gitignore` (create if needed):

```
.kubeconfig
.terraform/
```

- [ ] **Step 6: Verify with terraform plan**

```bash
cd environments/prod/terraform
terraform init -backend-config=../backend.hcl
terraform plan -var-file=terraform.tfvars
```

Expected: Shows new `local_file.kubeconfig`, `null_resource.wait_for_nodes`, and updated `helm_release.argocd` dependency.

- [ ] **Step 7: Commit**

```bash
git add core/terraform/modules/talos-cluster/scripts/wait-for-nodes.sh
git add environments/prod/terraform/.gitignore
git commit -m "feat(terraform): add node readiness wait after Cilium install

Adds a script + null_resource that waits for all nodes to be Ready
before ArgoCD is installed. This ensures Longhorn can schedule on
workers whose disks have been partitioned."
```

### Task 2: Generate Talos Factory Schematic with Newt Extension

The current Talos image does NOT include the Newt system extension. Without Newt, there is no WireGuard tunnel to Pangolin, so no public access.

**Files:**
- Modify: `environments/prod/terraform/terraform.tfvars:12`

- [ ] **Step 1: Generate a new Talos Factory schematic**

Go to https://factory.talos.dev and create a schematic with these system extensions for Talos v1.11.3:
- `siderolabs/qemu-guest-agent` — Proxmox VM agent
- `siderolabs/iscsi-tools` — required by Longhorn
- `siderolabs/util-linux-tools` — required by Longhorn
- `siderolabs/newt` — Pangolin agent (WireGuard tunnel)

The factory will output a schematic ID (64-char hex string) and an image URL.

- [ ] **Step 2: Update terraform.tfvars with the new image URL**

Replace line 12 in `environments/prod/terraform/terraform.tfvars`:

```hcl
talos_image_url = "https://factory.talos.dev/image/<NEW_SCHEMATIC_ID>/v1.11.3/nocloud-amd64.raw.zst"
```

Where `<NEW_SCHEMATIC_ID>` is the hex string from factory.talos.dev.

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(talos): update image schematic to include Newt extension"
```

**Note:** This is a manual step (factory.talos.dev is a web UI). The schematic only needs regenerating when you change extensions or upgrade Talos versions.

### Task 3: Add Newt Configuration to Talos Machine Config

Newt needs to know the Pangolin endpoint URL, site ID, and auth token. These are stored in AWS Secrets Manager and injected into the Talos machine config as environment variables for the Newt extension.

**Files:**
- Modify: `core/terraform/modules/talos-cluster/main.tf:121-166`
- Modify: `core/terraform/modules/talos-cluster/variables.tf`
- Modify: `environments/prod/terraform/main.tf:65-101` (module call)
- Modify: `environments/prod/terraform/variables.tf`

- [ ] **Step 1: Add Newt variables to the talos-cluster module**

Add to `core/terraform/modules/talos-cluster/variables.tf`:

```hcl
# Newt (Pangolin agent) configuration
variable "newt_enabled" {
  description = "Enable Newt system extension for Pangolin connectivity"
  type        = bool
  default     = false
}

variable "newt_endpoint" {
  description = "Pangolin endpoint URL (e.g., https://pangolin.example.com)"
  type        = string
  default     = ""
}

variable "newt_id" {
  description = "Newt site ID from Pangolin"
  type        = string
  default     = ""
  sensitive   = true
}

variable "newt_secret" {
  description = "Newt auth secret from Pangolin"
  type        = string
  default     = ""
  sensitive   = true
}
```

- [ ] **Step 2: Add Newt config patch to the locals block in main.tf**

Add a new local in `core/terraform/modules/talos-cluster/main.tf` inside the `locals {}` block, after `worker_config_patch`:

```hcl
  # Newt system extension config (Pangolin agent)
  newt_config_patch = var.newt_enabled ? yamlencode({
    machine = {
      files = [
        {
          content     = join("\n", [
            "NEWT_ENDPOINT=${var.newt_endpoint}",
            "NEWT_ID=${var.newt_id}",
            "NEWT_SECRET=${var.newt_secret}",
          ])
          path        = "/var/etc/newt/env"
          permissions = 384  # 0600
          op          = "create"
        }
      ]
    }
  }) : null
```

- [ ] **Step 3: Add Newt patch to control plane and worker config_patches**

Newt should run on all nodes (or at minimum the control plane). Update both `config_patches`:

For control planes (line ~177):
```hcl
  config_patches = var.newt_enabled ? [local.common_config_patch, local.newt_config_patch] : [local.common_config_patch]
```

For workers (line ~189):
```hcl
  config_patches = var.newt_enabled ? [local.common_config_patch, local.worker_config_patch, local.newt_config_patch] : [local.common_config_patch, local.worker_config_patch]
```

This uses a conditional expression instead of `compact()`, which avoids type issues — `compact()` only removes empty strings, not `null` values.

- [ ] **Step 4: Add Newt variables to prod environment**

Add to `environments/prod/terraform/variables.tf`:

```hcl
# Newt (Pangolin connectivity)
variable "newt_enabled" {
  description = "Enable Newt system extension"
  type        = bool
  default     = false
}

variable "newt_endpoint" {
  description = "Pangolin endpoint URL"
  type        = string
  default     = ""
}

variable "newt_id" {
  description = "Newt site ID"
  type        = string
  default     = ""
  sensitive   = true
}

variable "newt_secret" {
  description = "Newt auth secret"
  type        = string
  default     = ""
  sensitive   = true
}
```

- [ ] **Step 5: Pass Newt variables through in prod main.tf module call**

Add inside the `module "cluster"` block in `environments/prod/terraform/main.tf`:

```hcl
  # Newt (Pangolin agent)
  newt_enabled  = var.newt_enabled
  newt_endpoint = var.newt_endpoint
  newt_id       = var.newt_id
  newt_secret   = var.newt_secret
```

- [ ] **Step 6: Add Newt values to terraform.tfvars**

Add to `environments/prod/terraform/terraform.tfvars`:

```hcl
# Newt — Pangolin agent for public ingress
# Get these from Pangolin dashboard > Sites > your site
newt_enabled  = true
newt_endpoint = "https://pangolin.example.com"  # Replace with actual Pangolin URL
newt_id       = ""  # Fill from Pangolin dashboard
newt_secret   = ""  # Fill from Pangolin dashboard
```

**IMPORTANT:** The `newt_id` and `newt_secret` values must be filled manually from the Pangolin dashboard. These are the site credentials that Newt uses to authenticate. Alternatively, store them in AWS Secrets Manager and fetch them like Proxmox creds.

- [ ] **Step 7: Verify with terraform plan**

```bash
cd environments/prod/terraform
terraform plan -var-file=terraform.tfvars
```

Expected: Shows `talos_machine_configuration_apply` changes (new Newt config patch in machine files).

- [ ] **Step 8: Commit**

```bash
git add core/terraform/modules/talos-cluster/main.tf core/terraform/modules/talos-cluster/variables.tf
git add environments/prod/terraform/variables.tf
git commit -m "feat(newt): add Pangolin Newt config to Talos machine patches

Newt runs as a Talos system extension and establishes a WireGuard
tunnel to the Pangolin VPS for public ingress. Config is injected
via machine.files into /var/etc/newt/env."
```

---

## Chunk 2: Test App + Merge + Deploy

### Task 4: Create Test App ArgoCD Application

A simple nginx deployment to validate the full traffic path: ArgoCD → K8s → Newt → Pangolin → public URL.

**Files:**
- Create: `core/manifests/argocd/apps/nginx-test.yaml`

- [ ] **Step 1: Create the nginx test Application**

Create `core/manifests/argocd/apps/nginx-test.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx-test
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "10"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/aaronreynoza/homelab.git
    targetRevision: main
    path: core/manifests/apps/nginx-test
  destination:
    server: https://kubernetes.default.svc
    namespace: nginx-test
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

- [ ] **Step 2: Create the nginx-test manifests directory**

Create `core/manifests/apps/nginx-test/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-test
  namespace: nginx-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-test
  template:
    metadata:
      labels:
        app: nginx-test
    spec:
      containers:
        - name: nginx
          image: nginx:1.27-alpine
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: 10m
              memory: 16Mi
            limits:
              cpu: 50m
              memory: 32Mi
```

Create `core/manifests/apps/nginx-test/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-test
  namespace: nginx-test
spec:
  selector:
    app: nginx-test
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
```

- [ ] **Step 3: Commit**

```bash
git add core/manifests/argocd/apps/nginx-test.yaml core/manifests/apps/nginx-test/
git commit -m "feat(apps): add nginx-test for validating full traffic path

Simple nginx deployment managed by ArgoCD. Used to validate:
Pangolin VPS → Newt tunnel → K8s service → pod"
```

### Task 5: Merge to Main and Deploy

The root ArgoCD Application targets `main` branch. All manifests must be on `main` for ArgoCD to find them.

- [ ] **Step 1: Verify all changes are committed**

```bash
git status
git log --oneline -10
```

Expected: Clean working tree, all changes committed on `refactor/modular-structure`.

- [ ] **Step 2: Merge to main**

```bash
git checkout main
git merge refactor/modular-structure --no-ff -m "Merge refactor/modular-structure: cluster fixes, platform automation, Newt integration"
```

- [ ] **Step 3: Connect to office router wifi**

Required for VLAN routing (management network → PROD VLAN 10 via OPNSense). Verify:

```bash
ping -c 3 10.10.10.1  # OPNSense PROD interface
```

If no route, add: `sudo route add -net 10.10.0.0/16 REDACTED_OPNSENSE_IP`

- [ ] **Step 4: Run terraform init**

```bash
cd environments/prod/terraform
terraform init -backend-config=../backend.hcl
```

Expected: Downloads `hashicorp/helm`, `gavinbunney/kubectl`, `hashicorp/local` providers.

- [ ] **Step 5: Run terraform plan**

```bash
terraform plan -var-file=terraform.tfvars
```

Review carefully. Expected changes:
- `talos_machine_configuration_apply.worker` — config patches updated (machine.disks + Newt)
- `talos_machine_configuration_apply.control_plane` — config patches updated (Newt)
- `helm_release.cilium` — NEW
- `null_resource.wait_for_nodes` — NEW
- `helm_release.argocd` — NEW
- `kubectl_manifest.argocd_root_app` — NEW
- `local_file.kubeconfig` — NEW

VMs should show NO changes (already exist).

- [ ] **Step 6: Run terraform apply**

```bash
terraform apply -var-file=terraform.tfvars
```

Expected sequence (5-10 minutes):
1. Talos config patches applied to all nodes
2. Cilium installed → nodes go Ready (~60-90s)
3. `wait_for_nodes` script confirms all 3 nodes Ready
4. ArgoCD installed
5. Root Application applied
6. ArgoCD syncs child apps: Cilium (wave 1), Longhorn (wave 2), ArgoCD self-mgmt (wave 3), nginx-test (wave 10)

- [ ] **Step 7: Verify cluster health**

```bash
export KUBECONFIG=environments/prod/terraform/.kubeconfig
kubectl get nodes                        # All 3 nodes Ready
kubectl -n cilium get pods               # Cilium agents Running
kubectl -n argocd get pods               # ArgoCD pods Running
kubectl -n argocd get applications       # Root + child apps
kubectl -n longhorn-system get pods      # Longhorn Running
kubectl -n nginx-test get pods           # nginx-test Running
```

- [ ] **Step 8: Reboot workers if Longhorn disks not mounted**

Check if disk partitioning happened:

```bash
talosctl --talosconfig environments/prod/talosconfig --nodes 10.10.10.20 mounts | grep longhorn
```

If `/var/mnt/u-longhorn` is NOT mounted:

```bash
talosctl --talosconfig environments/prod/talosconfig --nodes 10.10.10.20 reboot --wait=false
talosctl --talosconfig environments/prod/talosconfig --nodes 10.10.10.21 reboot --wait=false
```

Wait 2 minutes, verify:

```bash
talosctl --talosconfig environments/prod/talosconfig --nodes 10.10.10.20 mounts | grep longhorn
talosctl --talosconfig environments/prod/talosconfig --nodes 10.10.10.21 mounts | grep longhorn
```

Expected: `/var/mnt/u-longhorn` mounted from `/dev/vdb1`.

- [ ] **Step 9: Verify Newt connection to Pangolin**

Check Pangolin dashboard (https://pangolin.example.com) → Sites → your site. Status should show "Connected".

If not connected, check Newt logs on a node:

```bash
talosctl --talosconfig environments/prod/talosconfig --nodes REDACTED_K8S_API logs ext-newt
```

- [ ] **Step 10: Create Pangolin resource for nginx-test**

In the Pangolin dashboard:
1. Go to Resources → Add Resource
2. Domain: `test.<your-domain>` (e.g., `test.example.com`)
3. Target: `http://nginx-test.nginx-test.svc.cluster.local:80`
4. Site: your homelab site
5. Save — Pangolin auto-provisions TLS

- [ ] **Step 11: Test public access**

From ANY network (phone cellular, different wifi):

```bash
curl -v https://test.<your-domain>/
```

Expected: nginx default page. TLS valid (Let's Encrypt via Pangolin).

- [ ] **Step 12: Commit any remaining changes**

```bash
git add -A
git commit -m "docs: update with deployment verification notes"
```

---

## Chunk 3: Document Deferred Work

### Task 6: Create Backlog Document

Document all future tasks that were identified during this project but deferred to keep scope focused.

**Files:**
- Create: `docs/issues/backlog.md`

- [ ] **Step 1: Create the backlog document**

Create `docs/issues/backlog.md`:

```markdown
# Deferred Work Backlog

Tasks identified during cluster setup that are not needed for the initial deployment but should be addressed for production readiness.

## Priority 1: Ops Maturity (Next Sprint)

### Templatize environment-specific values
- **Why:** Cilium `k8sServiceHost: "REDACTED_K8S_API"` and Pangolin URLs are hardcoded in ArgoCD manifests
- **Fix:** Use `templatefile()` in `environments/prod/terraform/main.tf` to render manifests with env-specific variables, or move manifests to `environments/<env>/manifests/`
- **Blocks:** Dev cluster deployment

### Store Newt credentials in AWS Secrets Manager
- **Why:** Currently in terraform.tfvars (gitignored, but risky)
- **Fix:** Add `data "aws_secretsmanager_secret_version" "newt"` like Proxmox creds
- **Blocks:** Nothing (works as-is, just better practice)

### Automate worker reboot for disk partitioning
- **Why:** `machine.disks` only applies on reboot. Current flow may need manual reboot.
- **Fix:** Add `null_resource` with `talosctl reboot` + readiness poll after config apply
- **Alternative:** Investigate if Talos auto-reboots on disk config change in `auto` apply mode

### Pre-commit hooks
- **Why:** No linting or validation before commits
- **Fix:** Add `terraform fmt`, `terraform validate`, YAML lint, Helm lint
- **Effort:** Half day

## Priority 2: Production Hardening

### TrueNAS VM for NFS storage
- **Decision doc:** `docs/decisions/002-truenas-storage.md`
- **Plan:** `docs/superpowers/plans/` (TrueNAS plan exists)
- **Why deferred:** Longhorn on local disks works for initial deployment

### ctrld on OPNSense for DNS management
- **Decision doc:** `docs/decisions/003-pangolin-controld-architecture.md`
- **Why:** Split-horizon DNS, per-VLAN filtering, encrypted DoH3
- **Why deferred:** DNS works fine with 8.8.8.8 for now. No internal DNS needed yet.
- **Steps:** Install ctrld, configure per-VLAN policies, replace Unbound

### OPNSense API automation
- **Why:** Firewall rules are currently manual via Web UI
- **Fix:** OPNSense has a REST API at `/api/`. Could use Terraform `http` provider or community `browningluke/opnsense` provider
- **Why deferred:** OPNSense is already configured correctly, rules rarely change

### Velero + Longhorn backups to S3
- **Why:** No disaster recovery for persistent data
- **Fix:** Deploy Velero via ArgoCD, configure S3 backend
- **Issue:** `docs/issues/005-backup-disaster-recovery.md`

### CARP HA for OPNSense
- **Issue:** `docs/issues/001-opnsense-carp-ha.md`
- **Why deferred:** Requires second OPNSense VM, adds complexity

### Longhorn replica increase
- **Issue:** `docs/issues/003-longhorn-replica-strategy.md`
- **Current:** replica: 1 (single-node storage, data loss risk)
- **Fix:** Increase to 2 when 3+ workers with data disks

## Priority 3: Dev Environment

### Deploy dev cluster on VLAN 11
- **Why:** Need isolated testing environment
- **Blocks:** Templatized manifests (Priority 1)
- **Steps:** New `environments/dev/` directory, different IPs, same modules
- **Network:** 10.11.10.0/16, VLAN 11, gateway 10.11.10.1

### Harbor container registry per environment
- **Why:** Private image registry, vulnerability scanning
- **Why deferred:** Public images work fine for initial apps

## Priority 4: Applications

### Race telemetry app
- **Why:** Production workload with paying clients
- **Blocks:** Full traffic path validated (nginx-test)
- **Steps:** ArgoCD Application manifest, Pangolin resource, domain config

### Media services (Jellyfin, etc.)
- **Why:** Personal use
- **Why deferred:** Not urgent, deploy after telemetry app

## Won't Do (Decided Against)

### Ansible for Talos operations
- **Why not:** Talos is immutable and API-driven. No SSH, no shell. `talosctl` and Terraform provider handle everything. Adding Ansible creates unnecessary tool sprawl.
- **Reference:** PM analysis from 2026-03-11 expert review

### Cloudflare Tunnel
- **Why not:** See ADR-003. Conflicts with learning goals and traffic ownership.

---

**Last Updated:** 2026-03-11
```

- [ ] **Step 2: Update CLAUDE.md next tasks section**

In `CLAUDE.md`, update the "Next Tasks" section to reflect current state:

Replace the current next tasks with:
```markdown
**Next Tasks** (in order):
1. Generate Talos Factory schematic with Newt extension (manual: factory.talos.dev)
2. Fill Newt credentials in terraform.tfvars (from Pangolin dashboard)
3. Merge `refactor/modular-structure` to `main`
4. `terraform apply` — deploys full platform stack + nginx-test app
5. Create Pangolin resource for test app (manual: Pangolin dashboard)
6. Verify public access to test app
7. Deploy race telemetry app via ArgoCD

See [docs/issues/backlog.md](docs/issues/backlog.md) for deferred work.
```

- [ ] **Step 3: Commit**

```bash
git add docs/issues/backlog.md CLAUDE.md
git commit -m "docs: add deferred work backlog and update CLAUDE.md next tasks"
```

---

## Post-Deployment Notes

### What's automated after this plan:
- `terraform apply` → VMs + Talos + Cilium + wait for Ready + ArgoCD + root Application + Longhorn + nginx-test
- ArgoCD manages all apps — push a manifest to `core/manifests/argocd/apps/`, it auto-deploys
- Newt tunnel establishes automatically on boot (Talos system extension)

### What remains manual (one-time):
- Talos Factory schematic generation (per Talos version upgrade)
- Newt credentials from Pangolin dashboard (per site, one-time)
- Pangolin resource creation (per public app, 5 min via dashboard)
- Worker reboot IF disk partitioning didn't apply (check, then reboot if needed)
- Static route on Mac for VLAN access (`sudo route add`)

### What remains manual (won't automate):
- OPNSense initial setup (already done, one-time)
- Home router static routes (consumer router, no API)

### Verification checklist:
```bash
# Cluster
kubectl get nodes                                    # 3 nodes Ready
kubectl -n cilium exec ds/cilium -- cilium status    # Cilium healthy

# Platform
kubectl -n argocd get applications                   # All apps Synced/Healthy
kubectl -n longhorn-system get pods                  # Longhorn running

# Storage
kubectl -n longhorn-system get nodes.longhorn.io     # Workers show disk space

# Connectivity
talosctl --nodes REDACTED_K8S_API logs ext-newt           # Newt connected
curl https://test.<domain>/                          # Public access works
```
