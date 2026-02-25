# OPNSense HA with CARP Failover

**Priority**: High
**Labels**: networking, high-availability, resilience
**Depends on**: OPNSense running on primary-host (already done)

## Problem

OPNSense runs as a single VM on primary-host. If primary-host goes down, all VLAN routing dies — prod and dev clusters lose network connectivity entirely. This is the single biggest point of failure in the homelab.

## Goal

Deploy a second OPNSense VM on secondary-host as a hot standby using CARP (Common Address Redundancy Protocol). If the primary fails, the secondary takes over automatically with zero manual intervention.

## How CARP Works

- Both OPNSense instances share a **Virtual IP (VIP)** on each interface
- Primary actively responds to traffic, secondary monitors via heartbeat
- If primary goes silent, secondary promotes itself (typically <5 seconds)
- All clients use the VIP as their gateway — failover is transparent

## Architecture

```
         primary-host                              secondary-host
    ┌─────────────────┐               ┌─────────────────┐
    │  OPNSense       │               │  OPNSense       │
    │  (CARP PRIMARY) │◄── heartbeat──│  (CARP BACKUP)  │
    │                 │    (pfsync)    │                 │
    │  WAN: DHCP      │               │  WAN: DHCP      │
    │  PROD: 10.10.10.2│              │  PROD: 10.10.10.3│
    │  DEV:  10.11.10.2│              │  DEV:  10.11.10.3│
    └────────┬────────┘               └────────┬────────┘
             │                                  │
             └──────────┬───────────────────────┘
                        │
                   Virtual IPs (CARP)
                   PROD: 10.10.10.1 (gateway)
                   DEV:  10.11.10.1 (gateway)
```

## Implementation Steps

1. **Deploy second OPNSense VM on secondary-host**
   - Use existing Terraform module (`core/terraform/modules/opnsense/`)
   - VLAN-aware NIC on vmbr0 (secondary-host already has VLAN-aware bridge)
   - WAN NIC (need to check secondary-host WAN connectivity)

2. **Configure pfsync interface**
   - Dedicated VLAN or interface for state sync between primary/secondary
   - Syncs firewall state table so active connections survive failover

3. **Configure CARP VIPs on primary**
   - WAN VIP (if needed)
   - PROD VIP: 10.10.10.1/16
   - DEV VIP: 10.11.10.1/16
   - Set primary to CARP priority 200 (higher = preferred)

4. **Configure CARP on secondary**
   - Same VIPs, CARP priority 100 (lower = backup)
   - Same firewall rules, DHCP config (synced via config sync)

5. **Enable config sync (XMLRPC)**
   - Primary pushes firewall rules, DHCP, NAT config to secondary
   - Only config changes on primary — secondary mirrors automatically

6. **Update DHCP to use VIPs as gateway**
   - Clients already use 10.10.10.1 / 10.11.10.1 — these become CARP VIPs
   - No client changes needed

7. **Test failover**
   - Shut down primary OPNSense
   - Verify secondary takes over VIPs
   - Verify VLAN clients maintain internet access
   - Verify failback when primary comes back

## Proxmox Requirement

secondary-host needs WAN connectivity. Check if secondary-host has a second NIC or bridge for WAN, or if WAN can be trunked on the same bridge.

## References

- [OPNSense CARP Documentation](https://docs.opnsense.org/manual/hacarp.html)
- [OPNSense High Availability Setup](https://docs.opnsense.org/manual/how-tos/carp.html)

## Acceptance Criteria

- [ ] Second OPNSense VM running on secondary-host
- [ ] CARP VIPs configured on PROD and DEV interfaces
- [ ] pfsync state synchronization working
- [ ] Config sync (XMLRPC) working — changes on primary auto-replicate
- [ ] Failover tested: shut down primary, secondary takes over <10s
- [ ] Failback tested: primary returns, resumes as primary
- [ ] No client configuration changes needed
