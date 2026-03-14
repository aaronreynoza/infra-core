# Zitadel SSO Terraform Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Configure Zitadel SSO for all homelab apps using Terraform to create OIDC applications and distribute client secrets as K8s secrets.

**Architecture:** Terraform live config at `core/terraform/live/zitadel/` uses the official `zitadel/zitadel` provider (PAT auth via SOPS) and `hashicorp/kubernetes` provider (kubeconfig on mgmt VM) to create a project, 9 OIDC apps, K8s secrets in target namespaces, and human users. ArgoCD Application manifests are then updated to enable OIDC login.

**Tech Stack:** Terraform, Zitadel provider v2.10+, Kubernetes provider, SOPS (carlpett/sops), ArgoCD, Helm

**Spec:** `docs/superpowers/specs/2026-03-13-zitadel-sso-design.md`

---

## File Structure

| File | Responsibility |
|------|---------------|
| `core/terraform/live/zitadel/versions.tf` (create) | Provider version constraints (zitadel, kubernetes, sops) |
| `core/terraform/live/zitadel/variables.tf` (create) | Input variables: Zitadel URL, app redirect URIs, user config, secret toggle flags |
| `core/terraform/live/zitadel/main.tf` (create) | Providers, SOPS data source, Zitadel project, OIDC apps, K8s secrets, users |
| `core/terraform/live/zitadel/outputs.tf` (create) | Client IDs per app (no secrets in output) |
| `environments/prod/zitadel/backend.hcl` (create) | S3 backend config for zitadel state |
| `environments/prod/zitadel/terraform.tfvars` (create) | Non-sensitive vars: Zitadel URL, redirect URIs, user emails |
| `environments/prod/zitadel/secrets.enc.yaml` (create) | SOPS-encrypted Zitadel PAT |
| `core/manifests/argocd/apps/argocd.yaml` (modify) | Add OIDC config to ArgoCD Helm values |
| `core/manifests/argocd/apps/forgejo.yaml` (modify) | Enable OAuth2 with Zitadel provider |
| `core/manifests/argocd/apps/harbor.yaml` (modify) | Add OIDC auth mode |
| `core/manifests/argocd/apps/kube-prometheus-stack.yaml` (modify) | Add Grafana generic_oauth config |

---

## Chunk 1: PAT Bootstrapping

### Task 1: Verify Zitadel Health and Get LoadBalancer IP

**Context:** Before anything, confirm Zitadel is running and find its IP. The Helm chart's initJob creates the initial instance.

- [ ] **Step 1: Check Zitadel pods are running**

```bash
kubectl get pods -n zitadel
```

Expected: `zitadel-0` in Running state, init job completed.

- [ ] **Step 2: Get Zitadel's LoadBalancer IP**

```bash
kubectl get svc -n zitadel -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].status.loadBalancer.ingress[0].ip}'
```

Record this IP — it will be used as `zitadel_url` throughout. Format: `http://<IP>:8080`

- [ ] **Step 3: Verify Zitadel is accessible from mgmt VM**

```bash
ssh admin@REDACTED_MGMT_IP "curl -s http://<ZITADEL_IP>:8080/debug/ready"
```

Expected: `ok` response confirming Zitadel is healthy.

---

### Task 2: Bootstrap PAT for Terraform

**Context:** The Terraform provider needs a Personal Access Token (PAT) to authenticate. Check if the Helm chart created one automatically, otherwise create it manually via the Zitadel console.

- [ ] **Step 1: Check if PAT secret exists**

```bash
kubectl get secret -n zitadel | grep -E "iam-admin|pat"
```

If a secret like `iam-admin-pat` exists, extract it:

```bash
kubectl get secret iam-admin-pat -n zitadel -o jsonpath='{.data.pat}' | base64 -d
```

If no PAT secret exists, proceed to Step 2.

- [ ] **Step 2: (If no PAT) Get initial admin credentials**

Check the Zitadel setup job logs for the initial admin credentials:

```bash
kubectl logs -n zitadel -l app.kubernetes.io/component=setup --tail=100
```

Or check for machine key secrets:

```bash
kubectl get secrets -n zitadel -o name | grep -i admin
```

