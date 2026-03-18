# Management Network to VLAN Routing Fix

This runbook fixes bidirectional routing between the management network (REDACTED_MGMT_CIDR) and PROD/DEV VLANs (10.10.0.0/16, 10.11.0.0/16) through OPNSense.

## Problem

Devices on the management network (e.g., your Mac at <WORKSTATION_IP>) cannot reach VLAN devices (e.g., Talos node at REDACTED_K8S_API), even with a static route pointing 10.10.0.0/16 to OPNSense WAN (<OPNSENSE_WAN_IP>).

**Symptoms:**
- `ping REDACTED_K8S_API` from Mac: timeout
- `nc -zv REDACTED_K8S_API 6443`: "Can't assign requested address"
- OPNSense can route PROD to internet (NAT works), but not PROD to management network

## Root Cause

Three interacting issues:

1. **Outbound NAT rewrites return traffic**: Automatic outbound NAT translates ALL traffic from PROD exiting the WAN interface, including traffic to REDACTED_MGMT_CIDR. Return packets from REDACTED_K8S_API to <WORKSTATION_IP> get source-rewritten to <OPNSENSE_WAN_IP>, breaking end-to-end connectivity.

2. **reply-to directive causes asymmetric routing drops**: OPNSense adds `reply-to` to WAN rules by default, forcing replies out the originating interface. Routed traffic (WAN->PROD) has replies entering on PROD, which pf drops as not matching the WAN state table.

3. **Missing WAN firewall rules**: WAN rules may not explicitly allow traffic from management network to PROD/DEV subnets.

## Fix Steps

### Step 1: Exclude management traffic from Outbound NAT

**Firewall > NAT > Outbound**

1. Change mode to **Hybrid outbound NAT** (keeps auto rules for internet, allows manual overrides).
2. Add a manual rule at the top:

| Setting | Value |
|---------|-------|
| Interface | WAN |
| Protocol | any |
| Source | 10.10.0.0/16 (PROD net) |
| Destination | REDACTED_MGMT_CIDR |
| Translation | **Do not NAT** |
| Description | No NAT: PROD to management |

3. Add another rule for DEV:

| Setting | Value |
|---------|-------|
| Source | 10.11.0.0/16 (DEV net) |
| Destination | REDACTED_MGMT_CIDR |
| Translation | **Do not NAT** |
| Description | No NAT: DEV to management |

4. Click **Apply Changes**.

### Step 2: Disable reply-to on WAN

**Firewall > Settings > Advanced**

- Check **"Disable reply-to"** (globally), OR
- Edit each WAN pass rule individually and check "Disable reply-to" under Advanced Options

This prevents pf from dropping routed return traffic that enters on a different interface than the original request.

### Step 3: Verify WAN firewall rules

**Firewall > Rules > WAN**

Ensure these rules exist (in order):

| # | Action | Source | Destination | Description |
|---|--------|--------|-------------|-------------|
| 1 | Pass | * | This Firewall | Anti-lockout (auto) |
| 2 | Pass | WAN net | PROD net | Allow mgmt to PROD |
| 3 | Pass | WAN net | DEV net | Allow mgmt to DEV |

### Step 4: Static route on Mac

```bash
# Verify route exists
netstat -rn | grep 10.10

# Add if missing
sudo route add -net 10.10.0.0/16 <OPNSENSE_WAN_IP>
sudo route add -net 10.11.0.0/16 <OPNSENSE_WAN_IP>
```

### Step 5 (Optional): Static route on home router

On your home router (<HOME_ROUTER_IP>), if it supports static routes:

```
10.10.0.0/16 via <OPNSENSE_WAN_IP>
10.11.0.0/16 via <OPNSENSE_WAN_IP>
```

This allows any device on the management network to reach VLANs without per-device routes.

## Verification

```bash
# From Mac
ping REDACTED_K8S_API          # Should succeed
ping 10.10.10.1           # OPNSense PROD interface
nc -zv REDACTED_K8S_API 6443   # Talos API (should connect)

# From OPNSense shell (Diagnostics > Shell)
ping -S <OPNSENSE_WAN_IP> <WORKSTATION_IP>   # Ping Mac from WAN IP
```

## Packet flow after fix

```
Mac (<WORKSTATION_IP>)
  |
  | dst: REDACTED_K8S_API (static route via <OPNSENSE_WAN_IP>)
  v
Home Router (<HOME_ROUTER_IP>)
  |
  | forwards to <OPNSENSE_WAN_IP> (L2, same subnet)
  v
OPNSense WAN (<OPNSENSE_WAN_IP>)
  |
  | WAN rule: Pass WAN net -> PROD net
  | Routes to PROD interface (10.10.10.1)
  | NO NAT applied (hybrid rule excludes REDACTED_MGMT_CIDR)
  v
OPNSense PROD (10.10.10.1)
  |
  | Delivers to REDACTED_K8S_API
  v
Talos Node (REDACTED_K8S_API)
  |
  | Reply: dst <WORKSTATION_IP>, gateway 10.10.10.1
  v
OPNSense PROD (10.10.10.1)
  |
  | Routes to WAN (REDACTED_MGMT_CIDR is on WAN interface)
  | NO NAT (hybrid rule), NO reply-to drop
  v
OPNSense WAN (<OPNSENSE_WAN_IP>)
  |
  | Sends to <WORKSTATION_IP> (L2, same subnet)
  v
Mac (<WORKSTATION_IP>) -- reply received
```

## Known Limitation: Multi-Router Topology

This runbook assumes the client device is on the **same L2 segment** as OPNSense WAN (e.g., both connected to the office router). If the client is on a different router/AP (e.g., home router in another room), routing will fail because the home router doesn't know about the 10.10.0.0/16 and 10.11.0.0/16 subnets.

**Workaround:** Connect to the office router wifi when accessing VLAN services.

**Permanent fix:** Add static routes on the home router (<HOME_ROUTER_IP>). See [issue #007](../issues/007-multi-router-vlan-access.md).

---

**Last Updated:** 2026-03-11
