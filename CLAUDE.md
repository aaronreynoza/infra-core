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
- **Proxmox Hosts**: Two nodes with VLAN-aware bridges
- **OPNSense** (VM on primary host):
  - WAN: DHCP on management network, SSH/HTTPS accessible
  - VLAN 10 (PROD): 10.10.10.1/16
  - VLAN 11 (DEV): 10.11.10.1/16
- **K8s**: Single cluster on Talos Linux v1.11.3 (to be migrated to VLANs)

### Deployed Applications
- Cilium (CNI + Hubble)
- Longhorn (storage, replica: 1)
- ArgoCD (GitOps)

### Technology Stack
- **Virtualization**: Proxmox VE
- **Cluster OS**: Talos Linux
- **IaC**: Terraform (Proxmox provider)
- **Config Mgmt**: Ansible
- **GitOps**: ArgoCD (app-of-apps)
- **Remote State**: AWS S3 + DynamoDB

---

## Key Decisions

- **Cilium** as CNI (with Hubble observability)
- **Talos Linux** for immutable, secure cluster OS
- **Two-repo architecture**: homelab (public) + environments (private)
- **Harbor** per environment (isolated registries)
- **Cloudflare Tunnel** for public access (no port forwarding)
- **Zitadel** for SSO/OAuth
- **Velero + Longhorn** for backup/DR to AWS S3

---

## Work Status

**Current Phase**: Phase 3 - Multi-Environment Clusters
**Branch**: `refactor/modular-structure`

**Phase 2 Complete** (2026-02-04):
- OPNSense VM deployed with WAN + LAN trunk NICs
- VLAN 10 (PROD): 10.10.10.1/16, DHCP REDACTED_VLAN_IP0-200 ✅
- VLAN 11 (DEV): 10.11.10.1/16, DHCP 10.11.10.50-200 ✅
- NAT working: VLAN clients can reach internet ✅
- Firewall working: SSH/HTTPS accessible ✅
- Inter-VLAN isolation: PROD/DEV cannot communicate ✅

**Next Tasks** (in order):
1. Deploy TrueNAS VM on PROD VLAN (see `docs/decisions/002-truenas-storage.md`)
2. Test Talos cluster deployment on PROD VLAN (10.10.10.0/16)
3. Phase 2.6: Ops maturity (pre-commit hooks, SOPs, checklists)

See [docs/roadmap.md](docs/roadmap.md) for full implementation plan.

---

## Directory Structure

```
homelab/                     # This repo (public, reusable)
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

environments/                # Private (gitignored, see docs/configuration.md)
├── network/                 # Shared network infra (OPNSense)
├── bootstrap/               # AWS backend bootstrap
├── prod/                    # Prod K8s cluster
└── dev/                     # Dev K8s cluster
```

---

## Commands Reference

```bash
# Terraform (with external config)
cd core/terraform/live/network
terraform init -backend-config=../../../../environments/network/backend.hcl
terraform plan -var-file=../../../../environments/network/terraform.tfvars

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

---

## Important Rules

- **No local terraform state** - always use S3 backend (no single points of failure)
- **NEVER edit OPNSense config.xml directly** - always use Web UI (direct edits cause corruption on reboot)
- Test infrastructure changes in dev before prod
- Update docs with new decisions or context
- Use `workflow_dispatch` for destructive operations
- Keep this file lean - detailed info goes in docs/
