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
- **Management VM** (VM 110): Debian 12, dual-homed, Ansible-configured

### Deployed Applications
- Cilium (CNI + Hubble + LB-IPAM)
- Longhorn (storage on SSD, replica: 1)
- ArgoCD (GitOps, sourcing from Forgejo)
- Forgejo, Harbor, Zitadel, Velero
- kube-prometheus-stack, Loki, Tempo, Mimir, OTel Collector, CNPG
- Zitadel SSO for ArgoCD, Forgejo, Grafana, Harbor

### Git Architecture
- **Forgejo**: Source of truth (http://10.10.10.222:3000)
- **Two repos**: infra-core (public, reusable) + prod (private, env-specific)
- **GitHub**: Read-only mirror for portfolio visibility
- **ArgoCD**: Sources all apps from Forgejo prod repo `apps/` directory

### External Services (Operational)
- **Pangolin** on Vultr VPS — deployed and configured (shared with William)
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
- **Newt** (Talos system extension) as Pangolin agent inside the cluster
- **Zitadel** for SSO/OAuth (Terraform-driven, zero manual steps)
- **Velero + Longhorn** for backup/DR to Backblaze B2
- **Backblaze B2** for off-site backups (not AWS S3)

---

## Work Status

**Current Phase**: CI/CD Complete, Docs Site Next
**Branch**: `main`

**Completed:**
- ~~Phase 1: Platform Apps~~ — All deployed and running via ArgoCD (2026-03-12)
- ~~Phase 3: Management VM (ID 110)~~ — Ansible-configured, dual-homed, quorum fix automated (2026-03-14)
- ~~Phase 6: Zitadel SSO~~ — Terraform-driven OIDC for ArgoCD, Forgejo, Grafana, Harbor (2026-03-14)
- ~~Phase 4: Forgejo migration + two-repo split~~ — Source of truth on Forgejo, repos renamed to infra-core/prod (2026-03-16)
- ~~Phase 5: CI/CD pipelines~~ — Mgmt VM runner + K8s runner, 4 workflow files (2026-03-17)
- ~~DNS instability~~ — Fixed (Cilium k8sServiceHost broken by history rewrite) (2026-03-17)

**Next Tasks** (in order):
1. Set up GitHub push mirrors from Forgejo
2. MkDocs docs site (first publicly exposed app via Pangolin)
3. Observability tuning (dashboards, alerts)
4. Production readiness (Velero test restore, network policies)
5. Self-hosted media platform (*arr stack + Jellyfin + Navidrome)
6. Ollama + Open WebUI + LiteLLM + GPU passthrough
7. Uptime Kuma + public Grafana dashboard
8. Immich (Google Photos replacement)
9. Paperless-ngx (document OCR/management)

See [docs/issues/backlog.md](docs/issues/backlog.md) and `internal-docs/master-plan.md` for full roadmap.

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