- [ ] **Step 3: (If no PAT) Create PAT via Zitadel console**

1. Open browser to `http://<ZITADEL_IP>:8080/ui/console`
2. Log in with initial admin credentials from Step 2
3. Navigate to **Users** → find the admin machine user (or create one)
4. If creating new: **Users** → **Service Users** → **New** → Name: `terraform`, Access Token Type: `Bearer`
5. Go to the user → **Personal Access Tokens** → **New**
6. Set expiration (or no expiration for homelab)
7. Copy the PAT value

- [ ] **Step 4: SOPS-encrypt the PAT**

```bash
mkdir -p environments/prod/zitadel
cat > /tmp/zitadel-secrets.yaml << 'EOF'
pat: "<PASTE_PAT_VALUE_HERE>"
EOF
export SOPS_AGE_KEY_FILE="/Users/aaronvaldez/.config/sops/age/keys.txt"
sops -e --age age19ddrrdwawdwntvjuufh06gav90svgzugaaflv08esqsnq2ntkcdsyv2fmd /tmp/zitadel-secrets.yaml > environments/prod/zitadel/secrets.enc.yaml
rm /tmp/zitadel-secrets.yaml
```

Verify it decrypts:

```bash
sops -d environments/prod/zitadel/secrets.enc.yaml
```

Expected: `pat: <the-actual-pat-value>`

---

## Chunk 2: Terraform Scaffolding

### Task 3: Create Backend Config

**Files:**
- Create: `environments/prod/zitadel/backend.hcl`

- [ ] **Step 1: Create backend.hcl**

```hcl
bucket         = "homelab-terraform-state-REDACTED_AWS_ACCOUNT"
key            = "zitadel/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "homelab-terraform-locks"
encrypt        = true
```

---

### Task 4: Create Terraform Version Constraints

**Files:**
- Create: `core/terraform/live/zitadel/versions.tf`

- [ ] **Step 1: Create versions.tf**

```hcl
terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    # Configure via: terraform init -backend-config=../../../../environments/prod/zitadel/backend.hcl
  }

  required_providers {
    zitadel = {
      source  = "zitadel/zitadel"
      version = ">= 2.10.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = ">= 1.1.0"
    }
  }
}
```

---

### Task 5: Create Variables

**Files:**
- Create: `core/terraform/live/zitadel/variables.tf`

- [ ] **Step 1: Create variables.tf**

```hcl
# --- Zitadel connection ---
variable "zitadel_url" {
  description = "Zitadel instance URL (e.g., http://10.10.10.X:8080)"
  type        = string
}

variable "zitadel_port" {
  description = "Zitadel port"
  type        = string
  default     = "8080"
}

variable "sops_secrets_path" {
  description = "Path to SOPS-encrypted secrets file"
  type        = string
  default     = "../../../../environments/prod/zitadel/secrets.enc.yaml"
}

# --- Kubeconfig ---
variable "kubeconfig_path" {
  description = "Path to kubeconfig file for Kubernetes provider"
  type        = string
  default     = "~/.kube/config"
}

# --- Redirect URIs (populated from kubectl get svc output) ---
variable "argocd_url" {
  description = "ArgoCD base URL (e.g., http://REDACTED_LB_IP:8080)"
  type        = string
}

variable "forgejo_url" {
  description = "Forgejo base URL (e.g., http://REDACTED_LB_IP:3000)"
  type        = string
}

variable "harbor_url" {
  description = "Harbor base URL (e.g., http://REDACTED_LB_IP)"
  type        = string
}

variable "grafana_url" {
  description = "Grafana base URL (e.g., http://REDACTED_LB_IP:3000)"
  type        = string
}

# --- User management ---
variable "admin_email" {
  description = "Primary admin user email"
  type        = string
}

variable "admin_first_name" {
  description = "Primary admin first name"
  type        = string
}

variable "admin_last_name" {
  description = "Primary admin last name"
  type        = string
}

variable "additional_users" {
  description = "Additional users with app-level access"
  type = list(object({
    email      = string
    first_name = string
    last_name  = string
  }))
  default = []
}

# --- Secret creation toggles for future apps ---
variable "create_jellyfin_secret" {
  description = "Create K8s secret for Jellyfin OIDC"
  type        = bool
  default     = false
}

variable "create_navidrome_secret" {
  description = "Create K8s secret for Navidrome OIDC"
  type        = bool
  default     = false
}

variable "create_openwebui_secret" {
  description = "Create K8s secret for Open WebUI OIDC"
  type        = bool
  default     = false
}

variable "create_immich_secret" {
  description = "Create K8s secret for Immich OIDC"
  type        = bool
  default     = false
}

variable "create_paperless_secret" {
  description = "Create K8s secret for Paperless-ngx OIDC"
  type        = bool
  default     = false
}
```

