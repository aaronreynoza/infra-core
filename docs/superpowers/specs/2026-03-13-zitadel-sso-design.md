# Zitadel SSO Design Spec

## Overview

Centralized SSO for all homelab applications using Zitadel as the OIDC identity provider. Terraform manages OIDC application registration, secret distribution, and user provisioning. All apps authenticate through Zitadel while retaining local admin fallback accounts.

## Architecture

```
                    +-----------+
                    |  Zitadel  |  (K8s, LoadBalancer 10.10.10.X)
                    |  OIDC IdP |
                    +-----+-----+
                          |
          +-------+-------+-------+-------+
          |       |       |       |       |
        ArgoCD  Forgejo Harbor  Grafana  (future apps)
          |       |       |       |
     OIDC Login Flow (redirect → Zitadel → callback)
```

### Components

- **Zitadel** — already deployed in K8s (Helm chart v9.26.0, namespace `zitadel`, CloudNativePG PostgreSQL backend)
- **Terraform** (`zitadel` + `kubernetes` providers) — creates OIDC apps in Zitadel, writes client secrets as K8s secrets
- **Helm values** — each app's ArgoCD manifest updated to consume OIDC secrets and enable SSO
- **SOPS** — encrypts the Zitadel PAT in `environments/prod/`

### Decision: Why Terraform

Evaluated 8 approaches (CronJob, Terraform, ArgoCD hooks, Crossplane, Zitadel CLI, Helm init, Zitadel Actions, ESO). Chose Terraform because:
- Official provider (v2.10.0, 104 resources, production-ready)
- Already part of the stack — same patterns, same state backend
- Idempotent via state — re-run safely
- Single `terraform apply` creates OIDC apps + K8s secrets in one step
- No polling/scheduling overhead (vs CronJob)

Trade-off: no automatic self-healing (vs CronJob). Acceptable for a homelab — if a secret is deleted, re-run `terraform apply`.

## Terraform Structure

```
core/terraform/live/zitadel/
├── main.tf          # Providers, project, OIDC apps, K8s secrets
├── variables.tf     # Zitadel URL, PAT, redirect URIs, user config
├── outputs.tf       # App client IDs (no secrets in output)
├── versions.tf      # Provider version constraints

environments/prod/zitadel/
├── backend.hcl          # S3 backend (key: zitadel/terraform.tfstate)
├── terraform.tfvars     # Non-sensitive vars (Zitadel URL, redirect URIs, user emails)
└── secrets.enc.yaml     # SOPS-encrypted (Zitadel PAT)
```

### Providers

| Provider | Purpose | Auth |
|----------|---------|------|
| `zitadel/zitadel` | Create OIDC apps, users, project | PAT from SOPS via `carlpett/sops` provider |
| `hashicorp/kubernetes` | Create K8s secrets in app namespaces | kubeconfig (`~/.kube/config` on mgmt VM) |

### SOPS Integration

The Zitadel PAT is stored in `environments/prod/zitadel/secrets.enc.yaml` (SOPS-encrypted with age key). Terraform reads it via the `carlpett/sops` provider — same pattern used for Proxmox credentials and other secrets in this project. The `terraform.tfvars` file contains only non-sensitive values.

### Init/Apply Pattern

```bash
cd core/terraform/live/zitadel
terraform init -backend-config=../../../../environments/prod/zitadel/backend.hcl
terraform plan -var-file=../../../../environments/prod/zitadel/terraform.tfvars
terraform apply -var-file=../../../../environments/prod/zitadel/terraform.tfvars
```

## OIDC Applications

Single Zitadel project: `HOMELAB`

### Current Apps (created + secrets deployed)

| App | Namespace | K8s Secret Name | Auth Method | Redirect URI Pattern |
|-----|-----------|-----------------|-------------|---------------------|
| ArgoCD | `argocd` | `argocd-oidc-secrets` | PKCE (User Agent/SPA app type) | `http://<argocd-ip>:8080/auth/callback` |
| Forgejo | `forgejo` | `forgejo-oidc-secrets` | Client Secret POST (Web app type) | `http://<forgejo-ip>:3000/user/oauth2/Zitadel/callback` |
| Harbor | `harbor` | `harbor-oidc-secrets` | Client Secret POST (Web app type) | `http://<harbor-ip>/c/oidc/callback` |
| Grafana | `monitoring` | `grafana-oidc-secrets` | Client Secret BASIC (Web app type) | `http://<grafana-ip>:3000/login/generic_oauth` |

Redirect URIs use Cilium LB-IPAM IPs (from the REDACTED_LB_IP-250 pool). Actual IPs are populated in `terraform.tfvars` from `kubectl get svc` output. All flows are HTTP (Zitadel runs with `ExternalSecure: false`).

### Future Apps (OIDC app created, K8s secret deferred until namespace exists)

| App | Namespace | K8s Secret Name | Auth Method |
|-----|-----------|-----------------|-------------|
| Jellyfin | `media` | `jellyfin-oidc-secrets` | Client Secret (POST) |
| Navidrome | `media` | `navidrome-oidc-secrets` | Client Secret (POST) |
| Open WebUI | `ai` | `open-webui-oidc-secrets` | Client Secret (POST) |
| Immich | `media` | `immich-oidc-secrets` | Client Secret (POST) |
| Paperless | `management` | `paperless-oidc-secrets` | Client Secret (POST) |

Future app secrets are gated by a `create_secret` variable — set to `true` when the app is deployed and its namespace exists.

**Note:** Navidrome's OIDC support is community-contributed and may be limited. If the deployed version does not support OIDC natively, an OAuth2 Proxy sidecar will be used instead. Verify at deploy time.

