# Zitadel SSO Design Spec v2

## Overview

Centralized SSO for all homelab applications using Zitadel as the OIDC identity provider. Terraform manages **both sides** of the integration: OIDC app registration in Zitadel AND app-side OIDC configuration (ConfigMap patches, CLI commands, API calls). No manual UI steps. No hardcoded IPs in the public repo -- all IPs come from `terraform.tfvars` in the private `environments/` repo.

Inspired by [mojaloop/iac-modules](https://github.com/mojaloop/iac-modules), which uses Terraform to configure Zitadel OIDC apps and wire them into downstream services in a single apply.

## Architecture

```
                    +-----------+
                    |  Zitadel  |  (K8s, LB IP from tfvars)
                    |  OIDC IdP |
                    +-----+-----+
                          |
          +-------+-------+-------+-------+
          |       |       |       |       |
        ArgoCD  Forgejo Harbor  Grafana  (future apps)

Terraform configures BOTH sides:
  Zitadel side:  OIDC app, redirect URIs, project roles
  App side:      ConfigMap patch / CLI exec / API call / K8s secret
```

### Key Principles

1. **No hardcoded IPs** -- ArgoCD manifests in `core/` are IP-free. All IPs live in `environments/prod/zitadel/terraform.tfvars`.
2. **No manual UI steps** -- Everything is `terraform apply`.
3. **Bootstrap-then-configure** -- ArgoCD deploys apps without OIDC. Terraform adds OIDC afterward.
4. **prevent_destroy** -- Zitadel project and OIDC apps use `lifecycle { prevent_destroy = true }` to keep client IDs stable across applies.
5. **JWT key auth** -- Terraform authenticates to Zitadel via JWT profile key (not PAT). Key extracted from the `iam-admin` K8s secret created by the Helm chart.

## Bootstrap Sequence

```
1. ArgoCD deploys all apps (no OIDC config)
   - Apps are functional with local admin accounts
   - Zitadel is running, accessible on its LB IP

2. Extract JWT key from K8s
   kubectl get secret iam-admin -n zitadel \
     -o jsonpath='{.data.iam-admin\.json}' | base64 -d \
     > ~/.config/zitadel-key.json

3. Populate terraform.tfvars with LB IPs
   kubectl get svc -A | grep LoadBalancer
   -> argocd_url, forgejo_url, harbor_url, grafana_url, zitadel_url

4. terraform apply (from mgmt VM)
   Creates in Zitadel:
     - HOMELAB project + roles (admin, user)
     - OIDC apps (ArgoCD, Forgejo, Harbor, Grafana, future apps)
     - Human users + project grants
     - Login policy (disable registration, token lifetimes)
   Configures apps:
     - ArgoCD: patches argocd-cm ConfigMap with OIDC block
     - Forgejo: kubectl exec -> gitea admin auth add-oauth
     - Harbor: PUT /api/v2.0/configurations API call
     - Grafana: K8s secret with env vars (Helm values reference them)
   Creates K8s secrets:
     - Per-app OIDC credentials in each namespace

5. Apps pick up config
   - ArgoCD: detects ConfigMap change, no restart needed
   - Forgejo: OAuth provider registered in DB via CLI
   - Harbor: config API takes effect immediately
   - Grafana: pod restart picks up env vars from secret

6. Verify SSO login + local admin fallback for each app
```

## Terraform Structure

```
core/terraform/live/zitadel/
  main.tf          # Providers, Zitadel resources (project, OIDC apps, roles, users)
  app_config.tf    # App-side configuration (ConfigMap patches, exec, API calls)
  variables.tf     # All parameterized (no defaults with IPs)
  outputs.tf       # Project ID, client IDs (sensitive)
  versions.tf      # Provider constraints
  login_policy.tf  # Disable registration, token lifetimes, v2 login disable

environments/prod/zitadel/         # Private repo (gitignored)
  backend.hcl                      # S3 backend (key: zitadel/terraform.tfstate)
  terraform.tfvars                 # All IPs, URLs, user config, org ID
```

### Init/Apply

```bash
cd core/terraform/live/zitadel
terraform init -backend-config=../../../../environments/prod/zitadel/backend.hcl
terraform plan -var-file=../../../../environments/prod/zitadel/terraform.tfvars
terraform apply -var-file=../../../../environments/prod/zitadel/terraform.tfvars
```

## Providers

| Provider | Version | Purpose | Auth |
|----------|---------|---------|------|
| `zitadel/zitadel` | >= 2.10.0 | OIDC apps, users, project, login policy | JWT profile key (`jwt_profile_file`) |
| `hashicorp/kubernetes` | >= 2.0.0 | K8s secrets, ConfigMap patches, exec | kubeconfig on mgmt VM |
| `hashicorp/http` | >= 3.0.0 | Harbor config API call | Basic auth to Harbor admin |

**Important:** The Zitadel provider's `token` param expects a file path (confusingly named). Use `jwt_profile_file` instead, which clearly takes a file path to the JSON key.

## Zitadel ExternalDomain

Zitadel is configured with its **LB IP as ExternalDomain** (parameterized in Helm values via tfvars). This eliminates the DNS/hostAliases problem entirely -- no `zitadel.internal` hostname, no `hostAliases` injection needed in every pod.

```
ExternalDomain: 10.10.10.X    # From tfvars, not hardcoded
ExternalPort: 8080
ExternalSecure: false
```

The OIDC issuer URL becomes `http://<zitadel-lb-ip>:8080` -- resolvable from every pod without DNS tricks.

## OIDC Applications

Single Zitadel project: `HOMELAB`

### Current Apps

| App | Type | Auth Method | Redirect URI |
|-----|------|-------------|--------------|
| ArgoCD | User Agent (SPA) | PKCE (no secret) | `{argocd_url}/auth/callback` |
| Forgejo | Web | Client Secret POST | `{forgejo_url}/user/oauth2/Zitadel/callback` |
| Harbor | Web | Client Secret POST | `{harbor_url}/c/oidc/callback` |
| Grafana | Web | Client Secret BASIC | `{grafana_url}/login/generic_oauth` |

All URLs come from `terraform.tfvars`. All use `dev_mode = true` (HTTP redirect URIs). All have `lifecycle { prevent_destroy = true }`.

### Future Apps (OIDC app created, app-side config deferred)

Jellyfin, Navidrome, Open WebUI, Immich, Paperless-ngx. K8s secrets gated by `create_<app>_secret` toggle variables (default `false`).

## App-Side Configuration (app_config.tf)

This is the key difference from v1. Terraform does not just create secrets -- it configures each app to use OIDC.

### ArgoCD -- ConfigMap Patch

Terraform patches `argocd-cm` in the `argocd` namespace. The OIDC block is **not** in `core/manifests/argocd/apps/argocd.yaml` -- the ArgoCD manifest ships without OIDC config. Terraform injects it.

```hcl
resource "kubernetes_config_map_v1_data" "argocd_oidc" {
  metadata {
    name      = "argocd-cm"
    namespace = "argocd"
  }

  data = {
    "oidc.config" = yamlencode({
      name      = "Zitadel"
      issuer    = var.zitadel_url
      clientID  = zitadel_application_oidc.argocd.client_id
      requestedScopes = ["openid", "profile", "email",
                         "urn:zitadel:iam:org:project:roles"]
    })
  }

  force = true  # Overwrite existing key if present
}
```

**Lesson learned:** ArgoCD's `$secret:key` interpolation only works for `clientSecret`, not `clientID`. Since ArgoCD uses PKCE (no client secret), the client ID must be in the ConfigMap directly. Terraform handles this.

### Forgejo -- kubectl exec

Forgejo has no config API. Terraform runs `kubectl exec` into the Forgejo pod to register the OAuth provider via the Gitea admin CLI.

```hcl
resource "null_resource" "forgejo_oauth" {
  triggers = {
    client_id = zitadel_application_oidc.forgejo.client_id
  }

  provisioner "local-exec" {
    command = <<-EOT
      kubectl exec -n forgejo deploy/forgejo -- \
        gitea admin auth add-oauth \
        --name Zitadel \
        --provider openidConnect \
        --key ${zitadel_application_oidc.forgejo.client_id} \
        --secret ${zitadel_application_oidc.forgejo.client_secret} \
        --auto-discover-url ${var.zitadel_url}/.well-known/openid-configuration \
        --admin-group admin \
        --group-claim-name "urn:zitadel:iam:org:project:roles"
    EOT
  }

  depends_on = [kubernetes_secret_v1.forgejo_oidc]
}
```

If the provider already exists, use `update-oauth` instead. The `triggers` block ensures re-execution if the client ID changes.

### Harbor -- HTTP API

Terraform calls Harbor's configuration API to set OIDC auth mode.

```hcl
resource "null_resource" "harbor_oidc" {
  triggers = {
    client_id = zitadel_application_oidc.harbor.client_id
  }

  provisioner "local-exec" {
    command = <<-EOT
      curl -s -X PUT "${var.harbor_url}/api/v2.0/configurations" \
        -u "admin:${var.harbor_admin_password}" \
        -H "Content-Type: application/json" \
        -d '{
          "auth_mode": "oidc_auth",
          "oidc_name": "Zitadel",
          "oidc_endpoint": "${var.zitadel_url}",
          "oidc_client_id": "${zitadel_application_oidc.harbor.client_id}",
          "oidc_client_secret": "${zitadel_application_oidc.harbor.client_secret}",
          "oidc_scope": "openid,profile,email",
          "oidc_auto_onboard": true,
          "oidc_admin_group": "admin"
        }'
    EOT
  }
}
```

### Grafana -- K8s Secret with Env Vars

Grafana reads OIDC config from environment variables. Terraform creates a secret with the OIDC settings; the Helm values in ArgoCD reference these env vars via `envFromSecret`. No hardcoded URLs in Helm values except `auth_url` and `token_url` (browser-facing, must be the LB IP).

```hcl
resource "kubernetes_secret_v1" "grafana_oidc" {
  metadata {
    name      = "grafana-oidc-secrets"
    namespace = "monitoring"
  }

  data = {
    GF_AUTH_GENERIC_OAUTH_ENABLED       = "true"
    GF_AUTH_GENERIC_OAUTH_NAME          = "Zitadel"
    GF_AUTH_GENERIC_OAUTH_CLIENT_ID     = zitadel_application_oidc.grafana.client_id
    GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET = zitadel_application_oidc.grafana.client_secret
    GF_AUTH_GENERIC_OAUTH_SCOPES        = "openid profile email"
    GF_AUTH_GENERIC_OAUTH_AUTH_URL      = "${var.zitadel_url}/oauth/v2/authorize"
    GF_AUTH_GENERIC_OAUTH_TOKEN_URL     = "${var.zitadel_url}/oauth/v2/token"
    GF_AUTH_GENERIC_OAUTH_API_URL       = "${var.zitadel_url}/oidc/v1/userinfo"
    GF_AUTH_GENERIC_OAUTH_AUTO_LOGIN    = "true"
  }
}
```

The Grafana Helm values only need:
```yaml
grafana:
  envFromSecret: grafana-oidc-secrets
```

Server-to-server calls (token exchange) work because the Zitadel LB IP is routable from every pod. The `auth_url` is browser-facing (user's browser redirects there), which also works because the user's workstation has a static route to the VLAN.

## Zitadel Login Policy (login_policy.tf)

```hcl
resource "zitadel_default_login_policy" "instance" {
  user_login                  = true
  allow_register              = false    # No self-registration
  allow_external_idp          = false    # Zitadel is the only IdP
  force_mfa                   = false    # Future enhancement
  passwordless_type           = "PASSWORDLESS_TYPE_NOT_ALLOWED"
  hide_password_reset         = false
  default_redirect_uri        = var.argocd_url
  password_check_lifetime     = "864000s"   # 10 days
  mfa_init_skip_lifetime      = "2592000s"  # 30 days
  external_login_check_lifetime = "864000s"
}
```

### Disabling v2 Login UI

Zitadel's v2 login UI requires ingress routing for `/<instance-id>/login/` paths, which does not work with a bare LB IP setup. Disable it via API call during bootstrap:

```hcl
resource "null_resource" "disable_v2_login" {
  provisioner "local-exec" {
    command = <<-EOT
      curl -s -X PUT "${var.zitadel_url}/admin/v1/features" \
        -H "Authorization: Bearer $(cat ${var.zitadel_key_file} | jq -r .key)" \
        -H "Content-Type: application/json" \
        -d '{"loginDefaultOrg": false}'
    EOT
  }
}
```

## ArgoCD Manifest (IP-Free)

The ArgoCD manifest at `core/manifests/argocd/apps/argocd.yaml` ships **without** OIDC config and **without** hardcoded IPs. Terraform injects the OIDC block into `argocd-cm` after deployment.

What gets removed from argocd.yaml:
- `global.hostAliases` (no more `zitadel.internal`)
- `configs.cm.url` (Terraform sets this too)
- `configs.cm."oidc.config"` (Terraform injects this)
- Hardcoded client ID `REDACTED_CLIENT_ID`

What stays:
- Helm chart source, version, resource limits
- Dex disabled, RBAC policy, SSH known hosts
- CNPG health check customization
- Sync policy

## K8s Secret Format

Each app gets an OIDC secret in its namespace:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: <app>-oidc-secrets
  namespace: <app-namespace>
type: Opaque
data:
  client-id: <base64>
  client-secret: <base64>      # Omitted for ArgoCD (PKCE)
```

For Grafana, the secret contains `GF_AUTH_*` env vars instead (see above).

## Secret Lifecycle

Secrets exist in two locations:
1. **K8s cluster** -- runtime consumption
2. **Terraform state in S3** -- encrypted at rest (AES-256), DynamoDB-locked

No SOPS file for OIDC secrets (JWT key is extracted from K8s, not SOPS-managed). If a secret is deleted, `terraform apply` recreates it.

## User Management

| User | Type | Role | Purpose |
|------|------|------|---------|
| Aaron | `zitadel_human_user` | `ORG_OWNER` + admin project grant | Admin of everything |
| William / family | `zitadel_human_user` | user project grant | App-level access |

### Authentication Flow

1. User navigates to app (e.g., Grafana at `http://<grafana-ip>:3000`)
2. App redirects to Zitadel login (`http://<zitadel-ip>:8080`)
3. User authenticates (email + password)
4. Zitadel redirects back to app with authorization code
5. App exchanges code for tokens via back-channel (pod-to-pod via LB IP)
6. App creates session

### Fallback

Every app retains local admin credentials (`existingSecret` passwords). If Zitadel is down, admin access via local accounts is the break-glass path.

## Lessons Learned

These were discovered during v1 implementation and directly informed this design:

| Issue | Resolution |
|-------|------------|
| Zitadel provider `token` param is actually a file path | Use `jwt_profile_file` instead -- clearer semantics |
| `DefaultInstance` Helm config keys are initialization-only | Use Zitadel API / Terraform resources for running instance config |
| v2 login UI needs ingress routing (`/<id>/login/`) | Disable via API call; use v1 login UI |
| ArgoCD `$secret:key` only works for `clientSecret` | Put `clientID` directly in ConfigMap (Terraform patches it) |
| Redirect URIs must match exactly | No default ports (`:80`, `:443`); include port when non-standard |
| `hostAliases` for `zitadel.internal` required injection into every pod | Use LB IP as ExternalDomain; no DNS resolution needed |
| Debian cloud image has built-in `operator` group | No need to create it in Ansible for mgmt VM |
| Hardcoded client IDs drift when Zitadel is rebuilt | `prevent_destroy` + Terraform state keeps IDs stable |

## Dependencies

- Zitadel healthy and accessible from mgmt VM (VLAN 10)
- JWT key extracted from `iam-admin` K8s secret
- Target namespaces exist (argocd, forgejo, harbor, monitoring)
- Mgmt VM has: kubeconfig, Terraform, kubectl, curl, jq
- Harbor admin password available (for config API call)

## terraform.tfvars Example

```hcl
# All IPs from: kubectl get svc -A | grep LoadBalancer
zitadel_url    = "http://REDACTED_LB_IP:8080"
zitadel_port   = "8080"
zitadel_org_id = "<from Zitadel>"
zitadel_key_file = "~/.config/zitadel-key.json"

argocd_url  = "http://REDACTED_LB_IP:8080"
forgejo_url = "http://REDACTED_LB_IP:3000"
harbor_url  = "http://REDACTED_LB_IP"
grafana_url = "http://REDACTED_LB_IP:3000"

harbor_admin_password = "<from harbor-admin-secret>"

admin_email      = "aaron@example.com"
admin_first_name = "Aaron"
admin_last_name  = "Valdez"

additional_users = [
  {
    email      = "william@example.com"
    first_name = "William"
    last_name  = "Doe"
  }
]
```

This file lives at `environments/prod/zitadel/terraform.tfvars` (gitignored). The public repo has zero IPs.

## Out of Scope

- MFA (future enhancement)
- Zitadel branding/login page customization
- Email notifications from Zitadel
- Service mesh or mTLS between apps and Zitadel
- Automatic secret rotation (re-run Terraform if needed)
- HTTPS/TLS (all internal, HTTP only)