---

### Task 6: Create terraform.tfvars

**Files:**
- Create: `environments/prod/zitadel/terraform.tfvars`

**Context:** Populate with actual service IPs after running `kubectl get svc -A | grep LoadBalancer`.

- [ ] **Step 1: Get all LoadBalancer IPs**

```bash
kubectl get svc -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,TYPE:.spec.type,IP:.status.loadBalancer.ingress[0].ip,PORTS:.spec.ports[*].port' | grep LoadBalancer
```

- [ ] **Step 2: Create terraform.tfvars**

```hcl
# Zitadel
zitadel_url = "http://<ZITADEL_IP>:8080"

# App URLs (from kubectl get svc LoadBalancer IPs)
argocd_url  = "http://<ARGOCD_IP>:8080"
forgejo_url = "http://<FORGEJO_IP>:3000"
harbor_url  = "http://<HARBOR_IP>"
grafana_url = "http://<GRAFANA_IP>:3000"

# Admin user
admin_email      = "aaron@reynoza.org"
admin_first_name = "Aaron"
admin_last_name  = "Valdez"

# Additional users (add family/William here)
additional_users = []
```

- [ ] **Step 3: Commit scaffolding**

```bash
git add core/terraform/live/zitadel/versions.tf core/terraform/live/zitadel/variables.tf
git commit -m "feat: add Zitadel SSO Terraform scaffolding"
```

Note: `environments/` is gitignored — backend.hcl, terraform.tfvars, and secrets.enc.yaml are not committed to the public repo.

---

## Chunk 3: Terraform Main Config

### Task 7: Create main.tf — Providers and Project

**Files:**
- Create: `core/terraform/live/zitadel/main.tf`

- [ ] **Step 1: Create main.tf with providers and project**

```hcl
# --- SOPS ---
provider "sops" {}

data "sops_file" "secrets" {
  source_file = var.sops_secrets_path
}

# --- Zitadel provider ---
provider "zitadel" {
  domain   = replace(replace(var.zitadel_url, "http://", ""), "/:[0-9]+$/", "")
  port     = var.zitadel_port
  insecure = true  # No TLS in internal network
  token    = data.sops_file.secrets.data["pat"]
}

# --- Kubernetes provider ---
provider "kubernetes" {
  config_path = var.kubeconfig_path
}

# --- Project ---
resource "zitadel_project" "homelab" {
  name                     = "HOMELAB"
  project_role_assertion   = true
  project_role_check       = true
  has_project_check        = true
  private_labeling_setting = "PRIVATE_LABELING_SETTING_UNSPECIFIED"
}
```

---

### Task 8: Add OIDC Applications — Current Apps

**Files:**
- Modify: `core/terraform/live/zitadel/main.tf`

- [ ] **Step 1: Add ArgoCD OIDC app (PKCE / User Agent type)**

Append to `main.tf`:

```hcl
# --- ArgoCD (PKCE, no client secret needed) ---
resource "zitadel_application_oidc" "argocd" {
  project_id = zitadel_project.homelab.id
  name       = "ArgoCD"

  redirect_uris        = ["${var.argocd_url}/auth/callback"]
  response_types       = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types          = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  app_type             = "OIDC_APP_TYPE_USER_AGENT"
  auth_method_type     = "OIDC_AUTH_METHOD_TYPE_NONE"  # PKCE
  post_logout_redirect_uris = [var.argocd_url]
  dev_mode             = true  # Allow HTTP redirect URIs
}

resource "kubernetes_secret" "argocd_oidc" {
  metadata {
    name      = "argocd-oidc-secrets"
    namespace = "argocd"
  }

  data = {
    client-id = zitadel_application_oidc.argocd.client_id
  }
}
```

