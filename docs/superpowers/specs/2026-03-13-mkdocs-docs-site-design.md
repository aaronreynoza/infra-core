# MkDocs Documentation Site Design

**Goal:** Self-hosted documentation site at `docs.home-infra.net` — first publicly exposed app via Pangolin, doubles as portfolio showcase.

**Architecture:** Multi-stage Docker build (MkDocs Material generates static HTML, Caddy serves it). Image pushed to Harbor, deployed via ArgoCD as plain K8s manifests, exposed publicly through Pangolin with TLS.

**Tech Stack:** MkDocs Material, Caddy 2, Harbor registry, ArgoCD, Pangolin

---

## Architecture

```
docs/ (existing ~30 markdown files in homelab repo)
  → mkdocs build (multi-stage Docker build)
  → Caddy serves static HTML (~25MB image)
  → Harbor registry (harbor.internal/platform/docs:v1.0.0)
  → ArgoCD deploys K8s Deployment + Service
  → Cilium LB-IPAM assigns internal IP
  → Pangolin exposes at docs.home-infra.net (TLS via Let's Encrypt)
```

## Components

| Component | Detail |
|-----------|--------|
| Generator | MkDocs Material (dark/light toggle, search, code copy) |
| Web server | Caddy 2 Alpine (HTTP only internally — Pangolin handles TLS) |
| Image | Multi-stage: `python:3.12-slim` builds, `caddy:2-alpine` serves |
| Registry | Harbor at REDACTED_LB_IP |
| Deploy | ArgoCD Application, plain K8s manifests (Deployment + Service + ConfigMap) |
| Public access | Pangolin resource: `docs.home-infra.net`, no auth (public docs) |
| Namespace | `docs` |

## Files to Create

| File | Purpose |
|------|---------|
| `mkdocs.yml` | Site config: nav structure, Material theme, markdown extensions |
| `docs/index.md` | Homepage with project overview |
| `Dockerfile.docs` | Multi-stage: mkdocs build + caddy serve |
| `Caddyfile` | Static file server with gzip, security headers |
| `core/manifests/docs-site/deployment.yaml` | K8s Deployment (1 replica, resource limits) |
| `core/manifests/docs-site/service.yaml` | K8s Service (LoadBalancer via Cilium) |
| `core/manifests/docs-site/caddyfile-configmap.yaml` | ConfigMap for Caddyfile |
| `core/manifests/argocd/apps/docs-site.yaml` | ArgoCD Application (watches manifests dir) |

## MkDocs Configuration

- **Theme:** Material with slate (dark) + default (light) toggle
- **Features:** navigation.tabs, navigation.sections, search.suggest, search.highlight, content.code.copy
- **Extensions:** admonition, pymdownx.details, pymdownx.superfences, pymdownx.tabbed, pymdownx.highlight, tables, toc with permalinks
- **Nav structure:** Home, Architecture, Cloud Comparison, Configuration, Roadmap, Decisions (ADRs), Runbooks, Changelog

## Caddyfile

```
:80 {
    root * /srv
    file_server
    encode gzip
    try_files {path} {path}/ /index.html
    header {
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        Referrer-Policy strict-origin-when-cross-origin
    }
}
```

TLS is handled by Pangolin, not Caddy. Caddy serves HTTP only on the internal network.

## Dockerfile

```dockerfile
# Build stage
FROM python:3.12-slim AS builder
RUN pip install mkdocs-material
WORKDIR /docs
COPY mkdocs.yml .
COPY docs/ docs/
RUN mkdocs build

# Serve stage
FROM caddy:2-alpine
COPY --from=builder /docs/site /srv
COPY Caddyfile /etc/caddy/Caddyfile
```

## K8s Deployment

- Namespace: `docs`
- Replicas: 1
- Image: `harbor.internal/platform/docs:v1.0.0` (tagged per build)
- Resources: requests 50m/64Mi, limits 200m/128Mi
- Service: LoadBalancer (Cilium LB-IPAM assigns IP from REDACTED_LB_IP-250 pool)
- Liveness/readiness probe: HTTP GET / on port 80

## ArgoCD Application

- Source: Git repo, path `core/manifests/docs-site/`
- Destination: `docs` namespace
- Sync wave: 10
- Auto-sync with prune and selfHeal
- CreateNamespace=true

## Content Strategy

**Included (public):**
- Architecture overview, cloud comparison
- ADRs (decisions/)
- Configuration guides
- Runbooks (already sanitized)
- Changelog
- New index.md homepage

**Excluded (not in nav):**
- `internal-docs/` — gitignored, private planning
- `environments/` — gitignored, credentials
- `superpowers/` — implementation plans/specs, not user-facing docs
- `issues/` — internal backlog tracking

## Manual Steps (after code is deployed)

1. Build image: `docker build -f Dockerfile.docs -t harbor.internal/platform/docs:v1.0.0 .`
2. Push to Harbor: `docker push harbor.internal/platform/docs:v1.0.0`
3. Create Pangolin resource in dashboard: `docs.home-infra.net` → docs-site K8s service
4. Verify DNS: CNAME `docs.home-infra.net` → Pangolin VPS (may need to configure in domain registrar if not wildcarded)

## Future Enhancements (not in scope)

- Forgejo Actions pipeline: auto-build on docs/ changes
- Versioned docs (mike plugin)
- Custom domain SSL certificate pinning
