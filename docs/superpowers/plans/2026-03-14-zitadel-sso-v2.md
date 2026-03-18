# Zitadel SSO v2 — Terraform-Driven OIDC Configuration

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure SSO so that ArgoCD deploys apps with clean manifests (no hardcoded IPs, no OIDC config), and Terraform handles ALL OIDC wiring post-deploy: patching ConfigMaps, calling APIs, running CLI commands.

**Why v2:** The v1 plan put OIDC config in Helm values (hardcoded client IDs, issuer URLs). This caused drift when Zitadel client IDs changed, required hardcoded IPs in the public repo, and made ArgoCD fight Terraform over ConfigMap ownership. v2 makes Terraform the single owner of all OIDC configuration.

**Architecture:**
1. ArgoCD deploys apps WITHOUT OIDC config (clean manifests, no hardcoded IPs)
2. Terraform (from mgmt VM) does ALL OIDC configuration:
   - Creates OIDC apps in Zitadel (already done)
   - Creates K8s secrets (already done)
   - Patches `argocd-cm` ConfigMap with `oidc.config` (NEW)
   - Runs `kubectl exec` to add Forgejo auth source via CLI (NEW)
   - Calls Harbor `PUT /api/v2.0/configurations` API (NEW)
   - Grafana reads OIDC from K8s secret env vars (NEW — minimal Helm change)
3. All IPs from `environments/prod/zitadel/terraform.tfvars` (private)
4. Zitadel `ExternalDomain` changed to LB IP (parameterized, eliminates DNS issues)

**Supersedes:** `docs/superpowers/plans/2026-03-13-zitadel-sso.md`

**Tech Stack:** Terraform (zitadel, kubernetes, null, http providers), Zitadel, ArgoCD, Forgejo, Harbor, Grafana

---

## File Changes Overview

| File | Action | What Changes |
|------|--------|-------------|
| `core/manifests/argocd/apps/argocd.yaml` | modify | Remove `hostAliases`, `url`, `oidc.config`, hardcoded client ID |
| `core/manifests/argocd/apps/forgejo.yaml` | modify | Enable `oauth2.ENABLED: true` (Terraform adds the auth source) |
| `core/manifests/argocd/apps/kube-prometheus-stack.yaml` | modify | Add `envFromSecret` + `grafana.ini` OIDC using env vars |
| `core/manifests/argocd/apps/zitadel.yaml` | modify | Parameterize `ExternalDomain` to LB IP |
| `core/terraform/live/zitadel/main.tf` | modify | Add ConfigMap patch, Forgejo CLI exec, Harbor API call, Grafana secret, login policy |
| `core/terraform/live/zitadel/variables.tf` | modify | Add `zitadel_ip`, `harbor_admin_password_secret`, `forgejo_pod_label` vars |
| `core/terraform/live/zitadel/versions.tf` | modify | Add `hashicorp/null` and `hashicorp/http` providers |
| `environments/prod/zitadel/terraform.tfvars` | modify | Add `zitadel_ip` value |

---

## Chunk 1: Clean ArgoCD Manifests

Remove all hardcoded IPs and OIDC config from ArgoCD-managed Helm values. After this chunk, apps deploy cleanly without any Zitadel dependency.

### Task 1: Clean argocd.yaml

**File:** `core/manifests/argocd/apps/argocd.yaml`

- [ ] **Step 1: Remove `hostAliases`, `url`, and `oidc.config` from argocd.yaml**

Replace the entire `helm.values` block. Keep resource limits, RBAC, CNPG health check, SSH known hosts. Remove everything OIDC-related.

The current file has these lines that must be removed:
- Lines 18-22: `global.hostAliases` (hardcoded IP `REDACTED_LB_IP` for `zitadel.internal`)
- Line 68: `url: "http://REDACTED_LB_IP"` (hardcoded ArgoCD URL)
- Lines 69-77: `oidc.config` block (hardcoded client ID `REDACTED_CLIENT_ID`, hardcoded issuer)

The new `helm.values` section should be:

```yaml
    helm:
      values: |
        server:
          extraArgs:
            - --insecure
          service:
            type: LoadBalancer
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
          cm:
            resource.customizations.health.postgresql.cnpg.io_Cluster: |
              hs = {}
              if obj.status ~= nil then
                if obj.status.phase == "Cluster in healthy state" then
                  hs.status = "Healthy"
                  hs.message = "Cluster is ready"
                elseif obj.status.phase == "Setting up primary" or obj.status.phase == "Creating replica" or obj.status.phase == "Upgrading cluster" then
                  hs.status = "Progressing"
                  hs.message = obj.status.phase
                else
                  hs.status = "Degraded"
                  hs.message = obj.status.phase or "Unknown phase"
                end
              else
                hs.status = "Progressing"
                hs.message = "Waiting for status"
              end
              return hs
          rbac:
            policy.csv: |
              g, admin, role:admin
              g, user, role:readonly
            policy.default: role:readonly
          ssh:
            knownHosts: |
              github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
              github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
```

**Why:** Terraform will own `argocd-cm` OIDC fields. ArgoCD's Helm chart creates `argocd-cm` but Terraform patches it post-deploy. No `url` here because Terraform sets it. No `hostAliases` because we switch ExternalDomain to the LB IP (Chunk 3).

- [ ] **Step 2: Add ArgoCD syncPolicy to ignore Terraform-managed ConfigMap fields**

Add `ignoreDifferences` to the ArgoCD Application spec so ArgoCD does not revert Terraform's ConfigMap patches:

```yaml
spec:
  ignoreDifferences:
    - group: ""
      kind: ConfigMap
      name: argocd-cm
      namespace: argocd
      jqPathExpressions:
        - '.data["url"]'
        - '.data["oidc.config"]'
```

This goes right after `spec:` and before `project: default` in `core/manifests/argocd/apps/argocd.yaml`.

---

### Task 2: Enable OAuth2 in forgejo.yaml

**File:** `core/manifests/argocd/apps/forgejo.yaml`

- [ ] **Step 1: Set `oauth2.ENABLED` to `true`**

In `core/manifests/argocd/apps/forgejo.yaml`, change line 63:

```yaml
            # BEFORE
            oauth2:
              ENABLED: false

            # AFTER
            oauth2:
              ENABLED: true
```

That is the only change. Terraform will add the actual Zitadel auth source via `kubectl exec` (Chunk 2). Forgejo's OAuth2 subsystem just needs to be turned on.

**Do NOT add** `openid`, `oauth2_client`, or environment variables for OIDC here. Forgejo's auth source is configured imperatively, not through Helm values.

---

### Task 3: Add Grafana OIDC config referencing env vars

**File:** `core/manifests/argocd/apps/kube-prometheus-stack.yaml`

- [ ] **Step 1: Add `envFromSecret` and `grafana.ini` OIDC config**

In the `grafana:` section of the Helm values (after `service:` block, around line 54), add:

```yaml
          envFromSecret: grafana-oidc-secrets
          grafana.ini:
            server:
              root_url: "%(GF_SERVER_ROOT_URL)s"
            auth.generic_oauth:
              enabled: true
              name: Zitadel
              client_id: $__env{GF_AUTH_GENERIC_OAUTH_CLIENT_ID}
              client_secret: $__env{GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET}
              scopes: openid profile email urn:zitadel:iam:org:project:roles
              auth_url: $__env{GF_AUTH_GENERIC_OAUTH_AUTH_URL}
              token_url: $__env{GF_AUTH_GENERIC_OAUTH_TOKEN_URL}
              api_url: $__env{GF_AUTH_GENERIC_OAUTH_API_URL}
              allow_sign_up: true
              auto_login: false
              role_attribute_path: "contains(keys(@), 'urn:zitadel:iam:org:project:roles') && contains(keys(\"urn:zitadel:iam:org:project:roles\"), 'admin') && 'Admin' || 'Viewer'"
```

**Why `$__env` syntax:** Grafana resolves `$__env{VAR}` at startup from environment variables. The env vars come from `envFromSecret: grafana-oidc-secrets`. Terraform creates that secret with the correct keys (see Chunk 2, Task 7).

