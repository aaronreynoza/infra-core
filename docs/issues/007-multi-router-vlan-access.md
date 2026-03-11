# Multi-Router VLAN Access

**Priority:** Medium
**Labels:** networking, routing
**Blocked by:** Access to home (room) router admin panel

## Problem

Devices connected to the **office router** (same L2 segment as Proxmox/OPNSense) can reach PROD VLAN services (10.10.10.0/16) via a static route through OPNSense WAN (REDACTED_OPNSENSE_IP). However, devices connected to the **home (room) router** cannot, even with the same static route configured on the device.

## Network Topology

```
ISP
 |
Home Router (192.168.1.1) ← main router, DHCP server
 ├── Office Router (bridge/AP mode?) ← Proxmox hosts + OPNSense connected here
 │    ├── daytona (REDACTED_PVE_IP)
 │    ├── OPNSense WAN (REDACTED_OPNSENSE_IP, DHCP)
 │    └── Laptop (192.168.1.214 when on office wifi)
 └── Room wifi
      └── Laptop (192.168.1.184 when on room wifi)
```

## Root Cause Analysis

When the laptop is on the **office router**, it shares L2 with OPNSense WAN. The static route (`10.10.0.0/16 via REDACTED_OPNSENSE_IP`) works because:
1. Laptop sends packet to OPNSense directly (same L2 broadcast domain)
2. OPNSense forwards to PROD VLAN
3. Reply comes back to OPNSense, which sends it back to laptop (same L2)

When the laptop is on the **room wifi** (home router), even though it's on the same 192.168.1.0/24 subnet:
1. Laptop sends packet toward REDACTED_OPNSENSE_IP, but it goes through the **home router first**
2. The home router doesn't have a route for 10.10.10.0/16 — it may drop/misroute the return traffic
3. Even if the forward path works, the return path fails: OPNSense sends the reply to the laptop's IP, but the packet goes to the home router, which may not forward it correctly to the room wifi segment

The key issue is that **the home router doesn't know about the 10.10.0.0/16 and 10.11.0.0/16 subnets** and can't properly route return traffic.

## Observed Behavior

- OPNSense pflog0 showed packets arriving with source .214 (office IP) even when laptop was on room wifi (.184) — this was due to outbound NAT rewriting or stale state
- After clearing pf states (`pfctl -Fs`), packets still showed .214 source — indicating the Mac was somehow still associated with .214 in the routing path
- Switching back to office router (getting .214) immediately fixed connectivity

## Fix Options

### Option A: Static route on home router (Preferred)

Add static routes on the home router (192.168.1.1):

```
10.10.0.0/16 via REDACTED_OPNSENSE_IP
10.11.0.0/16 via REDACTED_OPNSENSE_IP
```

This tells the home router to forward VLAN-destined traffic to OPNSense, and properly route return traffic back to any device on the network.

**Requires:** Admin access to home router (currently unavailable)

### Option B: Connect all infrastructure to home router

Move Proxmox hosts and OPNSense to be directly connected to the home router instead of the office router. This puts everything on the same L2 segment.

**Downside:** Physical rewiring, may not be practical

### Option C: VPN/tunnel from room network

Set up a WireGuard or SSH tunnel from the laptop to OPNSense or a Proxmox host, and route VLAN traffic through the tunnel.

**Downside:** Extra complexity, but works without router access

### Option D: OPNSense as default gateway

Configure the home router to use OPNSense (REDACTED_OPNSENSE_IP) as its default gateway, or set up OPNSense as the DHCP server pushing itself as the gateway.

**Downside:** All traffic goes through OPNSense, single point of failure for internet

## Current Workaround

Connect laptop to the **office router** wifi when needing to access VLAN services. This provides direct L2 connectivity to OPNSense WAN.

## Prerequisites for Fix

1. Get admin access to home router (192.168.1.1)
2. Verify home router supports static routes
3. Also: set a DHCP reservation for OPNSense WAN to prevent IP changes (currently .245 via DHCP)

## Acceptance Criteria

- [ ] Any device on 192.168.1.0/24 (regardless of which router/AP) can ping REDACTED_K8S_API
- [ ] Any device can access K8s services (port 6443, HTTP/HTTPS)
- [ ] OPNSense WAN has a stable IP (DHCP reservation or static)

---

**Created:** 2026-03-11
**Status:** Blocked (need router access)
