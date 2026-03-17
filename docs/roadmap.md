# Implementation Roadmap

This document tracks the implementation phases for the homelab project.

**Current Phase**: MkDocs Docs Site (next publicly exposed app)
**Last Updated**: 2026-03-17

---

## Phase Overview

| Phase | Name | Status |
|-------|------|--------|
| 0 | Code Review & Cleanup | ✅ Complete |
| 1 | Repository Restructure | ✅ Complete |
| 2 | Network & External Services | ✅ Complete |
| 2.5 | Storage Infrastructure | ❌ Deferred |
| 2.6 | Ops Maturity (ArgoCD/GitOps) | ✅ Complete |
| 3 | Multi-Environment Clusters | ✅ Prod Complete (Dev deferred) |
| 4 | Platform Services | ✅ Complete |
| 5 | Backup & Disaster Recovery | ✅ Velero Deployed |
| 6 | Observability | ✅ Complete |
| 7 | Applications | ⏳ Pending (racing app deferred) |
| 8 | Future (GPU-dependent) | ⏳ Pending |

---

## Phase 0: Code Review & Cleanup ✅ COMPLETE

**Goal**: Review ChatGPT-generated code, understand patterns, identify what to keep/refactor

### Tasks
- [x] Review existing Terraform code quality and patterns
- [x] Review Ansible playbooks and roles
- [x] Review ArgoCD application manifests
- [x] Document findings and cleanup tasks
- [x] Identify breaking changes for the restructure

### Fixes Applied
- Fixed worker 2 IP bug in cluster.tf (was pointing to worker_01 IP)
- Added worker-02 to VM definitions with dynamic IP assignment
- Fixed cluster health check to include both workers
- Fixed empty argocd.yaml.j2 template with sensible defaults
- Removed duplicate lognhorn.yaml.j2 (typo)
- Fixed install-apps.yml to include Longhorn apps
- Converted ns-longhorn from file to directory structure
- Created terraform-apply.yml workflow with confirmation
- Renamed/fixed terraform-destroy.yml with approval gates

---

## Phase 1: Repository Restructure ✅ COMPLETE

**Goal**: Transform this repo into homelab-core with reusable modules

### 1.1 Terraform Module Structure
- [x] Create `modules/talos-cluster/` - provisions Talos K8s cluster on Proxmox
- [x] Create `modules/opnsense/` - provisions and configures OPNSense VM
- [x] Create `modules/proxmox-vm/` - generic VM provisioning module
- [x] Create `modules/aws-backend/` - S3 + DynamoDB + Secrets Manager setup
- [x] Define clear inputs/outputs for each module
- [x] Add validation and sensible defaults

### 1.2 Kubernetes Base Charts
- [x] Organize charts in `charts/platform/` (cilium, longhorn, argocd, velero)
- [x] Organize charts in `charts/apps/` (harbor, forgejo, jellyfin, grafana-stack, zitadel)
- [x] Create `defaults.yaml` for toggling default applications
- [x] Ensure all charts use values files pattern
- [x] Pin Helm chart versions for stability (Cilium 1.16.5, Longhorn 1.7.2)

### 1.3 Create homelab-config Template
- [x] Define `environments/prod/` structure
- [x] Define `environments/dev/` structure
- [x] Create example `terraform.tfvars` for each environment
- [ ] Create `apps/` directory structure for environment-specific apps (when needed)
- [ ] Document how to consume homelab-core modules (README to be added)

---

## Phase 2: Network & External Services ✅ COMPLETE

**Goal**: Set up VLAN-segmented network with OPNSense, deploy external services (Pangolin, Control D)

### 2.1 OPNSense VM
- [x] Create Terraform module for OPNSense VM provisioning (`core/terraform/modules/opnsense/`)
- [x] Create `environments/network/terraform/` for shared network infrastructure
- [x] Configure dual NICs (WAN + LAN trunk) in module
- [x] Deploy OPNSense VM via Terraform
- [x] Complete OPNSense installation wizard (manual)
- [x] Document manual OPNSense initial setup steps
- [x] Create OPNSense configuration export/backup (`/conf/backup/config-2026-02-04-vlans-dhcp-firewall.xml`)

