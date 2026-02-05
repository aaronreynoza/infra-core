# VLAN/OPNSense Fix Runbook

This runbook documents how to fix the VLAN configuration on OPNSense when interface mappings get confused after reboots, config restores, or changes.

## Problem Summary

OPNSense interface assignments (`vtnet0`/`vtnet1`) can get swapped after:
- Config restores
- Reboots
- Interface reassignment

This causes:
- NAT rules applying to wrong interface
- `<GATEWAY_IP>` (office router IP) assigned to OPNSense (routing loops)
- VLAN clients can ping gateway but cannot reach internet

## Prerequisites

- SSH access to Proxmox host at `<PROXMOX_IP>`
- Access to OPNSense console via Proxmox (VM 100)

---

## Step 1: Verify Proxmox Bridge/VM Wiring

```bash
ssh root@<PROXMOX_IP>

# Check bridge IPs
ip -br addr show vmbr0 vmbr1

# Check VM network config - get MAC addresses
qm config 100 | grep -E 'net[01]'
```

Expected output:
```
net0: virtio=BC:24:11:XX:XX:XX,bridge=vmbr1   # WAN bridge
net1: virtio=BC:24:11:YY:YY:YY,bridge=vmbr0   # LAN trunk bridge
```

**Record the MAC addresses:**
- `net0` (vmbr1/WAN) MAC: `________________`
- `net1` (vmbr0/LAN) MAC: `________________`

---

## Step 2: Map OPNSense vtnet to Proxmox net via MAC

Access OPNSense console (Proxmox UI → VM 100 → Console), select option `8` (Shell):

```bash
ifconfig vtnet0 | grep ether
ifconfig vtnet1 | grep ether
```

**Match MACs to determine correct assignment:**

| vtnet | MAC Address | Matches Proxmox | Should Be |
|-------|-------------|-----------------|-----------|
| vtnet0 | | net0/vmbr1? or net1/vmbr0? | WAN or LAN |
| vtnet1 | | net0/vmbr1? or net1/vmbr0? | WAN or LAN |

**Rule:**
- vtnet matching **net0/vmbr1** MAC → **WAN**
- vtnet matching **net1/vmbr0** MAC → **LAN**

---

## Step 3: Fix OPNSense Interface Assignments

From OPNSense console menu, select option `1` (Assign Interfaces):

1. LAGGs? → `N`
2. VLANs? → `N`
3. WAN → `vtnetX` (the one matching vmbr1/net0 MAC)
4. LAN → `vtnetY` (the one matching vmbr0/net1 MAC)
5. Optional interfaces → (press Enter to skip)
6. Confirm → `y`

Wait for configuration to complete.

---

## Step 4: Verify WAN Gets DHCP

After reconfiguration, the console should show:
```
WAN (vtnetX) -> v4/DHCP4: <WAN_DHCP_IP>/24
LAN (vtnetY) -> v4: <GATEWAY_IP>/24 (or no IP if VLAN-only)
```

**Important:** WAN should have a DHCP address from your upstream network, NOT the gateway IP itself

---

## Step 5: Configure VLANs on LAN Interface

Access OPNSense web UI at `https://<WAN_IP>` (disable firewall if needed: `pfctl -d`).

Go to **Interfaces → Other Types → VLAN**:

| Device | Parent | VLAN Tag | Description |
|--------|--------|----------|-------------|
| vlan0.10 | vtnetY (LAN) | 10 | PROD |
| vlan0.11 | vtnetY (LAN) | 11 | DEV |

Go to **Interfaces → Assignments** and add:
- OPT1 → vlan0.10 (rename to PROD)
- OPT2 → vlan0.11 (rename to DEV)

Configure each interface:
- **PROD**: Static IPv4 `10.10.10.1/16`, Enable
- **DEV**: Static IPv4 `10.11.10.1/16`, Enable

---

## Step 6: Configure DHCP for VLANs

Go to **Services → DHCPv4**:

