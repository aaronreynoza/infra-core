# OPNSense Recovery — 2026-02-11

## Incident

Power outage caused OPNSense to lose all VLAN configuration. TrueNAS (VLAN 10) became unreachable.

## Root Cause

OPNSense was **never installed to disk**. It had been running from the live installer CD the entire time. The config was stored in RAM (tmpfs overlay), so any power loss or reboot wiped it completely.

Evidence:
- Root filesystem: `/dev/iso9660/OPNSENSE_INSTALL on / (cd9660, local, read-only)`
- `/conf` was a unionfs overlay on tmpfs
- `vtbd0` (32GB virtual disk) had no partition table
- Boot order was `ide3;virtio0` (CD-ROM first)

## Recovery Steps

### 1. Diagnosed the problem
- SSH'd into primary-host (`root@<MGMT_IP>`)
- Confirmed OPNSense (VM 100) and TrueNAS (VM 101) were running
- Found OPNSense at `<OPNSENSE_WAN_IP>` (vtnet1 DHCP) with factory-default config
- No VLAN interfaces, no DHCP on 10.10.x.x/10.11.x.x
- Backup files in `/conf/backup/` were all post-reset (no VLAN config)

### 2. Found local backup
- Located config exports in `~/Downloads/`:
  - `config-OPNsense.localdomain-20260201013943.xml` (Feb 1)
  - `config-OPNsense.localdomain-20260205024559.xml` (Feb 5) ← used this one
- Verified it contained VLAN config (10.10.10.1, 10.11.10.1, DHCP ranges)

### 3. Fixed bridge mismatch
The backup config expected:
- `vtnet0` = LAN trunk (VLANs)
- `vtnet1` = WAN (DHCP)

But the Proxmox VM had bridges swapped after a prior Terraform change:
- `net0` (vtnet0) → `vmbr1` (WAN bridge)
- `net1` (vtnet1) → `vmbr0` (LAN bridge)

Fix applied from primary-host:
```bash
qm stop 100
qm set 100 --net0 virtio=<MAC_ADDR_LAN>,bridge=vmbr0,firewall=0 \
            --net1 virtio=<MAC_ADDR_WAN>,bridge=vmbr1,firewall=0
qm start 100
```

### 4. Installed OPNSense to disk
- Ran `opnsense-installer` from the live CD console
- Selected ZFS → Stripe → `vtbd0`
- Completed installation

### 5. Changed boot order to disk-only
```bash
qm stop 100
qm set 100 --boot order=virtio0
qm start 100
```

### 6. Restored config on disk install
Served the backup from primary-host via HTTP and fetched from OPNSense console:
```bash
# On primary-host:
cd /tmp && python3 -m http.server 8888 &

# On OPNSense console (option 8 → Shell):
fetch -o /conf/config.xml http://<MGMT_IP>:8888/opnsense-restore.xml
reboot
```

### 7. Verified
- PROD (vlan0.10): `10.10.10.1/16` — up
- DEV (vlan0.11): `10.11.10.1/16` — up
- TrueNAS: `10.10.10.50` — reachable from OPNSense
- Config persists across reboot

## Key Learnings

1. **Always install OPNSense to disk** — the live CD stores config in RAM only
2. **Export config backups outside the VM** — the user's `~/Downloads` backup saved this recovery
3. **`rc.reload_all` applies config without reboot** — useful when OPNSense overwrites config on boot (live CD issue)
4. **Bridge assignments must match config** — if Terraform changes NIC→bridge mapping, the OPNSense config's interface assignments (vtnet0/vtnet1) must align
5. **Never edit config.xml directly** — always use Web UI or restore from backup

## Known Issues After Recovery

- **LAN interface has no IP**: Backup config had `<ISP_ROUTER_IP>/24` on vtnet0 (LAN), which conflicts with the ISP router at the same IP. Needs to be disabled or reassigned via Web UI.
- **SSH not accessible from management network**: SSH was enabled in the backup config but only on LAN, which has no working IP. Enable SSH on PROD or WAN interface if remote management is needed.
- **Terraform state drift**: Boot order and bridge assignments were changed via `qm` commands, not Terraform. The Terraform module (`core/terraform/modules/opnsense/`) needs to be updated to match:
  - `net0` → `vmbr0` (LAN trunk)
  - `net1` → `vmbr1` (WAN)
  - Boot order → `virtio0`

## VM Configuration (Post-Recovery)

```
VM ID: 100
Name: opnsense
Status: running
Boot order: virtio0 (disk only)
net0: virtio=<MAC_ADDR_LAN>,bridge=vmbr0  (LAN trunk, VLANs)
net1: virtio=<MAC_ADDR_WAN>,bridge=vmbr1  (WAN, DHCP)
Disk: vtbd0 (32GB, ZFS)
```

## Backup Config Used

```
Source: ~/Downloads/config-OPNsense.localdomain-20260205024559.xml
Size: 38647 bytes
Date: 2026-02-05
Contents: WAN (DHCP), LAN (<ISP_ROUTER_IP>/24), VLAN 10 (10.10.10.1/16), VLAN 11 (10.11.10.1/16)
DHCP: PROD 10.10.10.50-200, DEV 10.11.10.50-200
```