**Important:** The K8s secret keys must be valid env var names (uppercase, underscores). Terraform creates the secret with keys like `GF_AUTH_GENERIC_OAUTH_CLIENT_ID`, not `client-id`. This avoids the hyphen-in-env-var problem.

---

### Task 4: Commit and push Chunk 1

- [ ] **Step 1: Commit clean manifests**

```bash
cd /Users/aaronvaldez/repos/homelab
git add core/manifests/argocd/apps/argocd.yaml
git add core/manifests/argocd/apps/forgejo.yaml
git add core/manifests/argocd/apps/kube-prometheus-stack.yaml
git commit -m "refactor: remove hardcoded OIDC config from ArgoCD manifests

ArgoCD, Forgejo, and Grafana manifests no longer contain Zitadel
issuer URLs, client IDs, or hostAliases. OIDC configuration is
now fully owned by Terraform (applied post-deploy from mgmt VM)."
```

- [ ] **Step 2: Push to trigger ArgoCD sync**

```bash
git push origin main
```

- [ ] **Step 3: Verify ArgoCD syncs without OIDC (apps still work, just no SSO button)**

```bash
kubectl get app argocd -n argocd -o jsonpath='{.status.sync.status}'
# Expected: Synced
kubectl get app forgejo -n argocd -o jsonpath='{.status.sync.status}'
# Expected: Synced
kubectl get app kube-prometheus-stack -n argocd -o jsonpath='{.status.sync.status}'
# Expected: Synced
```

---

## Chunk 2: Update Terraform — App-Side OIDC Configuration

Add Terraform resources that configure each app's OIDC after ArgoCD has deployed it.

### Task 5: Add providers to versions.tf

**File:** `core/terraform/live/zitadel/versions.tf`

- [ ] **Step 1: Add `null` and `http` providers**

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
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0.0"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.0.0"
    }
  }
}
```

---

### Task 6: Add new variables

**File:** `core/terraform/live/zitadel/variables.tf`

- [ ] **Step 1: Add `zitadel_ip` variable**

Append to `variables.tf`:

```hcl
variable "zitadel_ip" {
  description = "Zitadel LoadBalancer IP (e.g., REDACTED_LB_IP). Used for ExternalDomain and issuer URL."
  type        = string
}

variable "harbor_admin_password" {
  description = "Harbor admin password for API authentication"
  type        = string
  sensitive   = true
}
```

**Why `zitadel_ip` separately from `zitadel_url`:** The IP is used for `ExternalDomain` (no protocol, no port). The URL includes `http://` and `:8080`. Having both avoids string manipulation.

---

### Task 7: Add Grafana OIDC secret with proper env var keys

**File:** `core/terraform/live/zitadel/main.tf`

- [ ] **Step 1: Replace the existing `grafana_oidc` secret**

The current `grafana_oidc` secret uses keys `client-id` and `client-secret`. Replace it with env-var-compatible keys that Grafana's `$__env{}` can reference, plus the OIDC endpoint URLs:

Find and replace the existing `kubernetes_secret_v1.grafana_oidc` resource:

```hcl
resource "kubernetes_secret_v1" "grafana_oidc" {
  metadata {
    name      = "grafana-oidc-secrets"
    namespace = "monitoring"
  }

  data = {
    GF_AUTH_GENERIC_OAUTH_CLIENT_ID     = zitadel_application_oidc.grafana.client_id
    GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET = zitadel_application_oidc.grafana.client_secret
    GF_AUTH_GENERIC_OAUTH_AUTH_URL      = "${var.zitadel_url}/oauth/v2/authorize"
    GF_AUTH_GENERIC_OAUTH_TOKEN_URL     = "${var.zitadel_url}/oauth/v2/token"
    GF_AUTH_GENERIC_OAUTH_API_URL       = "${var.zitadel_url}/oidc/v1/userinfo"
    GF_SERVER_ROOT_URL                  = var.grafana_url
  }
}
```

**Why URLs in the secret:** Grafana's `$__env{}` syntax can only reference environment variables. The issuer URL contains the Zitadel IP which lives in `terraform.tfvars` (private). By putting the full URLs in the secret, the Helm values stay IP-free.

