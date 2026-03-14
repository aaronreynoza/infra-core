output "project_id" {
  description = "Zitadel HOMELAB project ID"
  value       = zitadel_project.homelab.id
}

output "argocd_client_id" {
  description = "ArgoCD OIDC client ID"
  value       = zitadel_application_oidc.argocd.client_id
  sensitive   = true
}

output "forgejo_client_id" {
  description = "Forgejo OIDC client ID"
  value       = zitadel_application_oidc.forgejo.client_id
  sensitive   = true
}

output "harbor_client_id" {
  description = "Harbor OIDC client ID"
  value       = zitadel_application_oidc.harbor.client_id
  sensitive   = true
}

output "grafana_client_id" {
  description = "Grafana OIDC client ID"
  value       = zitadel_application_oidc.grafana.client_id
  sensitive   = true
}