### 2.2 VLAN Configuration
- [x] Configure NETGEAR GS308EP switch with VLANs (done manually)
- [x] Configure VLAN 10 (Prod: 10.10.10.0/16) in OPNSense
- [x] Configure VLAN 11 (Dev: 10.11.10.0/16) in OPNSense
- [x] Configure trunk ports for OPNSense and Proxmox
- [x] Test VLAN 10 outbound access (DHCP + NAT working, tested 2026-02-04)
- [ ] Test inter-VLAN isolation (PROD cannot reach DEV)
- [ ] Test VLAN 11 connectivity

### 2.3 Proxmox Network
- [x] Restore Proxmox host connectivity (vmbr0 reachable; bond0 active-backup with `enp11s0` primary)
- [x] Create VLAN-aware bridge in Proxmox (vmbr0 with VLAN tagging)
- [x] Configure switch port for Proxmox as VLAN trunk (native mgmt + tagged workload VLANs)
- [x] Validate VLAN 10 with a tagged test VM
- [x] Split WAN/LAN on primary host (dedicated NIC per bridge: vmbr0 LAN, vmbr1 WAN)
- [x] Move OPNSense WAN to `vmbr1` (Terraform updated, VM reconfigured)
- [x] Configure VLANs on LAN interface (vtnet0)
- [x] Validate VLAN 10 can reach internet (NAT working - tested 2026-02-04)

**Runbook**: See `docs/runbooks/vlan-opnsense-fix.md` for interface debugging steps

**Backup**: `/conf/backup/config-2026-02-04-vlans-dhcp-firewall.xml`

### 2.4 Pangolin + Control D (External Services)
- [x] Deploy Pangolin stack on Vultr VPS (Traefik, Gerbil, Badger, Pangolin)
- [x] Configure Control D profiles (PROD strict filtering, DEV permissive)
- [x] Provision "Aaron-Homelab" endpoint in Control D
- [x] Create homelab site in Pangolin dashboard
- [ ] Install ctrld on OPNsense — replace Unbound, configure per-VLAN DNS policies (after Phase 3 cluster testing)
- [ ] Configure split-horizon DNS — internal domains resolve locally via ctrld rules (after ctrld)

**Decision**: See `docs/decisions/003-pangolin-controld-architecture.md`

**Note**: ctrld installation on OPNsense is deferred until after Talos cluster deployment is validated (Phase 3).

---

## Phase 2.5: Storage Infrastructure ❌ PERMANENTLY DEFERRED

**Permanently deferred.** TrueNAS is not worth it for only 2 disks. Storage is handled by:
- **ZFS on Proxmox** (hdd-mirror pool: 2x 4TB WD Gold, ~3.6TB)
- **Longhorn on SSD** for app PVCs (databases, configs, platform services)
- **NFS from Proxmox** for media stack (hdd-mirror/media-data dataset, exported to K8s)

**Decision**: See `docs/decisions/002-truenas-storage.md`

---

## Phase 2.6: Ops Maturity (ArgoCD/GitOps) ✅ COMPLETE

**Goal**: ArgoCD-driven GitOps, CI/CD guardrails, secrets management

- [x] ArgoCD deployed and sourcing apps from Forgejo
- [x] SOPS + age for secrets management (replaced AWS Secrets Manager + ESO)
- [x] Pre-commit hooks for secret detection
- [x] Forgejo Actions CI/CD (mgmt VM runner + K8s runner)
- [ ] Renovate for dependency updates (future)
- [ ] Additional runbooks (future)

---

## Phase 3: Multi-Environment Clusters ✅ PROD COMPLETE

**Goal**: Deploy separate Kubernetes clusters for prod and dev

### 3.1 Prod Cluster ✅
- [x] Add Newt as K8s pod (not system extension) for Pangolin connectivity
- [x] Update Terraform to use new IP scheme (10.10.10.x)
- [x] Deploy control plane: prod-cp-01 (REDACTED_K8S_API) — single CP, no HA
- [x] Deploy workers: prod-wk-01 (10.10.10.20), prod-wk-02 (10.10.10.21)
- [x] Configure Longhorn (replica: 1 currently, increase when more workers)
- [x] Deploy ArgoCD pointing to Forgejo prod repo apps/