---

### Task 8: Add `kubernetes_config_map_v1_data` for ArgoCD OIDC injection

**File:** `core/terraform/live/zitadel/main.tf`

- [ ] **Step 1: Add ArgoCD ConfigMap patch**

Append to `main.tf`:

```hcl
# =============================================================================
# App-Side OIDC Configuration (Terraform owns these, not ArgoCD)
# =============================================================================

# --- ArgoCD: Patch argocd-cm with OIDC config ---
# Uses kubernetes_config_map_v1_data to merge into existing ConfigMap
# without taking ownership of the entire resource (ArgoCD Helm owns it).
resource "kubernetes_config_map_v1_data" "argocd_oidc" {
  metadata {
    name      = "argocd-cm"
    namespace = "argocd"
  }

  data = {
    "url" = var.argocd_url

    "oidc.config" = yamlencode({
      name     = "Zitadel"
      issuer   = "http://${var.zitadel_ip}:8080"
      clientID = zitadel_application_oidc.argocd.client_id
      requestedScopes = [
        "openid",
        "profile",
        "email",
        "urn:zitadel:iam:org:project:roles"
      ]
    })
  }

  force = true

  depends_on = [
    kubernetes_secret_v1.argocd_oidc
  ]
}
```

**Why `kubernetes_config_map_v1_data`:** This resource patches specific keys in an existing ConfigMap without replacing the whole thing. ArgoCD's Helm chart creates `argocd-cm` with the CNPG health check and other settings. This resource just adds `url` and `oidc.config`.

**Why `force = true`:** The ConfigMap already has these keys from the previous manual setup. `force` allows Terraform to overwrite them.

**Important:** The `ignoreDifferences` in the ArgoCD Application (Task 1, Step 2) prevents ArgoCD from reverting these fields on the next sync.

---

### Task 9: Add Forgejo auth source via `kubectl exec`

**File:** `core/terraform/live/zitadel/main.tf`

- [ ] **Step 1: Add null_resource for Forgejo auth source**

Append to `main.tf`:

```hcl
# --- Forgejo: Add Zitadel as OAuth2 authentication source ---
# Forgejo requires auth sources to be added via CLI or admin UI.
# This runs `gitea admin auth add-oauth` inside the Forgejo pod.
resource "null_resource" "forgejo_oauth_source" {
  triggers = {
    client_id     = zitadel_application_oidc.forgejo.client_id
    client_secret = zitadel_application_oidc.forgejo.client_secret
    issuer_url    = "http://${var.zitadel_ip}:8080"
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      KUBECONFIG="${var.kubeconfig_path}"
      FORGEJO_POD=$(kubectl --kubeconfig="$KUBECONFIG" get pods -n forgejo -l app.kubernetes.io/name=forgejo -o jsonpath='{.items[0].metadata.name}')

      # Check if auth source already exists
      EXISTING=$(kubectl --kubeconfig="$KUBECONFIG" exec -n forgejo "$FORGEJO_POD" -- \
        gitea admin auth list 2>/dev/null | grep -c "Zitadel" || true)

      if [ "$EXISTING" -gt 0 ]; then
        echo "Zitadel auth source already exists. Updating..."
        # Get the source ID
        SOURCE_ID=$(kubectl --kubeconfig="$KUBECONFIG" exec -n forgejo "$FORGEJO_POD" -- \
          gitea admin auth list 2>/dev/null | grep "Zitadel" | awk '{print $1}')

        kubectl --kubeconfig="$KUBECONFIG" exec -n forgejo "$FORGEJO_POD" -- \
          gitea admin auth update-oauth \
            --id "$SOURCE_ID" \
            --name "Zitadel" \
            --provider "openidConnect" \
            --key "${zitadel_application_oidc.forgejo.client_id}" \
            --secret "${zitadel_application_oidc.forgejo.client_secret}" \
            --auto-discover-url "http://${var.zitadel_ip}:8080/.well-known/openid-configuration" \
            --skip-local-2fa \
            --scopes "openid profile email" \
            --group-claim-name "" \
            --admin-group "" \
            --auto-discover-url "http://${var.zitadel_ip}:8080/.well-known/openid-configuration"
      else
        echo "Adding Zitadel auth source..."
        kubectl --kubeconfig="$KUBECONFIG" exec -n forgejo "$FORGEJO_POD" -- \
          gitea admin auth add-oauth \
            --name "Zitadel" \
            --provider "openidConnect" \
            --key "${zitadel_application_oidc.forgejo.client_id}" \
            --secret "${zitadel_application_oidc.forgejo.client_secret}" \
            --auto-discover-url "http://${var.zitadel_ip}:8080/.well-known/openid-configuration" \
            --skip-local-2fa \
            --scopes "openid profile email"
      fi
    EOT
  }

  depends_on = [
    kubernetes_secret_v1.forgejo_oidc
  ]
}
```

