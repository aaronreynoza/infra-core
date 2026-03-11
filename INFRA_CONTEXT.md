# Infrastructure Context for Race Telemetry Application

This file describes the hosting infrastructure where this application will be deployed. Use this to make informed decisions about containerization, deployment configuration, and service integration.

---

## Hosting Overview

The application runs on a **self-hosted Kubernetes cluster** (Talos Linux) inside a homelab, exposed to the internet via a **Pangolin reverse proxy** on a Vultr VPS. There is no cloud hosting — everything runs on physical hardware at home.

### Environments

| Environment | Network | K8s Nodes | Purpose |
|-------------|---------|-----------|---------|
| **prod** | `10.10.10.0/16` (VLAN 10) | 2 control plane + 2 workers | Client-facing, paying users |
| **dev** | `10.11.10.0/16` (VLAN 11) | 2 control plane + 2 workers | Testing, can break freely |

Environments are **fully isolated** — separate VLANs, separate clusters, separate state. No communication between them.

---

## Kubernetes Platform

### Cluster OS
- **Talos Linux** v1.11.3 — immutable, API-driven, no SSH

### Platform Services Available
| Service | Purpose |
|---------|---------|
| **ArgoCD** | GitOps continuous delivery — syncs manifests from Git to cluster |
| **Cilium** | CNI + network policies + Hubble observability |
| **Longhorn** | Distributed block storage (PersistentVolumes) |
| **Harbor** | Private container registry (one per environment) |
| **Forgejo + Actions** | Self-hosted Git + CI/CD (like GitHub Actions) |
| **Zitadel** | SSO/OAuth identity provider |
| **Velero** | Cluster backup to AWS S3 |
| **Grafana + InfluxDB** | Monitoring and dashboards |

### Storage
- **Longhorn** for application data (block storage, PVCs). Prod uses replica count 2+, dev uses 1.
- **TrueNAS** (planned) for bulk media storage via NFS.
- **AWS S3** for backups (Velero + Longhorn snapshots).

---

## How Your App Gets Deployed

### Container Registry
- Push images to **Harbor** (private registry, one per environment)
- Harbor is accessible within the cluster at its internal service address
- Image vulnerability scanning is enabled

### GitOps Flow
```
You push code
  -> Forgejo Actions builds container image
  -> Image pushed to Harbor
  -> Update Helm values / manifests in config repo
  -> ArgoCD detects change and syncs to cluster
```

### What You Need to Provide
1. **Dockerfile** — to build your application image
2. **Helm chart or K8s manifests** — for deployment, service, ingress, PVCs, etc.
3. **Health check endpoints** — for liveness/readiness probes (recommended)

### Helm Chart Location
App charts live in the homelab repo under `core/charts/apps/`. Example structure:
```
core/charts/apps/race-telemetry/
  values.yaml          # Default values (non-sensitive)
```
Environment-specific overrides go in the private environments repo.

---

## How Traffic Reaches Your App (Public Access)

No ports are opened on the home network. External traffic flows through a **Pangolin** reverse proxy on a Vultr VPS via WireGuard tunnel:

```
User (internet)
  -> DNS resolves your domain to Vultr VPS public IP
  -> HTTPS hits Traefik on VPS (TLS terminated, Let's Encrypt auto-cert)
  -> Badger checks authentication (if resource is private)
  -> Gerbil forwards through WireGuard tunnel
  -> Newt (Talos system extension) receives inside cluster
  -> Newt proxies to your K8s Service
  -> Response travels back the same path
```

### What This Means for Your App
- Your app just needs a standard **K8s Service** (ClusterIP is fine)
- **No Ingress controller config needed** — Pangolin handles external routing
- TLS is handled automatically by Let's Encrypt on the VPS
- You can configure per-resource auth via the Pangolin dashboard (Badger)
- Domain routing is configured in the Pangolin dashboard, not in K8s

### Internal Access (devices on the VLAN)
Split-horizon DNS resolves the same domain directly to the cluster IP, bypassing the VPS tunnel entirely. Internal traffic stays internal.

---

## Authentication & SSO

- **Zitadel** is the identity provider for all services
- You can integrate your app with Zitadel via **OAuth2/OIDC**
- Alternatively, use Pangolin's **Badger** for simple auth gating (no code changes needed — just toggle in the dashboard)

---

## Database & Persistence

There is no managed database service. Options for your app:

1. **Deploy your own database as a K8s workload** — PostgreSQL, MySQL, etc. with a Longhorn PVC for persistence
2. **Use an embedded database** — SQLite with a Longhorn PVC
3. **External managed DB** — e.g., a cloud-hosted PostgreSQL if preferred

Longhorn PVCs are backed up to S3 via Velero, so your data has off-site backups.

---

## Observability

- **Grafana** for dashboards
- **InfluxDB** for metrics storage
- **Hubble** (Cilium) for network flow visibility
- Your app can export metrics to InfluxDB for custom dashboards
- Standard K8s logging — `kubectl logs` or future log aggregation

---

## CI/CD Pipeline (Forgejo Actions)

Forgejo Actions is compatible with GitHub Actions syntax. Your pipeline would typically:

1. Run tests
2. Build Docker image
3. Push to Harbor (environment-specific registry)
4. Update image tag in deployment manifests
5. ArgoCD auto-syncs the change

---

## Networking Constraints

- **No public IP** on the homelab — all public access goes through the VPS
- **No port forwarding** on the home router
- Inter-VLAN traffic is blocked — prod and dev cannot communicate
- DNS is managed by **Control D** with per-VLAN policies (strict filtering on prod, permissive on dev)
- All DNS queries are encrypted (DoH3)

---

## Deployment Checklist for a New App

1. Create a Dockerfile for your app
2. Create Helm chart or K8s manifests (Deployment, Service, PVC if needed)
3. Add chart to `core/charts/apps/<app-name>/` in the homelab repo
4. Add environment-specific values to the private environments repo
5. Create ArgoCD Application manifest pointing to your chart
6. Build and push your image to Harbor
7. Create a Pangolin resource in the dashboard mapping your domain to the K8s service
8. (Optional) Configure Zitadel OAuth or Badger auth for the resource

---

## Key Contacts & Repos

| Resource | Location |
|----------|----------|
| Infrastructure repo (public) | `homelab/` — Terraform modules, Helm charts, docs |
| Environment config (private) | `environments/` — tfvars, secrets, backend config |
| Pangolin dashboard | Hosted on the Vultr VPS (shared with William) |
| Harbor registry | Internal to each cluster |
| ArgoCD dashboard | `kubectl port-forward svc/argocd-server -n argocd 8080:443` |
