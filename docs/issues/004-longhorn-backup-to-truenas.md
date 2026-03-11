# Longhorn Backup Target on TrueNAS

**Priority**: Medium
**Labels**: storage, backup
**Depends on**: TrueNAS deployed, Longhorn running

## Problem

Longhorn replicas protect against node failure, but not against data corruption or accidental deletion. Need an external backup target for point-in-time recovery.

## Goal

Configure Longhorn to back up volume snapshots to TrueNAS via NFS. This gives us the ability to restore any production volume to a previous point in time.

## Implementation

1. **Create TrueNAS dataset**: `tank/backups/longhorn`
2. **Configure NFS share** for the backup dataset (restricted to K8s node IPs)
3. **Set Longhorn backup target**: `nfs://<TRUENAS_IP>:/mnt/tank/backups/longhorn`
4. **Create recurring backup jobs** for production PVCs (daily)
5. **Test restore** from backup to verify integrity

## Reference

William's implementation:
- Backup target: `nfs://<TRUENAS_IP>:/mnt/tank/backups/longhorn`
- Configured via Terraform `null_resource` patching the BackupTarget CRD

## Acceptance Criteria

- [ ] Longhorn backup target configured and healthy
- [ ] Recurring daily backups for all production PVCs
- [ ] Backup retention: 7 daily, 4 weekly
- [ ] Restore tested: create volume from backup, verify data