**Why `null_resource` with `local-exec`:** Forgejo has no API for adding auth sources. The only options are the admin UI or the `gitea admin auth add-oauth` CLI command. Since Terraform runs from the mgmt VM which has kubectl access, `local-exec` with `kubectl exec` is the cleanest automation path.

**Why `triggers`:** If the client ID, secret, or issuer URL changes, Terraform re-runs the provisioner. The script is idempotent (checks for existing source, updates if found).

---

### Task 10: Add Harbor OIDC configuration via API

**File:** `core/terraform/live/zitadel/main.tf`

- [ ] **Step 1: Add null_resource for Harbor API configuration**

Append to `main.tf`:

```hcl
# --- Harbor: Configure OIDC via REST API ---
# Harbor's OIDC settings are stored in its internal database,
# configured via PUT /api/v2.0/configurations.
resource "null_resource" "harbor_oidc_config" {
  triggers = {
    client_id     = zitadel_application_oidc.harbor.client_id
    client_secret = zitadel_application_oidc.harbor.client_secret
    issuer_url    = "http://${var.zitadel_ip}:8080"
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      HARBOR_URL="${var.harbor_url}"
      HARBOR_PASS="${var.harbor_admin_password}"

      curl -sf -X PUT "$HARBOR_URL/api/v2.0/configurations" \
        -u "admin:$HARBOR_PASS" \
        -H "Content-Type: application/json" \
        -d '{
          "auth_mode": "oidc_auth",
          "oidc_name": "Zitadel",
          "oidc_endpoint": "http://${var.zitadel_ip}:8080",
          "oidc_client_id": "${zitadel_application_oidc.harbor.client_id}",
          "oidc_client_secret": "${zitadel_application_oidc.harbor.client_secret}",
          "oidc_scope": "openid,profile,email",
          "oidc_verify_cert": false,
          "oidc_auto_onboard": true,
          "oidc_user_claim": "email",
          "oidc_groups_claim": "groups",
          "oidc_admin_group": "admin"
        }'

      echo "Harbor OIDC configuration applied."
    EOT
  }

  depends_on = [
    kubernetes_secret_v1.harbor_oidc
  ]
}
```

**Why `null_resource` instead of `http` provider:** The `http` provider is read-only (data sources only). Harbor's configuration endpoint is a PUT. `local-exec` with `curl` is the standard pattern for imperative API calls in Terraform.

**Important:** After switching to `oidc_auth` mode, the local admin can still log in by navigating to `<harbor_url>/c/login` (bypasses OIDC redirect). Document this in the verification steps.

---

### Task 11: Add Zitadel login policy and OIDC settings

**File:** `core/terraform/live/zitadel/main.tf`

- [ ] **Step 1: Add default login policy (allow username/password + external IDP)**

Append to `main.tf`:

```hcl
# =============================================================================
# Zitadel Instance Settings
# =============================================================================

# Allow both password and external IDP login
resource "zitadel_default_login_policy" "default" {
  user_login                  = true
  allow_register              = false
  allow_external_idp          = true
  force_mfa                   = false
  passwordless_type           = "PASSWORDLESS_TYPE_NOT_ALLOWED"
  hide_password_reset         = false
  multi_factors               = []
  second_factors              = []
  password_check_lifetime     = "240h"
  external_login_check_lifetime = "12h"
  mfa_init_skip_lifetime      = "720h"
  second_factor_check_lifetime = "12h"
  multi_factor_check_lifetime  = "12h"
}

# OIDC settings — token lifetimes
resource "zitadel_default_oidc_settings" "default" {
  access_token_lifetime          = "12h"
  id_token_lifetime              = "12h"
  refresh_token_idle_expiration  = "720h"
  refresh_token_expiration       = "720h"
}
```

