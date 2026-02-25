# Architecture Diagrams

## Table of Contents
- [High-Level Network Overview](#high-level-network-overview)
- [Public Access (Pangolin)](#public-access-pangolin--wireguard)
- [DNS Architecture (Control D)](#dns-architecture-control-d--ctrld)
- [DDoS / WAF Protection](#ddos--waf-protection-cloudflare-in-front)
- [Application Architecture](#application-architecture)
- [Backup & DR](#data-flow-backup--disaster-recovery)
- [GitOps Flow](#repository-structure--gitops-flow)

---

## High-Level Network Overview

```
       ┌────────────────────────────┐
       │         AWS Cloud          │
       │  ┌──────┐  ┌───────────┐   │
       │  │  S3  │  │ Secrets   │   │
       │  └──────┘  │ Manager   │   │
       │  ┌──────┐  └───────────┘   │
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
       │ │ ctrld (DNS proxy)      │ │
       │ │ Per-VLAN DNS + DoH3    │ │
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
       │  ┌──────────┐ ┌─────────┐  │
       │  │  PROD    │ │  DEV    │  │
       │  │ Cluster  │ │ Cluster │  │
       │  │ (Talos)  │ │ (Talos) │  │
       │  │ 2xCP     │ │ 2xCP    │  │
       │  │ 2xWK     │ │ 2xWK    │  │
       │  │ +Newt    │ │ +Newt   │  │
       │  └──────────┘ └─────────┘  │
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
  │  Newt (Talos extension)    │
  │  Receives WG traffic,      │
  │  proxies to K8s services   │
  │                            │
  │  Services:                 │
  │  Forgejo, Harbor,          │
  │  Jellyfin, Race Telemetry  │
  └────────────────────────────┘

  [x] No public IP on homelab
  [x] No port forwarding
  [x] All traffic encrypted (WireGuard)
  [x] Auth via Badger (per resource)
  [x] Auto TLS via Let's Encrypt
  [x] You own the entire traffic path
```

---

## DNS Architecture (Control D + ctrld)

ctrld replaces Unbound on OPNsense. Adds per-VLAN
DNS policies, encrypted queries (DoH3), and analytics.

### Per-VLAN DNS Routing

```
  PROD device (10.10.x.x)
       │
       │ DNS query (UDP :53)
       │
  ┌────┴───────────────────────┐
  │  OPNSense -- ctrld daemon  │
  │                            │
  │  1. Inspect source IP      │
  │  2. Match to network CIDR  │
  │                            │
  │  ┌──────────────────────┐  │
  │  │ 10.10.x.x (PROD)     │  │
  │  │  -> "PROD" upstream  │  │
  │  │  (strict filtering)  │  │
  │  └──────────────────────┘  │
  │  ┌──────────────────────┐  │
  │  │ 10.11.x.x (DEV)      │  │
  │  │  -> "DEV" upstream   │  │
  │  │  (permissive)        │  │
  │  └──────────────────────┘  │
  │                            │
  │  3. Forward over DoH3      │
  │  (ISP can't see queries)   │
  └────────────┬───────────────┘
               │ DNS-over-HTTPS/3
               │
  ┌────────────┴───────────────┐
  │     Control D Cloud        │
  │                            │
  │  ┌─────────┐ ┌─────────┐   │
  │  │ "PROD"  │ │ "DEV"   │   │
  │  │ Profile │ │ Profile │   │
  │  │         │ │         │   │
  │  │ Blk ads │ │ Blk mal │   │
  │  │ Blk trk │ │ Alw ads │   │
  │  │ Blk mal │ │ Alw trk │   │
  │  └─────────┘ └─────────┘   │
  │                            │
  │  Dashboard: analytics,     │
  │  top domains, blocked      │
  └────────────────────────────┘
```

### Split-Horizon DNS

Same domain resolves differently based on
where you ask from.

```
  Query: "app.example.com"

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
  │ Resolves to: cluster IP    │
  │ (ClusterIP or Ingress)     │
  │                            │
  │ Path:                      │
  │   Device -> K8s svc        │
  │   No tunnel, no VPS hop.   │
  └────────────────────────────┘

  Configured in ctrld:

    [listener.0.policy]
      rules = [
        # internal domains -> local
        { '*.example.com' =
            ['upstream.local'] }
      ]

    [upstream.local]
      type = 'legacy'
      endpoint = '<cluster-dns>:53'

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
  │  PLATFORM                  │
  │  ArgoCD  Cilium  Longhorn  │
  │  Velero  Harbor  Newt      │
  │  Forgejo FgActn  Zitadel   │
  │                            │
  │  OBSERVABILITY             │
  │  Grafana InfluxDB Hubble   │
  │                            │
  │  APPLICATIONS              │
  │  Race Telemetry (prod)     │
  │  Jellyfin (media)          │
  │  Other personal services   │
  └────────────────────────────┘
```

### Development Cluster

```
  ┌────────────────────────────┐
  │  DEV K8s CLUSTER           │
  │                            │
  │  PLATFORM (same as prod)   │
  │  ArgoCD  Cilium  Longhorn  │
  │  Velero  Harbor  Newt      │
  │                            │
  │  APPLICATIONS              │
  │  Race Telemetry (dev)      │
  │  Homelab testing           │
  └────────────────────────────┘
```

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
  │  Velero     │  │   AWS S3      │
  │  K8s state  ├─>│               │
  │  CRDs +     │  │ longhorn/     │
  │  Secrets    │  │  prod/ + dev/ │
  └─────────────┘  │ velero/       │
                   │  prod/ + dev/ │
                   └───────────────┘

  Full cluster restore from S3
  in case of complete failure.
```

---

## Repository Structure & GitOps Flow

```
  ┌────────────────┐ ┌────────────────┐
  │homelab (Public)│ │ envs (Private) │
  │                │ │                │
  │ modules/       │ │ environments/  │
  │  talos-cluster/<─┤  prod/         │
  │  proxmox-vm/   │ │   main.tf      │
  │  aws-backend/  │ │   tfvars       │
  │                │ │   values/      │
  │ charts/        │ │  dev/          │
  │  platform/   <─┤ │ main.tf        │
  │   argocd,      │ │   tfvars       │
  │   cilium, etc  │ │   values/      │
  │  apps/         │ │                │
  │   harbor,      │ │ apps/          │
  │   jellyfin     │ │  prod/         │
  │                │ │  dev/          │
  └────────────────┘ └────────────────┘

  GITOPS FLOW:

  Developer
    -> Push to config repo
      -> Forgejo Actions
        |- Terraform Plan -> Apply
        |- Build Images -> Harbor
        '- Lint / Test
          -> ArgoCD detects changes
            |- Prod: sync prod apps
            '- Dev: sync dev apps
```
