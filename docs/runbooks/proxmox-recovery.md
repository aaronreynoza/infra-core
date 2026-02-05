# Proxmox Recovery Runbook

**Date**: 2026-01-21
**Affected System**: Proxmox VE Host
**Severity**: Critical (host unresponsive)

---

## Incident Summary

Proxmox host booted into **systemd emergency mode** with the following symptoms:
- Error: `Timed out waiting for device /dev/disk/by-uuid/<UUID>`
- Failed dependency for `/mnt/hd.mount`
- Proxmox UI unreachable (even though `pveproxy` was listening on `:8006`)

---

## Root Causes

### 1. Stale fstab Mount
`/etc/fstab` contained an `ext4` mount for `/mnt/hd` pointing to UUID `94dc160b-b4ad-445d-b300-f9a36be601ee` - a device that no longer existed.

### 2. Bond/Bridge Misconfiguration
`/etc/network/interfaces` referenced incorrect NIC names:
- Config had: `emp11s0` / `emp3s0f2`
- Actual device: `enp11s0`

Result: `bond0` had **no active slave**, and `vmbr0` showed `NO-CARRIER/linkdown`.

---

## Resolution Steps

### Fix Storage (from emergency shell)

1. Remount root filesystem as read-write:
   ```bash
   mount -o remount,rw /
   ```

2. Remove/comment the stale `/mnt/hd` UUID line in `/etc/fstab`

3. Verify ZFS pool status:
   ```bash
   zpool status
   # Expected: pool `hdd-pool` (mirror on sda + sdb)

   zfs list
   ```

4. Set ZFS mountpoint to expected location:
   ```bash
   mkdir -p /mnt/hd
   zfs set mountpoint=/mnt/hd hdd-pool
   ```

5. Verify:
   ```bash
   zfs get mountpoint hdd-pool
   df -h | grep /mnt/hd
   ```

### Fix Network

1. Identify which physical NIC has link:
   ```bash
   ip -br link
   ethtool enp11s0 | egrep -i 'Link detected|Speed|Duplex'
   ```

2. Ensure bonding module is loaded:
   ```bash
   modprobe bonding
   ```

3. Fix `/etc/network/interfaces` - update to use correct device name: `enp11s0`

4. Restart networking:
   ```bash
   systemctl restart networking
   ```

5. Verify bond health:
   ```bash
   cat /proc/net/bonding/bond0
   # Expected: Currently Active Slave: enp11s0, MII Status: up

   ip route
   # Expected: default via <GATEWAY_IP> (no 'linkdown')
   ```

---

## Final State

- UI reachable at: `https://<PROXMOX_IP>:8006/`
- Network stack: `vmbr0` (management bridge) on top of `bond0` (mode: `active-backup`)
  - Primary: `enp11s0`
  - Standby: `mgmt0`

---

## Prevention / Hardening

1. **Non-critical mounts**: Use `nofail,x-systemd.device-timeout=10` for optional mounts in `/etc/fstab`

2. **Network config validation**: Before rebooting, verify NIC names match:
   ```bash
   ip -br link
   grep -E '^(auto|iface)' /etc/network/interfaces
   ```

3. **Configuration backup**: Keep a copy of working configs:
   - `/etc/fstab`
   - `/etc/network/interfaces`
   - ZFS pool configuration (`zpool get all hdd-pool`)

---

## Related Tasks

### Second RJ45 (for workload VLANs)

When the second cable is available:

1. Plug into port mapped to `mgmt0` and confirm link:
   ```bash
   ethtool mgmt0 | egrep -i 'Link detected|Speed|Duplex'
   ```

2. **Short term** (keep `bond0` active-backup):
   - Ensure both switch ports are in the **same L2/VLAN**
   - Do NOT enable LACP

3. **Later migration** (Option B - dedicated workload uplink):
   - Keep `vmbr0` for management (native/untagged VLAN)
   - Create `vmbr1` on second NIC as VLAN trunk for VM/K8s workloads
