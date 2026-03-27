# Zitadel SSO Configuration
# Creates OIDC applications in Zitadel and distributes client secrets as K8s secrets.
# Run from mgmt VM with kubeconfig and SOPS age key available.

# --- URL construction from base_domain ---
# Subdomains are app identity (public, not secret).
# base_domain is environment-specific (set in prod tfvars).
locals {
  zitadel_url   = "https://zitadel.${var.base_domain}"
  argocd_url    = "https://argocd.${var.base_domain}"
  forgejo_url   = "https://forgejo.${var.base_domain}"
  harbor_url    = "https://harbor.${var.base_domain}"
  outline_url   = "https://docs.${var.base_domain}"
  grafana_url   = "https://grafana.${var.base_domain}"
  openwebui_url = "https://chat.${var.base_domain}"
plane_url     = "https://plane.${var.base_domain}"
  jellyfin_url  = "https://jellyfin.${var.base_domain}"
  navidrome_url = "https://navidrome.${var.base_domain}"
  immich_url    = "https://immich.${var.base_domain}"
  paperless_url = "https://paperless.${var.base_domain}"
  langfuse_url  = "https://langfuse.${var.base_domain}"
  temporal_url  = "https://temporal.${var.base_domain}"
}

# --- Zitadel provider ---
# JWT key extracted from K8s: kubectl get secret iam-admin -n zitadel -o jsonpath='{.data.iam-admin\.json}' | base64 -d > ~/.config/zitadel-key.json
# Connects via HTTPS/443 through the Cilium Gateway.
# Requires GRPC_ENFORCE_ALPN_ENABLED=false until Cilium fixes ALPN (cilium/cilium#39484).
# Requires split-horizon DNS (OPNSense or /etc/hosts).
provider "zitadel" {
  domain           = "zitadel.${var.base_domain}"
  port             = "443"
  insecure         = false
  jwt_profile_file = var.zitadel_key_file
}

# --- Kubernetes provider ---
provider "kubernetes" {
  config_path = var.kubeconfig_path
}

# --- Project ---
resource "zitadel_project" "homelab" {
  org_id                   = var.zitadel_org_id
  name                     = "HOMELAB"
  project_role_assertion   = true
  project_role_check       = true
  has_project_check        = true
  private_labeling_setting = "PRIVATE_LABELING_SETTING_UNSPECIFIED"

  lifecycle {
    ignore_changes = [org_id]
  }
}

# =============================================================================
# Current Apps — OIDC app + K8s secret always created
# =============================================================================

# --- ArgoCD (PKCE, no client secret needed) ---
resource "zitadel_application_oidc" "argocd" {
  org_id     = var.zitadel_org_id
  project_id = zitadel_project.homelab.id
  name       = "ArgoCD"

  redirect_uris             = ["${local.argocd_url}/auth/callback"]
  response_types            = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types               = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  app_type                  = "OIDC_APP_TYPE_USER_AGENT"
  auth_method_type          = "OIDC_AUTH_METHOD_TYPE_NONE" # PKCE
  post_logout_redirect_uris = [local.argocd_url]
  dev_mode                  = false
}

resource "kubernetes_secret_v1" "argocd_oidc" {
  metadata {
    name      = "argocd-oidc-secrets"
    namespace = "argocd"
  }

  data = {
    client-id = zitadel_application_oidc.argocd.client_id
  }
}

# --- Forgejo ---
resource "zitadel_application_oidc" "forgejo" {
  org_id     = var.zitadel_org_id
  project_id = zitadel_project.homelab.id
  name       = "Forgejo"

  redirect_uris             = ["${local.forgejo_url}/user/oauth2/Zitadel/callback"]
  response_types            = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types               = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  app_type                  = "OIDC_APP_TYPE_WEB"
  auth_method_type          = "OIDC_AUTH_METHOD_TYPE_POST"
  post_logout_redirect_uris = [local.forgejo_url]
  dev_mode                  = false
}