**PROD (OPT1):**
- Enable: ✓
- Range: `10.10.10.50` - `10.10.10.200`

**DEV (OPT2):**
- Enable: ✓
- Range: `10.11.10.50` - `10.11.10.200`

---

## Step 7: Add Firewall Rules for VLANs

Go to **Firewall → Rules → PROD**:
- Action: Pass
- Interface: PROD
- Source: PROD net
- Destination: any
- Description: Allow PROD to any

Repeat for **DEV**.

---

## Step 8: Enable pf (Required for NAT)

From OPNSense shell:
```bash
pfctl -e
```

Verify NAT is on WAN interface:
```bash
pfctl -sn | grep 'nat on'
```

Expected: `nat on vtnetX` where vtnetX is WAN (vmbr1).

---

## Step 9: Test with Throwaway VM

Create test container on Proxmox:
```bash
ssh root@<PROXMOX_IP>
pct create 999 local:vztmpl/alpine-3.21-default_20241217_amd64.tar.xz \
  --hostname test-vlan10 --memory 256 --storage local-lvm \
  --rootfs local-lvm:1 --net0 name=eth0,bridge=vmbr0,tag=10,ip=dhcp \
  --unprivileged 1 --password test123
pct start 999
```

Test connectivity:
```bash
# Get DHCP
pct exec 999 -- udhcpc -i eth0

# Check IP (should be 10.10.10.x)
pct exec 999 -- ip addr show eth0

# Test gateway
pct exec 999 -- ping -c 3 10.10.10.1

# Test internet (NAT working)
pct exec 999 -- ping -c 3 8.8.8.8

# Test DNS
pct exec 999 -- nslookup google.com
```

**Success criteria:**
- [x] DHCP gives 10.10.10.x address
- [x] Gateway (10.10.10.1) reachable
- [x] Internet (8.8.8.8) reachable
- [x] DNS resolves

Delete test VM:
```bash
pct stop 999 && pct destroy 999
```

---

## Troubleshooting

### NAT Not Working (can ping gateway, not internet)

```bash
# Check pf is enabled
pfctl -s info | head

# Check NAT rules exist
pfctl -sn | grep 'nat on'

# Verify NAT is on WAN interface (not LAN)
```

### TTL Exceeded / Routing Loops

OPNSense has `<GATEWAY_IP>` assigned somewhere:
```bash
ifconfig | grep "<GATEWAY_IP>"
```

Fix: Reassign interfaces (Step 3), ensure `<GATEWAY_IP>` is NOT on OPNSense.

### Can Ping Gateway But Not Internet (traceroute shows 127.0.0.1)

**Symptom**: `traceroute 8.8.8.8` shows `127.0.0.1` as first hop.

**Cause**: LAN interface has same IP as WAN gateway (e.g., LAN = <GATEWAY_IP>, WAN gateway = <GATEWAY_IP>).

Check routing table:
```bash
netstat -rn | grep "<GATEWAY_IP>"
```

If you see `<GATEWAY_IP> link#3 UHS lo0`, the gateway is being routed to loopback.

**Fix**: Change LAN IP to a non-conflicting address:
1. Menu option `2` (Set interface IP)
2. Select LAN
3. Set to `10.0.0.1/24` (or leave empty if VLAN-only)
4. No gateway, no DHCP on trunk interface

### Firewall Blocking

Temporarily disable:
```bash
pfctl -d
```

Add rules, then re-enable:
```bash
pfctl -e
```

---

## Quick Reference

| Item | Value |
|------|-------|
| Proxmox host | `<PROXMOX_IP>` |
| OPNSense VM ID | 100 |
| vmbr0 | LAN trunk, mgmt |
| vmbr1 | WAN |
| PROD VLAN | 10, 10.10.10.0/16 |
| DEV VLAN | 11, 10.11.10.0/16 |
| Office router | `<GATEWAY_IP>` |

---

**Last Updated:** 2026-02-01
