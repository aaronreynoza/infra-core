# Forgejo Migration + Two-Repo Split Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate Git source of truth from GitHub to Forgejo, split into public (homelab) and private (homelab-env) repos, purge sensitive data from public history.

**Architecture:** Initialize `environments/prod/` as its own git repo. Move all 18 ArgoCD app manifests there. Push to Forgejo as origin, GitHub as mirror. Cutover ArgoCD to source from Forgejo. Purge public repo history of IPs/secrets. Register Forgejo Actions runner.

**Tech Stack:** Forgejo, ArgoCD, Git, git-filter-repo, Forgejo Actions

**Spec:** `docs/superpowers/specs/2026-03-14-forgejo-migration-design.md`

---

## File Changes Overview

| Action | Source | Destination |
|--------|--------|-------------|
| Move | `core/manifests/argocd/apps/*.yaml` (18 files) | `environments/prod/apps/` |
| Move | `core/manifests/argocd/root-app.yaml` | Deleted (root.yaml already in `environments/prod/apps/`) |
| Move | `environments/.sops.yaml` | `environments/prod/.sops.yaml` |
| Move | `environments/network/` | `environments/prod/network/` |
| Move | `environments/bootstrap/` | `environments/prod/bootstrap/` |
| Create | `environments/prod/.gitignore` | Exclude .terraform/, kubeconfig, talosconfig |
| Modify | `environments/prod/apps/root.yaml` | Point to Forgejo repo |
| Delete | `core/manifests/argocd/apps/` | After cutover verified |
| Delete | `core/manifests/argocd/root-app.yaml` | After cutover verified |
| Delete | `environments/dev/` | No dev environment |

---

## Chunk 1: Initialize Private Repo

### Task 1: Set up git repo at environments/prod/

- [ ] **Step 1: Create .gitignore for the private repo**

```bash
cat > /Users/aaronvaldez/repos/homelab/environments/prod/.gitignore << 'EOF'
# Terraform
.terraform/
*.tfstate
*.tfstate.backup
*.tfplan

# Kubeconfig and Talosconfig (sensitive, copied manually)
kubeconfig
talosconfig

# OS
.DS_Store
EOF
```

- [ ] **Step 2: Move .sops.yaml into prod/**

The SOPS config currently lives at `environments/.sops.yaml`. Move it into the repo root and update the path_regex patterns (remove `prod/` prefix since we're now at the root):

```bash
cp /Users/aaronvaldez/repos/homelab/environments/.sops.yaml /Users/aaronvaldez/repos/homelab/environments/prod/.sops.yaml
```

Edit `environments/prod/.sops.yaml` — update path_regex patterns:
```yaml
creation_rules:
  - path_regex: secrets/.*\.yaml$
    age: "age19ddrrdwawdwntvjuufh06gav90svgzugaaflv08esqsnq2ntkcdsyv2fmd"
  - path_regex: .*/secrets\.tfvars$
    age: "age19ddrrdwawdwntvjuufh06gav90svgzugaaflv08esqsnq2ntkcdsyv2fmd"
  - path_regex: .*secrets.*\.yaml$
    age: "age19ddrrdwawdwntvjuufh06gav90svgzugaaflv08esqsnq2ntkcdsyv2fmd"
```

- [ ] **Step 3: Move network/ and bootstrap/ into prod/**

```bash
cp -r /Users/aaronvaldez/repos/homelab/environments/network /Users/aaronvaldez/repos/homelab/environments/prod/network
cp -r /Users/aaronvaldez/repos/homelab/environments/bootstrap /Users/aaronvaldez/repos/homelab/environments/prod/bootstrap
```

- [ ] **Step 4: Initialize git repo**

```bash
cd /Users/aaronvaldez/repos/homelab/environments/prod
git init
git add .sops.yaml .gitignore
git add backend.hcl
git add secrets/
git add terraform/ --ignore-errors  # excludes .terraform via .gitignore
git add zitadel/
git add network/
git add bootstrap/
git add apps/
git commit -m "Initial commit: homelab-env private repo