resource "kubernetes_secret_v1" "forgejo_oidc" {
  metadata {
    name      = "forgejo-oidc-secrets"
    namespace = "forgejo"
  }

  data = {
    client-id     = zitadel_application_oidc.forgejo.client_id
    client-secret = zitadel_application_oidc.forgejo.client_secret
  }
}

# --- Harbor ---
resource "zitadel_application_oidc" "harbor" {
  org_id     = var.zitadel_org_id
  project_id = zitadel_project.homelab.id
  name       = "Harbor"

  redirect_uris             = ["${local.harbor_url}/c/oidc/callback"]
  response_types            = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types               = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  app_type                  = "OIDC_APP_TYPE_WEB"
  auth_method_type          = "OIDC_AUTH_METHOD_TYPE_POST"
  post_logout_redirect_uris = [local.harbor_url]
  dev_mode                  = false
}

resource "kubernetes_secret_v1" "harbor_oidc" {
  metadata {
    name      = "harbor-oidc-secrets"
    namespace = "harbor"
  }

  data = {
    client-id     = zitadel_application_oidc.harbor.client_id
    client-secret = zitadel_application_oidc.harbor.client_secret
  }
}

# --- Grafana ---
resource "zitadel_application_oidc" "grafana" {
  org_id     = var.zitadel_org_id
  project_id = zitadel_project.homelab.id
  name       = "Grafana"

  redirect_uris             = ["${local.grafana_url}/login/generic_oauth"]
  response_types            = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types               = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  app_type                  = "OIDC_APP_TYPE_WEB"
  auth_method_type          = "OIDC_AUTH_METHOD_TYPE_BASIC"
  post_logout_redirect_uris = [local.grafana_url]
  dev_mode                  = false
}

resource "kubernetes_secret_v1" "grafana_oidc" {
  metadata {
    name      = "grafana-oidc-secrets"
    namespace = "monitoring"
  }

  data = {
    GF_AUTH_GENERIC_OAUTH_CLIENT_ID     = zitadel_application_oidc.grafana.client_id
    GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET = zitadel_application_oidc.grafana.client_secret
    GF_AUTH_GENERIC_OAUTH_AUTH_URL      = "${local.zitadel_url}/oauth/v2/authorize"
    GF_AUTH_GENERIC_OAUTH_TOKEN_URL     = "${local.zitadel_url}/oauth/v2/token"
    GF_AUTH_GENERIC_OAUTH_API_URL       = "${local.zitadel_url}/oidc/v1/userinfo"
    GF_SERVER_ROOT_URL                  = local.grafana_url
  }
}

# =============================================================================
# Apps — OIDC app + K8s secret (gated by toggle for undeployed apps)
# =============================================================================

# --- Open WebUI ---
resource "zitadel_application_oidc" "openwebui" {
  org_id     = var.zitadel_org_id
  project_id = zitadel_project.homelab.id
  name       = "Open WebUI"

  redirect_uris             = ["${local.openwebui_url}/oauth/oidc/callback"]
  response_types            = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types               = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  app_type                  = "OIDC_APP_TYPE_WEB"
  auth_method_type          = "OIDC_AUTH_METHOD_TYPE_POST"
  post_logout_redirect_uris = [local.openwebui_url]
  dev_mode                  = false
}

resource "kubernetes_secret_v1" "openwebui_oidc" {
  metadata {
    name      = "open-webui-oidc-secrets"
    namespace = "ai"
  }

  data = {
    client-id     = zitadel_application_oidc.openwebui.client_id
    client-secret = zitadel_application_oidc.openwebui.client_secret
  }
}

# --- Outline ---
resource "zitadel_application_oidc" "outline" {
  org_id     = var.zitadel_org_id
  project_id = zitadel_project.homelab.id
  name       = "Outline"

  redirect_uris             = ["${local.outline_url}/auth/oidc.callback"]
  response_types            = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types               = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  app_type                  = "OIDC_APP_TYPE_WEB"
  auth_method_type          = "OIDC_AUTH_METHOD_TYPE_POST"
  post_logout_redirect_uris = [local.outline_url]
  dev_mode                  = false
}

