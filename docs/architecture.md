# Architecture Diagrams

## Table of Contents
- [High-Level Network Overview](#high-level-network-overview)
- [Public Access (Pangolin)](#public-access-pangolin--wireguard)
- [DNS Architecture](#dns-architecture)
- [DDoS / WAF Protection](#ddos--waf-protection-cloudflare-in-front)
- [Application Architecture](#application-architecture)
- [Backup & DR](#data-flow-backup--disaster-recovery)
- [Observability](#observability-architecture)
- [GitOps Flow](#repository-structure--gitops-flow)

---

## High-Level Network Overview

```
       ┌────────────────────────────┐
       │         AWS Cloud          │
       │  ┌──────┐                  │
       │  │  S3  │  (TF state)      │
       │  └──────┘                  │
       │  ┌──────┐                  │
       │  │DynDB │  (TF locks)      │
       │  └──────┘                  │
       └─────────────┬──────────────┘
                     │ HTTPS
       ┌─────────────┼──────────────┐
       │ VULTR VPS   │              │
       │ ┌───────────┴───────────┐  │
       │ │   Pangolin Stack      │  │
       │ │ Traefik + Gerbil      │  │
       │ │ Badger + Pangolin     │  │
       │ │                       │  │
       │ │ *.example.com         │  │
       │ │   -> VPS public IP    │  │
       │ └───────────┬───────────┘  │
       └─────────────┼──────────────┘
                     │ WireGuard
  ─ ─ ─ ─ ─ ─ ─ ─ ─ ┼ ─ ─ ─ ─ ─ ─ ─
  HOMELAB            │
       ┌─────────────┴──────────────┐
       │     ISP Router / Modem     │
       └─────────────┬──────────────┘
                     │ WAN
       ┌─────────────┴──────────────┐
       │       OPNSense VM          │
       │  Firewall, Router, DHCP    │
       │ ┌────────────────────────┐ │
       │ │ Unbound (DNS resolver) │ │
       │ │ Wildcard override +    │ │
       │ │ CoreDNS custom zone    │ │
       │ └────────────────────────┘ │
       │                            │
       │  VLAN 10: Prod gateway     │
       │  VLAN 11: Dev gateway      │
       └────┬──────────────────┬────┘
            │                  │
       VLAN 10 (Prod)    VLAN 11 (Dev)
            │                  │
       ┌────┴──────────────────┴────┐
       │  Managed Switch (802.1Q)   │
       │  Trunk: OPNSense+Proxmox   │
       │  Access: per-VLAN ports    │
       └─────────────┬──────────────┘
                     │ Trunk
       ┌─────────────┴──────────────┐
       │      Proxmox VE Host       │
       │                            │
       │  ┌──────────────────────┐   │
       │  │  PROD Cluster        │   │
       │  │  (Talos Linux)       │   │
       │  │  1x CP + 2x WK      │   │
       │  │  + Newt (K8s pod)    │   │
       │  └──────────────────────┘   │
       └────────────────────────────┘
```

---

## Public Access (Pangolin + WireGuard)

Replaces Cloudflare Tunnel. See
[ADR-003](decisions/003-pangolin-controld-architecture.md).

```
  User types: app.example.com
       │
       │ 1. DNS -> VPS public IP
       │ 2. HTTPS request
       │
  ┌────┴───────────────────────┐
  │    VULTR VPS (Pangolin)    │
  │                            │
  │  Traefik -> TLS terminate  │
  │  Badger  -> Auth check     │
  │  Pangolin   Control plane  │
  │  Gerbil  -> WG tunnel mgr  │
  │                            │
  │  Auto Let's Encrypt TLS    │
  └────────────┬───────────────┘
               │
      WireGuard Tunnel
      (encrypted, outbound)
               │
  ─ ─ ─ ─ HOMELAB ─ ─ ─ ─ ─ ─
  No inbound ports opened
               │
  ┌────────────┴───────────────┐
  │  Kubernetes Cluster        │
  │                            │
  │  Newt (K8s pod)            │
  │  Receives WG traffic,      │
  │  proxies to K8s services   │
  │                            │
  │  Services (all via Cilium  │
  │  Gateway + HTTPRoutes):    │
  │  Forgejo, Harbor,          │
  │  ArgoCD, Grafana,          │
  │  Zitadel, Plane,           │
  │  Open WebUI, code-server   │
  └────────────────────────────┘

  [x] No public IP on homelab
  [x] No port forwarding
  [x] All traffic encrypted (WireGuard)
  [x] Auth via Badger (per resource)
  [x] Auto TLS via Let's Encrypt
  [x] You own the entire traffic path
```

---

## DNS Architecture

DNS is handled by OPNSense Unbound with a wildcard override for
`*.aaron.reynoza.org`, forwarding internal lookups to the CoreDNS
custom zone inside the cluster. This avoids hairpinning — internal
devices resolve service hostnames directly to cluster IPs without
routing through the Pangolin VPS.

### DNS Resolution Flow

```
  PROD device (10.10.x.x)
       │
       │ DNS query (UDP :53)
       │
  ┌────┴───────────────────────┐
  │  OPNSense -- Unbound       │
  │                            │
  │  Wildcard override:        │
  │  *.aaron.reynoza.org ->    │
  │  CoreDNS custom zone       │
  │  (Cilium Gateway / svc IP) │
  │                            │
  │  All other queries ->      │
  │  upstream public resolvers │
  └────────────┬───────────────┘
               │ (internal queries)
               │
  ┌────────────┴───────────────┐
  │  CoreDNS (K8s cluster)     │
  │                            │
  │  Custom zone for           │
  │  *.aaron.reynoza.org       │
  │  -> Cilium Gateway IP      │
  │     (10.10.10.228)         │
  └────────────────────────────┘
```

### Split-Horizon DNS

Same domain resolves differently based on
where you ask from.

```
  Query: "app.aaron.reynoza.org"

  ┌────────────────────────────┐
  │ EXTERNAL (internet user)   │
  │                            │
  │ Resolves to: VPS public IP │
  │                            │
  │ Path:                      │
  │   User -> VPS (Traefik)    │
  │     -> WireGuard tunnel    │
  │       -> Newt -> K8s svc   │
  └────────────────────────────┘

  ┌────────────────────────────┐
  │ INTERNAL (device on VLAN)  │
  │                            │
  │ Resolves to: Cilium GW IP  │
  │ (10.10.10.228)             │
  │                            │
  │ Path:                      │
  │   Device -> Cilium Gateway │
  │   -> HTTPRoute -> K8s svc  │
  │   No tunnel, no VPS hop.   │
  └────────────────────────────┘

  Avoids "hairpinning" -- internal
  traffic stays internal instead of
  going out to VPS and back.
```

---

## DDoS / WAF Protection (Cloudflare in Front)

> **Status**: Future task.
> See [Issue #006](issues/006-security-hardening-ddos-protection.md).

Additive layer -- no architecture changes needed.

```
  WITHOUT Cloudflare (current):

    User -> VPS -> WireGuard -> Homelab
    ! VPS is directly exposed
    ! No DDoS mitigation

  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─

  WITH Cloudflare (future):

    User
      -> Cloudflare Edge
         DDoS absorbed
         WAF: SQLi/XSS/bots
         Rate limiting
         VPS IP hidden
           -> VPS (Pangolin)
             -> WireGuard -> Homelab

  Pangolin still handles the tunnel.
  Cloudflare only shields the VPS.
```

---

## Application Architecture

### Production Cluster

```
  ┌────────────────────────────┐
  │  PROD K8s CLUSTER          │
  │                            │
  │  NETWORKING                │
  │  Cilium (CNI + LB-IPAM)    │
  │  Cilium Gateway API        │
  │    -> 10.10.10.228         │
  │    HTTPRoutes per service  │
  │                            │
  │  PLATFORM                  │
  │  ArgoCD  Longhorn  Velero  │
  │  Harbor  Newt  CNPG        │
  │  Forgejo FgActn  Zitadel   │
  │                            │
  │  OBSERVABILITY             │
  │  Grafana  Prometheus Hubble│
  │  Mimir  Loki  Tempo  OTel  │
  │                            │
  │  APPLICATIONS              │
  │  Plane (project mgmt)      │
  │  Open WebUI + Ollama       │
  │    + LiteLLM (LLM stack)   │
  │  code-server (VM 110)      │
  │                            │
  │  APPS                       │
  │  Outline (docs wiki)       │
  │                            │
  │  PLANNED                   │
  │  Jellyfin + *arr (media)   │
  │  Immich (photos)           │
  └────────────────────────────┘
```

### Cilium Gateway API

All services are exposed via a single Cilium Gateway at `10.10.10.228`
with per-service HTTPRoutes for hostname-based routing. Pangolin/Newt
forward external HTTPS traffic (from `*.aaron.reynoza.org`) into this
gateway — the same path used for internal access.

```
  External user
    -> Pangolin VPS (Traefik TLS)
      -> WireGuard tunnel
        -> Newt (K8s pod)
          -> Cilium Gateway (10.10.10.228)
            -> HTTPRoute (hostname match)
              -> K8s Service

  Internal device (VLAN 10)
    -> Cilium Gateway (10.10.10.228)
      -> HTTPRoute (hostname match)
        -> K8s Service
```

### Development Cluster

> **Not deployed.** Dev cluster is deferred. All work currently runs on the prod cluster.

---

## Data Flow: Backup & Disaster Recovery

```
  LOCAL (Fast Recovery)
  ┌─────────────┐
  │  Longhorn   │
  │  Snapshots  │── Scheduled ──┐
  │  Hourly +   │   Backup      │
  │  Daily      │               │
  └──────┬──────┘               │
         │ restore              │
  ┌──────┴──────┐               │
  │  PV/PVC     │               │
  │  Restored   │               │
  └─────────────┘               │
                                │
  ┌─────────────┐  ┌────────────┴──┐
  │  Velero     │  │ Backblaze B2  │
  │  K8s state  ├─>│               │
  │  CRDs +     │  │ longhorn/     │
  │  Secrets    │  │  prod/        │
  └─────────────┘  │ velero/       │
                   │  prod/        │
                   └───────────────┘

  Full cluster restore from B2
  in case of complete failure.
```

---

## Observability Architecture

### Data Flow

```
  METRICS PIPELINE
  ┌──────────────┐    scrape     ┌──────────────┐   remote-write  ┌──────────┐
  │ Exporters    │──────────────>│  Prometheus   │───────────────>│  Mimir   │
  │              │               │  (15d local)  │                │(long-term│
  │ node-exporter│               └──────┬───────┘                │ storage) │
  │ kube-state   │                      │                         └──────────┘
  │ kubelet      │                      │ query
  │ app metrics  │               ┌──────┴───────┐
  │ (ServiceMon) │               │   Grafana    │
  │              │               │ (dashboards  │
  │ PVE exporter │               │  + alerts)   │
  │ (planned)    │               └──────┬───────┘
  └──────────────┘                      │ query
                                 ┌──────┴───────┐
  LOGS PIPELINE                  │    Loki      │
  ┌──────────────┐   push       │  (log store) │
  │ OTel Collect │─────────────>└──────────────┘
  │              │
  └──────────────┘               ┌──────────────┐
                                 │    Tempo     │
  TRACES PIPELINE                │(trace store) │
  App -> OTel -> Tempo           └──────────────┘
```

### Dashboards (Grafana)

| Folder | Dashboard | Purpose |
|--------|-----------|---------|
| **Home** | Home Overview | Landing page with status summary, navigation, cluster graphs |
| **Cluster** | Cluster Overview | Node status, CPU/mem/disk gauges, pod counts, top consumers |
| **Cluster** | Node Detail | Per-node CPU, memory, disk, network, etcd, load avg |
| **Cluster** | Namespace & Workload | Resource usage vs requests/limits, pod restarts, container states |
| **Applications** | App Metrics | ArgoCD, cert-manager, Longhorn, Harbor, Forgejo, Cilium |
| **Infrastructure** | Target Health | Up/down status for all Prometheus scrape targets |

Dashboards are deployed as ConfigMaps with `grafana_dashboard: "1"` label and
`grafana-folder` annotation. The Grafana sidecar auto-discovers and loads them.

### Alert Rules (PrometheusRules)

| Rule Group | Alerts | Severity |
|------------|--------|----------|
| node.rules | NodeDown, NodeDiskFull, NodeMemoryPressure | critical |
| pod.rules | PodCrashLooping, PodOOMKilled | critical/warning |
| cert.rules | CertExpiringSoon (<14 days) | warning |
| pve.rules | PVENodeUnreachable, PVEDiskFull | critical |
| infra.rules | PersistentVolumeFillingUp, TargetDown | warning |

Alerts are visible in Grafana and AlertManager UI. Notification routing
(Ntfy/Slack) is planned (HOMELAB-107).

### ServiceMonitors Enabled

ArgoCD (controller, server, repo-server), cert-manager, Cilium (agent,
operator, Hubble), Forgejo, Harbor, Longhorn, Loki, Mimir, Tempo.

### Adding Monitoring for New Apps

1. Check if the Helm chart has `metrics.enabled` or `serviceMonitor.enabled`
2. Enable in `core/charts/{platform,apps}/<chart>/values.yaml`
3. If the app exposes a dashboard, create a ConfigMap in
   `core/manifests/monitoring/dashboards/` with the `grafana_dashboard: "1"` label
4. Add critical alerts as PrometheusRules in `core/manifests/monitoring/rules/`

---

## Repository Structure & GitOps Flow

```
  ┌─────────────────┐ ┌────────────────┐
  │infra-core (Pub) │ │ prod (Private) │
  │                 │ │                │
  │ core/terraform/ │ │ apps/          │
  │  modules/     <─┤ │  (ArgoCD apps) │
  │   talos-cluster │ │                │
  │   proxmox-vm   │ │ values/        │
  │   aws-backend  │ │  (Helm values) │
  │                 │ │                │
  │ core/charts/    │ │ secrets/       │
  │  platform/    <─┤ │  (SOPS-encrypted)│
  │   argocd,       │ │                │
  │   cilium, etc   │ │ terraform.tfvars│
  │  apps/          │ │ backend.hcl    │
  │   harbor, etc   │ │                │
  │                 │ │                │
  │ docs/           │ │                │
  └─────────────────┘ └────────────────┘

  GITOPS FLOW:

  Developer
    -> Push to config repo
      -> Forgejo Actions
        |- Terraform Plan -> Apply
        |- Build Images -> Harbor
        '- Lint / Test
          -> ArgoCD detects changes
            -> Sync prod apps
```
