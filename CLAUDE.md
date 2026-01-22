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
- **Proxmox Host**: `https://REDACTED_IP:8006/` (bond0 active-backup, ZFS pool at `/mnt/hd`)
- **Network**: Flat 192.168.1.x (VLAN segmentation pending - Phase 2)
- **K8s**: Single cluster on Talos Linux v1.11.3

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
- **Two-repo architecture**: homelab-core (public) + homelab-config (private)
- **Harbor** per environment (isolated registries)
- **Cloudflare Tunnel** for public access (no port forwarding)
- **Zitadel** for SSO/OAuth
- **Velero + Longhorn** for backup/DR to AWS S3

---

## Work Status

**Current Phase**: Phase 2 - Network Infrastructure (OPNSense, VLANs)
**Branch**: `refactor/modular-structure` (DO NOT MERGE until testing complete)

**Next Steps**:
1. Make Proxmox bridge VLAN-aware
2. Deploy OPNSense VM
3. Configure VLANs 10/11

See [docs/roadmap.md](docs/roadmap.md) for full implementation plan.

---

## Directory Structure

```
homelab/
├── core/                    # Reusable modules (open source ready)
│   ├── terraform/modules/   # talos-cluster, proxmox-vm, aws-backend
│   ├── charts/              # platform/ and apps/ Helm values
│   ├── manifests/           # K8s manifests, ArgoCD apps
│   └── ansible/             # Playbooks & inventory
├── environments/            # Environment-specific configs
│   ├── network/terraform/   # Shared network infra (OPNSense)
│   ├── prod/terraform/      # Prod K8s cluster
│   └── dev/terraform/       # Dev K8s cluster
└── docs/                    # Documentation
    ├── CHANGELOG.md         # Progress log
    ├── architecture.md      # Network/app diagrams
    ├── roadmap.md           # Implementation phases
    ├── runbooks/            # Operational procedures
    └── decisions/           # Architecture Decision Records
```

---

## Commands Reference

```bash
# Terraform
cd environments/prod/terraform && terraform init && terraform plan

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
| Architecture diagrams | [docs/architecture.md](docs/architecture.md) |
| Implementation roadmap | [docs/roadmap.md](docs/roadmap.md) |
| Progress log | [docs/CHANGELOG.md](docs/CHANGELOG.md) |
| OPNSense setup | [docs/04-opnsense.md](docs/04-opnsense.md) |
| Terraform backend setup | [docs/runbooks/terraform-backend-setup.md](docs/runbooks/terraform-backend-setup.md) |
| Proxmox recovery | [docs/runbooks/proxmox-recovery.md](docs/runbooks/proxmox-recovery.md) |
| VLAN architecture decision | [docs/decisions/001-vlan-architecture.md](docs/decisions/001-vlan-architecture.md) |

---

## Important Rules

- **No local terraform state** - always use S3 backend (no single points of failure)
- Test infrastructure changes in dev before prod
- Update docs with new decisions or context
- Use `workflow_dispatch` for destructive operations
- Keep this file lean - detailed info goes in docs/
