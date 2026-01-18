# Homelab Project - Claude Context

## Project Purpose

This is a homelab project with three main goals:
1. **Showcase Skills** - Demonstrate DevOps/Platform Engineering capabilities
2. **Personal Use** - Host personal services (music, videos, media)
3. **Production Workload** - Host a race telemetry application with actual paying clients

---

## Architecture Overview

### Repository Structure (Planned)

The project will be split into **two repositories**:

1. **homelab-core** (this repo, public)
   - Reusable Terraform modules
   - Base Kubernetes manifests and Helm charts
   - Default applications (can be enabled/disabled)
   - **Default configurations for all apps** (sensible defaults out of the box)
   - Generic, hardware-agnostic configuration

2. **homelab-config** (private repo)
   - Uses homelab-core as a module/dependency
   - Environment-specific configurations (dev, prod)
   - Hardware-specific settings
   - **Override any default app configuration** as needed
   - Secrets references (AWS Secrets Manager)
   - Custom applications beyond defaults

### Environments

| Environment | Purpose | Network | Notes |
|-------------|---------|---------|-------|
| **prod** | Actual clients, race telemetry app, personal services | `10.10.10.0/16` | High availability, backups critical |
| **dev** | Completely separate infrastructure for testing | `10.11.10.0/16` | Can break, mirrors prod architecture |

**Dev Environment Purpose (Clarified):**
- Totally separate infrastructure (own cluster, own VMs)
- Runs development version of the race telemetry application
- Tests homelab infrastructure changes before promoting to prod
- Safe to destroy and rebuild frequently

---

## Current State (As-Is)

### Technology Stack
- **Virtualization**: Proxmox VE
- **Cluster OS**: Talos Linux v1.11.3
- **Container Orchestration**: Kubernetes
- **GitOps**: ArgoCD (app-of-apps pattern)
- **Infrastructure-as-Code**: Terraform (Proxmox provider)
- **Configuration Management**: Ansible
- **Remote State**: AWS S3 + DynamoDB
- **CI/CD**: Forgejo Actions (self-hosted runner)

### Current Infrastructure
- **Control Plane**: 1x VM (2 CPU, 4GB RAM, 20GB disk) - REDACTED_IP0
- **Workers**: 1x VM defined (4 CPU, 16GB RAM, 20GB + 1TB data disk) - REDACTED_IP1-52
- **Network**: Single flat network on vmbr0

### Currently Deployed Applications
- Cilium (CNI with Hubble observability)
- Longhorn (distributed storage, replica count: 1)
- ArgoCD (GitOps controller)

### Directory Structure
```
homelab/
├── core/                           # Reusable homelab-core (open source ready)
│   ├── terraform/modules/          # Reusable Terraform modules
│   │   ├── talos-cluster/         # Talos K8s cluster provisioning
│   │   ├── proxmox-vm/            # Generic VM provisioning
│   │   └── aws-backend/           # S3 + DynamoDB backend
│   ├── charts/                     # Helm values (organized by layer)
│   │   ├── defaults.yaml          # Toggle default applications
│   │   ├── platform/              # Platform layer (cilium, longhorn, argocd, velero)
│   │   └── apps/                  # Application layer (harbor, forgejo, jellyfin, etc.)
│   ├── manifests/                  # Base K8s manifests
│   │   ├── namespaces/            # Namespace definitions
│   │   └── argocd/                # ArgoCD app templates
│   ├── ansible/                    # Playbooks & inventory
│   └── scripts/                    # Image management scripts
│
├── environments/                   # Environment-specific configs
│   ├── prod/
│   │   ├── terraform/             # Prod Terraform config (uses core modules)
│   │   ├── values/                # Helm value overrides for prod
│   │   └── apps/                  # ArgoCD Applications for prod
│   └── dev/
│       ├── terraform/             # Dev Terraform config (uses core modules)
│       ├── values/                # Helm value overrides for dev
│       └── apps/                  # ArgoCD Applications for dev
│
└── docs/                           # Documentation
```

---

## Target Architecture (To-Be)

### Default Applications (Toggleable in Core Module)
- [x] Cilium (CNI with Hubble) - **CONFIRMED**
- [x] Longhorn (storage)
- [ ] Grafana + InfluxDB (monitoring/metrics)
- [ ] Velero (disaster recovery)

### Additional Services (Config Repo)
- [ ] Forgejo (self-hosted Git)
- [ ] Forgejo Actions (CI/CD) - **CONFIRMED**
- [ ] Harbor (container registry) - **CONFIRMED** - one per environment, no cross-VLAN access
- [ ] Zitadel (OAuth/Identity Provider) - **CONFIRMED**
- [ ] Cloudflare Tunnel (public exposure) - **CONFIRMED**
- [ ] Jellyfin (media server) - **CONFIRMED**
- [ ] Ollama + Web UI (self-hosted LLM) - **CONFIRMED** - disabled until GPU available
- [ ] Race telemetry application

