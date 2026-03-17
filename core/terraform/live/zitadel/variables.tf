# --- Zitadel connection ---
variable "zitadel_url" {
  description = "Zitadel instance URL (e.g., https://zitadel.example.org)"
  type        = string
}

variable "zitadel_internal_domain" {
  description = "Zitadel internal domain/IP for Terraform provider (direct access, no Pangolin)"
  type        = string
  default     = "10.10.10.225"
}

variable "zitadel_internal_port" {
  description = "Zitadel internal port"
  type        = string
  default     = "8080"
}

variable "zitadel_org_id" {
  description = "Zitadel default organization ID"
  type        = string
}

variable "zitadel_key_file" {
  description = "Path to Zitadel JWT service account key file (JSON)"
  type        = string
  default     = null # Set via TF_VAR_zitadel_key_file or -var (must be absolute path, ~ not expanded)
}

# --- Kubeconfig ---
variable "kubeconfig_path" {
  description = "Path to kubeconfig file for Kubernetes provider"
  type        = string
  default     = null # Set via TF_VAR_kubeconfig_path or -var (must be absolute path, ~ not expanded)
}

# --- App URLs ---
variable "argocd_url" {
  description = "ArgoCD base URL (e.g., https://argocd.example.org)"
  type        = string
}

variable "forgejo_url" {
  description = "Forgejo base URL (e.g., https://forgejo.example.org)"
  type        = string
}

variable "harbor_url" {
  description = "Harbor base URL (e.g., https://harbor.example.org)"
  type        = string
}

variable "grafana_url" {
  description = "Grafana base URL (e.g., https://grafana.example.org)"
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

