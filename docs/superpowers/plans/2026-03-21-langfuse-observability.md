# Langfuse v3 LLM Observability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy Langfuse v3 as the unified LLM observability platform with Zitadel SSO, CNPG PostgreSQL, and LiteLLM integration.

**Architecture:** Official Langfuse Helm chart (v1.5.22) deployed via ArgoCD multi-source pattern. External CNPG PostgreSQL, bundled ClickHouse/Valkey/MinIO. Exposed at `langfuse.aaron.reynoza.org` via Cilium Gateway + Pangolin.

**Tech Stack:** Langfuse v3 (3.155.1), CNPG PostgreSQL, ClickHouse, Valkey, MinIO (Bitnami subcharts), ArgoCD, Cilium Gateway API, Zitadel OIDC, SOPS, Pangolin

**Spec:** `docs/superpowers/specs/2026-03-21-langfuse-llm-observability-design.md`
**Ticket:** HOMELAB-159
**Branch:** `plane/HOMELAB-159-langfuse-observability` (from `live`)

---

## File Structure

### infra-core (public — base values)

| File | Purpose |
|------|---------|
| `core/charts/apps/langfuse/values.yaml` | Base Helm values for Langfuse (non-secret defaults) |

### prod (private — ArgoCD apps + secrets)

| File | Purpose |
|------|---------|
| `apps/cnpg-cluster-langfuse.yaml` | ArgoCD Application for CNPG PostgreSQL cluster |
| `apps/langfuse.yaml` | ArgoCD Application for Langfuse |
| `values/cnpg-cluster-langfuse/values.yaml` | CNPG prod overrides (DB name, B2 backup path) |
| `values/langfuse/values.yaml` | SOPS-encrypted Langfuse overrides (OIDC, secrets, URLs) |
| `pangolin/resources.yaml` | Add Langfuse entry for public HTTPS exposure |

### Zitadel (manual step)

| Action | Purpose |
|--------|---------|
| Create OIDC application in Zitadel | SSO for Langfuse login |

---

## Task 1: CNPG PostgreSQL Cluster

**Files:**
- Create: `prod/apps/cnpg-cluster-langfuse.yaml`
- Create: `prod/values/cnpg-cluster-langfuse/values.yaml`

Reference files:
- `prod/apps/cnpg-cluster-outline.yaml` (ArgoCD app template)
- `prod/values/cnpg-cluster-outline/values.yaml` (values template)
- `infra-core/core/charts/platform/cnpg-cluster/values.yaml` (shared base)

- [ ] **Step 1: Create CNPG prod values**

Create `prod/values/cnpg-cluster-langfuse/values.yaml`:
```yaml
cluster:
  enableSuperuserAccess: false
  initdb:
    database: langfuse
    owner: langfuse
backups:
  endpointURL: "https://s3.us-east-005.backblazeb2.com"
  s3:
    region: us-east-005
    bucket: reynoza-cnpg
    path: "/langfuse/"
  secret:
    name: cnpg-b2-credentials
```

- [ ] **Step 2: Create ArgoCD Application manifest**