### Networking
- **Switch**: NETGEAR GS308EP (8-port PoE Gigabit Smart Managed)
- **Firewall/Router**: OPNSense (to be deployed as VM via Terraform)
- **VLANs**:
  - VLAN for prod: `10.10.10.0/16`
  - VLAN for dev: `10.11.10.0/16`
- VLANs managed by OPNSense

### Backup & Disaster Recovery
- **Local Storage**: Longhorn with snapshots
- **Backup Destination**: AWS S3
- **DR Tool**: Velero
- **Secrets**: AWS Secrets Manager
- **Recovery Scenarios**:
  - Single disk failure (Longhorn handles)
  - Complete cluster failure (Velero restores from AWS)

### CI/CD & Git
- Self-hosted Forgejo as primary Git server
- Mirror repositories to GitHub
- **One Harbor registry per environment** (prod and dev isolated)
- No cross-VLAN registry access

---

## Technical Decisions

### Confirmed
- Talos Linux as cluster OS (immutable, secure)
- ArgoCD for GitOps
- Terraform for infrastructure provisioning
- AWS for backup storage and secrets
- Two-environment strategy (dev/prod) - completely separate infrastructures
- Two-repo architecture (core module + config)
- **Cilium** as CNI (with Hubble observability)
- **Forgejo Actions** for CI/CD
- **Harbor** for container registry - **one per environment, isolated**
- **Zitadel** for OAuth/Identity Provider
- **Cloudflare Tunnel** for public exposure (no port forwarding needed)
- **Jellyfin** for media server
- **Ollama + Web UI** for self-hosted LLM (disabled until GPU available)
- **2 control plane nodes** per environment for HA
- **No inter-VLAN communication** - environments fully isolated
- **Default app configs in core**, overridable in config repo

### Hardware
- **2x x99 servers** with dual CPUs each
- Generous resource allocation for both dev and prod (plenty of cores and memory available)

### Pending / Post-Plan Tasks
- [ ] Configure Proxmox servers (storage, networking) - **after plan complete**
- [ ] GPU procurement for Ollama

---

## Network Architecture

