# Post-Deployment Issues

These files are draft issues for tracking remaining work. The prod cluster (1 CP + 2 workers) is deployed and running with all platform services.

## Priority Order

| # | Issue | Priority | Status |
|---|-------|----------|--------|
| 001 | [OPNSense HA (CARP failover)](001-opnsense-ha-carp-failover.md) | **High** | Open |
| 003 | [Longhorn cross-node replicas](003-longhorn-cross-node-replicas.md) | **High** | Open |
| 002 | [TrueNAS ZFS replication](002-truenas-zfs-replication.md) | -- | **Deferred** (TrueNAS permanently deferred) |
| 004 | [Longhorn backup to TrueNAS](004-longhorn-backup-to-truenas.md) | -- | **Superseded** (Velero + Backblaze B2) |
| 005 | [Velero cluster backup](005-velero-cluster-backup.md) | Medium | Deployed (scheduled backups pending) |
| 006 | [Security hardening & DDoS protection](006-security-hardening-ddos-protection.md) | Medium | Open |
| 007 | [Multi-router VLAN access](007-multi-router-vlan-access.md) | Medium | Open |

## Converting to Forgejo Issues

```bash
# Use the Forgejo web UI or API to create issues from these files
# Forgejo issue tracker: http://10.10.10.222:3000/<org>/<repo>/issues
```
