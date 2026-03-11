# TrueNAS ZFS Replication to secondary-host

**Priority**: Medium
**Labels**: storage, backup, resilience
**Depends on**: TrueNAS deployed on primary-host (in progress)

## Problem

TrueNAS runs on primary-host with passthrough HDDs (ZFS mirror). If primary-host dies, all media/downloads/backups stored on TrueNAS are inaccessible. While this data isn't critical (movies, music, personal files), recovering from zero is painful.

## Goal

Set up hourly ZFS replication from TrueNAS on primary-host to secondary-host's `hdd-pool`, so if primary-host dies we can spin up TrueNAS on secondary-host with at most 1 hour of data loss.

## Architecture

```
   primary-host                              secondary-host
┌──────────────────┐              ┌──────────────────┐
│  TrueNAS VM      │    hourly    │  hdd-pool        │
│  sda+sdb mirror  │───ZFS send──▶│  sda+sdb mirror  │
│  tank/media      │              │  (receives snaps) │
│  tank/downloads  │              │                    │
│  tank/backups    │              │                    │
└──────────────────┘              └──────────────────┘
```

## Implementation Steps

1. **Configure SSH key auth from TrueNAS to secondary-host**
   - TrueNAS needs to SSH into secondary-host for ZFS send/receive

2. **Create replication task in TrueNAS UI**
   - Data Protection → Replication Tasks → Add
   - Source: `tank` (all datasets)
   - Destination: `hdd-pool` on secondary-host via SSH
   - Schedule: Hourly
   - Snapshot retention: Keep last 24 on source, 48 on destination

3. **Test replication**
   - Create test file on TrueNAS
   - Verify it appears on secondary-host's `hdd-pool` after next replication run

4. **Document failover procedure**
   - Destroy hdd-pool ZFS on primary-host? No, disks are passthrough
   - Create TrueNAS VM on secondary-host
   - Import replicated pool
   - Update NFS PV IPs in Kubernetes
   - Verify pods can mount NFS shares

## Failover Runbook (to be created)

`docs/runbooks/truenas-failover.md` — step-by-step for recovering TrueNAS on secondary-host.

## Acceptance Criteria

- [ ] ZFS replication running hourly from TrueNAS to secondary-host
- [ ] Replication monitoring/alerting (TrueNAS alerts on failure)
- [ ] Failover runbook documented and tested
- [ ] RPO (Recovery Point Objective): <= 1 hour
- [ ] RTO (Recovery Time Objective): <= 30 minutes manual failover