### High-Level Overview
```
                                    ┌─────────────────────────────────────┐
                                    │              AWS Cloud              │
                                    │  ┌───────────┐  ┌────────────────┐  │
                                    │  │    S3     │  │    Secrets     │  │
                                    │  │ (Backups) │  │    Manager     │  │
                                    │  └───────────┘  └────────────────┘  │
                                    │  ┌───────────┐                      │
                                    │  │ DynamoDB  │ (Terraform locks)   │
                                    │  └───────────┘                      │
                                    └──────────────┬──────────────────────┘
                                                   │
                                                   │ HTTPS/API
                                                   │
┌──────────────────────────────────────────────────┼──────────────────────────────────────────────────┐
│                                    HOMELAB       │                                                  │
│                                                  │                                                  │
│   ┌──────────────────────────────────────────────┼───────────────────────────────────────────────┐  │
│   │                              ISP Router / Modem                                              │  │
│   └──────────────────────────────────────────────┬───────────────────────────────────────────────┘  │
│                                                  │                                                  │
│                                                  │ WAN                                              │
│                                                  ▼                                                  │
│   ┌──────────────────────────────────────────────────────────────────────────────────────────────┐  │
│   │                                    OPNSense VM                                               │  │
│   │                          (Firewall, Router, VLAN Gateway, DHCP, DNS)                        │  │
│   │                                                                                              │  │
│   │   WAN: DHCP from ISP          LAN: 10.10.10.1 (Prod)        LAN: 10.11.10.1 (Dev)          │  │
│   └──────────────┬───────────────────────┬──────────────────────────────┬────────────────────────┘  │
│                  │                       │                              │                           │
│                  │              VLAN 10 (Prod)                 VLAN 11 (Dev)                        │
│                  │                       │                              │                           │
│   ┌──────────────┴───────────────────────┴──────────────────────────────┴────────────────────────┐  │
│   │                              NETGEAR GS308EP Switch                                          │  │
│   │                         (802.1Q VLAN Tagging, PoE for devices)                               │  │
│   │                                                                                              │  │
│   │   Port 1: Trunk (OPNSense - all VLANs)                                                      │  │
│   │   Port 2: Trunk (Proxmox Host - all VLANs)                                                  │  │
│   │   Port 3-5: VLAN 10 (Prod devices)                                                          │  │
│   │   Port 6-8: VLAN 11 (Dev devices)                                                           │  │
│   └──────────────────────────────────────┬───────────────────────────────────────────────────────┘  │
│                                          │                                                          │
│                                          │ Trunk (VLAN 10 + 11)                                     │
│                                          ▼                                                          │
│   ┌──────────────────────────────────────────────────────────────────────────────────────────────┐  │
│   │                                   Proxmox VE Host                                            │  │
│   │                                                                                              │  │
│   │   ┌─────────────────────────────────────────┐  ┌─────────────────────────────────────────┐  │  │
│   │   │          VLAN 10 (Prod Cluster)         │  │          VLAN 11 (Dev Cluster)          │  │  │
│   │   │            10.10.10.0/16                │  │            10.11.10.0/16                │  │  │
│   │   │                                         │  │                                         │  │  │
│   │   │  ┌───────────────────────────────────┐  │  │  ┌───────────────────────────────────┐  │  │  │
│   │   │  │     Control Plane 01 (Talos)      │  │  │  │     Control Plane 01 (Talos)      │  │  │  │
│   │   │  │     prod-cp-01: 10.10.10.10       │  │  │  │     dev-cp-01: 10.11.10.10        │  │  │  │
│   │   │  │     4 CPU / 8GB RAM / 50GB        │  │  │  │     4 CPU / 8GB RAM / 50GB        │  │  │  │
│   │   │  └───────────────────────────────────┘  │  │  └───────────────────────────────────┘  │  │  │
│   │   │                                         │  │                                         │  │  │
│   │   │  ┌───────────────────────────────────┐  │  │  ┌───────────────────────────────────┐  │  │  │
│   │   │  │     Control Plane 02 (Talos)      │  │  │  │     Control Plane 02 (Talos)      │  │  │  │
│   │   │  │     prod-cp-02: 10.10.10.11       │  │  │  │     dev-cp-02: 10.11.10.11        │  │  │  │
│   │   │  │     4 CPU / 8GB RAM / 50GB        │  │  │  │     4 CPU / 8GB RAM / 50GB        │  │  │  │
│   │   │  └───────────────────────────────────┘  │  │  └───────────────────────────────────┘  │  │  │
│   │   │                                         │  │                                         │  │  │
│   │   │  ┌───────────────────────────────────┐  │  │  ┌───────────────────────────────────┐  │  │  │
│   │   │  │     Worker 01 (Talos)             │  │  │  │     Worker 01 (Talos)             │  │  │  │
│   │   │  │     prod-wk-01: 10.10.10.20       │  │  │  │     dev-wk-01: 10.11.10.20        │  │  │  │
│   │   │  │     8 CPU / 32GB RAM              │  │  │  │     8 CPU / 32GB RAM              │  │  │  │
│   │   │  │     50GB OS + 500GB Data          │  │  │  │     50GB OS + 500GB Data          │  │  │  │
│   │   │  └───────────────────────────────────┘  │  │  └───────────────────────────────────┘  │  │  │
│   │   │                                         │  │                                         │  │  │
│   │   │  ┌───────────────────────────────────┐  │  │  ┌───────────────────────────────────┐  │  │  │
│   │   │  │     Worker 02 (Talos)             │  │  │  │     Worker 02 (Talos)             │  │  │  │
│   │   │  │     prod-wk-02: 10.10.10.21       │  │  │  │     dev-wk-02: 10.11.10.21        │  │  │  │
│   │   │  │     8 CPU / 32GB RAM              │  │  │  │     8 CPU / 32GB RAM              │  │  │  │
│   │   │  │     50GB OS + 500GB Data          │  │  │  │     50GB OS + 500GB Data          │  │  │  │
│   │   │  └───────────────────────────────────┘  │  │  └───────────────────────────────────┘  │  │  │
│   │   │                                         │  │                                         │  │  │
│   │   └─────────────────────────────────────────┘  └─────────────────────────────────────────┘  │  │
│   │                                                                                              │  │
│   └──────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                     │
└─────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Application Architecture (Per Environment)
```
┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
│                              PROD KUBERNETES CLUSTER (10.10.10.0/16)                            │
│                                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────────────────────┐   │
│  │                                    PLATFORM LAYER                                        │   │
│  │                                                                                          │   │
│  │   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐   │   │
│  │   │   ArgoCD    │  │   Cilium    │  │  Longhorn   │  │   Velero    │  │   Harbor    │   │   │
│  │   │   (GitOps)  │  │ (CNI+Hubble)│  │  (Storage)  │  │    (DR)     │  │ (Registry)  │   │   │
│  │   └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘   │   │
│  │                                                                                          │   │
│  │   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐   │   │
│  │   │   Forgejo   │  │   Forgejo   │  │  External   │  │   Zitadel   │  │ Cloudflare  │   │   │
│  │   │    (Git)    │  │   Actions   │  │   Secrets   │  │   (OAuth)   │  │   Tunnel    │   │   │
│  │   │             │  │    (CI)     │  │    (AWS)    │  │    (SSO)    │  │  (Ingress)  │   │   │
│  │   └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘   │   │
│  │                                                                                          │   │
│  │   ┌─────────────────────────────────────────────────────────────────────────────────┐   │   │
│  │   │   Ollama + Web UI (Self-hosted LLM) [DISABLED - waiting for GPU]                │   │   │
│  │   └─────────────────────────────────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────────────────────┐   │
│  │                                  OBSERVABILITY LAYER                                     │   │
│  │                                                                                          │   │
│  │   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                                     │   │
│  │   │   Grafana   │  │  InfluxDB   │  │   Hubble    │                                     │   │
│  │   │ (Dashboards)│  │  (Metrics)  │  │ (Network)   │                                     │   │
│  │   └─────────────┘  └─────────────┘  └─────────────┘                                     │   │
│  └─────────────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────────────────────┐   │
│  │                                  APPLICATION LAYER                                       │   │
│  │                                                                                          │   │
│  │   ┌──────────────────────────┐  ┌──────────────────────────┐  ┌─────────────────────┐   │   │
│  │   │   Race Telemetry App    │  │       Jellyfin           │  │   Other Personal    │   │   │
│  │   │      (PRODUCTION)       │  │     (Media Server)       │  │      Services       │   │   │
│  │   │   - Client-facing       │  │   - Music / Videos       │  │                     │   │   │
│  │   │   - Real users          │  │   - Personal use         │  │                     │   │   │
│  │   └──────────────────────────┘  └──────────────────────────┘  └─────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
│                               DEV KUBERNETES CLUSTER (10.11.10.0/16)                            │
│                                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────────────────────┐   │
│  │                                    PLATFORM LAYER                                        │   │
│  │   (Same stack as prod, fully isolated - own registry, own everything)                   │   │
│  │                                                                                          │   │
│  │   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐   │   │
│  │   │   ArgoCD    │  │   Cilium    │  │  Longhorn   │  │   Velero    │  │   Harbor    │   │   │
│  │   │   (GitOps)  │  │ (CNI+Hubble)│  │  (Storage)  │  │    (DR)     │  │ (Registry)  │   │   │
│  │   └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────────────────────┐   │
│  │                                  APPLICATION LAYER                                       │   │
│  │                                                                                          │   │
│  │   ┌──────────────────────────┐  ┌──────────────────────────────────────────────────┐    │   │
│  │   │   Race Telemetry App    │  │           Homelab Testing                         │    │   │
│  │   │     (DEVELOPMENT)       │  │   - Test infra changes before prod               │    │   │
│  │   │   - Feature testing     │  │   - Validate Terraform modules                   │    │   │
│  │   │   - Integration tests   │  │   - Test new applications                        │    │   │
│  │   └──────────────────────────┘  └──────────────────────────────────────────────────┘    │   │
│  └─────────────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Data Flow: Backup & Disaster Recovery
```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    BACKUP STRATEGY                                       │
│                                                                                          │
│   LOCAL (Fast Recovery)                          REMOTE (Disaster Recovery)             │
│   ─────────────────────                          ───────────────────────────            │
│                                                                                          │
│   ┌─────────────┐                                         ┌─────────────────────────┐   │
│   │  Longhorn   │                                         │         AWS S3          │   │
│   │  Snapshots  │ ────── Scheduled Backup ──────────────▶ │                         │   │
│   │             │        (Longhorn Backup Target)         │  s3://homelab-backups/  │   │
│   │  - Hourly   │                                         │    ├── longhorn/        │   │
│   │  - Daily    │                                         │    │   ├── prod/        │   │
│   └─────────────┘                                         │    │   └── dev/         │   │
│         │                                                 │    │                     │   │
│         │ Fast restore                                    │    └── velero/          │   │
│         ▼ (disk failure)                                  │        ├── prod/        │   │
│   ┌─────────────┐                                         │        └── dev/         │   │
│   │   PV/PVC    │                                         └─────────────────────────┘   │
│   │  Restored   │                                                      ▲                │
│   └─────────────┘                                                      │                │
│                                                                        │                │
│   ┌─────────────┐                                                      │                │
│   │   Velero    │ ────── Cluster State Backup ─────────────────────────┘                │
│   │             │        (Daily for prod, Weekly for dev)                               │
│   │  - CRDs     │                                                                       │
│   │  - Secrets  │        Full cluster restore possible                                  │
│   │  - Configs  │        from complete failure                                          │
│   └─────────────┘                                                                       │
│                                                                                          │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

### Public Access Flow (Cloudflare Tunnel)
```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                   PUBLIC ACCESS                                          │
│                                                                                          │
│   User Device                      Cloudflare Edge                     Homelab          │
│   ───────────                      ───────────────                     ───────          │
│                                                                                          │
│   ┌─────────┐     HTTPS      ┌──────────────────┐                                       │
│   │ Browser │ ─────────────▶ │  Cloudflare CDN  │                                       │
│   │   or    │                │   (DDoS protect) │                                       │
│   │   App   │                └────────┬─────────┘                                       │
│   └─────────┘                         │                                                 │
│                                       ▼                                                 │
│                              ┌──────────────────┐      ┌────────────────────────────┐   │
│                              │ Cloudflare Access│ ◀──▶ │       Zitadel (OAuth)      │   │
│                              │   (Zero Trust)   │      │    (Identity Provider)     │   │
│                              └────────┬─────────┘      └────────────────────────────┘   │
│                                       │                                                 │
│                                       │ Authenticated                                   │
│                                       ▼                                                 │
│                              ┌──────────────────┐                                       │
│                              │ Cloudflare Tunnel│                                       │
│                              │   (Argo Tunnel)  │                                       │
│                              └────────┬─────────┘                                       │
│                                       │                                                 │
│                    ───────────────────┼──────────────────                              │
│                    Outbound only      │     No inbound                                  │
│                    (no port forward)  │     ports open                                  │
│                    ───────────────────┼──────────────────                              │
│                                       │                                                 │
│                                       ▼                                                 │
│   ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│   │                           Kubernetes Cluster                                     │   │
│   │                                                                                  │   │
│   │   ┌───────────────┐                                                             │   │
│   │   │  cloudflared  │ ◀──── Outbound connection to Cloudflare                     │   │
│   │   │   (DaemonSet) │                                                             │   │
│   │   └───────┬───────┘                                                             │   │
│   │           │                                                                      │   │
│   │           ▼                                                                      │   │
│   │   ┌───────────────────────────────────────────────────────────────────────┐     │   │
│   │   │                         Internal Services                              │     │   │
│   │   │   ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐    │     │   │
│   │   │   │ Forgejo │  │ Harbor  │  │ Grafana │  │Jellyfin │  │  Race   │    │     │   │
│   │   │   │         │  │         │  │         │  │         │  │Telemetry│    │     │   │
│   │   │   └─────────┘  └─────────┘  └─────────┘  └─────────┘  └─────────┘    │     │   │
│   │   └───────────────────────────────────────────────────────────────────────┘     │   │
│   │                                                                                  │   │
│   └─────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                          │
│   Benefits:                                                                             │
│   ✓ No public IP needed                                                                │
│   ✓ No port forwarding                                                                 │
│   ✓ DDoS protection included                                                           │
│   ✓ Zero Trust authentication via Zitadel                                              │
│   ✓ All traffic encrypted                                                              │
│                                                                                          │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