---

### Task 12: Commit Terraform changes

- [ ] **Step 1: Commit all Terraform changes**

```bash
cd /Users/aaronvaldez/repos/homelab
git add core/terraform/live/zitadel/
git commit -m "feat: add Terraform-driven OIDC configuration for all apps

- ArgoCD: kubernetes_config_map_v1_data patches argocd-cm
- Forgejo: null_resource runs gitea admin auth add-oauth via kubectl exec
- Harbor: null_resource calls PUT /api/v2.0/configurations
- Grafana: secret with GF_* env var keys for envFromSecret
- Zitadel: default login policy and OIDC token settings
- All IPs sourced from terraform.tfvars (no hardcoded values)"
```

---

## Chunk 3: Update Zitadel ExternalDomain

Change Zitadel's `ExternalDomain` from `zitadel.internal` to its actual LB IP. This eliminates the need for `hostAliases` in every pod that talks to Zitadel, and makes the OIDC issuer URL match what clients see.

### Task 13: Parameterize ExternalDomain in zitadel.yaml

**File:** `core/manifests/argocd/apps/zitadel.yaml`

- [ ] **Step 1: Change ExternalDomain to the Zitadel LB IP**

This is a one-time change. The IP is stable (Cilium LB-IPAM assigns it deterministically).

In `core/manifests/argocd/apps/zitadel.yaml`, change line 23:

```yaml
            # BEFORE
            ExternalDomain: zitadel.internal

            # AFTER
            ExternalDomain: "REDACTED_LB_IP"
```

**Why not a variable:** ArgoCD Application manifests are static YAML, not Helm templates. The Zitadel LB IP is assigned by Cilium LB-IPAM and is stable. If it ever changes, this one line is the only place to update.

**What this changes:**
- OIDC issuer URL becomes `http://REDACTED_LB_IP:8080` (was `http://zitadel.internal:8080`)
- OIDC discovery URL becomes `http://REDACTED_LB_IP:8080/.well-known/openid-configuration`
- No DNS resolution needed — all apps can reach the IP directly
- `hostAliases` hacks are no longer needed anywhere

- [ ] **Step 2: Commit and push**

```bash
cd /Users/aaronvaldez/repos/homelab
git add core/manifests/argocd/apps/zitadel.yaml
git commit -m "fix: change Zitadel ExternalDomain to LB IP (eliminates DNS dependency)"
git push origin main
```

- [ ] **Step 3: Wait for Zitadel to restart with new ExternalDomain**

```bash
# Watch the rollout
kubectl rollout status statefulset/zitadel -n zitadel --timeout=120s

# Verify the new issuer URL works
curl -s http://REDACTED_LB_IP:8080/.well-known/openid-configuration | grep issuer
# Expected: "issuer":"http://REDACTED_LB_IP:8080"
```

**WARNING:** Changing ExternalDomain invalidates all existing OIDC tokens and issuer references. This is why we do it BEFORE applying Terraform OIDC config (Chunk 4). If Zitadel already has OIDC apps pointing to the old issuer, they will break until Terraform re-applies.

---

## Chunk 4: Apply and Verify

### Task 14: Update terraform.tfvars

**File:** `environments/prod/zitadel/terraform.tfvars` (private, not committed to public repo)

- [ ] **Step 1: Add new variables to terraform.tfvars**

```hcl
# Zitadel
zitadel_url = "http://REDACTED_LB_IP:8080"
zitadel_ip  = "REDACTED_LB_IP"

# App URLs (from kubectl get svc LoadBalancer IPs)
argocd_url  = "http://REDACTED_LB_IP"
forgejo_url = "http://REDACTED_LB_IP:3000"
harbor_url  = "http://REDACTED_LB_IP"
grafana_url = "http://REDACTED_LB_IP:3000"

# Harbor admin password (for API call)
harbor_admin_password = "<from harbor-credentials secret>"

# Admin user
admin_email      = "<ADMIN_EMAIL>"
admin_first_name = "Aaron"
admin_last_name  = "Valdez"

additional_users = []
```

