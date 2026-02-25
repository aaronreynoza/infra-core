# Implementation Roadmap

This document tracks the implementation phases for the homelab project.

**Current Phase**: Phase 3 (Multi-Environment Clusters)
**Last Updated**: 2026-02-09

---

## Phase Overview

| Phase | Name | Status |
|-------|------|--------|
| 0 | Code Review & Cleanup | ✅ Complete |
| 1 | Repository Restructure | ✅ Complete |
| 2 | Network & External Services | ✅ Complete |
| 2.5 | Storage Infrastructure | ⏳ Pending |
| 2.6 | Ops Maturity (guardrails, SOPs) | ⏳ Pending |
| 3 | Multi-Environment Clusters | 🔄 In Progress |
| 4 | Platform Services | ⏳ Pending |
| 5 | Backup & Disaster Recovery | ⏳ Pending |
| 6 | Observability | ⏳ Pending |
| 7 | Applications | ⏳ Pending |
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

## Phase 2.5: Storage Infrastructure ⏳ PENDING

**Goal**: Deploy TrueNAS for media storage, integrate with Kubernetes via NFS

**Decision**: See `docs/decisions/002-truenas-storage.md`

### 2.5.1 TrueNAS VM
- [ ] Deploy TrueNAS VM on Proxmox (VLAN 10)
- [ ] Allocate dedicated disk(s) for ZFS pool
- [ ] Create ZFS datasets (media, downloads, backups)
- [ ] Configure NFS shares for Kubernetes

### 2.5.2 Kubernetes Integration
- [ ] Create NFS PersistentVolumes for media/downloads
- [ ] Test NFS mounts from Kubernetes pod
- [ ] Document storage split (Longhorn vs NFS)

### 2.5.3 Mobile Access
- [ ] Configure TrueNAS mobile app or WebDAV
- [ ] Test file upload from phone to media library

---

## Phase 2.6: Ops Maturity ⏳ PENDING

