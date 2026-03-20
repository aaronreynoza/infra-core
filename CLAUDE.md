# Homelab Project - Claude Context

## Project Purpose

1. **Showcase Skills** - Demonstrate DevOps/Platform Engineering capabilities
2. **Personal Use** - Host personal services (music, videos, media)
3. **Production Workload** - Host a race telemetry application with paying clients

---

## Environments

| Environment | Network | Purpose |
|-------------|---------|---------|
| **prod** | `10.10.10.0/16` (VLAN 10) | Client-facing apps, personal services |
| **dev** | `10.11.10.0/16` (VLAN 11) | Testing, can break freely |

Environments are **fully isolated** - no inter-VLAN communication.

---

## Current State

### Infrastructure
- **Proxmox Hosts**: Two nodes with VLAN-aware bridges (pve currently off)
- **OPNSense** (VM 100 on daytona):
  - WAN: DHCP on management network, SSH/HTTPS accessible
  - VLAN 10 (PROD): 10.10.10.1/16
  - VLAN 11 (DEV): 10.11.10.1/16
- **K8s**: Talos Linux v1.12.5, 1 CP + 2 workers on VLAN 10
- **Management VM** (VM 110): Debian 12, dual-homed, Ansible-configured, agent workspace (code-server + Claude Code Remote Control)

### Deployed Applications
- Cilium (CNI + Hubble + LB-IPAM)
- Longhorn (storage on SSD, replica: 1)
- ArgoCD (GitOps, sourcing from Forgejo)
- Forgejo, Harbor, Zitadel, Velero
- kube-prometheus-stack, Loki, Tempo, Mimir, OTel Collector, CNPG
- Zitadel SSO for ArgoCD, Forgejo, Grafana, Harbor
- Plane (project management, Plane MCP)
- CNPG (CloudNativePG operator + clusters)
- Open WebUI + Ollama + LiteLLM (LLM stack)
- Outline (documentation wiki)
- code-server on VM 110 (agent workspace)

