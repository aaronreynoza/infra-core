# Velero Cluster-Level Backup to S3

**Priority**: Medium
**Labels**: backup, disaster-recovery, production
**Depends on**: K8s cluster running, AWS S3 bucket

## Problem

Longhorn backs up volume data, but not Kubernetes resources (Deployments, Services, ConfigMaps, Secrets, CRDs). If we lose the entire cluster, we need to restore both the K8s objects and the data.

## Goal

Deploy Velero for full cluster backup — K8s resources to S3, volume data via Longhorn integration or restic.

## Implementation

1. **Deploy Velero** via Helm on prod cluster
2. **Configure S3 backend** for K8s resource backups
3. **Configure Longhorn CSI snapshot integration** (or restic for volume data)
4. **Schedule backups**: daily prod, weekly dev
5. **Test full restore** to a clean cluster

## Acceptance Criteria

- [ ] Velero deployed and backing up to S3
- [ ] Daily scheduled backups for prod namespace
- [ ] Full restore tested: nuke cluster, restore from Velero, verify everything works
- [ ] Backup retention: 30 daily, 12 weekly
- [ ] Disaster recovery runbook created