Create `prod/apps/cnpg-cluster-langfuse.yaml`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cnpg-cluster-langfuse
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "8"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  sources:
    - repoURL: https://cloudnative-pg.github.io/charts
      chart: cluster
      targetRevision: "0.6.0"
      helm:
        releaseName: cnpg-cluster-langfuse
        valueFiles:
          - "$values/core/charts/platform/cnpg-cluster/values.yaml"
          - "$overrides/values/cnpg-cluster-langfuse/values.yaml"
    - repoURL: http://10.10.10.222:3000/aaron/infra-core.git
      targetRevision: live
      ref: values
    - repoURL: http://10.10.10.222:3000/aaron/prod.git
      targetRevision: live
      ref: overrides
  destination:
    server: https://kubernetes.default.svc
    namespace: langfuse
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    retry:
      limit: 5
      backoff:
        duration: 30s
        factor: 2
        maxDuration: 5m
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - SkipDryRunOnMissingResource=true
```

- [ ] **Step 3: Ensure B2 credentials secret exists in langfuse namespace**

Check if `cnpg-b2-credentials` is synced to the `langfuse` namespace via Reflector (it should be — same pattern as other CNPG clusters). Verify:
```bash
kubectl get secret cnpg-b2-credentials -n outline -o yaml | head -5
# Check for reflector annotations
```

If Reflector is already configured to sync this secret cluster-wide, no action needed. Otherwise, add the Reflector annotation to the source secret.

- [ ] **Step 4: Commit CNPG cluster files**

```bash
cd /home/claude-agent/workspace/homelab/prod
git checkout -b plane/HOMELAB-159-langfuse-observability live
git add apps/cnpg-cluster-langfuse.yaml values/cnpg-cluster-langfuse/values.yaml
git commit -m "feat: add CNPG PostgreSQL cluster for Langfuse (HOMELAB-159)"
```

- [ ] **Step 5: Push and open PR for CNPG cluster**

```bash
git push -u origin plane/HOMELAB-159-langfuse-observability
```

The CNPG PR (prod) can merge first — ArgoCD sync-wave 8 ensures the DB is ready before Langfuse (sync-wave 10). The infra-core PR (base values only) has no deployment side effects and can merge independently.

- [ ] **Step 6: Verify CNPG cluster health (after merge)**

```bash
kubectl get cluster -n langfuse
# Expected: cnpg-cluster-langfuse with STATUS: Cluster in healthy state
kubectl get secret cnpg-cluster-langfuse-app -n langfuse
# Expected: secret exists with uri key
```

---

## Task 2: Langfuse Base Values (infra-core)

**Files:**
- Create: `infra-core/core/charts/apps/langfuse/values.yaml`

- [ ] **Step 1: Create base values file**

Create `infra-core/core/charts/apps/langfuse/values.yaml`:
```yaml
# Langfuse v3 — Base Values (reusable, non-secret)
# Environment-specific overrides (secrets, OIDC, URLs) go in prod/values/langfuse/
# Chart: langfuse/langfuse v1.5.22 from https://langfuse.github.io/langfuse-k8s

# -- Disable bundled PostgreSQL (using external CNPG)
postgresql:
  deploy: false

# -- Bundled ClickHouse (OLAP store for traces)
# Bitnami ClickHouse subchart — Langfuse v3 requires >= 24.3
clickhouse:
  deploy: true
  clusterEnabled: false
  shards: 1
  replicaCount: 1
  resourcesPreset: "small"
  # Bitnami subchart persistence (passes through to subchart)
  persistence:
    size: 10Gi
    storageClass: longhorn

# -- Bundled Valkey/Redis (cache + queue)
# Bitnami Valkey subchart (aliased as redis)
redis:
  deploy: true
  architecture: standalone
  primary:
    extraFlags:
      - "--maxmemory-policy noeviction"
    persistence:
      enabled: false

# -- Bundled MinIO (S3 blob storage for events/media)
# Bitnami MinIO subchart (aliased as s3)
s3:
  deploy: true
  defaultBuckets: "langfuse"
  persistence:
    size: 5Gi
    storageClass: longhorn

# -- Langfuse core config
langfuse:
  logging:
    level: info
    format: json

  features:
    signUpDisabled: true

  ingress:
    enabled: false

  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

  web:
    service:
      type: ClusterIP
      port: 3000

# -- HTTPRoute for Cilium Gateway (set in prod overlay via extraManifests)
```

- [ ] **Step 2: Validate values against chart schema**

```bash
helm repo add langfuse https://langfuse.github.io/langfuse-k8s
helm repo update
helm template langfuse langfuse/langfuse \
  --version 1.5.22 \
  -f core/charts/apps/langfuse/values.yaml \
  --debug 2>&1 | head -50
```

Verify: no unknown key warnings, templates render correctly. Check the generated Service name for the web component (needed for HTTPRoute backendRef in Task 4).

- [ ] **Step 3: Commit to feature branch**

```bash
cd /home/claude-agent/workspace/homelab/infra-core
git add core/charts/apps/langfuse/values.yaml
git commit -m "feat: add Langfuse base Helm values (HOMELAB-159)"
```

---

## Task 3: Zitadel OIDC Application

This is a manual/API step — create an OIDC application in Zitadel for Langfuse SSO.

- [ ] **Step 1: Create OIDC application in Zitadel**

Navigate to `https://zitadel.aaron.reynoza.org` → Projects → Create Application:
- Name: `Langfuse`
- Type: Web
- Auth method: `CODE` (authorization code flow)
- Redirect URIs: `https://langfuse.aaron.reynoza.org/api/auth/callback/custom`
- Post-logout redirect: `https://langfuse.aaron.reynoza.org`