Environment-specific configuration for the homelab infrastructure.
Contains ArgoCD app manifests, SOPS-encrypted secrets, Terraform
configs, kubeconfig references, and backend configs."
```

---

### Task 2: Move ArgoCD app manifests from public to private repo

- [ ] **Step 1: Copy all 18 app manifests**

```bash
cp /Users/aaronvaldez/repos/homelab/core/manifests/argocd/apps/*.yaml /Users/aaronvaldez/repos/homelab/environments/prod/apps/
```

This copies all 18 files. The 5 existing files in `environments/prod/apps/` (cilium.yaml, cilium-namespace.yaml, longhorn.yaml, longhorn-namespace.yaml, root.yaml) will be overwritten by the ones from `core/` — but we need to check if the existing prod versions have env-specific overrides that differ from the core versions.

- [ ] **Step 2: Resolve conflicts between existing prod apps and core apps**

The existing `environments/prod/apps/cilium.yaml` and `longhorn.yaml` use the multi-source pattern. The `core/` versions use single-source. Keep the existing prod versions (they're already production-tested):

```bash
# Don't overwrite these — the prod versions are the correct ones
# cilium.yaml, cilium-namespace.yaml, longhorn.yaml, longhorn-namespace.yaml, root.yaml
# Only copy files that DON'T already exist in prod/apps/

cd /Users/aaronvaldez/repos/homelab
for f in core/manifests/argocd/apps/*.yaml; do
  basename=$(basename "$f")
  if [ ! -f "environments/prod/apps/$basename" ]; then
    cp "$f" "environments/prod/apps/$basename"
    echo "Copied: $basename"
  else
    echo "Skipped (already exists): $basename"
  fi
done
```

- [ ] **Step 3: Commit the moved manifests**

```bash
cd /Users/aaronvaldez/repos/homelab/environments/prod
git add apps/
git commit -m "feat: move all ArgoCD app manifests from public repo

18 app manifests moved from core/manifests/argocd/apps/.
Existing prod-specific manifests (cilium, longhorn) preserved."
```

---

### Task 3: Create Forgejo user and repos

**Context:** Forgejo is running at `http://REDACTED_LB_IP:3000` with Zitadel OIDC. You need to create the repos there.

- [ ] **Step 1: Log in to Forgejo via Zitadel**

Open `http://REDACTED_LB_IP:3000` and sign in with Zitadel (`aaron@reynoza.org`).

- [ ] **Step 2: Create the private repo on Forgejo**

In Forgejo UI: **+** → **New Repository**
- Name: `homelab-env`
- Visibility: **Private**
- Do NOT initialize with README
- Create

- [ ] **Step 3: Create the public repo on Forgejo**

In Forgejo UI: **+** → **New Repository**
- Name: `homelab`
- Visibility: **Public**
- Do NOT initialize with README
- Create

- [ ] **Step 4: Generate a Forgejo access token for ArgoCD**

In Forgejo UI: **Settings** → **Applications** → **Manage Access Tokens**
- Token Name: `argocd-repo-access`
- Permissions: `repo` (read)
- Generate and save the token value

- [ ] **Step 5: Push private repo to Forgejo**

```bash
cd /Users/aaronvaldez/repos/homelab/environments/prod
git remote add origin http://REDACTED_LB_IP:3000/<your-username>/homelab-env.git
git push -u origin main
```

Replace `<your-username>` with your Forgejo username (from Zitadel — likely `aaron@reynoza.org` or the username part).

- [ ] **Step 6: Push public repo to Forgejo**

```bash
cd /Users/aaronvaldez/repos/homelab
git remote add forgejo http://REDACTED_LB_IP:3000/<your-username>/homelab.git
git push forgejo main
```

---

### Task 4: Create GitHub private repo for homelab-env

- [ ] **Step 1: Create private repo on GitHub**

```bash
gh repo create aaronreynoza/homelab-env --private --source=/Users/aaronvaldez/repos/homelab/environments/prod --push
```

Or via GitHub UI: create `homelab-env` as a private repo, then:

```bash
cd /Users/aaronvaldez/repos/homelab/environments/prod
git remote add github git@github.com:aaronreynoza/homelab-env.git
git push github main
```

---

## Chunk 2: ArgoCD Cutover

### Task 5: Register Forgejo repo in ArgoCD

- [ ] **Step 1: Create ArgoCD repo credentials secret**

```bash
kubectl apply -f - << 'EOF'
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
  url: http://REDACTED_LB_IP:3000
  username: argocd-bot
  password: <FORGEJO_ACCESS_TOKEN_FROM_TASK_3>
EOF
```

Replace `<FORGEJO_ACCESS_TOKEN_FROM_TASK_3>` with the token generated in Task 3, Step 4.

- [ ] **Step 2: Verify ArgoCD can reach Forgejo repo**

```bash
argocd repo add http://REDACTED_LB_IP:3000/<your-username>/homelab-env.git \
  --username argocd-bot \
  --password <FORGEJO_ACCESS_TOKEN> \
  --insecure-skip-server-verification
```

Or verify via ArgoCD UI: Settings → Repositories — should show the Forgejo repo as connected.

---

### Task 6: Update root.yaml and cutover

- [ ] **Step 1: Update root.yaml to point to Forgejo**

Edit `environments/prod/apps/root.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: http://REDACTED_LB_IP:3000/<your-username>/homelab-env.git
    targetRevision: main
    path: apps
    directory:
      recurse: false
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: false
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

- [ ] **Step 2: Commit and push to Forgejo**

```bash
cd /Users/aaronvaldez/repos/homelab/environments/prod
git add apps/root.yaml
git commit -m "feat: point root app to Forgejo private repo"
git push origin main
```

- [ ] **Step 3: Apply the new root app**

```bash
kubectl apply -f /Users/aaronvaldez/repos/homelab/environments/prod/apps/root.yaml
```

This replaces the existing root app. ArgoCD will now scan `apps/` in the Forgejo repo.

- [ ] **Step 4: Verify all apps sync from Forgejo**

```bash
kubectl get app -n argocd -o custom-columns='NAME:.metadata.name,STATUS:.status.sync.status,HEALTH:.status.health.status,REPO:.spec.source.repoURL'
```

Expected: All apps show `Synced` with the Forgejo repoURL. If any apps are missing or degraded, check the Forgejo repo has all manifests.

- [ ] **Step 5: Wait and verify stability (5 minutes)**

Watch for any sync issues:

```bash
watch -n 10 'kubectl get app -n argocd --no-headers -o custom-columns="NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status"'
```

All apps should remain Synced/Healthy. If anything breaks, rollback by re-applying the old root app:

```bash
kubectl apply -f /Users/aaronvaldez/repos/homelab/core/manifests/argocd/root-app.yaml
```

---

## Chunk 3: Clean Public Repo

### Task 7: Remove ArgoCD manifests from public repo

- [ ] **Step 1: Delete app manifests and root app from public repo**

```bash
cd /Users/aaronvaldez/repos/homelab
rm -rf core/manifests/argocd/apps/
rm core/manifests/argocd/root-app.yaml
```

- [ ] **Step 2: Keep core/manifests/argocd/ directory for shared resources**

Check if anything else lives in `core/manifests/argocd/` that should stay:

```bash
ls core/manifests/argocd/
```

If empty, leave it or add a README explaining manifests moved to private repo.

- [ ] **Step 3: Also check for other shared manifests**

```bash
ls core/manifests/
```

Keep `core/manifests/cilium/` (lb-ipam.yaml, l2-announcement.yaml) — these are shared K8s resources, not ArgoCD apps.

- [ ] **Step 4: Commit and push**

```bash
git add -A core/manifests/argocd/
git commit -m "refactor: remove ArgoCD app manifests (moved to private repo)

All 18 app manifests and root-app.yaml moved to homelab-env.
ArgoCD now sources from Forgejo private repo.
core/manifests/ retains shared K8s resources (Cilium LB-IPAM)."

git push origin main
git push forgejo main
```

---

### Task 8: Set up GitHub push mirrors on Forgejo

- [ ] **Step 1: Create GitHub personal access token**

Go to GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens:
- Name: `forgejo-mirror`
- Repository access: `homelab` and `homelab-env`
- Permissions: Contents (read/write)
- Generate and save the token

- [ ] **Step 2: Configure push mirror for homelab (public)**

In Forgejo UI: `homelab` repo → Settings → Mirror Settings → Push Mirror:
- Remote URL: `https://github.com/aaronreynoza/homelab.git`
- Authorization: Username `aaronreynoza`, Password: GitHub token
- Interval: `8h` (or whatever frequency)
- Save

- [ ] **Step 3: Configure push mirror for homelab-env (private)**

In Forgejo UI: `homelab-env` repo → Settings → Mirror Settings → Push Mirror:
- Remote URL: `https://github.com/aaronreynoza/homelab-env.git`
- Authorization: Username `aaronreynoza`, Password: GitHub token
- Interval: `8h`
- Save

- [ ] **Step 4: Trigger initial mirror sync**

Click "Synchronize Now" on both mirrors. Verify GitHub repos are updated.

---

## Chunk 4: History Purge

### Task 9: Purge sensitive data from public repo history

- [ ] **Step 1: Install git-filter-repo if needed**

```bash
brew install git-filter-repo
```

- [ ] **Step 2: Create a fresh clone for the purge**

```bash
cd /tmp
git clone https://github.com/aaronreynoza/homelab.git homelab-purge
cd homelab-purge
```

- [ ] **Step 3: Create expressions file for replacements**

```bash
cat > /tmp/expressions.txt << 'EOF'
REDACTED_LB_IP==>REDACTED_LB_IP
REDACTED_LB_IP==>REDACTED_LB_IP
REDACTED_LB_IP==>REDACTED_LB_IP
REDACTED_LB_IP==>REDACTED_LB_IP
REDACTED_LB_IP==>REDACTED_LB_IP
REDACTED_LB_IP==>REDACTED_LB_IP
REDACTED_LB_IP==>REDACTED_LB_IP
REDACTED_K8S_API==>REDACTED_K8S_API
REDACTED_VLAN_IP==>REDACTED_VLAN_IP
REDACTED_PVE_IP==>REDACTED_PVE_IP
REDACTED_MGMT_IP==>REDACTED_MGMT_IP
REDACTED_PVE2_IP==>REDACTED_PVE2_IP
REDACTED_OPNSENSE_IP==>REDACTED_OPNSENSE_IP
REDACTED_VPS_IP==>REDACTED_VPS_IP
REDACTED_AWS_ACCOUNT==>REDACTED_AWS_ACCOUNT
REDACTED_CLIENT_ID==>REDACTED_CLIENT_ID
REDACTED_ORG_ID==>REDACTED_ORG_ID
EOF
```

- [ ] **Step 4: Run git-filter-repo**

```bash
cd /tmp/homelab-purge
git filter-repo --replace-text /tmp/expressions.txt
```

- [ ] **Step 5: Verify the purge worked**

```bash
git log --all -p | grep -c "10.10.10"
# Expected: 0

git log --all -p | grep -c "192.168.1"
# Expected: 0
```

- [ ] **Step 6: Force push to GitHub and Forgejo**

```bash
git remote add origin https://github.com/aaronreynoza/homelab.git
git push origin main --force

git remote add forgejo http://REDACTED_LB_IP:3000/<your-username>/homelab.git
git push forgejo main --force
```

- [ ] **Step 7: Re-clone on your Mac**

```bash
cd /Users/aaronvaldez/repos
mv homelab homelab-old
git clone https://github.com/aaronreynoza/homelab.git
# Verify environments/prod/ is still gitignored and intact
cp -r homelab-old/environments homelab/environments
rm -rf homelab-old
```

- [ ] **Step 8: Re-clone on mgmt VM**

```bash
ssh admin@REDACTED_MGMT_IP "rm -rf ~/homelab && git clone http://REDACTED_LB_IP:3000/<your-username>/homelab.git ~/homelab"
```

---

## Chunk 5: Forgejo Actions Runner

### Task 10: Register runner on mgmt VM

- [ ] **Step 1: Get runner registration token from Forgejo**

In Forgejo UI: Site Administration → Actions → Runners → Create new runner.
Copy the registration token.

Or if using user-level runner: Settings → Actions → Runners.

- [ ] **Step 2: Register the runner**

```bash
ssh admin@REDACTED_MGMT_IP
forgejo-runner register \
  --instance http://REDACTED_LB_IP:3000 \
  --token <REGISTRATION_TOKEN> \
  --labels self-hosted,linux,x64,infra \
  --name mgmt-infra-runner
```

- [ ] **Step 3: Start the runner service**

```bash
sudo systemctl enable --now forgejo-runner
sudo systemctl status forgejo-runner
```

Expected: Active (running).

- [ ] **Step 4: Verify runner appears in Forgejo**

In Forgejo UI: Site Administration → Actions → Runners. Should show `mgmt-infra-runner` as online.

---

### Task 11: Create CI workflows

- [ ] **Step 1: Create validation workflow for public repo**

Create `core/.forgejo/workflows/validate.yml` in the homelab repo:

```yaml
name: Validate
on: [push, pull_request]
jobs:
  terraform:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - name: Validate Terraform modules
        run: |
          for dir in core/terraform/live/*/; do
            echo "=== Validating $dir ==="
            terraform -chdir="$dir" init -backend=false 2>/dev/null
            terraform -chdir="$dir" validate
          done