### Repository Structure & GitOps Flow
```
┌──────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                      REPOSITORY ARCHITECTURE                                      │
│                                                                                                   │
│   ┌─────────────────────────────────────────┐    ┌─────────────────────────────────────────────┐ │
│   │         homelab-core (Public)           │    │         homelab-config (Private)            │ │
│   │                                         │    │                                             │ │
│   │   modules/                              │    │   environments/                             │ │
│   │   ├── talos-cluster/                    │    │   ├── prod/                                 │ │
│   │   │   ├── main.tf                       │    │   │   ├── main.tf ──────┐                  │ │
│   │   │   ├── variables.tf                  │◀───│   │   ├── terraform.tfvars                 │ │
│   │   │   └── outputs.tf                    │    │   │   └── values/                          │ │
│   │   │                                     │    │   │       ├── argocd.yaml                  │ │
│   │   ├── opnsense/                         │    │   │       ├── harbor.yaml                  │ │
│   │   │   └── ...                           │    │   │       └── ...                          │ │
│   │   │                                     │    │   │                                         │ │
│   │   └── kubernetes-base/                  │    │   └── dev/                                  │ │
│   │       └── ...                           │    │       ├── main.tf ──────┘                  │ │
│   │                                         │    │       ├── terraform.tfvars   (uses same    │ │
│   │   charts/                               │    │       └── values/            modules)      │ │
│   │   ├── platform/                         │    │                                             │ │
│   │   │   ├── argocd/                       │    │   apps/                                     │ │
│   │   │   ├── cilium/                       │◀───│   ├── prod/                                 │ │
│   │   │   ├── longhorn/                     │    │   │   ├── race-telemetry/                  │ │
│   │   │   ├── velero/                       │    │   │   ├── jellyfin/                        │ │
│   │   │   └── grafana-stack/                │    │   │   └── ...                              │ │
│   │   │                                     │    │   │                                         │ │
│   │   └── apps/                             │    │   └── dev/                                  │ │
│   │       ├── harbor/                       │    │       ├── race-telemetry/                  │ │
│   │       ├── forgejo/                      │    │       └── ...                              │ │
│   │       └── jellyfin/                     │    │                                             │ │
│   │                                         │    │   secrets/ (references only, actual         │ │
│   │   defaults.yaml (toggle apps)           │    │            values in AWS Secrets Manager)  │ │
│   │   ├── cilium: true                      │    │                                             │ │
│   │   ├── longhorn: true                    │    │                                             │ │
│   │   ├── velero: true                      │    │                                             │ │
│   │   └── grafana: true                     │    │                                             │ │
│   │                                         │    │                                             │ │
│   └─────────────────────────────────────────┘    └─────────────────────────────────────────────┘ │
│                                                                                                   │
│   ┌──────────────────────────────────────────────────────────────────────────────────────────┐   │
│   │                                    GITOPS FLOW                                            │   │
│   │                                                                                           │   │
│   │   Developer ───▶ Push to homelab-config ───▶ Forgejo ───▶ Mirror to GitHub              │   │
│   │                         │                                                                │   │
│   │                         ▼                                                                │   │
│   │                  Forgejo Actions                                                         │   │
│   │                         │                                                                │   │
│   │         ┌───────────────┼───────────────┐                                               │   │
│   │         ▼               ▼               ▼                                               │   │
│   │   Terraform Plan   Build Images   Lint/Test                                             │   │
│   │         │               │                                                               │   │
│   │         ▼               ▼                                                               │   │
│   │   Terraform Apply  Push to Harbor                                                       │   │
│   │   (if approved)         │                                                               │   │
│   │                         ▼                                                               │   │
│   │                  ArgoCD detects                                                         │   │
│   │                  manifest changes                                                       │   │
│   │                         │                                                               │   │
│   │         ┌───────────────┴───────────────┐                                               │   │
│   │         ▼                               ▼                                               │   │
│   │   Prod ArgoCD                     Dev ArgoCD                                            │   │
│   │   syncs prod apps                 syncs dev apps                                        │   │
│   │                                                                                          │   │
│   └──────────────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                                   │
└──────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Infrastructure Components

### Proxmox Host
- Hypervisor for all VMs
- Storage: local-lvm for VM disks

### OPNSense VM (To Be Created)
- Manages VLANs and inter-VLAN routing
- Firewall rules between environments
- DHCP for each VLAN
- DNS resolution

### Kubernetes Clusters
- **Prod Cluster**: Production workloads, client-facing
- **Dev Cluster**: Development and testing

---

## Backup Strategy

### Longhorn (Local)
- Scheduled snapshots
- Replica count: 2+ for prod, 1 for dev
- Fast recovery from disk failures

### Velero (Remote)
- Cluster state backups to AWS S3
- Scheduled backups (daily for prod, weekly for dev)
- Disaster recovery from complete failure
- Namespace-level restores possible

### AWS Integration
- **S3**: Velero backups, Longhorn backup target
- **Secrets Manager**: Sensitive configuration (API keys, passwords)
- **DynamoDB**: Terraform state locking (already in use)

---

## Implementation Plan

### Phase 0: Code Review & Cleanup ✅ COMPLETE
**Goal**: Review ChatGPT-generated code, understand patterns, identify what to keep/refactor
- [x] Review existing Terraform code quality and patterns
- [x] Review Ansible playbooks and roles
- [x] Review ArgoCD application manifests
- [x] Document findings and cleanup tasks
- [x] Identify breaking changes for the restructure

**Fixes Applied:**
- Fixed worker 2 IP bug in cluster.tf (was pointing to worker_01 IP)
- Added worker-02 to VM definitions with dynamic IP assignment
- Fixed cluster health check to include both workers
- Fixed empty argocd.yaml.j2 template with sensible defaults
- Removed duplicate lognhorn.yaml.j2 (typo)
- Fixed install-apps.yml to include Longhorn apps
- Converted ns-longhorn from file to directory structure
- Created terraform-apply.yml workflow with confirmation
- Renamed/fixed terraform-destroy.yml with approval gates

### Phase 1: Repository Restructure ✅ COMPLETE
**Goal**: Transform this repo into homelab-core with reusable modules

#### 1.1 Terraform Module Structure
- [x] Create `modules/talos-cluster/` - provisions Talos K8s cluster on Proxmox
- [ ] Create `modules/opnsense/` - provisions and configures OPNSense VM (Phase 2)
- [x] Create `modules/proxmox-vm/` - generic VM provisioning module
- [x] Create `modules/aws-backend/` - S3 + DynamoDB + Secrets Manager setup
- [x] Define clear inputs/outputs for each module
- [x] Add validation and sensible defaults

#### 1.2 Kubernetes Base Charts
- [x] Organize charts in `charts/platform/` (cilium, longhorn, argocd, velero)
- [x] Organize charts in `charts/apps/` (harbor, forgejo, jellyfin, grafana-stack, zitadel)
- [x] Create `defaults.yaml` for toggling default applications
- [x] Ensure all charts use values files pattern
- [x] Pin Helm chart versions for stability (Cilium 1.16.5, Longhorn 1.7.2)

#### 1.3 Create homelab-config Template
- [x] Define `environments/prod/` structure
- [x] Define `environments/dev/` structure
- [x] Create example `terraform.tfvars` for each environment
- [ ] Create `apps/` directory structure for environment-specific apps (when needed)
- [ ] Document how to consume homelab-core modules (README to be added)

### Phase 2: Network Infrastructure
**Goal**: Set up VLAN-segmented network with OPNSense

#### 2.1 OPNSense VM
- [ ] Create Terraform module for OPNSense VM provisioning
- [ ] Configure dual NICs (WAN + LAN trunk)
- [ ] Document manual OPNSense initial setup steps
- [ ] Create OPNSense configuration export/backup

#### 2.2 VLAN Configuration
- [ ] Document NETGEAR GS308EP VLAN configuration steps
- [ ] Configure VLAN 10 (Prod: 10.10.10.0/16)
- [ ] Configure VLAN 11 (Dev: 10.11.10.0/16)
- [ ] Configure trunk ports for OPNSense and Proxmox
- [ ] Test inter-VLAN routing through OPNSense

#### 2.3 Proxmox Network
- [ ] Create VLAN-aware bridge in Proxmox (vmbr0 with VLAN tagging)
- [ ] Update VM configurations to use VLAN tags
- [ ] Test VM connectivity on each VLAN

### Phase 3: Multi-Environment Clusters
**Goal**: Deploy separate Kubernetes clusters for prod and dev

#### 3.1 Prod Cluster
- [ ] Update Terraform to use new IP scheme (10.10.10.x)
- [ ] Deploy control plane: prod-cp-01 (10.10.10.10)
- [ ] Deploy workers: prod-wk-01 (10.10.10.11), prod-wk-02 (10.10.10.12)
- [ ] Configure Longhorn with appropriate replica count (2+)
- [ ] Deploy ArgoCD pointing to homelab-config/apps/prod

#### 3.2 Dev Cluster
- [ ] Deploy control plane: dev-cp-01 (10.11.10.10)
- [ ] Deploy worker: dev-wk-01 (10.11.10.11)
- [ ] Configure Longhorn with replica count 1
- [ ] Deploy ArgoCD pointing to homelab-config/apps/dev

#### 3.3 Separate Terraform State
- [ ] Configure separate S3 paths for prod/dev state
- [ ] Ensure state isolation between environments

### Phase 4: Platform Services
**Goal**: Deploy core platform services on prod cluster

#### 4.1 Forgejo + Actions
- [ ] Deploy Forgejo with Helm
- [ ] Configure Forgejo Actions runners
- [ ] Set up GitHub mirroring for repos
- [ ] Create CI pipeline templates

#### 4.2 Harbor Registry (Per Environment)
- [ ] Deploy Harbor on prod cluster
- [ ] Deploy Harbor on dev cluster
- [ ] Configure storage (Longhorn PVC) for each
- [ ] Set up vulnerability scanning
- [ ] No cross-environment replication (isolated)

#### 4.3 External Secrets
- [ ] Deploy External Secrets Operator
- [ ] Configure AWS Secrets Manager backend
- [ ] Create SecretStore resources
- [ ] Migrate sensitive values to AWS Secrets Manager

#### 4.4 Zitadel (Identity Provider)
- [ ] Deploy Zitadel with Helm
- [ ] Configure PostgreSQL backend (or use embedded)
- [ ] Set up OAuth applications for each service
- [ ] Integrate with Forgejo, Harbor, Grafana, etc.
- [ ] Configure SSO across all services

#### 4.5 Cloudflare Tunnel
- [ ] Deploy cloudflared on prod cluster
- [ ] Deploy cloudflared on dev cluster (separate tunnel)
- [ ] Configure tunnel routes for public services
- [ ] Set up Cloudflare Access policies (integrate with Zitadel)
- [ ] No port forwarding or public IPs required

### Phase 5: Backup & Disaster Recovery
**Goal**: Implement comprehensive backup strategy

#### 5.1 Longhorn Backups
- [ ] Configure S3 backup target for Longhorn
- [ ] Set up recurring backup schedules (hourly snapshots, daily backups)
- [ ] Configure backup retention policies
- [ ] Test volume restore from S3

#### 5.2 Velero
- [ ] Deploy Velero with AWS plugin
- [ ] Configure S3 bucket for cluster backups
- [ ] Set up scheduled backups (daily prod, weekly dev)
- [ ] Create backup/restore runbooks
- [ ] Test full cluster restore procedure

#### 5.3 DR Documentation
- [ ] Document disk failure recovery procedure
- [ ] Document complete cluster rebuild procedure
- [ ] Create disaster recovery runbook
- [ ] Schedule regular DR drills

### Phase 6: Observability
**Goal**: Deploy monitoring and observability stack

#### 6.1 Grafana + InfluxDB
- [ ] Deploy InfluxDB for metrics storage
- [ ] Deploy Grafana with Helm
- [ ] Configure InfluxDB as data source
- [ ] Create dashboards for cluster health
- [ ] Create dashboards for application metrics

#### 6.2 Hubble Integration
- [ ] Enable Hubble UI in Cilium
- [ ] Configure Hubble metrics export to InfluxDB
- [ ] Create network observability dashboards

### Phase 7: Applications
**Goal**: Deploy user-facing applications

#### 7.1 Jellyfin
- [ ] Deploy Jellyfin with Helm
- [ ] Configure persistent storage for media
- [ ] Set up Longhorn volume with backups
- [ ] Configure ingress/access

#### 7.2 Race Telemetry App
- [ ] Set up development environment in dev cluster
- [ ] Configure CI/CD pipeline in Forgejo
- [ ] Deploy production version to prod cluster
- [ ] Set up monitoring and alerting

### Phase 8: Future / When Ready
**Goal**: Deploy services pending hardware

#### 8.1 Ollama + Web UI (Requires GPU)
- [ ] Procure GPU for LLM inference
- [ ] Deploy Ollama with GPU passthrough
- [ ] Deploy Open WebUI or similar interface
- [ ] Configure access from devices

---

## Work Status

**Current Phase**: Phase 1 Complete, Ready for Phase 2 (Network Infrastructure)
**Last Updated**: January 2025

### Completed:
- Phase 0: Code Review & Cleanup (bugs fixed, workflows created)
- Phase 1: Repository Restructure (modules created, charts organized)

### Next Steps:
- Phase 2: Network Infrastructure (OPNSense, VLANs)
- Configure Proxmox servers with VLAN-aware bridges
- Deploy OPNSense VM for routing

---

## Commands Reference

```bash
# Terraform (prod environment)
cd environments/prod/terraform
terraform init
terraform plan
terraform apply

