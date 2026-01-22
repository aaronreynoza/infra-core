# Changelog

This document tracks significant milestones, work sessions, and progress on the homelab project.

---

## 2026-01-21 - Terraform Backend Setup & State Migration

### Summary
- Created S3 + DynamoDB backend for Terraform remote state
- Migrated bootstrap state from local to S3 (critical fix)
- Documented backend setup process to prevent single points of failure

### Details
- **AWS Resources Created**:
  - S3 bucket: `homelab-terraform-state-REDACTED_ACCOUNT_ID` (versioned, encrypted)
  - DynamoDB table: `homelab-terraform-locks` (state locking)
- **State Migration**:
  - Bootstrap initially used local state (chicken-and-egg problem)
  - Immediately migrated to S3 after backend resources created
  - Local state files removed to avoid confusion
- **Documentation**:
  - Created `docs/runbooks/terraform-backend-setup.md`
  - Documents why remote state is critical (no single points of failure)
  - Includes disaster recovery procedures

### Outcomes
- All terraform state now in S3 - survives local machine loss
- State locking prevents concurrent modification issues
- Clear runbook for future reference

---

## 2026-01-21 - OPNSense Terraform Module & Documentation Refactor

### Summary
- Created OPNSense Terraform module for firewall/router VM
- Refactored CLAUDE.md from 845 lines to 130 lines
- Moved detailed content to dedicated documentation files

### Details
- **OPNSense Module** (`core/terraform/modules/opnsense/`):
  - Downloads OPNSense ISO automatically
  - Creates VM with 2 NICs (WAN + LAN trunk)
  - Configures UEFI boot with CD-ROM for initial installation
- **Repository Structure**:
  - Code in `core/terraform/` (modules, bootstrap, live configs)
  - Values only in `environments/` (terraform.tfvars files)
- **Documentation Refactor**:
  - Created `docs/architecture.md` (network diagrams)
  - Created `docs/roadmap.md` (implementation phases)
  - Slimmed CLAUDE.md to essential context only

### Outcomes
- Ready to deploy OPNSense VM
- Clean separation: code in core, config in environments
- Documentation is organized and maintainable

---

## 2026-01-21 - Proxmox Recovery & Documentation Setup

### Summary
- Recovered Proxmox host from emergency mode (stale fstab + network misconfig)
- Established documentation structure for ongoing work

### Details
- **Incident**: Proxmox booted into systemd emergency mode
- **Root causes**: Stale `/etc/fstab` mount + wrong NIC names in `/etc/network/interfaces`
- **Resolution**: See [runbooks/proxmox-recovery.md](runbooks/proxmox-recovery.md)

### Outcomes
- Proxmox UI accessible at `https://REDACTED_IP:8006/`
- Bond0 active-backup with `enp11s0` primary
- ZFS pool `hdd-pool` mounted at `/mnt/hd`

---

## 2026-01-XX - Repository Restructure (Phase 1)

### Summary
- Transformed repository into modular core/environments structure
- Created reusable Terraform modules
- Organized Helm charts by layer (platform/apps)

### Details
- Created `core/terraform/modules/` with talos-cluster, proxmox-vm, aws-backend
- Organized charts into `core/charts/platform/` and `core/charts/apps/`
- Set up `environments/prod/` and `environments/dev/` structures
- Fixed several bugs in original ChatGPT-generated code

### Outcomes
- Repository ready for multi-environment deployments
- PR opened: `refactor/modular-structure` branch

---

## Template for Future Entries

```markdown
## YYYY-MM-DD - Title

### Summary
- Brief bullet points of what was accomplished

### Details
- More detailed explanation if needed
- Reference to related docs/runbooks/decisions

### Outcomes
- What's the end state after this work
```