- [ ] **Step 2: Add Forgejo OIDC app**

```hcl
# --- Forgejo ---
resource "zitadel_application_oidc" "forgejo" {
  project_id = zitadel_project.homelab.id
  name       = "Forgejo"

  redirect_uris        = ["${var.forgejo_url}/user/oauth2/Zitadel/callback"]
  response_types       = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types          = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  app_type             = "OIDC_APP_TYPE_WEB"
  auth_method_type     = "OIDC_AUTH_METHOD_TYPE_POST"
  post_logout_redirect_uris = [var.forgejo_url]
  dev_mode             = true
}

resource "kubernetes_secret" "forgejo_oidc" {
  metadata {
    name      = "forgejo-oidc-secrets"
    namespace = "forgejo"
  }

  data = {
    client-id     = zitadel_application_oidc.forgejo.client_id
    client-secret = zitadel_application_oidc.forgejo.client_secret
  }
}
```

- [ ] **Step 3: Add Harbor OIDC app**

```hcl
# --- Harbor ---
resource "zitadel_application_oidc" "harbor" {
  project_id = zitadel_project.homelab.id
  name       = "Harbor"

  redirect_uris        = ["${var.harbor_url}/c/oidc/callback"]
  response_types       = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types          = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  app_type             = "OIDC_APP_TYPE_WEB"
  auth_method_type     = "OIDC_AUTH_METHOD_TYPE_POST"
  post_logout_redirect_uris = [var.harbor_url]
  dev_mode             = true
}

resource "kubernetes_secret" "harbor_oidc" {
  metadata {
    name      = "harbor-oidc-secrets"
    namespace = "harbor"
  }

  data = {
    client-id     = zitadel_application_oidc.harbor.client_id
    client-secret = zitadel_application_oidc.harbor.client_secret
  }
}
```

- [ ] **Step 4: Add Grafana OIDC app**

```hcl
# --- Grafana ---
resource "zitadel_application_oidc" "grafana" {
  project_id = zitadel_project.homelab.id
  name       = "Grafana"

  redirect_uris        = ["${var.grafana_url}/login/generic_oauth"]
  response_types       = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types          = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  app_type             = "OIDC_APP_TYPE_WEB"
  auth_method_type     = "OIDC_AUTH_METHOD_TYPE_BASIC"
  post_logout_redirect_uris = [var.grafana_url]
  dev_mode             = true
}

resource "kubernetes_secret" "grafana_oidc" {
  metadata {
    name      = "grafana-oidc-secrets"
    namespace = "monitoring"
  }

  data = {
    client-id     = zitadel_application_oidc.grafana.client_id
    client-secret = zitadel_application_oidc.grafana.client_secret
  }
}
```

---

### Task 9: Add OIDC Applications — Future Apps

**Files:**
- Modify: `core/terraform/live/zitadel/main.tf`

**Context:** OIDC apps are always created in Zitadel (no cost). K8s secrets are only created when `create_*_secret` is true (namespace must exist).

- [ ] **Step 1: Add future app OIDC resources**

