# Langfuse LLM Observability Platform — Design Spec

**Date:** 2026-03-21
**Status:** Draft
**Ticket:** HOMELAB-159

## Overview

Deploy Langfuse v3 as the LLM observability platform for the homelab, providing unified tracing, prompt management, and evaluation across all AI workloads (LiteLLM/Ollama local models and Claude agent sessions).

## Goals

1. **Unified LLM observability** — single pane of glass for all LLM interactions
2. **LiteLLM native integration** — automatic tracing of Ollama/local model usage via LiteLLM proxy
3. **Claude agent tracing** — trace agent tool calls and workflows (with known constraints)
4. **Zitadel SSO** — consistent authentication with the rest of the stack
5. **Prometheus metrics** — export key metrics to existing Grafana dashboards (Phase 2)

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│ langfuse namespace                                       │
│                                                          │
│  ┌──────────────┐  ┌───────────────┐  ┌──────────────┐  │
│  │ langfuse-web  │  │langfuse-worker│  │  ClickHouse  │  │
│  │  (UI + API)   │  │ (async proc)  │  │  (OLAP)      │  │
│  └──────┬───────┘  └───────┬───────┘  └──────────────┘  │
│         │                  │                              │
│  ┌──────┴──────┐  ┌───────┴───────┐  ┌──────────────┐  │
│  │   Redis     │  │    MinIO      │  │ CNPG Postgres │  │
│  │  (cache/q)  │  │  (blob S3)    │  │  (external)   │  │
│  └─────────────┘  └───────────────┘  └──────────────┘  │
└─────────────────────────────────────────────────────────┘
         │
    HTTPRoute (langfuse.aaron.reynoza.org)
         │
    homelab-gateway (cilium-system)
         │
    Pangolin VPS → Internet

Integration:
  LiteLLM ──(LANGFUSE_* env vars)──→ langfuse-web (cluster-internal)
  Claude Agent ──(future: SDK/OTEL)──→ langfuse-web
```

## Deployment Strategy

### Pattern: Upstream Helm Chart via ArgoCD (like CNPG)

Use the official Langfuse Helm chart (`langfuse/langfuse` from `https://langfuse.github.io/langfuse-k8s`) referenced directly in an ArgoCD Application manifest. No custom chart in infra-core.

### Repo Split

**infra-core** (public):
- `core/charts/apps/langfuse/values.yaml` — base Helm values (non-secret defaults)
- This spec document

**prod** (private):
- `apps/langfuse.yaml` — ArgoCD Application manifest
- `apps/cnpg-cluster-langfuse.yaml` — ArgoCD Application for CNPG cluster
- `values/langfuse/values.yaml` — SOPS-encrypted secret overrides (OIDC creds, Langfuse secrets)
- `values/cnpg-cluster-langfuse/values.yaml` — DB name, B2 backup config

### ArgoCD Applications

**1. CNPG PostgreSQL Cluster** (sync-wave: 8)
- Chart: `cluster` from `https://cloudnative-pg.github.io/charts` (v0.6.0)
- Base values: infra-core `core/charts/platform/cnpg-cluster/values.yaml` (shared)
- Override values: prod `values/cnpg-cluster-langfuse/values.yaml`
- Namespace: `langfuse`
- Database: `langfuse`, owner: `langfuse`
- Backups: B2 (same pattern as Outline/Forgejo/Zitadel)

**2. Langfuse** (sync-wave: 10)
- Chart: `langfuse` from `https://langfuse.github.io/langfuse-k8s`
- Base values: infra-core `core/charts/apps/langfuse/values.yaml`
- Override values: prod `values/langfuse/values.yaml`
- Namespace: `langfuse`

### Component Configuration

**PostgreSQL (external via CNPG):**
```yaml
postgresql:
  deploy: false
  auth:
    username: langfuse
    database: langfuse
    host: cnpg-cluster-langfuse-rw.langfuse.svc.cluster.local
    # password/URI injected from CNPG secret in prod values
    # Note: CNPG generates secret `cnpg-cluster-langfuse-app` with `uri` key
    # Exact Helm values schema must be verified against official chart at deploy time
    # Prefer DATABASE_URL from CNPG secret if chart supports it (like Outline pattern)
```

**ClickHouse (bundled):**
- Image version >= 24.3 (required by Langfuse v3) — pin in base values
- Longhorn PVC for persistence, `storageClass: longhorn`
- Single-node (appropriate for homelab scale)

**Redis (bundled):**
- Default chart settings, no persistence needed (cache/queue)