resource "kubernetes_secret_v1" "outline_oidc" {
  metadata {
    name      = "outline-oidc-secrets"
    namespace = "outline"
  }

  data = {
    client-id     = zitadel_application_oidc.outline.client_id
    client-secret = zitadel_application_oidc.outline.client_secret
  }
}

# --- Plane ---
resource "zitadel_application_oidc" "plane" {
  org_id     = var.zitadel_org_id
  project_id = zitadel_project.homelab.id
  name       = "Plane"

  redirect_uris             = ["${local.plane_url}/auth/oidc/callback/"]
  response_types            = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types               = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  app_type                  = "OIDC_APP_TYPE_WEB"
  auth_method_type          = "OIDC_AUTH_METHOD_TYPE_POST"
  post_logout_redirect_uris = ["${local.plane_url}/auth/oidc/logout/"]
  dev_mode                  = false
}

resource "kubernetes_secret_v1" "plane_oidc" {
  metadata {
    name      = "plane-oidc-secrets"
    namespace = "management"
  }

  data = {
    client-id     = zitadel_application_oidc.plane.client_id
    client-secret = zitadel_application_oidc.plane.client_secret
  }
}

# --- Jellyfin ---
resource "zitadel_application_oidc" "jellyfin" {
  org_id     = var.zitadel_org_id
  project_id = zitadel_project.homelab.id
  name       = "Jellyfin"

  redirect_uris    = ["${local.jellyfin_url}/sso/OID/redirect/Zitadel"]
  response_types   = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types      = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  app_type         = "OIDC_APP_TYPE_WEB"
  auth_method_type = "OIDC_AUTH_METHOD_TYPE_POST"
  dev_mode         = false
}