```hcl
# --- Future Apps (OIDC app always created, K8s secret gated) ---

resource "zitadel_application_oidc" "jellyfin" {
  project_id = zitadel_project.homelab.id
  name       = "Jellyfin"

  redirect_uris    = ["http://jellyfin.internal/sso/OID/redirect/Zitadel"]
  response_types   = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types      = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  app_type         = "OIDC_APP_TYPE_WEB"
  auth_method_type = "OIDC_AUTH_METHOD_TYPE_POST"
  dev_mode         = true
}

resource "kubernetes_secret" "jellyfin_oidc" {
  count = var.create_jellyfin_secret ? 1 : 0

  metadata {
    name      = "jellyfin-oidc-secrets"
    namespace = "media"
  }

  data = {
    client-id     = zitadel_application_oidc.jellyfin.client_id
    client-secret = zitadel_application_oidc.jellyfin.client_secret
  }
}

resource "zitadel_application_oidc" "navidrome" {
  project_id = zitadel_project.homelab.id
  name       = "Navidrome"

  redirect_uris    = ["http://navidrome.internal/app/callback"]
  response_types   = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types      = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  app_type         = "OIDC_APP_TYPE_WEB"
  auth_method_type = "OIDC_AUTH_METHOD_TYPE_POST"
  dev_mode         = true
}

resource "kubernetes_secret" "navidrome_oidc" {
  count = var.create_navidrome_secret ? 1 : 0

  metadata {
    name      = "navidrome-oidc-secrets"
    namespace = "media"
  }

  data = {
    client-id     = zitadel_application_oidc.navidrome.client_id
    client-secret = zitadel_application_oidc.navidrome.client_secret
  }
}

resource "zitadel_application_oidc" "openwebui" {
  project_id = zitadel_project.homelab.id
  name       = "Open WebUI"

  redirect_uris    = ["http://openwebui.internal/oauth/oidc/callback"]
  response_types   = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types      = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  app_type         = "OIDC_APP_TYPE_WEB"
  auth_method_type = "OIDC_AUTH_METHOD_TYPE_POST"
  dev_mode         = true
}

resource "kubernetes_secret" "openwebui_oidc" {
  count = var.create_openwebui_secret ? 1 : 0

  metadata {
    name      = "open-webui-oidc-secrets"
    namespace = "ai"
  }

  data = {
    client-id     = zitadel_application_oidc.openwebui.client_id
    client-secret = zitadel_application_oidc.openwebui.client_secret
  }
}

resource "zitadel_application_oidc" "immich" {
  project_id = zitadel_project.homelab.id
  name       = "Immich"

  redirect_uris    = ["http://immich.internal/auth/login"]
  response_types   = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types      = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  app_type         = "OIDC_APP_TYPE_WEB"
  auth_method_type = "OIDC_AUTH_METHOD_TYPE_POST"
  dev_mode         = true
}

resource "kubernetes_secret" "immich_oidc" {
  count = var.create_immich_secret ? 1 : 0

  metadata {
    name      = "immich-oidc-secrets"
    namespace = "media"
  }

  data = {
    client-id     = zitadel_application_oidc.immich.client_id
    client-secret = zitadel_application_oidc.immich.client_secret
  }
}

resource "zitadel_application_oidc" "paperless" {
  project_id = zitadel_project.homelab.id
  name       = "Paperless-ngx"

  redirect_uris    = ["http://paperless.internal/accounts/oidc/zitadel/login/callback/"]
  response_types   = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types      = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  app_type         = "OIDC_APP_TYPE_WEB"
  auth_method_type = "OIDC_AUTH_METHOD_TYPE_POST"
  dev_mode         = true
}

resource "kubernetes_secret" "paperless_oidc" {
  count = var.create_paperless_secret ? 1 : 0

  metadata {
    name      = "paperless-oidc-secrets"
    namespace = "management"
  }

  data = {
    client-id     = zitadel_application_oidc.paperless.client_id
    client-secret = zitadel_application_oidc.paperless.client_secret
  }
}
```

---

### Task 10: Add User Management

**Files:**
- Modify: `core/terraform/live/zitadel/main.tf`

- [ ] **Step 1: Add admin user and project grants**

```hcl
# --- Admin user ---
resource "zitadel_human_user" "admin" {
  user_name          = var.admin_email
  first_name         = var.admin_first_name
  last_name          = var.admin_last_name
  email              = var.admin_email
  is_email_verified  = true
  initial_password   = "ChangeMe123!"  # Must be changed on first login
}

resource "zitadel_user_grant" "admin_project" {
  project_id = zitadel_project.homelab.id
  user_id    = zitadel_human_user.admin.id
  role_keys  = ["admin"]
}

resource "zitadel_org_member" "admin_iam" {
  user_id = zitadel_human_user.admin.id
  roles   = ["ORG_OWNER"]
}

# --- Additional users ---
resource "zitadel_human_user" "additional" {
  for_each = { for u in var.additional_users : u.email => u }

  user_name          = each.value.email
  first_name         = each.value.first_name
  last_name          = each.value.last_name
  email              = each.value.email
  is_email_verified  = true
  initial_password   = "ChangeMe123!"
}

resource "zitadel_user_grant" "additional_project" {
  for_each = { for u in var.additional_users : u.email => u }

  project_id = zitadel_project.homelab.id
  user_id    = zitadel_human_user.additional[each.key].id
  role_keys  = ["user"]
}
```

