# OPNSense Configuration

This document provides configuration guidance for OPNSense as the firewall/router for the homelab, using the dev and prod VLAN architecture.

## Overview

OPNSense acts as the central network gateway, managing:
- VLAN routing between prod and dev environments
- DHCP services per VLAN
- DNS resolution
- Firewall rules for network isolation
- NAT for internet access

## Status

**Phase 2 Complete** (2026-02-04)

All network infrastructure is working:
- OPNSense VM deployed via Terraform
- WAN on dedicated bridge (vmbr1), LAN trunk on vmbr0
- VLANs 10/11 with DHCP and NAT working
- Inter-VLAN isolation verified
- Firewall rules in place

**Backups**: Store OPNSense config.xml files in `docs/opnsense-backups/` (gitignored for security).

## Network Architecture

```
                         ┌─────────────────────────┐
                         │      ISP Router         │
                         │    (Bridge Mode)        │
                         └───────────┬─────────────┘
                                     │ WAN
                                     │
┌────────────────────────────────────┼────────────────────────────────────┐
│                              OPNSense VM                                │
│                                                                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐   │
│  │     WAN     │  │   VLAN 10   │  │   VLAN 11   │  │  Management │   │
│  │   (DHCP)    │  │    PROD     │  │     DEV     │  │  (Optional) │   │
│  │             │  │ 10.10.10.1  │  │ 10.11.10.1  │  │ <MGMT_IP>   │   │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘   │
│                           │                │                           │
└───────────────────────────┼────────────────┼───────────────────────────┘
                            │                │
                    ┌───────┴────────────────┴───────┐
                    │      Managed Switch            │
                    │   (VLAN Trunk to Proxmox)      │
                    └───────┬────────────────┬───────┘
                            │                │
                    ┌───────┴───────┐ ┌──────┴────────┐
                    │   VLAN 10     │ │    VLAN 11    │
                    │ Prod Cluster  │ │  Dev Cluster  │
                    └───────────────┘ └───────────────┘
```

## OPNSense VM Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 2 cores | 4 cores |
| Memory | 2 GB | 4 GB |
| Disk | 20 GB | 40 GB |
| NICs | 2 (WAN + LAN) | 2+ |

## Installation Steps

### 1. Create OPNSense VM in Proxmox

```bash
# Download OPNSense ISO
wget https://mirror.ams1.nl.leaseweb.net/opnsense/releases/24.7/OPNsense-24.7-dvd-amd64.iso

# Upload to Proxmox storage
# Or use the Proxmox UI: Datacenter > Storage > ISO Images > Upload
```

**VM Configuration:**
- OS Type: Other
- CPU: 2-4 cores, type "host"
- Memory: 4096 MB
- Network Device 1: vmbr0 (WAN - will get DHCP from ISP)
- Network Device 2: vmbr0, VLAN tag: none (trunk for all VLANs)

### 2. Initial OPNSense Setup

After booting from ISO:

1. Install OPNSense to disk
2. Reboot and complete initial wizard
3. Access web UI at `https://<LAN_IP>` (default: 192.168.1.1)
4. Login: root / opnsense

### 3. Interface Configuration

#### WAN Interface

```
Interfaces > WAN
├── Enable: ✓
├── IPv4 Configuration Type: DHCP
├── IPv6 Configuration Type: None
├── Block private networks: ✗ (see note below)
└── Block bogon networks: ✗ (if behind private upstream)
```

**Critical**: If your WAN is on a private network (e.g., behind an office router on 192.168.x.x), you MUST disable "Block private networks". Otherwise, the firewall will block all incoming traffic from your private LAN, including SSH and web UI access.

#### VLAN Interfaces

Navigate to: **Interfaces > Other Types > VLAN**

**Create VLAN 10 (Production):**
```
Parent Interface: vtnet1 (or your LAN NIC)
VLAN Tag: 10
Description: PROD
```

**Create VLAN 11 (Development):**
```
Parent Interface: vtnet1
VLAN Tag: 11
Description: DEV
```

#### Assign Interfaces

Navigate to: **Interfaces > Assignments**

| Interface | Network Port | Description |
|-----------|-------------|-------------|
| WAN | vtnet0 | WAN |
| LAN | - | (disable if not needed) |
| OPT1 | vlan10 | PROD |
| OPT2 | vlan11 | DEV |