```

- [ ] **Step 2: Create plan workflow for private repo**

Create `.forgejo/workflows/plan.yml` in the homelab-env repo (environments/prod/):

```yaml
name: Terraform Plan
on:
  push:
    paths: ['terraform/**', 'zitadel/**', 'network/**']
  workflow_dispatch:
jobs:
  plan:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - name: Terraform Plan (cluster)
        run: |
          cd terraform
          terraform init -backend-config=../backend.hcl
          terraform plan -var-file=terraform.tfvars -no-color
```

- [ ] **Step 3: Commit and push workflows**

```bash
# Public repo
cd /Users/aaronvaldez/repos/homelab
mkdir -p .forgejo/workflows
# (create validate.yml as above)
git add .forgejo/
git commit -m "feat: add Forgejo Actions validation workflow"
git push forgejo main

# Private repo
cd /Users/aaronvaldez/repos/homelab/environments/prod
mkdir -p .forgejo/workflows
# (create plan.yml as above)
git add .forgejo/
git commit -m "feat: add Forgejo Actions terraform plan workflow"
git push origin main
```

---

## Summary

After completing all chunks:

| Component | Before | After |
|-----------|--------|-------|
| Git origin | GitHub | Forgejo |
| ArgoCD source | GitHub `core/manifests/argocd/apps/` | Forgejo `homelab-env` repo `apps/` |
| App manifests | Public repo (hardcoded IPs) | Private repo (IPs are fine) |
| Public repo history | Contains IPs, client IDs | Purged with git-filter-repo |
| GitHub role | Origin | Push mirror (read-only) |
| CI/CD | None | Forgejo Actions (validate + plan) |
| Runner | Installed but unregistered | Registered and running |

**Rollback:** If Forgejo is unavailable, re-add GitHub as ArgoCD source and apply the old root app. The GitHub mirror always has an up-to-date copy.

**Next:** Step 4 — Forgejo Actions CI/CD (build pipelines, container image builds, MkDocs deployment).