---

### Task 11: Create Outputs

**Files:**
- Create: `core/terraform/live/zitadel/outputs.tf`

- [ ] **Step 1: Create outputs.tf**

```hcl
output "project_id" {
  description = "Zitadel HOMELAB project ID"
  value       = zitadel_project.homelab.id
}

output "argocd_client_id" {
  description = "ArgoCD OIDC client ID"
  value       = zitadel_application_oidc.argocd.client_id
}

output "forgejo_client_id" {
  description = "Forgejo OIDC client ID"
  value       = zitadel_application_oidc.forgejo.client_id
}

output "harbor_client_id" {
  description = "Harbor OIDC client ID"
  value       = zitadel_application_oidc.harbor.client_id
}

output "grafana_client_id" {
  description = "Grafana OIDC client ID"
  value       = zitadel_application_oidc.grafana.client_id
}
```

- [ ] **Step 2: Commit Terraform config**

```bash
git add core/terraform/live/zitadel/
git commit -m "feat: add Zitadel SSO Terraform config (OIDC apps + K8s secrets)"
```

---

### Task 12: Terraform Init, Plan, Apply

**Context:** Run from the mgmt VM (REDACTED_MGMT_IP) which has Terraform, kubeconfig, and SOPS age key.

- [ ] **Step 1: Copy Terraform files to mgmt VM**

The mgmt VM needs the homelab repo. Clone or pull latest:

```bash
ssh admin@REDACTED_MGMT_IP
cd ~/homelab && git pull  # or git clone if first time
```

Also copy the environments directory:

```bash
scp -r environments/prod/zitadel/ admin@REDACTED_MGMT_IP:~/environments/prod/zitadel/
```

- [ ] **Step 2: Terraform init**

```bash
ssh admin@REDACTED_MGMT_IP
cd ~/homelab/core/terraform/live/zitadel
export SOPS_AGE_KEY_FILE="/home/admin/.config/sops/age/keys.txt"
terraform init -backend-config=../../../../environments/prod/zitadel/backend.hcl
```

Expected: `Terraform has been successfully initialized!`

- [ ] **Step 3: Terraform plan**

```bash
terraform plan -var-file=../../../../environments/prod/zitadel/terraform.tfvars
```

Expected: Plan shows creation of:
- 1 `zitadel_project`
- 9 `zitadel_application_oidc` (4 current + 5 future)
- 4 `kubernetes_secret` (current apps only, future toggles are false)
- 1 `zitadel_human_user` (admin)
- 1 `zitadel_user_grant`
- 1 `zitadel_org_member`

- [ ] **Step 4: Terraform apply**

```bash
terraform apply -var-file=../../../../environments/prod/zitadel/terraform.tfvars
```

Type `yes` to confirm.

- [ ] **Step 5: Verify secrets were created**

```bash
kubectl get secret argocd-oidc-secrets -n argocd
kubectl get secret forgejo-oidc-secrets -n forgejo
kubectl get secret harbor-oidc-secrets -n harbor
kubectl get secret grafana-oidc-secrets -n monitoring
```

Expected: All four secrets exist.

---

## Chunk 4: Helm Values — Enable OIDC in Apps

### Task 13: Update ArgoCD Helm Values

**Files:**
- Modify: `core/manifests/argocd/apps/argocd.yaml`

**Context:** ArgoCD uses OIDC natively (Dex is already disabled). Add OIDC config to `configs.cm` and RBAC policy. ArgoCD uses PKCE so only the client ID is needed (no secret).

- [ ] **Step 1: Add OIDC config to ArgoCD values**

In the `helm.values` section of `argocd.yaml`, add under the existing config:

```yaml
        configs:
          cm:
            url: "<ARGOCD_URL>"
            oidc.config: |
              name: Zitadel
              issuer: "<ZITADEL_URL>"
              clientID: $argocd-oidc-secrets:client-id
              requestedScopes:
                - openid
                - profile
                - email
                - urn:zitadel:iam:org:project:roles
          rbac:
            policy.csv: |
              g, admin, role:admin
              g, user, role:readonly
            policy.default: role:readonly
```