Or use Zitadel Terraform provider if available.

- [ ] **Step 2: Record client ID and client secret**

Save these for use in the SOPS-encrypted prod values (Task 4). Do not commit in plaintext.

---

## Task 4: Langfuse ArgoCD Application + Prod Values

**Files:**
- Create: `prod/apps/langfuse.yaml`
- Create: `prod/values/langfuse/values.yaml` (SOPS-encrypted)

- [ ] **Step 1: Generate Langfuse secrets**

```bash
# Generate required secrets
SALT=$(openssl rand -hex 32)
ENCRYPTION_KEY=$(openssl rand -hex 32)
NEXTAUTH_SECRET=$(openssl rand -hex 32)
echo "SALT: $SALT"
echo "ENCRYPTION_KEY: $ENCRYPTION_KEY"
echo "NEXTAUTH_SECRET: $NEXTAUTH_SECRET"
```

Save these for the prod values file.

- [ ] **Step 2: Create prod values file**

Create `prod/values/langfuse/values.yaml`:
```yaml
# External PostgreSQL (CNPG cluster)
postgresql:
  deploy: false
  host: cnpg-cluster-langfuse-rw.langfuse.svc.cluster.local
  auth:
    username: langfuse
    database: langfuse
    existingSecret: cnpg-cluster-langfuse-app
    secretKeys:
      userPasswordKey: password

langfuse:
  nextauth:
    url: "https://langfuse.aaron.reynoza.org"
    secret:
      value: "<NEXTAUTH_SECRET>"

  salt:
    value: "<SALT>"

  encryptionKey:
    value: "<ENCRYPTION_KEY>"

  # Zitadel OIDC SSO + disable password auth
  auth:
    disableUsernamePassword: true
    providers:
      custom:
        clientId: "<ZITADEL_CLIENT_ID>"
        clientSecret: "<ZITADEL_CLIENT_SECRET>"
        issuer: "https://zitadel.aaron.reynoza.org"
        name: "Zitadel"
        scope: "openid email profile"

# -- HTTPRoute via extraManifests
# NOTE: verify actual service name with `helm template` before deploying.
# With releaseName: langfuse, service is likely named `langfuse-web`.
extraManifests:
  - apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: langfuse
    spec:
      parentRefs:
        - name: homelab-gateway
          namespace: cilium-system
      hostnames:
        - langfuse.aaron.reynoza.org
      rules:
        - backendRefs:
            - name: langfuse-web
              port: 3000
```

Replace `<PLACEHOLDERS>` with actual values, then SOPS-encrypt:
```bash
sops -e -i prod/values/langfuse/values.yaml
```

- [ ] **Step 3: Create ArgoCD Application manifest**

Create `prod/apps/langfuse.yaml`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: langfuse
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "10"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  sources:
    - repoURL: https://langfuse.github.io/langfuse-k8s
      chart: langfuse
      targetRevision: "1.5.22"
      helm:
        releaseName: langfuse
        valueFiles:
          - "$values/core/charts/apps/langfuse/values.yaml"
          - "$overrides/values/langfuse/values.yaml"
    - repoURL: http://10.10.10.222:3000/aaron/infra-core.git
      targetRevision: live
      ref: values
    - repoURL: http://10.10.10.222:3000/aaron/prod.git
      targetRevision: live
      ref: overrides
  destination:
    server: https://kubernetes.default.svc
    namespace: langfuse
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    retry:
      limit: 5
      backoff:
        duration: 30s
        factor: 2
        maxDuration: 5m
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

- [ ] **Step 4: Commit prod files**

```bash
cd /home/claude-agent/workspace/homelab/prod
git add apps/langfuse.yaml values/langfuse/values.yaml
git commit -m "feat: add Langfuse ArgoCD app with OIDC + encrypted secrets (HOMELAB-159)"
```

---

## Task 5: Pangolin Resource for External Access

**Files:**
- Modify: `prod/pangolin/resources.yaml`

- [ ] **Step 1: Add Langfuse entry to resources.yaml**

Add to `prod/pangolin/resources.yaml`:
```yaml
  - name: LangFuse
    subdomain: langfuse.aaron
    target_ip: 10.10.10.228
    target_port: 80
```

- [ ] **Step 2: Dry-run Pangolin sync**