# Terraform (dev environment)
cd environments/dev/terraform
terraform init
terraform plan
terraform apply

# Ansible
cd core/ansible
ansible-playbook -i inventories/local/hosts.ini playbooks/install-argocd.yml
ansible-playbook -i inventories/local/hosts.ini playbooks/install-apps.yml

# Talos
talosctl --talosconfig=./talosconfig kubeconfig ./kubeconfig

# ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

---

## Files of Interest

### Core - Terraform Modules
- `core/terraform/modules/talos-cluster/` - Reusable Talos cluster module
- `core/terraform/modules/proxmox-vm/` - Generic VM provisioning module
- `core/terraform/modules/aws-backend/` - S3 + DynamoDB backend module

### Core - Charts & Manifests
- `core/charts/defaults.yaml` - Toggle default applications
- `core/charts/platform/` - Platform layer values (cilium, longhorn, argocd, velero)
- `core/charts/apps/` - Application layer values (harbor, forgejo, jellyfin, etc.)
- `core/manifests/namespaces/` - Namespace definitions

### Core - Ansible
- `core/ansible/playbooks/install-argocd.yml` - ArgoCD installation
- `core/ansible/playbooks/install-apps.yml` - Apply root app and wait for sync

### Environments
- `environments/prod/terraform/` - Production Terraform config
- `environments/prod/apps/` - ArgoCD Applications for prod
- `environments/dev/terraform/` - Development Terraform config
- `environments/dev/apps/` - ArgoCD Applications for dev

### Documentation
- `docs/` - Infrastructure and deployment documentation

---

## Notes

- Phase 0 and Phase 1 completed - code reviewed and restructured
- Repository reorganized into core/ (reusable) and environments/ (env-specific)
- Talos image management automated via core/scripts/
- Current network is flat (192.168.1.x) - VLAN segmentation is Phase 2
- Helm chart versions now pinned for stability
- Using Forgejo Actions for CI/CD (to be configured)

## Important Rules

- Update this CLAUDE.md file with any new decisions or context
- Keep diagrams and plans up to date as requirements evolve
- Test infrastructure changes in dev environment before prod
- Always use workflow_dispatch for destructive operations