Replace `<ARGOCD_URL>` and `<ZITADEL_URL>` with actual IPs from terraform.tfvars.

Note: `$argocd-oidc-secrets:client-id` is ArgoCD's secret reference syntax — it reads the value from the K8s secret at runtime.

---

### Task 14: Update Forgejo Helm Values

**Files:**
- Modify: `core/manifests/argocd/apps/forgejo.yaml`

**Context:** Forgejo uses Gitea's OAuth2 provider system. Enable OAuth2 and add Zitadel as the provider via environment variables that reference the K8s secret.

- [ ] **Step 1: Enable OAuth2 in Forgejo config**

In the `helm.values` section, change `oauth2.ENABLED` from `false` to `true` and add the OpenID Connect provider config:

```yaml
            oauth2:
              ENABLED: true

            openid:
              ENABLE_OPENID_SIGNIN: true
              ENABLE_OPENID_SIGNUP: true
```

- [ ] **Step 2: Add OAuth2 environment variables**

Add to the `additionalConfigFromEnvs` list:

```yaml
            - name: FORGEJO__oauth2_client__REGISTER_EMAIL_CONFIRM
              value: "false"
            - name: FORGEJO__oauth2_client__OPENID_CONNECT_SCOPES
              value: "openid profile email"
            - name: FORGEJO__oauth2_client__ENABLE_AUTO_REGISTRATION
              value: "true"
            - name: FORGEJO__oauth2_client__ACCOUNT_LINKING
              value: "auto"
            - name: FORGEJO__oauth2_client__USERNAME
              value: "email"
```

Note: The actual OAuth2 provider (Zitadel) is configured through Forgejo's admin UI or API after first login — Forgejo requires an admin to add authentication sources. This is a manual post-deploy step documented in the verification runbook.

---

### Task 15: Update Grafana Helm Values

**Files:**
- Modify: `core/manifests/argocd/apps/kube-prometheus-stack.yaml`

**Context:** Grafana supports generic OAuth2/OIDC natively. Add `auth.generic_oauth` config referencing the K8s secret.

- [ ] **Step 1: Add Grafana OAuth config**

In the `grafana` section of the Helm values, add:

```yaml
          envFromSecret: grafana-oidc-secrets
          grafana.ini:
            auth.generic_oauth:
              enabled: true
              name: Zitadel
              client_id: $__env{client-id}
              client_secret: $__env{client-secret}
              scopes: openid profile email
              auth_url: "<ZITADEL_URL>/oauth/v2/authorize"
              token_url: "<ZITADEL_URL>/oauth/v2/token"
              api_url: "<ZITADEL_URL>/oidc/v1/userinfo"
              allow_sign_up: true
              auto_login: false
              role_attribute_path: "contains(\"urn:zitadel:iam:org:project:roles\"[*], 'admin') && 'Admin' || 'Viewer'"
            server:
              root_url: "<GRAFANA_URL>"
```

Replace `<ZITADEL_URL>` and `<GRAFANA_URL>` with actual values.

Note: `envFromSecret` loads the secret as environment variables. Grafana's `$__env{key}` syntax references them. The secret keys use `client-id` (with hyphen) which becomes the env var name.

---

### Task 16: Update Harbor Helm Values

**Files:**
- Modify: `core/manifests/argocd/apps/harbor.yaml`

**Context:** Harbor OIDC is configured via its core config, not Helm values directly. Harbor reads OIDC config from its internal database, so the initial setup is done through the Harbor UI after deployment. However, we can pre-configure the OIDC secret reference.

- [ ] **Step 1: Document Harbor OIDC setup**

Harbor's OIDC configuration is done through the admin UI:
1. Log in to Harbor as admin
2. Go to **Configuration** → **Authentication**
3. Set Auth Mode to **OIDC**
4. Fill in:
   - OIDC Provider: `Zitadel`
   - OIDC Endpoint: `<ZITADEL_URL>`
   - OIDC Client ID: (from `harbor-oidc-secrets`)
   - OIDC Client Secret: (from `harbor-oidc-secrets`)
   - OIDC Scope: `openid,profile,email`
   - Automatic onboarding: checked
   - Username Claim: `email`