Get the Harbor admin password:

```bash
kubectl get secret harbor-credentials -n harbor -o jsonpath='{.data.admin-password}' | base64 -d
```

Get the actual LB IPs to confirm:

```bash
kubectl get svc -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,TYPE:.spec.type,IP:.status.loadBalancer.ingress[0].ip,PORTS:.spec.ports[*].port' | grep LoadBalancer
```

---

### Task 15: Copy files to mgmt VM and apply

- [ ] **Step 1: Push latest changes to git**

```bash
cd /Users/aaronvaldez/repos/homelab
git push origin main
```

- [ ] **Step 2: Pull on mgmt VM**

```bash
ssh admin@REDACTED_MGMT_IP "cd ~/homelab && git pull"
```

- [ ] **Step 3: Copy private files to mgmt VM**

```bash
scp -r environments/prod/zitadel/ admin@REDACTED_MGMT_IP:~/environments/prod/zitadel/
```

- [ ] **Step 4: Terraform init (re-init for new providers)**

```bash
ssh admin@REDACTED_MGMT_IP << 'REMOTE'
cd ~/homelab/core/terraform/live/zitadel
export SOPS_AGE_KEY_FILE="/home/admin/.config/sops/age/keys.txt"
terraform init -backend-config=../../../../environments/prod/zitadel/backend.hcl -upgrade
REMOTE
```

Expected: `Terraform has been successfully initialized!` with `hashicorp/null` and `hashicorp/http` downloaded.

- [ ] **Step 5: Terraform plan**

```bash
ssh admin@REDACTED_MGMT_IP << 'REMOTE'
cd ~/homelab/core/terraform/live/zitadel
export SOPS_AGE_KEY_FILE="/home/admin/.config/sops/age/keys.txt"
terraform plan -var-file=../../../../environments/prod/zitadel/terraform.tfvars
REMOTE
```

Expected new resources:
- `kubernetes_config_map_v1_data.argocd_oidc` (ArgoCD OIDC config)
- `null_resource.forgejo_oauth_source` (Forgejo auth source)
- `null_resource.harbor_oidc_config` (Harbor OIDC config)
- `zitadel_default_login_policy.default`
- `zitadel_default_oidc_settings.default`

Expected changes:
- `kubernetes_secret_v1.grafana_oidc` — keys change from `client-id`/`client-secret` to `GF_*` env vars

- [ ] **Step 6: Terraform apply**

```bash
ssh admin@REDACTED_MGMT_IP << 'REMOTE'
cd ~/homelab/core/terraform/live/zitadel
export SOPS_AGE_KEY_FILE="/home/admin/.config/sops/age/keys.txt"
terraform apply -var-file=../../../../environments/prod/zitadel/terraform.tfvars
REMOTE
```

Type `yes`. Watch for errors in the `null_resource` provisioners (Forgejo pod not ready, Harbor API unreachable, etc.).

- [ ] **Step 7: Restart Grafana to pick up new secret keys**

The secret key names changed, so Grafana needs a restart:

```bash
kubectl rollout restart deployment -n monitoring -l app.kubernetes.io/name=grafana
kubectl rollout status deployment -n monitoring -l app.kubernetes.io/name=grafana --timeout=120s
```

---

### Task 16: Verify ArgoCD OIDC login

- [ ] **Step 1: Verify ConfigMap was patched**

```bash
kubectl get cm argocd-cm -n argocd -o jsonpath='{.data.oidc\.config}'
# Expected: YAML with name: Zitadel, issuer: http://REDACTED_LB_IP:8080, clientID: <actual-id>

kubectl get cm argocd-cm -n argocd -o jsonpath='{.data.url}'
# Expected: http://REDACTED_LB_IP
```

- [ ] **Step 2: Test OIDC login**