**MinIO (bundled):**
- Longhorn PVC for persistence, `storageClass: longhorn`
- Internal only (no external exposure needed)

### Authentication — Zitadel SSO

Env vars on Langfuse pods:

| Variable | Value |
|---|---|
| `AUTH_CUSTOM_CLIENT_ID` | (from Zitadel — SOPS in prod) |
| `AUTH_CUSTOM_CLIENT_SECRET` | (from Zitadel — SOPS in prod) |
| `AUTH_CUSTOM_ISSUER` | `https://zitadel.aaron.reynoza.org` |
| `AUTH_CUSTOM_NAME` | `Zitadel` |
| `AUTH_DISABLE_USERNAME_PASSWORD` | `true` |
| `AUTH_CUSTOM_SCOPE` | `openid email profile` |
| `NEXTAUTH_URL` | `https://langfuse.aaron.reynoza.org` |
| `SALT` | (random 32+ char string — SOPS in prod) |
| `ENCRYPTION_KEY` | (random 256-bit hex — SOPS in prod) |
| `NEXTAUTH_SECRET` | (random secret — SOPS in prod) |

Requires creating an OIDC application in Zitadel for Langfuse with redirect URI `https://langfuse.aaron.reynoza.org/api/auth/callback/custom`.

### Networking

- **HTTPRoute:** `langfuse.aaron.reynoza.org` → `langfuse-web` service port 3000
- **Parent ref:** `homelab-gateway` in `cilium-system`
- **Internal access:** `langfuse-web.langfuse.svc.cluster.local:3000` for LiteLLM integration

### Resources (Homelab-Appropriate)

| Component | CPU Req | CPU Lim | Mem Req | Mem Lim | Storage |
|---|---|---|---|---|---|
| langfuse-web | 100m | 500m | 256Mi | 512Mi | — |
| langfuse-worker | 100m | 500m | 256Mi | 512Mi | — |
| ClickHouse | 100m | 1000m | 256Mi | 1Gi | 10Gi (Longhorn) |
| Redis | 50m | 200m | 64Mi | 128Mi | — |
| MinIO | 50m | 200m | 128Mi | 256Mi | 5Gi (Longhorn) |
| PostgreSQL (CNPG) | 100m | 500m | 256Mi | 512Mi | 5Gi (Longhorn-db) |

## Integration Plan

### Phase 1: Core Deployment
- CNPG cluster for Langfuse
- Langfuse v3 via official Helm chart
- Zitadel OIDC SSO (create OIDC app in Zitadel)
- HTTPRoute external access
- Create Pangolin resource for `langfuse.aaron.reynoza.org`
- Verify UI accessible and functional

### Phase 2: LiteLLM Integration
- Add `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`, `LANGFUSE_HOST` env vars to LiteLLM deployment
- Add `langfuse` to LiteLLM callback list
- Verify traces appear in Langfuse for Ollama/local model calls

### Phase 3: Prometheus Metrics (Future)
- No native `/metrics` endpoint in Langfuse
- Options: custom exporter polling `/api/public/metrics`, or OTEL-based export
- ServiceMonitor for Prometheus autodiscovery
- Grafana dashboard for LLM cost/latency/token usage

### Phase 4: Claude Agent Tracing (Future)
- Claude Code (Max subscription) doesn't expose instrumentable SDK calls
- Options when available:
  - Langfuse Python SDK for post-hoc tool call logging
  - Claude Code OTEL export (if/when supported)
  - OpenTelemetry instrumentation of Anthropic SDK calls

## Constraints & Decisions

1. **Official chart over custom** — Langfuse v3 is complex (6 components); maintaining a custom chart is not worth it
2. **Bundled ClickHouse** — no existing ClickHouse in the cluster; let the chart manage it
3. **Bundled Redis/MinIO** — simple, isolated; no need to share with other apps
4. **CNPG for PostgreSQL** — consistent with all other apps, gets B2 backups and monitoring for free
5. **Claude agent tracing deferred** — technical limitation of Claude Code, not a blocker for Phase 1-2
6. **Prometheus metrics deferred** — get Langfuse running first, add monitoring later

## Security

- All secrets SOPS-encrypted in prod repo (OIDC creds, SALT, ENCRYPTION_KEY, NEXTAUTH_SECRET)
- Zitadel SSO enforced, password auth disabled
- Internal services (ClickHouse, Redis, MinIO, PostgreSQL) not exposed externally
- Langfuse API keys generated post-deployment for LiteLLM integration