The K8s secret `harbor-oidc-secrets` is created by Terraform for reference. The actual values are read from the secret and entered into Harbor's UI. This is a one-time manual step.

---

### Task 17: Commit Helm Value Changes

- [ ] **Step 1: Commit all Helm value updates**

```bash
git add core/manifests/argocd/apps/argocd.yaml
git add core/manifests/argocd/apps/forgejo.yaml
git add core/manifests/argocd/apps/kube-prometheus-stack.yaml
git commit -m "feat: enable Zitadel OIDC in ArgoCD, Forgejo, and Grafana"
```

- [ ] **Step 2: Push to trigger ArgoCD sync**

```bash
git push
```

---

## Chunk 5: Verification

### Task 18: Verify ArgoCD OIDC

- [ ] **Step 1: Wait for ArgoCD to sync**

```bash
kubectl get app argocd -n argocd -o jsonpath='{.status.sync.status}'
```

Expected: `Synced`

- [ ] **Step 2: Test OIDC login**

Open `http://<ARGOCD_IP>:8080` in browser. You should see a "Log in via Zitadel" button alongside the local admin login. Click it, authenticate with your Zitadel credentials (admin_email + initial password from Task 10).

- [ ] **Step 3: Verify local admin fallback**

Log out and log in with the existing ArgoCD admin password. Confirm local login still works.

---

### Task 19: Verify Forgejo OIDC

- [ ] **Step 1: Configure Zitadel as auth source in Forgejo**

1. Log in to Forgejo as local admin
2. Go to **Site Administration** → **Authentication Sources** → **Add Authentication Source**
3. Type: **OAuth2**
4. Name: `Zitadel`
5. OAuth2 Provider: **OpenID Connect**
6. Client ID: (from `kubectl get secret forgejo-oidc-secrets -n forgejo -o jsonpath='{.data.client-id}' | base64 -d`)
7. Client Secret: (from `kubectl get secret forgejo-oidc-secrets -n forgejo -o jsonpath='{.data.client-secret}' | base64 -d`)
8. OpenID Connect Auto Discovery URL: `<ZITADEL_URL>/.well-known/openid-configuration`
9. Save

- [ ] **Step 2: Test OIDC login**

Log out. Click "Sign in with Zitadel" on the login page.

---

### Task 20: Verify Grafana OIDC

- [ ] **Step 1: Wait for Grafana to restart**

```bash
kubectl rollout status deployment -n monitoring -l app.kubernetes.io/name=grafana
```

- [ ] **Step 2: Test OIDC login**

Open Grafana in browser. You should see a "Sign in with Zitadel" button. Authenticate and verify you land on the Grafana dashboard.

- [ ] **Step 3: Verify local admin fallback**

Log out, log in with existing Grafana admin credentials.

---

### Task 21: Verify Harbor OIDC

- [ ] **Step 1: Configure OIDC in Harbor UI**

Follow the steps in Task 16, Step 1.

- [ ] **Step 2: Test OIDC login**

Log out. Click "Login via OIDC Provider" on Harbor login page.

- [ ] **Step 3: Verify local admin fallback**

Log out, log in with existing Harbor admin password.

---

### Task 22: Final Commit and Documentation

- [ ] **Step 1: Push any remaining changes**

```bash
git push
```

- [ ] **Step 2: Verify all OIDC apps in Zitadel console**

Open `http://<ZITADEL_IP>:8080/ui/console` and navigate to the HOMELAB project. Verify all 9 OIDC apps are listed.

---

## Summary

After completing all tasks:
- Zitadel HOMELAB project with 9 OIDC applications (4 active, 5 future)
- K8s secrets deployed in argocd, forgejo, harbor, monitoring namespaces
- ArgoCD, Forgejo, Grafana configured with Zitadel OIDC login
- Harbor OIDC configured via admin UI
- Admin user created in Zitadel with full access
- Local admin fallback verified for all apps
- Terraform state in S3, PAT SOPS-encrypted

**Next:** Sub-Project 3 — Migrate Git source of truth to Forgejo (with Zitadel OIDC already configured).