resource "kubernetes_secret_v1" "jellyfin_oidc" {
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

# --- Navidrome ---
resource "zitadel_application_oidc" "navidrome" {
  org_id     = var.zitadel_org_id
  project_id = zitadel_project.homelab.id
  name       = "Navidrome"

  redirect_uris    = ["${local.navidrome_url}/app/callback"]
  response_types   = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types      = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  app_type         = "OIDC_APP_TYPE_WEB"
  auth_method_type = "OIDC_AUTH_METHOD_TYPE_POST"
  dev_mode         = false
}

resource "kubernetes_secret_v1" "navidrome_oidc" {
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

# --- Immich ---
resource "zitadel_application_oidc" "immich" {
  org_id     = var.zitadel_org_id
  project_id = zitadel_project.homelab.id
  name       = "Immich"

  redirect_uris    = ["${local.immich_url}/auth/login"]
  response_types   = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types      = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  app_type         = "OIDC_APP_TYPE_WEB"
  auth_method_type = "OIDC_AUTH_METHOD_TYPE_POST"
  dev_mode         = false
}

resource "kubernetes_secret_v1" "immich_oidc" {
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

# --- Paperless-ngx ---
resource "zitadel_application_oidc" "paperless" {
  org_id     = var.zitadel_org_id
  project_id = zitadel_project.homelab.id
  name       = "Paperless-ngx"

  redirect_uris    = ["${local.paperless_url}/accounts/oidc/zitadel/login/callback/"]
  response_types   = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types      = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  app_type         = "OIDC_APP_TYPE_WEB"
  auth_method_type = "OIDC_AUTH_METHOD_TYPE_POST"
  dev_mode         = false
}

resource "kubernetes_secret_v1" "paperless_oidc" {
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

# --- Langfuse (LLM Observability) ---
resource "zitadel_application_oidc" "langfuse" {
  org_id     = var.zitadel_org_id
  project_id = zitadel_project.homelab.id
  name       = "Langfuse"

  redirect_uris              = ["${local.langfuse_url}/api/auth/callback/custom"]
  response_types             = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types                = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  app_type                   = "OIDC_APP_TYPE_WEB"
  auth_method_type           = "OIDC_AUTH_METHOD_TYPE_POST"
  post_logout_redirect_uris  = [local.langfuse_url]
  id_token_userinfo_assertion = true
  dev_mode                   = false
}

resource "kubernetes_secret_v1" "langfuse_oidc" {
  metadata {
    name      = "langfuse-oidc-secrets"
    namespace = "langfuse"
  }

  data = {
    client-id     = zitadel_application_oidc.langfuse.client_id
    client-secret = zitadel_application_oidc.langfuse.client_secret
  }
}

# --- Temporal (UI native OIDC) ---
resource "zitadel_application_oidc" "temporal" {
  org_id     = var.zitadel_org_id
  project_id = zitadel_project.homelab.id
  name       = "Temporal"

  redirect_uris             = ["${local.temporal_url}/auth/sso/callback"]
  response_types            = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types               = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  app_type                  = "OIDC_APP_TYPE_WEB"
  auth_method_type          = "OIDC_AUTH_METHOD_TYPE_POST"
  post_logout_redirect_uris = [local.temporal_url]
  dev_mode                  = false
}

resource "kubernetes_secret_v1" "temporal_oidc" {
  metadata {
    name      = "temporal-oidc-secrets"
    namespace = "temporal"
  }

  data = {
    TEMPORAL_AUTH_CLIENT_ID     = zitadel_application_oidc.temporal.client_id
    TEMPORAL_AUTH_CLIENT_SECRET = zitadel_application_oidc.temporal.client_secret
  }
}

# =============================================================================
# Project Roles
# =============================================================================

# --- RBAC roles ---
resource "zitadel_project_role" "admins" {
  org_id       = var.zitadel_org_id
  project_id   = zitadel_project.homelab.id
  role_key     = "admins"
  display_name = "Admins"
}

resource "zitadel_project_role" "cloud_engineers" {
  org_id       = var.zitadel_org_id
  project_id   = zitadel_project.homelab.id
  role_key     = "cloud-engineers"
  display_name = "Cloud Engineers"
}

resource "zitadel_project_role" "developers" {
  org_id       = var.zitadel_org_id
  project_id   = zitadel_project.homelab.id
  role_key     = "developers"
  display_name = "Developers"
}

resource "zitadel_project_role" "managers" {
  org_id       = var.zitadel_org_id
  project_id   = zitadel_project.homelab.id
  role_key     = "managers"
  display_name = "Managers"
}

resource "zitadel_project_role" "guests" {
  org_id       = var.zitadel_org_id
  project_id   = zitadel_project.homelab.id
  role_key     = "guests"
  display_name = "Guests"
}

# =============================================================================
# User Management
# =============================================================================

# --- Initial password (must be changed on first login) ---
resource "random_password" "initial_user_password" {
  length           = 24
  special          = true
  override_special = "!@#$%&*"
}

# --- Admin user ---
resource "zitadel_human_user" "admin" {
  org_id             = var.zitadel_org_id
  user_name          = var.admin_email
  first_name         = var.admin_first_name
  last_name          = var.admin_last_name
  email              = var.admin_email
  is_email_verified  = true
  initial_password   = random_password.initial_user_password.result
}

resource "zitadel_user_grant" "admin_project" {
  org_id     = var.zitadel_org_id
  project_id = zitadel_project.homelab.id
  user_id    = zitadel_human_user.admin.id
  role_keys  = ["admins"]

  depends_on = [zitadel_project_role.admins]
}

resource "zitadel_org_member" "admin_iam" {
  org_id  = var.zitadel_org_id
  user_id = zitadel_human_user.admin.id
  roles   = ["ORG_OWNER"]
}

# --- Additional users ---
resource "zitadel_human_user" "additional" {
  for_each = { for u in var.additional_users : u.email => u }

  org_id             = var.zitadel_org_id
  user_name          = each.value.email
  first_name         = each.value.first_name
  last_name          = each.value.last_name
  email              = each.value.email
  is_email_verified  = true
  initial_password   = random_password.initial_user_password.result
}

resource "zitadel_user_grant" "additional_project" {
  for_each = { for u in var.additional_users : u.email => u }

  org_id     = var.zitadel_org_id
  project_id = zitadel_project.homelab.id
  user_id    = zitadel_human_user.additional[each.key].id
  role_keys  = [each.value.role]
}

# --- Claude Agent (machine user — no MFA, API-only access) ---
resource "zitadel_machine_user" "claude_agent" {
  org_id      = var.zitadel_org_id
  user_name   = "claude-agent"
  name        = "Claude Agent"
  description = "AI development agent for the Reynoza Brothers homelab"
}

resource "zitadel_user_grant" "claude_agent_project" {
  org_id     = var.zitadel_org_id
  project_id = zitadel_project.homelab.id
  user_id    = zitadel_machine_user.claude_agent.id
  role_keys  = ["admins"]

  depends_on = [zitadel_project_role.admins]
}

# =============================================================================
# App-Side OIDC Configuration (Terraform owns these, not ArgoCD)
# =============================================================================

# --- ArgoCD: Patch argocd-cm with OIDC config ---
resource "kubernetes_config_map_v1_data" "argocd_oidc" {
  metadata {
    name      = "argocd-cm"
    namespace = "argocd"
  }

  data = {
    "url" = local.argocd_url

    "oidc.config" = yamlencode({
      name     = "Zitadel"
      issuer   = local.zitadel_url
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

# --- Forgejo: Add Zitadel as OAuth2 authentication source ---
resource "null_resource" "forgejo_oauth_source" {
  triggers = {
    client_id     = zitadel_application_oidc.forgejo.client_id
    client_secret = zitadel_application_oidc.forgejo.client_secret
    issuer_url    = local.zitadel_url
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
        SOURCE_ID=$(kubectl --kubeconfig="$KUBECONFIG" exec -n forgejo "$FORGEJO_POD" -- \
          gitea admin auth list 2>/dev/null | grep "Zitadel" | awk '{print $1}')

        kubectl --kubeconfig="$KUBECONFIG" exec -n forgejo "$FORGEJO_POD" -- \
          gitea admin auth update-oauth \
            --id "$SOURCE_ID" \
            --name "Zitadel" \
            --provider "openidConnect" \
            --key "${zitadel_application_oidc.forgejo.client_id}" \
            --secret "${zitadel_application_oidc.forgejo.client_secret}" \
            --auto-discover-url "${local.zitadel_url}/.well-known/openid-configuration" \
            --skip-local-2fa \
            --scopes "openid profile email" \
            --group-claim-name "" \
            --admin-group ""
      else
        echo "Adding Zitadel auth source..."
        kubectl --kubeconfig="$KUBECONFIG" exec -n forgejo "$FORGEJO_POD" -- \
          gitea admin auth add-oauth \
            --name "Zitadel" \
            --provider "openidConnect" \
            --key "${zitadel_application_oidc.forgejo.client_id}" \
            --secret "${zitadel_application_oidc.forgejo.client_secret}" \
            --auto-discover-url "${local.zitadel_url}/.well-known/openid-configuration" \
            --skip-local-2fa \
            --scopes "openid profile email"
      fi
    EOT
  }

  depends_on = [
    kubernetes_secret_v1.forgejo_oidc
  ]
}

# --- Harbor: Configure OIDC via REST API ---
resource "null_resource" "harbor_oidc_config" {
  triggers = {
    client_id     = zitadel_application_oidc.harbor.client_id
    client_secret = zitadel_application_oidc.harbor.client_secret
    issuer_url    = local.zitadel_url
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      HARBOR_URL="${local.harbor_url}"
      HARBOR_PASS=$(kubectl --kubeconfig="${var.kubeconfig_path}" get secret harbor-credentials -n harbor -o jsonpath='{.data.admin-password}' | base64 -d)

      curl -sf -X PUT "$HARBOR_URL/api/v2.0/configurations" \
        -u "admin:$HARBOR_PASS" \
        -H "Content-Type: application/json" \
        -d '{
          "auth_mode": "oidc_auth",
          "oidc_name": "Zitadel",
          "oidc_endpoint": "${local.zitadel_url}",
          "oidc_client_id": "${zitadel_application_oidc.harbor.client_id}",
          "oidc_client_secret": "${zitadel_application_oidc.harbor.client_secret}",
          "oidc_scope": "openid,profile,email",
          "oidc_verify_cert": false,
          "oidc_auto_onboard": true,
          "oidc_user_claim": "email",
          "oidc_groups_claim": "groups",
          "oidc_admin_group": "admins"
        }'

      echo "Harbor OIDC configuration applied."
    EOT
  }

  depends_on = [
    kubernetes_secret_v1.harbor_oidc
  ]
}

# =============================================================================
# Zitadel Instance Settings
# =============================================================================

resource "zitadel_default_login_policy" "default" {
  user_login                    = true
  allow_register                = false
  allow_external_idp            = true
  force_mfa                     = true
  force_mfa_local_only          = false
  passwordless_type             = "PASSWORDLESS_TYPE_NOT_ALLOWED"
  hide_password_reset           = false
  ignore_unknown_usernames      = false
  default_redirect_uri          = "${local.zitadel_url}/ui/console"
  multi_factors                 = []
  second_factors                = ["SECOND_FACTOR_TYPE_OTP"]
  password_check_lifetime       = "240h"
  external_login_check_lifetime = "12h"
  mfa_init_skip_lifetime        = "0s"
  second_factor_check_lifetime  = "12h"
  multi_factor_check_lifetime   = "12h"
}

resource "zitadel_default_oidc_settings" "default" {
  access_token_lifetime          = "12h"
  id_token_lifetime              = "12h"
  refresh_token_idle_expiration  = "720h"
  refresh_token_expiration       = "720h"
}

# =============================================================================
# Actions — Flatten project roles into a "groups" claim for ArgoCD / apps
# =============================================================================
# Zitadel's default urn:zitadel:iam:org:project:roles claim is a nested object:
#   { "admins": { "<orgId>": "<orgDomain>" } }
# ArgoCD (and most apps) expect a flat array: ["admins", "cloud-engineers", ...]
# This Action extracts role key names and sets them as a "groups" claim.

resource "zitadel_action" "flatten_roles" {
  org_id          = var.zitadel_org_id
  name            = "flattenRolesToGroups"
  timeout         = "10s"
  allowed_to_fail = false

  script = <<-JS
    function flattenRolesToGroups(ctx, api) {
      if (ctx.v1.user.grants == undefined || ctx.v1.user.grants.count == 0) {
        return;
      }

      let roles = [];
      ctx.v1.user.grants.grants.forEach(function(grant) {
        grant.roles.forEach(function(role) {
          if (roles.indexOf(role) === -1) {
            roles.push(role);
          }
        });
      });

      api.v1.claims.setClaim('groups', roles);
    }
  JS
}

# Attach the action to Pre Userinfo Creation (covers id_token, userinfo endpoint,
# and introspection endpoint — this is what ArgoCD reads via OIDC)
resource "zitadel_trigger_actions" "flatten_roles_userinfo" {
  org_id       = var.zitadel_org_id
  flow_type    = "FLOW_TYPE_CUSTOMISE_TOKEN"
  trigger_type = "TRIGGER_TYPE_PRE_USERINFO_CREATION"
  action_ids   = [zitadel_action.flatten_roles.id]
}

# Attach the action to Pre Access Token Creation (covers JWT access tokens,
# useful for services that inspect the access token directly)
resource "zitadel_trigger_actions" "flatten_roles_access_token" {
  org_id       = var.zitadel_org_id
  flow_type    = "FLOW_TYPE_CUSTOMISE_TOKEN"
  trigger_type = "TRIGGER_TYPE_PRE_ACCESS_TOKEN_CREATION"
  action_ids   = [zitadel_action.flatten_roles.id]
}