**Goal**: Add engineering guardrails and operational documentation (inspired by William's infra)

### 2.6.1 Pre-commit Hooks
- [ ] Add `.pre-commit-config.yaml` with terraform_fmt, tflint, trivy
- [ ] Add yamllint, ansible-lint hooks
- [ ] Add secret detection (gitleaks or similar)
- [ ] Add no-commit-to-main protection

### 2.6.2 SOPs (Standard Operating Procedures)
- [ ] Create `docs/runbooks/secrets.md` (AWS Secrets Manager + ESO)
- [ ] Create `docs/runbooks/backups.md` (Longhorn + Velero)
- [ ] Create `docs/runbooks/upgrades.md` (Talos + K8s + platform components)
- [ ] Create `docs/runbooks/destroy.md` (safe teardown + rebuild)
- [ ] Create `docs/runbooks/troubleshooting.md` (common issues + fixes)

### 2.6.3 Checklists
- [ ] Create `docs/checklists/day0.md` (hypervisor/network/storage readiness)
- [ ] Create `docs/checklists/day1.md` (cluster bootstrap validation)

### 2.6.4 CI/CD Guardrails
- [ ] Add GitHub Actions for pre-commit checks
- [ ] Add Renovate for dependency updates
- [ ] Pin Terraform provider versions with `.terraform.lock.hcl`

---

## Phase 3: Multi-Environment Clusters

**Goal**: Deploy separate Kubernetes clusters for prod and dev

### 3.1 Prod Cluster
- [ ] Add Newt system extension to Talos image (Factory schematic)
- [ ] Update Terraform to use new IP scheme (10.10.10.x)
- [ ] Deploy control plane: prod-cp-01 (10.10.10.10), prod-cp-02 (10.10.10.11)
- [ ] Deploy workers: prod-wk-01 (10.10.10.20), prod-wk-02 (10.10.10.21)
- [ ] Configure Longhorn with appropriate replica count (2+)
- [ ] Deploy ArgoCD pointing to homelab-config/apps/prod

### 3.2 Dev Cluster
- [ ] Deploy control plane: dev-cp-01 (10.11.10.10), dev-cp-02 (10.11.10.11)
- [ ] Deploy workers: dev-wk-01 (10.11.10.20), dev-wk-02 (10.11.10.21)
- [ ] Configure Longhorn with replica count 1
- [ ] Deploy ArgoCD pointing to homelab-config/apps/dev

### 3.3 Separate Terraform State
- [ ] Configure separate S3 paths for prod/dev state
- [ ] Ensure state isolation between environments

### 3.4 Validate Pangolin Connectivity
- [ ] Verify Newt connects to Pangolin VPS via WireGuard
- [ ] Deploy first Pangolin resource to validate full traffic path
- [ ] Install ctrld on OPNsense and configure split-horizon DNS (see Phase 2.4)

---

## Phase 4: Platform Services

**Goal**: Deploy core platform services on prod cluster

### 4.1 Forgejo + Actions
- [ ] Deploy Forgejo with Helm
- [ ] Configure Forgejo Actions runners
- [ ] Set up GitHub mirroring for repos
- [ ] Create CI pipeline templates

### 4.2 Harbor Registry (Per Environment)
- [ ] Deploy Harbor on prod cluster
- [ ] Deploy Harbor on dev cluster
- [ ] Configure storage (Longhorn PVC) for each
- [ ] Set up vulnerability scanning
- [ ] No cross-environment replication (isolated)

### 4.3 External Secrets
- [ ] Deploy External Secrets Operator
- [ ] Configure AWS Secrets Manager backend
- [ ] Create SecretStore resources
- [ ] Migrate sensitive values to AWS Secrets Manager

### 4.4 Zitadel (Identity Provider)
- [ ] Deploy Zitadel with Helm
- [ ] Configure PostgreSQL backend (or use embedded)
- [ ] Set up OAuth applications for each service
- [ ] Integrate with Forgejo, Harbor, Grafana, etc.
- [ ] Configure SSO across all services

---

## Phase 5: Backup & Disaster Recovery

**Goal**: Implement comprehensive backup strategy

### 5.1 Longhorn Backups
- [ ] Configure S3 backup target for Longhorn
- [ ] Set up recurring backup schedules (hourly snapshots, daily backups)
- [ ] Configure backup retention policies
- [ ] Test volume restore from S3

### 5.2 Velero
- [ ] Deploy Velero with AWS plugin
- [ ] Configure S3 bucket for cluster backups
- [ ] Set up scheduled backups (daily prod, weekly dev)
- [ ] Create backup/restore runbooks
- [ ] Test full cluster restore procedure

### 5.3 DR Documentation
- [ ] Document disk failure recovery procedure
- [ ] Document complete cluster rebuild procedure
- [ ] Create disaster recovery runbook
- [ ] Schedule regular DR drills

---

## Phase 6: Observability

**Goal**: Deploy monitoring and observability stack

### 6.1 Grafana + InfluxDB
- [ ] Deploy InfluxDB for metrics storage
- [ ] Deploy Grafana with Helm
- [ ] Configure InfluxDB as data source
- [ ] Create dashboards for cluster health
- [ ] Create dashboards for application metrics

### 6.2 Hubble Integration
- [ ] Enable Hubble UI in Cilium
- [ ] Configure Hubble metrics export to InfluxDB
- [ ] Create network observability dashboards

---

## Phase 7: Applications

**Goal**: Deploy user-facing applications

### 7.1 Jellyfin
- [ ] Deploy Jellyfin with Helm
- [ ] Configure persistent storage for media
- [ ] Set up Longhorn volume with backups
- [ ] Configure ingress/access

### 7.2 Race Telemetry App
- [ ] Set up development environment in dev cluster
- [ ] Configure CI/CD pipeline in Forgejo
- [ ] Deploy production version to prod cluster
- [ ] Set up monitoring and alerting

---

## Phase 8: Future / When Ready

**Goal**: Deploy services pending hardware

### 8.1 Ollama + Web UI (Requires GPU)
- [ ] Procure GPU for LLM inference
- [ ] Deploy Ollama with GPU passthrough
- [ ] Deploy Open WebUI or similar interface
- [ ] Configure access from devices
