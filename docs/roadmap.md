# Implementation Roadmap

This document tracks the implementation phases for the homelab project.

**Current Phase**: Phase 2 (Network Infrastructure)
**Last Updated**: January 2026

---

## Phase Overview

| Phase | Name | Status |
|-------|------|--------|
| 0 | Code Review & Cleanup | ✅ Complete |
| 1 | Repository Restructure | ✅ Complete |
| 2 | Network Infrastructure | 🔄 In Progress |
| 3 | Multi-Environment Clusters | ⏳ Pending |
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

## Phase 2: Network Infrastructure 🔄 IN PROGRESS

**Goal**: Set up VLAN-segmented network with OPNSense

### 2.1 OPNSense VM
- [x] Create Terraform module for OPNSense VM provisioning (`core/terraform/modules/opnsense/`)
- [x] Create `environments/network/terraform/` for shared network infrastructure
- [x] Configure dual NICs (WAN + LAN trunk) in module
- [ ] Deploy OPNSense VM via Terraform
- [ ] Complete OPNSense installation wizard (manual)
- [ ] Document manual OPNSense initial setup steps
- [ ] Create OPNSense configuration export/backup

### 2.2 VLAN Configuration
- [x] Configure NETGEAR GS308EP switch with VLANs (done manually)
- [ ] Configure VLAN 10 (Prod: 10.10.10.0/16) in OPNSense
- [ ] Configure VLAN 11 (Dev: 10.11.10.0/16) in OPNSense
- [ ] Configure trunk ports for OPNSense and Proxmox
- [ ] Test inter-VLAN routing through OPNSense

### 2.3 Proxmox Network
- [x] Restore Proxmox host connectivity (vmbr0 reachable; bond0 active-backup with `enp11s0` primary)
- [ ] Create VLAN-aware bridge in Proxmox (vmbr0 with VLAN tagging)
- [ ] Configure switch port for Proxmox as VLAN trunk (native mgmt + tagged workload VLANs)
- [ ] Update VM configurations to use VLAN tags (per-VM NIC VLAN Tag)
- [ ] Test VM connectivity on each VLAN
- [ ] (Later) Add second NIC/cable and migrate to dedicated workloads bridge

---

## Phase 3: Multi-Environment Clusters

**Goal**: Deploy separate Kubernetes clusters for prod and dev

### 3.1 Prod Cluster
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

### 4.5 Cloudflare Tunnel
- [ ] Deploy cloudflared on prod cluster
- [ ] Deploy cloudflared on dev cluster (separate tunnel)
- [ ] Configure tunnel routes for public services
- [ ] Set up Cloudflare Access policies (integrate with Zitadel)
- [ ] No port forwarding or public IPs required

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
