# Post-POC Issues

These files are draft GitHub issues for collaborators to pick up after the initial POC (TrueNAS + prod cluster deployment) is complete.

## Priority Order

| # | Issue | Priority | Why |
|---|-------|----------|-----|
| 001 | [OPNSense HA (CARP failover)](001-opnsense-ha-carp-failover.md) | **High** | Biggest SPOF — if primary-host dies, entire network goes down |
| 003 | [Longhorn cross-node replicas](003-longhorn-cross-node-replicas.md) | **High** | Production DB must survive node failure |
| 002 | [TrueNAS ZFS replication](002-truenas-zfs-replication.md) | Medium | Media data protection (not critical) |
| 004 | [Longhorn backup to TrueNAS](004-longhorn-backup-to-truenas.md) | Medium | Point-in-time recovery for volumes |
| 005 | [Velero cluster backup to S3](005-velero-cluster-backup.md) | Medium | Full disaster recovery |
| 006 | [Security hardening & DDoS protection](006-security-hardening-ddos-protection.md) | Medium | VPS is publicly exposed, paying clients need protection |
| 007 | [Multi-router VLAN access](007-multi-router-vlan-access.md) | Medium | Devices on room wifi can't reach VLAN services (needs router static routes) |

## Converting to GitHub Issues

```bash
# Example: create issues from these files
gh issue create --title "OPNSense HA with CARP Failover" --body-file docs/issues/001-opnsense-ha-carp-failover.md --label "networking,high-availability"
```
