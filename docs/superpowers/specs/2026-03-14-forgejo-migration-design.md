# Forgejo Migration + Two-Repo Split Design Spec

## Overview

Migrate Git source of truth from GitHub to self-hosted Forgejo. Split into two repos: public `homelab` (reusable infrastructure code) and private `homelab-env` (environment-specific config with IPs, secrets, ArgoCD manifests). GitHub becomes a read-only mirror for both repos.

## Architecture

```
GitHub (mirror)                    Forgejo (origin)
  homelab (public)  <-- push --  homelab (public)
  homelab-env (private) <-- push --  homelab-env (private)

ArgoCD sources ALL manifests from Forgejo homelab-env repo.
Public homelab repo has zero ArgoCD app manifests after migration.
```

### Key Principles

1. **Forgejo is origin** -- GitHub is a push mirror for both repos.
2. **Private repo is self-contained** -- every ArgoCD manifest has inline Helm values with IPs, no multi-source pattern.
3. **No submodules** -- private repo lives at `environments/prod/` on disk, nested inside homelab (gitignored), but is its own git repo.
4. **Zero IPs in public history** -- `git-filter-repo` purges all hardcoded IPs from the public repo after cutover.
5. **Zero-downtime cutover** -- ArgoCD supports multiple repo sources simultaneously during transition.

## Repo Structure

### Private Repo (`homelab-env`)

Git root: `environments/prod/` on disk. Repo name on Forgejo and GitHub: `homelab-env`.

```
environments/prod/                     # Repo root
  apps/                                # ALL ArgoCD app manifests
    root.yaml                          # Points to this directory in Forgejo
    argocd.yaml                        # Full manifest with IPs, OIDC config
    forgejo.yaml
    harbor.yaml
    zitadel.yaml
    kube-prometheus-stack.yaml
    cilium.yaml, cilium-namespace.yaml
    longhorn.yaml, longhorn-namespace.yaml
    cnpg-operator.yaml
    cnpg-cluster-forgejo.yaml, cnpg-cluster-zitadel.yaml
    loki.yaml, tempo.yaml, mimir.yaml
    opentelemetry-collector.yaml
    velero.yaml, newt.yaml
    nginx-test.yaml, docs-site.yaml
  secrets/                             # SOPS-encrypted secrets
  terraform/                           # Cluster bootstrap TF (talos-cluster)
  zitadel/                             # Zitadel OIDC TF config
  network/                             # OPNSense TF config
  bootstrap/                           # AWS backend TF config
  kubeconfig
  talosconfig
  backend.hcl
  .sops.yaml
  .gitignore
```

### Public Repo (`homelab`) -- After Migration

Deletions:
- `core/manifests/argocd/apps/` -- all app manifests removed
- `core/manifests/argocd/root-app.yaml` -- root app removed

Kept:
- `core/terraform/modules/` -- reusable Terraform modules (talos-cluster, proxmox-vm, aws-backend)
- `core/terraform/live/` -- live Terraform configs (parameterized, no IPs)
- `core/charts/` -- Helm values kept as reference/examples only
- `core/ansible/` -- playbooks and inventory
- `core/scripts/` -- utility scripts
- `docs/` -- all documentation

No hardcoded IPs anywhere in the repo or its git history after the final purge.

## App Manifest Migration

All ArgoCD app manifests move as-is from `core/manifests/argocd/apps/` to `environments/prod/apps/`. They keep their inline Helm values -- IPs are fine in the private repo. No refactoring to multi-source.

The `root.yaml` app-of-apps manifest is updated to point to the Forgejo private repo:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
spec:
  source:
    repoURL: http://<forgejo-lb-ip>:3000/<org>/homelab-env.git
    targetRevision: main
    path: apps
  destination:
    server: https://kubernetes.default.svc
  project: default