### Git Architecture
- **Forgejo**: Source of truth (http://10.10.10.222:3000)
- **Two repos**: infra-core (public, reusable) + prod (private, env-specific)
- **GitHub**: Read-only mirror for portfolio visibility
- **ArgoCD**: Sources all apps from Forgejo prod repo `apps/` directory

### Service URLs (via Pangolin)
- All services at `*.aaron.reynoza.org` with auto TLS via Pangolin
- `forgejo.aaron.reynoza.org`, `harbor.aaron.reynoza.org`, `argocd.aaron.reynoza.org`, `grafana.aaron.reynoza.org`, `zitadel.aaron.reynoza.org`
- `plane.aaron.reynoza.org`, `code.aaron.reynoza.org`, `chat.aaron.reynoza.org`, `docs.aaron.reynoza.org`
- Pangolin resources managed via `scripts/pangolin/pangolin-resources.py`
- Newt (K8s pod) maintains WireGuard tunnel to Pangolin VPS

### External Services (Operational)
- **Pangolin** on Vultr VPS — deployed, Newt tunnel online, 5 public HTTPS resources
- **Control D** — "Aaron-Homelab" endpoint provisioned, PROD/DEV profiles created
- **Backblaze B2** — off-site backup for irreplaceable personal media

### Technology Stack
- **Virtualization**: Proxmox VE
- **Cluster OS**: Talos Linux
- **IaC**: Terraform (Proxmox provider)
- **Config Mgmt**: Ansible
- **GitOps**: ArgoCD (app-of-apps)
- **Remote State**: AWS S3 + DynamoDB
- **CI/CD**: Forgejo Actions (mgmt VM runner + K8s runner)

---

## Key Decisions

- **Cilium** as CNI (with Hubble observability)
- **Talos Linux** for immutable, secure cluster OS
- **Two-repo architecture**: infra-core (public) + prod (private)
- **Harbor** per environment (isolated registries)
- **Pangolin** on Vultr VPS for public access (replaces Cloudflare Tunnel — see ADR-003)
- **Control D + ctrld** for DNS management with per-VLAN policies (replaces Unbound on OPNsense)
- **Newt** (K8s pod) as Pangolin agent inside the cluster
- **Zitadel** for SSO/OAuth (Terraform-driven, zero manual steps)
- **Velero + Longhorn** for backup/DR to Backblaze B2
- **Backblaze B2** for off-site backups (not AWS S3)
- **Docs platform**: Outline (replacing MkDocs plan)

---

## Work Status

**Current Phase**: Observability Implemented, Proxmox Monitoring Pending
**Branch**: `main`

**Completed:**
- ~~Phase 1: Platform Apps~~ — All deployed and running via ArgoCD (2026-03-12)
- ~~Phase 3: Management VM (ID 110)~~ — Ansible-configured, dual-homed, quorum fix automated (2026-03-14)
- ~~Phase 6: Zitadel SSO~~ — Terraform-driven OIDC for ArgoCD, Forgejo, Grafana, Harbor (2026-03-14)
- ~~Phase 4: Forgejo migration + two-repo split~~ — Source of truth on Forgejo, repos renamed to infra-core/prod (2026-03-16)
- ~~Phase 5: CI/CD pipelines~~ — Mgmt VM runner + K8s runner, 4 workflow files (2026-03-17)
- ~~DNS fix~~ — Cilium k8sServiceHost broken by history rewrite (2026-03-17)
- ~~Repo split remediation~~ — All 14 Helm apps converted to multi-source, Harbor/root/tempo fixes (2026-03-17)
- ~~GitHub push mirrors~~ — Repos renamed, Forgejo push mirrors with sync_on_commit (2026-03-17)
- ~~Subdomain migration~~ — All services at `*.aaron.reynoza.org` via Pangolin, IaC script (2026-03-17)
- ~~Docs overhaul~~ — 18 files updated to match current state (2026-03-17)
- ~~LLM Stack~~ — Ollama + LiteLLM + Open WebUI + GPU passthrough (2026-03-17)
- ~~Plane deployment~~ — Project management with MCP integration (2026-03-18)
- ~~Agent Pipeline (SP1-SP3)~~ — Agent config, skill framework, orchestration pipeline (2026-03-19)
- ~~Agent Workspace~~ — code-server + Claude Code Remote Control on VM 110 (2026-03-19)
- ~~Harbor pull-through cache~~ — GHCR/Docker/K8s proxy caches (2026-03-19)
- ~~Observability~~ — Dashboards (6), alert rules (10), ServiceMonitors (9 apps), Grafana folders + Home page (2026-03-20)

**Next Tasks** (in order):
1. Proxmox monitoring (HOMELAB-108/109/110) — blocked on OPNSense firewall rule
2. Deploy Ntfy push notifications
4. Configure ControlD split-horizon
5. Media platform (*arr stack + Jellyfin + Navidrome)
6. Immich (Google Photos replacement)

See [docs/issues/backlog.md](docs/issues/backlog.md) and [docs/roadmap.md](docs/roadmap.md) for full roadmap. Tickets and documentation live in Plane (workspace: homelab, project: HOMELAB).

---

## Directory Structure

```
infra-core/                  # This repo (public, reusable)
├── core/                    # Reusable modules (open source ready)
│   ├── terraform/modules/   # talos-cluster, proxmox-vm, aws-backend
│   ├── terraform/live/      # Live terraform configs (parameterized)
│   ├── terraform/bootstrap/ # AWS backend bootstrap
│   ├── charts/              # platform/ and apps/ Helm values
│   ├── manifests/           # K8s manifests, ArgoCD apps
│   └── ansible/             # Playbooks & inventory
└── docs/                    # Documentation
    ├── configuration.md     # How to set up your environments/
    ├── CHANGELOG.md         # Progress log
    ├── architecture.md      # Network/app diagrams
    ├── roadmap.md           # Implementation phases
    ├── runbooks/            # Operational procedures
    └── decisions/           # Architecture Decision Records

prod/                        # Private repo (env-specific config + secrets)
├── apps/                    # ArgoCD Application manifests (sourced by ArgoCD)
├── values/                  # Environment-specific Helm values
├── secrets/                 # SOPS-encrypted secrets
└── ...
```

---

## Commands Reference

```bash
# Terraform (with external config from prod repo)
cd core/terraform/live/network
terraform init -backend-config=../../../../prod/backend.hcl
terraform plan -var-file=../../../../prod/terraform.tfvars

# Ansible
cd core/ansible
ansible-playbook -i inventories/local/hosts.ini playbooks/install-argocd.yml

# Talos
talosctl --talosconfig=./talosconfig kubeconfig ./kubeconfig

# ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

---

## Documentation Links

| Topic | File |
|-------|------|
| **Configuration guide** | [docs/configuration.md](docs/configuration.md) |
| Architecture diagrams | [docs/architecture.md](docs/architecture.md) |
| Implementation roadmap | [docs/roadmap.md](docs/roadmap.md) |
| Progress log | [docs/CHANGELOG.md](docs/CHANGELOG.md) |
| OPNSense setup | [docs/04-opnsense.md](docs/04-opnsense.md) |
| VLAN fix runbook | [docs/runbooks/vlan-opnsense-fix.md](docs/runbooks/vlan-opnsense-fix.md) |
| Terraform backend setup | [docs/runbooks/terraform-backend-setup.md](docs/runbooks/terraform-backend-setup.md) |
| Proxmox recovery | [docs/runbooks/proxmox-recovery.md](docs/runbooks/proxmox-recovery.md) |
| VLAN architecture decision | [docs/decisions/001-vlan-architecture.md](docs/decisions/001-vlan-architecture.md) |
| TrueNAS storage proposal | [docs/decisions/002-truenas-storage.md](docs/decisions/002-truenas-storage.md) |
| Pangolin + Control D architecture | [docs/decisions/003-pangolin-controld-architecture.md](docs/decisions/003-pangolin-controld-architecture.md) |
| Security hardening (future) | [docs/issues/006-security-hardening-ddos-protection.md](docs/issues/006-security-hardening-ddos-protection.md) |
| Homelab vs Cloud comparison | [docs/cloud-comparison.md](docs/cloud-comparison.md) |

---

## Important Rules

- **No local terraform state** - always use S3 backend (no single points of failure)
- **NEVER edit OPNSense config.xml directly** - always use Web UI (direct edits cause corruption on reboot)
- Test infrastructure changes in dev before prod
- Update docs with new decisions or context
- Use `workflow_dispatch` for destructive operations
- Keep this file lean - detailed info goes in docs/