#### Configure PROD Interface (OPT1)

```
Interfaces > [PROD]
├── Enable: ✓
├── Description: PROD
├── IPv4 Configuration Type: Static IPv4
├── IPv4 Address: 10.10.10.1 / 16
└── IPv6 Configuration Type: None
```

#### Configure DEV Interface (OPT2)

```
Interfaces > [DEV]
├── Enable: ✓
├── Description: DEV
├── IPv4 Configuration Type: Static IPv4
├── IPv4 Address: 10.11.10.1 / 16
└── IPv6 Configuration Type: None
```

### 4. DHCP Configuration

Navigate to: **Services > DHCPv4**

#### PROD DHCP

```
Services > DHCPv4 > [PROD]
├── Enable: ✓
├── Range: 10.10.10.50 - 10.10.10.200
├── DNS Servers: 10.10.10.1 (or external)
├── Gateway: 10.10.10.1
└── Domain Name: prod.homelab.local
```

**Static Mappings (for Kubernetes nodes):**
```
MAC Address          IP Address      Hostname
XX:XX:XX:XX:XX:01    10.10.10.10    prod-cp-01
XX:XX:XX:XX:XX:02    10.10.10.11    prod-cp-02
XX:XX:XX:XX:XX:03    10.10.10.20    prod-wk-01
XX:XX:XX:XX:XX:04    10.10.10.21    prod-wk-02
```

#### DEV DHCP

```
Services > DHCPv4 > [DEV]
├── Enable: ✓
├── Range: 10.11.10.50 - 10.11.10.200 (verify actual pool)
├── DNS Servers: 10.11.10.1
├── Gateway: 10.11.10.1
└── Domain Name: dev.homelab.local
```

**Static Mappings:**
```
MAC Address          IP Address      Hostname
XX:XX:XX:XX:XX:05    10.11.10.10    dev-cp-01
XX:XX:XX:XX:XX:06    10.11.10.11    dev-cp-02
XX:XX:XX:XX:XX:07    10.11.10.20    dev-wk-01
XX:XX:XX:XX:XX:08    10.11.10.21    dev-wk-02
```

### 5. Firewall Rules

Navigate to: **Firewall > Rules**

#### PROD Rules

**Important**: Block rules must be ABOVE allow rules (rules are processed top-to-bottom).

| # | Action | Protocol | Source | Destination | Description |
|---|--------|----------|--------|-------------|-------------|
| 1 | Block | * | PROD net | DEV net | Block PROD to DEV |
| 2 | Pass | * | PROD net | * | Allow PROD to any |

#### DEV Rules

| # | Action | Protocol | Source | Destination | Description |
|---|--------|----------|--------|-------------|-------------|
| 1 | Block | * | DEV net | PROD net | Block DEV to PROD |
| 2 | Pass | * | DEV net | * | Allow DEV to any |

#### Key Principle: Environment Isolation

```
┌─────────────────┐          ┌─────────────────┐
│   PROD VLAN     │    ✗     │    DEV VLAN     │
│   10.10.10.0/16 │◄────────►│   10.11.10.0/16 │
│                 │  BLOCKED  │                 │
└────────┬────────┘          └────────┬────────┘
         │                            │
         │ ✓ ALLOWED                  │ ✓ ALLOWED
         │                            │
         ▼                            ▼
    ┌─────────────────────────────────────┐
    │            Internet (WAN)            │
    └─────────────────────────────────────┘
```

### 6. DNS Configuration

#### Unbound DNS (Local Resolver)

Navigate to: **Services > Unbound DNS > General**

```
Enable: ✓
Listen Port: 53
Network Interfaces: PROD, DEV
DNSSEC: ✓
```

#### Local Domain Overrides

Navigate to: **Services > Unbound DNS > Overrides**

**Host Overrides:**
```
Host        Domain              IP
argocd      prod.homelab.local  10.10.10.10
grafana     prod.homelab.local  10.10.10.10
harbor      prod.homelab.local  10.10.10.10
argocd      dev.homelab.local   10.11.10.10
```

### 7. NAT Configuration

By default, OPNSense creates outbound NAT rules automatically. Verify at:

**Firewall > NAT > Outbound**

Ensure "Automatic outbound NAT" is selected, or create manual rules:

```
Interface: WAN
Source: PROD net (10.10.10.0/16)
Translation: Interface Address

Interface: WAN
Source: DEV net (10.11.10.0/16)
Translation: Interface Address
```

**Note**: Automatic outbound NAT works when WAN and LAN are on separate bridges.

## Switch Configuration (NETGEAR GS308EP Example)

### VLAN Configuration

1. Access switch management UI
2. Navigate to VLAN > 802.1Q > Advanced > VLAN Configuration

**Create VLANs:**
```
VLAN ID: 10, Name: PROD
VLAN ID: 11, Name: DEV
```

### Port VLAN Membership

| Port | VLAN 1 | VLAN 10 | VLAN 11 | Description |
|------|--------|---------|---------|-------------|
| 1 | U | T | T | OPNSense (Trunk) |
| 2 | U | T | T | Proxmox (Trunk) |
| 3 | - | U | - | PROD device |
| 4 | - | U | - | PROD device |
| 5 | - | - | U | DEV device |
| 6 | - | - | U | DEV device |
| 7 | U | - | - | Management |
| 8 | U | - | - | Management |

**Legend:**
- T = Tagged (trunk)
- U = Untagged (access)
- `-` = Not a member

If WAN is on a dedicated NIC/bridge, connect that NIC to a switch port configured as **access VLAN 1** (or the upstream ISP VLAN) only.

### Port VLAN ID (PVID)

```
Port 1: PVID 1 (native VLAN for trunk)
Port 2: PVID 1
Port 3: PVID 10
Port 4: PVID 10
Port 5: PVID 11
Port 6: PVID 11
Port 7: PVID 1
Port 8: PVID 1
```

## Proxmox Network Configuration

### Recommended: Separate WAN and LAN Bridges

Use dedicated bridges for WAN and LAN trunk to ensure proper NAT:

```
auto <LAN_NIC>
iface <LAN_NIC> inet manual

auto <WAN_NIC>
iface <WAN_NIC> inet manual

# LAN trunk bridge (VLANs + management)
auto vmbr0
iface vmbr0 inet static
    address <MGMT_IP>/24
    gateway <GATEWAY_IP>
    bridge-ports <LAN_NIC>
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids 10 11

# WAN bridge (upstream to router/ISP)
auto vmbr1
iface vmbr1 inet manual
    bridge-ports <WAN_NIC>
    bridge-stp off
    bridge-fd 0
```

**Important**: WAN and LAN must be on separate L2 segments for NAT to work correctly.

### VM Network Configuration

When creating VMs in Proxmox, specify the VLAN tag:

```
Network Device:
  Bridge: vmbr0
  VLAN Tag: 10  (for PROD VMs)
  # or
  VLAN Tag: 11  (for DEV VMs)
```

## Testing Connectivity

### From OPNSense

```bash
# Test PROD gateway
ping 10.10.10.10

# Test DEV gateway
ping 10.11.10.10

# Verify isolation (should fail)
# From PROD: ping 10.11.10.10 (should be blocked)
```

### From Kubernetes Nodes

```bash
# Test internet access
curl -I https://google.com

# Test DNS resolution
nslookup argocd.prod.homelab.local

# Verify isolation
ping 10.11.10.10  # Should fail from PROD
```

## Backup and Restore

### Export Configuration

**System > Configuration > Backups**

- Download configuration XML
- Store securely (contains sensitive data)

### Automated Backups

Configure backup to remote location:
```
System > Configuration > Backups > Google Drive/Nextcloud
```

## Troubleshooting

### VLAN Not Working

1. Verify switch trunk configuration
2. Check Proxmox bridge VLAN awareness
3. Confirm OPNSense interface assignments
4. Review firewall rules (check logs)

### No Internet Access

1. Check WAN interface status
2. Verify NAT rules exist
3. Test DNS resolution
4. Check default gateway
5. Ensure WAN and LAN are on separate L2 segments (do not share the same bridge)

### Inter-VLAN Routing Issues

1. Verify interface IP addresses
2. Check firewall rules order
3. Review routing table: **System > Routes > Status**

## Security Recommendations

1. **Change default credentials** immediately
2. **Enable HTTPS** for web UI with valid certificate
3. **Disable unused services**
4. **Keep firmware updated**
5. **Enable logging** for firewall rules
6. **Configure alerting** for critical events
7. **Regular configuration backups**