```

## Migration Sequence

### Phase 1: Set Up Private Repo

```
1. cd environments/prod/
2. git init
3. Move all manifests: core/manifests/argocd/apps/*.yaml -> environments/prod/apps/
4. Move root-app.yaml -> environments/prod/apps/root.yaml
5. Update root.yaml repoURL to point to Forgejo
6. git add, git commit
7. Push to Forgejo (origin) + GitHub (private mirror)
```

### Phase 2: ArgoCD Cutover (Zero-Downtime)

```
1. Add Forgejo as a repo source in ArgoCD (alongside existing GitHub)
   - ArgoCD Settings -> Repositories -> Add repo
   - URL: http://<forgejo-lb-ip>:3000/<org>/homelab-env.git
   - Credentials: Forgejo service account token or Zitadel OIDC

2. Apply the new root app from Forgejo
   kubectl apply -f environments/prod/apps/root.yaml
   - This deploys a root app pointing to Forgejo's apps/ directory
   - Both old (GitHub) and new (Forgejo) root apps coexist temporarily

3. Verify all apps sync from Forgejo
   - Every app should show Synced/Healthy sourced from Forgejo
   - Compare with existing GitHub-sourced apps

4. Delete the old GitHub-based root app
   kubectl delete application root-old -n argocd
   - ArgoCD now sources everything exclusively from Forgejo
```

### Phase 3: Clean Public Repo

```
1. Delete core/manifests/argocd/apps/ directory
2. Delete core/manifests/argocd/root-app.yaml
3. Commit and push to GitHub + Forgejo
```

### Phase 4: History Purge

```
1. git-filter-repo on the public homelab repo to remove:
   - All hardcoded IPs (internal LB IPs, management network IPs)
   - OIDC client IDs (e.g., REDACTED_CLIENT_ID)
   - Any secrets that leaked into commits
   - References to environments/ directory contents

2. Force push to GitHub and Forgejo
3. All machines re-clone the public repo
```

Same approach used in the 2026-02-05 history rewrite.

### Phase 5: Forgejo Actions Runner

```
1. Register forgejo-runner on mgmt VM (REDACTED_MGMT_IP) to Forgejo org
2. Runner serves both repos
3. CI pipelines:
   - Public repo: lint, validate Terraform, validate Helm charts
   - Private repo: terraform plan, secret validation
```

## ArgoCD Repo Credentials

ArgoCD needs credentials to access the private Forgejo repo. Options:

| Method | Pros | Cons |
|--------|------|------|
| **Forgejo access token** | Simple, one-time setup | Token rotation is manual |
| **SSH deploy key** | No password, per-repo scoping | Key management |
| **Zitadel OIDC** | SSO-consistent | ArgoCD repo auth does not support OIDC natively |

Recommended: **Forgejo access token** stored as a K8s secret in the `argocd` namespace. ArgoCD references it via repository credential template.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: forgejo-repo-creds
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repo-creds
type: Opaque
stringData:
  type: git
  url: http://<forgejo-lb-ip>:3000
  username: argocd-bot
  password: <forgejo-access-token>
```

## GitHub Mirroring

Forgejo supports push mirrors natively. After migration:

```
Forgejo homelab (public)  --push mirror-->  GitHub homelab (public)
Forgejo homelab-env (private)  --push mirror-->  GitHub homelab-env (private)
```

Configure in Forgejo: Settings -> Mirror Settings -> Push Mirror. Requires a GitHub personal access token with `repo` scope stored in Forgejo.

Mirroring is one-way: Forgejo to GitHub. All development happens on Forgejo. GitHub is read-only.

## Forgejo Actions CI

### Public Repo (`homelab`)

```yaml
# .forgejo/workflows/validate.yml
on: [push, pull_request]
jobs:
  validate:
    runs-on: ubuntu-latest  # mgmt VM runner
    steps:
      - uses: actions/checkout@v4
      - name: Validate Terraform
        run: |
          cd core/terraform/live
          for dir in */; do
            terraform -chdir="$dir" init -backend=false
            terraform -chdir="$dir" validate
          done
      - name: Lint Ansible
        run: ansible-lint core/ansible/
```

### Private Repo (`homelab-env`)

```yaml
# .forgejo/workflows/plan.yml
on:
  workflow_dispatch:  # Manual trigger only for destructive ops
  push:
    paths: ['terraform/**', 'zitadel/**', 'network/**']
jobs:
  plan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Terraform Plan
        run: |
          cd terraform
          terraform init -backend-config=../backend.hcl
          terraform plan -var-file=../terraform.tfvars
```

## Key Constraints

- Private repo lives at `environments/prod/` nested inside homelab on disk (gitignored by homelab)
- No submodules -- two completely independent git repos
- No multi-source ArgoCD pattern -- manifests are self-contained with inline values
- Forgejo is origin, GitHub is mirror (both public and private repos)
- Zitadel OIDC already configured for Forgejo (Phase 2 of the SSO design is complete)
- `network/`, `bootstrap/`, `zitadel/` stay as subdirectories in the private repo
- `terraform plan` on private repo is manual trigger (`workflow_dispatch`) for destructive operations

## Dependencies

- Forgejo deployed, healthy, accessible on LB IP (Cilium LB-IPAM)
- Zitadel OIDC configured for Forgejo (login works)
- Mgmt VM (VM 110) operational with `forgejo-runner` installed
- ArgoCD accessible and managing all current apps from GitHub
- `git-filter-repo` available on workstation (used in 2026-02-05 rewrite)

## Rollback Plan

If Forgejo becomes unavailable after cutover:

1. ArgoCD apps continue running (last-synced state persists)
2. Re-add GitHub as a repo source in ArgoCD
3. Apply original root app pointing to GitHub
4. Apps sync from GitHub again

The GitHub mirror always has an up-to-date copy of both repos. Recovery is adding GitHub back as a source and repointing the root app.

## Out of Scope

- Dev environment split (only prod for now; dev cluster is not deployed)
- Automated GitHub-to-Forgejo PR mirroring (one-way push mirror only)
- Forgejo Actions for app deployments (ArgoCD handles GitOps)
- HTTPS/TLS for Forgejo (internal only, HTTP)
- Forgejo high availability (single instance, backed by CNPG Postgres)