Open `http://REDACTED_LB_IP` in browser. Click "Log in via Zitadel". Authenticate with `<ADMIN_EMAIL>` / `<INITIAL_PASSWORD>` (or whatever was set). Should redirect back to ArgoCD with admin role.

- [ ] **Step 3: Verify local admin fallback**

Log out. Log in with ArgoCD local admin password:

```bash
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d
```

Username: `admin`, password from above. Confirm local login still works.

---

### Task 17: Verify Forgejo OIDC login

- [ ] **Step 1: Verify auth source was added**

```bash
FORGEJO_POD=$(kubectl get pods -n forgejo -l app.kubernetes.io/name=forgejo -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n forgejo "$FORGEJO_POD" -- gitea admin auth list
# Expected: Row with Name=Zitadel, Type=OAuth2
```

- [ ] **Step 2: Test OIDC login**

Open `http://REDACTED_LB_IP:3000` in browser. Click "Sign in with Zitadel". Authenticate. Should create an account linked to your Zitadel identity.

- [ ] **Step 3: Verify local admin fallback**

Log out. Log in with local admin credentials:

```bash
kubectl get secret forgejo-credentials -n forgejo -o jsonpath='{.data.admin-password}' | base64 -d
```

Username from the secret's `admin-user` key.

---

### Task 18: Verify Grafana OIDC login

- [ ] **Step 1: Verify env vars are loaded**

```bash
GRAFANA_POD=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n monitoring "$GRAFANA_POD" -- env | grep GF_AUTH_GENERIC_OAUTH
# Expected: GF_AUTH_GENERIC_OAUTH_CLIENT_ID=<actual-id>, etc.
```

- [ ] **Step 2: Test OIDC login**

Open `http://REDACTED_LB_IP:3000` in browser. Click "Sign in with Zitadel". Authenticate. Should land on Grafana dashboard.

- [ ] **Step 3: Verify local admin fallback**

Log out. Log in with Grafana admin credentials:

```bash
kubectl get secret grafana-credentials -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d
```

Username from the secret's `admin-user` key.

---

### Task 19: Verify Harbor OIDC login

- [ ] **Step 1: Verify OIDC config was applied**

```bash
curl -s -u "admin:<harbor-password>" http://REDACTED_LB_IP/api/v2.0/configurations | python3 -m json.tool | grep oidc
# Expected: auth_mode: oidc_auth, oidc_endpoint: http://REDACTED_LB_IP:8080, etc.
```

- [ ] **Step 2: Test OIDC login**

Open `http://REDACTED_LB_IP` in browser. Click "Login via OIDC Provider". Authenticate.

- [ ] **Step 3: Verify local admin fallback**

Navigate directly to `http://REDACTED_LB_IP/c/login` (bypasses OIDC redirect). Log in with Harbor admin password.

---

## Summary

After completing all chunks:

| App | OIDC Config Method | Terraform Resource |
|-----|-------------------|-------------------|
| ArgoCD | ConfigMap patch (`argocd-cm`) | `kubernetes_config_map_v1_data.argocd_oidc` |
| Forgejo | CLI (`gitea admin auth add-oauth`) | `null_resource.forgejo_oauth_source` |
| Harbor | REST API (`PUT /api/v2.0/configurations`) | `null_resource.harbor_oidc_config` |
| Grafana | Env vars from K8s secret | `kubernetes_secret_v1.grafana_oidc` + Helm `envFromSecret` |

**What lives where:**
- **Public repo (homelab):** Clean manifests with no IPs, no OIDC config, no client IDs
- **Private (environments/):** `terraform.tfvars` with all IPs and passwords
- **Terraform state (S3):** OIDC client IDs, secrets, configuration state
- **K8s:** Secrets created by Terraform, ConfigMap patched by Terraform

**Rollback:** If OIDC breaks any app, the local admin fallback always works. To fully revert: `terraform destroy` the OIDC resources (secrets, ConfigMap patch, null_resources), then ArgoCD re-syncs the clean manifests.

**Next:** Sub-Project 3 — Migrate Git source of truth to Forgejo (Zitadel OIDC already working).