```bash
cd /home/claude-agent/workspace/homelab/infra-core
python3 scripts/pangolin/pangolin-resources.py \
  --config ../../prod/pangolin/config.yaml \
  --resources ../../prod/pangolin/resources.yaml \
  sync --dry-run
```

Expected: Shows `CREATE langfuse.aaron.reynoza.org`

- [ ] **Step 3: Apply Pangolin sync**

```bash
python3 scripts/pangolin/pangolin-resources.py \
  --config ../../prod/pangolin/config.yaml \
  --resources ../../prod/pangolin/resources.yaml \
  sync
```

- [ ] **Step 4: Commit Pangolin resource**

```bash
cd /home/claude-agent/workspace/homelab/prod
git add pangolin/resources.yaml
git commit -m "feat: add Pangolin resource for langfuse.aaron.reynoza.org (HOMELAB-159)"
```

---

## Task 6: Push, PR, and Deploy

- [ ] **Step 1: Push infra-core feature branch and open PR**

```bash
cd /home/claude-agent/workspace/homelab/infra-core
git push -u origin plane/HOMELAB-159-langfuse-observability
```

Open PR targeting `live`:
```bash
# Use Forgejo API or gh-compatible CLI
```

This is an additive change (new values file + spec + plan docs) — auto-merge after CI passes.

- [ ] **Step 2: Push prod feature branch and open PR**

```bash
cd /home/claude-agent/workspace/homelab/prod
git push -u origin plane/HOMELAB-159-langfuse-observability
```

Open PR targeting `live`. This is additive (new ArgoCD apps + values) — auto-merge after CI passes.

- [ ] **Step 3: Wait for ArgoCD sync**

After both PRs merge to `live`, ArgoCD will auto-sync:
1. CNPG cluster (sync-wave 8) creates first
2. Langfuse app (sync-wave 10) deploys after

Monitor:
```bash
argocd app list | grep langfuse
kubectl get pods -n langfuse -w
```

- [ ] **Step 4: Verify deployment**

```bash
# CNPG healthy
kubectl get cluster -n langfuse
# All pods running
kubectl get pods -n langfuse
# HTTPRoute created
kubectl get httproute -n langfuse
# Web UI accessible
curl -sI https://langfuse.aaron.reynoza.org | head -5
```

---

## Task 7: LiteLLM Integration (Phase 2)

**Files:**
- Modify: LiteLLM Helm values (prod/values/litellm/ or equivalent)

- [ ] **Step 1: Create Langfuse API keys**

Log in to `https://langfuse.aaron.reynoza.org` via Zitadel SSO.
Create a new project → Settings → API Keys → Create.
Note the public key (`pk-lf-...`) and secret key (`sk-lf-...`).

- [ ] **Step 2: Add Langfuse env vars to LiteLLM deployment**

Add to LiteLLM's values/config:
```yaml
# Additional env vars for Langfuse tracing
- name: LANGFUSE_PUBLIC_KEY
  value: "pk-lf-..."
- name: LANGFUSE_SECRET_KEY
  value: "sk-lf-..."
- name: LANGFUSE_HOST
  value: "http://langfuse-web.langfuse.svc.cluster.local:3000"
```

Also ensure LiteLLM's config includes the callback:
```yaml
litellm_settings:
  success_callback: ["langfuse"]
```

- [ ] **Step 3: Commit and deploy LiteLLM changes**

```bash
git add <litellm values files>
git commit -m "feat: integrate LiteLLM with Langfuse tracing (HOMELAB-159)"
git push
```

- [ ] **Step 4: Verify traces in Langfuse**

1. Make a test request through LiteLLM/Open WebUI
2. Check Langfuse UI → Traces → verify the request appears with model, tokens, latency
3. Verify both Ollama and any other model calls are traced

---

## Task 8: Verification and Ticket Closure

- [ ] **Step 1: End-to-end verification checklist**

```
[ ] CNPG cluster healthy with B2 backups configured
[ ] Langfuse web + worker pods running
[ ] ClickHouse, Valkey, MinIO pods running
[ ] HTTPRoute routing correctly
[ ] Zitadel SSO login works
[ ] Password auth disabled
[ ] Pangolin resource live (HTTPS external access)
[ ] LiteLLM traces appearing in Langfuse
[ ] Langfuse UI loads and is functional
```

- [ ] **Step 2: Post verification comment to HOMELAB-159**

Add a Plane comment with evidence of successful deployment.

- [ ] **Step 3: Move HOMELAB-159 to Done**
