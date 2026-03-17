# Velero Cluster-Level Backup to S3

**Priority**: Medium
**Labels**: backup, disaster-recovery, production
**Status**: Velero deployed, scheduled backups pending

## Problem

Longhorn backs up volume data, but not Kubernetes resources (Deployments, Services, ConfigMaps, Secrets, CRDs). If we lose the entire cluster, we need to restore both the K8s objects and the data.

## Goal

Deploy Velero for full cluster backup — K8s resources to Backblaze B2 (S3-compatible), volume data via Longhorn integration or restic.

## Implementation

1. ~~**Deploy Velero** via Helm on prod cluster~~ — DONE
2. ~~**Configure Backblaze B2 backend** (S3-compatible) for K8s resource backups~~ — DONE
3. **Configure Longhorn CSI snapshot integration** (or restic for volume data)
4. **Schedule backups**: daily prod
5. **Test full restore** to a clean cluster

## Acceptance Criteria

- [x] Velero deployed and backing up to Backblaze B2 (S3-compatible)
- [ ] Daily scheduled backups for prod namespace
- [ ] Full restore tested: nuke cluster, restore from Velero, verify everything works
- [ ] Backup retention: 30 daily, 12 weekly
- [ ] Disaster recovery runbook created