### K8s Secret Format

Each secret contains two keys:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: <app>-oidc-secrets
  namespace: <app-namespace>
type: Opaque
data:
  client-id: <base64>
  client-secret: <base64>
```

Apps reference these via `existingSecret` in their Helm values — same pattern already used for database passwords and other credentials.

## Secret Lifecycle

Secrets exist in two locations:
1. **K8s cluster** — where apps read them at runtime
2. **Terraform state in S3** — encrypted at rest (AES-256), locked with DynamoDB

No plaintext secrets on disk. No SOPS file for OIDC secrets (PAT is SOPS-encrypted, but app secrets are managed entirely by Terraform).

If a K8s secret is deleted: `terraform apply` recreates it.
If Zitadel is rebuilt: `terraform apply` recreates all OIDC apps + secrets.

## User Management

### Users

| User | Type | Role | Purpose |
|------|------|------|---------|
| Aaron | `zitadel_human_user` | `IAM_OWNER` + all project grants | Admin of everything |
| William / family | `zitadel_human_user` | Project-level grants (per app) | Access to specific apps |

### Authentication Flow

1. User navigates to app (e.g., Grafana)
2. App redirects to Zitadel login page
3. User authenticates (email + password, or future MFA)
4. Zitadel redirects back to app with authorization code
5. App exchanges code for tokens via back-channel
6. App creates session, user is logged in

### Fallback

Every app retains a local admin account (existing `existingSecret` passwords). If Zitadel is down, admins can still access apps via local credentials. This is the break-glass path.

## Helm Values Integration

After `terraform apply` creates the secrets, each app's Helm values are updated:

### ArgoCD

OIDC configured directly (Dex disabled). Uses PKCE — no client secret needed in config, only the client ID and issuer URL. RBAC policy maps Zitadel roles to ArgoCD roles (admin, readonly).

### Forgejo

`[oauth2]` section enabled. Provider name `Zitadel`, auto-discovery from issuer URL. Client ID/secret from `forgejo-oidc-secrets`. Auto-creates users on first login.

### Harbor

Auth mode set to `oidc_auth`. Issuer endpoint, client ID/secret from `harbor-oidc-secrets`. Admin group claim maps Zitadel role to Harbor admin.

### Grafana

`auth.generic_oauth` section enabled. Issuer URL, client ID/secret from `grafana-oidc-secrets`. Auto-login enabled. Role mapping from Zitadel claims (admin/editor/viewer).

### Future Apps

OIDC configuration prepared in Helm values but only activated when the app is deployed. Each app follows the same pattern: reference `<app>-oidc-secrets`, configure issuer URL, enable auto-user provisioning.

## PAT Bootstrapping

The Terraform provider needs a Personal Access Token (PAT) to authenticate to Zitadel. Two paths depending on what the Helm chart setup job creates:

**Path A — PAT exists as K8s secret** (if Helm values configure `machinekey` + PAT generation):
```bash
kubectl get secret iam-admin-pat -n zitadel -o jsonpath='{.data.pat}' | base64 -d
```

**Path B — Manual PAT creation** (if no K8s secret exists):
1. Access Zitadel console via `http://<zitadel-ip>:8080`
2. Log in with the initial admin credentials (check Helm chart setup job logs or `zitadel-admin-sa` secret)
3. Create a Service User (Machine type) with `IAM_OWNER` role
4. Generate a Personal Access Token for this user
5. Copy the PAT value

In either case, SOPS-encrypt the PAT:
```bash
echo "pat: <PAT_VALUE>" | sops -e --input-type yaml --output-type yaml /dev/stdin > environments/prod/zitadel/secrets.enc.yaml
```

The implementation plan will verify which path applies and document the exact steps.

## Issuer URL

Zitadel is configured with `ExternalSecure: false` and `ExternalPort: 8080`. The OIDC issuer URL is:

```
http://<zitadel-lb-ip>:8080
```

All apps must use this exact URL — OIDC clients are strict about issuer matching. The URL is stored in `terraform.tfvars` as `zitadel_url`.

## Execution Flow

```
1. Bootstrap PAT (see PAT Bootstrapping section above)
   → SOPS-encrypt into environments/prod/zitadel/secrets.enc.yaml

2. Get Zitadel's LoadBalancer IP
   kubectl get svc -n zitadel → 10.10.10.X
   → Add to terraform.tfvars as zitadel_url

3. Terraform apply (from mgmt VM)
   → Creates HOMELAB project
   → Creates 9 OIDC apps (4 current + 5 future)
   → Creates 4 K8s secrets (current app namespaces)
   → Creates human users + project grants

4. Update Helm values
   → Enable OIDC in ArgoCD, Forgejo, Harbor, Grafana values
   → Git commit + push

5. ArgoCD syncs
   → Apps pick up new values + secrets
   → Pods restart with OIDC enabled

6. Verify
   → Login to each app via Zitadel
   → Verify local admin fallback still works
```

## Dependencies

- Zitadel must be healthy and accessible from mgmt VM (via VLAN 10)
- PAT must be bootstrapped and SOPS-encrypted (see PAT Bootstrapping section)
- Target namespaces must exist for current apps (argocd, forgejo, harbor, monitoring)
- Mgmt VM must have kubeconfig and Terraform installed (already done)
- Zitadel provider version >= 2.10.0, kubernetes provider >= 2.x

## Out of Scope

- MFA configuration (future enhancement)
- Zitadel branding/login page customization
- Email notifications from Zitadel
- Service mesh or mTLS between apps and Zitadel
- Automatic secret rotation (re-run Terraform manually if needed)
