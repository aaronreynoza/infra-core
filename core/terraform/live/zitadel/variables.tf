# --- Domain ---
variable "base_domain" {
  description = "Base domain for all services (e.g., example.org). All app URLs are derived as https://<subdomain>.<base_domain>"
  type        = string
}

# --- Zitadel connection ---
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