### 3.2 Dev Cluster — Deferred
- Dev cluster deferred — single prod cluster sufficient for current needs

### 3.3 Separate Terraform State
- [x] Configure S3 backend for prod state
- Dev state deferred with dev cluster

### 3.4 Validate Pangolin Connectivity
- [x] Newt connects to Pangolin VPS via WireGuard
- [ ] Install ctrld on OPNsense and configure split-horizon DNS (see Phase 2.4)

---

## Phase 4: Platform Services ✅ COMPLETE

**Goal**: Deploy core platform services on prod cluster

### 4.1 Forgejo + Actions ✅
- [x] Deploy Forgejo with Helm
- [x] Configure Forgejo Actions runners (mgmt VM runner + K8s runner)
- [x] Forgejo is source of truth (GitHub becomes read-only mirror)
- [x] CI pipeline workflows created (lint, build, Terraform plan/apply)

### 4.2 Harbor Registry ✅
- [x] Deploy Harbor on prod cluster
- [x] Configure storage (Longhorn PVC)
- [x] Set up vulnerability scanning

### 4.3 Secrets Management ✅ (SOPS + age, not ESO)
- [x] SOPS + age encryption for all secrets
- [x] Pre-commit hook prevents unencrypted secrets
- [x] Terraform `carlpett/sops` provider v1.1.1
- ~~External Secrets Operator~~ — replaced by SOPS + age

### 4.4 Zitadel (Identity Provider) ✅
- [x] Deploy Zitadel with Helm (CNPG PostgreSQL backend)
- [x] Terraform-driven OIDC configuration (zero manual steps)
- [x] SSO working for ArgoCD, Forgejo, Grafana, Harbor

---

## Phase 5: Backup & Disaster Recovery ✅ VELERO DEPLOYED

**Goal**: Implement comprehensive backup strategy

### 5.1 Longhorn Backups
- [ ] Configure Backblaze B2 backup target for Longhorn
- [ ] Set up recurring backup schedules (hourly snapshots, daily backups)
- [ ] Configure backup retention policies
- [ ] Test volume restore from B2

### 5.2 Velero ✅
- [x] Deploy Velero with AWS plugin (S3-compatible)
- [x] Configure Backblaze B2 as backup target (not AWS S3)
- [ ] Set up scheduled backups
- [ ] Create backup/restore runbooks
- [ ] Test full cluster restore procedure

### 5.3 DR Documentation
- [ ] Document disk failure recovery procedure
- [ ] Document complete cluster rebuild procedure
- [ ] Create disaster recovery runbook
- [ ] Schedule regular DR drills

---

## Phase 6: Observability ✅ COMPLETE

**Goal**: Deploy monitoring and observability stack

### 6.1 Monitoring Stack ✅
- [x] Deploy kube-prometheus-stack (Prometheus + Grafana)
- [x] Deploy Loki (log aggregation)
- [x] Deploy Tempo (distributed tracing)
- [x] Deploy Mimir (long-term metrics storage)
- [x] Deploy OpenTelemetry Collector
- [x] Grafana SSO via Zitadel

### 6.2 Hubble Integration
- [x] Enable Hubble UI in Cilium
- [ ] Create network observability dashboards

---

## Phase 7: Applications

**Goal**: Deploy user-facing applications

### 7.1 Jellyfin
- [ ] Deploy Jellyfin with Helm
- [ ] Configure persistent storage for media
- [ ] Set up Longhorn volume with backups
- [ ] Configure ingress/access

### 7.2 Race Telemetry App — Deferred
- Racing app deferred — refining homelab infrastructure first

---

## Phase 8: Future / When Ready

**Goal**: Deploy services pending hardware

### 8.1 Ollama + Web UI (Requires GPU)
- [ ] Procure GPU for LLM inference
- [ ] Deploy Ollama with GPU passthrough
- [ ] Deploy Open WebUI or similar interface
- [ ] Configure access from devices
