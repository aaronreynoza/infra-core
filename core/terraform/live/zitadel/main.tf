# Zitadel SSO Configuration
# Creates OIDC applications in Zitadel and distributes client secrets as K8s secrets.
# Run from mgmt VM with kubeconfig and SOPS age key available.

# --- Zitadel provider ---
# JWT key extracted from K8s: kubectl get secret iam-admin -n zitadel -o jsonpath='{.data.iam-admin\.json}' | base64 -d > ~/.config/zitadel-key.json
provider "zitadel" {
  domain           = replace(replace(var.zitadel_url, "http://", ""), "/:[0-9]+$/", "")
  port             = var.zitadel_port
  insecure         = true  # No TLS in internal network
  jwt_profile_file = var.zitadel_key_file
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

# =============================================================================
# Current Apps — OIDC app + K8s secret always created
# =============================================================================

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

resource "kubernetes_secret_v1" "grafana_oidc" {
  metadata {
    name      = "grafana-oidc-secrets"
    namespace = "monitoring"
  }

  data = {
    client-id     = zitadel_application_oidc.grafana.client_id
    client-secret = zitadel_application_oidc.grafana.client_secret
  }
}

# =============================================================================
# Future Apps — OIDC app always created, K8s secret gated by toggle variable
# =============================================================================

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

resource "kubernetes_secret_v1" "openwebui_oidc" {
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

# =============================================================================
# Project Roles
# =============================================================================

resource "zitadel_project_role" "admin" {
  org_id       = var.zitadel_org_id
  project_id   = zitadel_project.homelab.id
  role_key     = "admin"
  display_name = "Admin"
}

resource "zitadel_project_role" "user" {
  org_id       = var.zitadel_org_id
  project_id   = zitadel_project.homelab.id
  role_key     = "user"
  display_name = "User"
}

# =============================================================================
# User Management
# =============================================================================

# --- Admin user ---
resource "zitadel_human_user" "admin" {
  org_id             = var.zitadel_org_id
  user_name          = var.admin_email
  first_name         = var.admin_first_name
  last_name          = var.admin_last_name
  email              = var.admin_email
  is_email_verified  = true
  initial_password   = "ChangeMe123!"  # Must be changed on first login
}

resource "zitadel_user_grant" "admin_project" {
  org_id     = var.zitadel_org_id
  project_id = zitadel_project.homelab.id
  user_id    = zitadel_human_user.admin.id
  role_keys  = ["admin"]

  depends_on = [zitadel_project_role.admin]
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
  initial_password   = "ChangeMe123!"
}

resource "zitadel_user_grant" "additional_project" {
  for_each = { for u in var.additional_users : u.email => u }

  project_id = zitadel_project.homelab.id
  user_id    = zitadel_human_user.additional[each.key].id
  role_keys  = ["user"]
}
