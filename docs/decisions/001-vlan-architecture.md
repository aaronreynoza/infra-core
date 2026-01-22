# ADR-001: VLAN Architecture for Environment Isolation

**Status**: Accepted
**Date**: 2026-01
**Decision Makers**: Aaron

---

## Context

The homelab needs to support two separate environments:
- **Production**: Hosts the race telemetry application with paying clients, plus personal services (Jellyfin, etc.)
- **Development**: Tests infrastructure changes and application development before promotion to prod

These environments must be fully isolated to prevent:
- Accidental data leakage between environments
- Development experiments affecting production workloads
- Security incidents in dev propagating to prod

---

## Decision

Implement VLAN-based network segmentation with OPNSense as the router/firewall.

### Network Scheme

| Environment | VLAN ID | Network | Gateway |
|-------------|---------|---------|---------|
| Production | 10 | 10.10.10.0/16 | 10.10.10.1 |
| Development | 11 | 10.11.10.0/16 | 10.11.10.1 |

### Architecture

```
ISP Router
    │
    ▼ WAN
┌─────────────────┐
│   OPNSense VM   │  ← Firewall, VLAN gateway, DHCP, DNS
│                 │
│  VLAN 10: 10.10.10.1 (Prod)
│  VLAN 11: 10.11.10.1 (Dev)
└────────┬────────┘
         │ Trunk (tagged VLANs)
         ▼
┌─────────────────┐
│ NETGEAR GS308EP │  ← 802.1Q VLAN tagging
└────────┬────────┘
         │ Trunk
         ▼
┌─────────────────┐
│   Proxmox Host  │  ← VLAN-aware bridge
│                 │
│  VLAN 10 VMs: prod-cp-*, prod-wk-*
│  VLAN 11 VMs: dev-cp-*, dev-wk-*
└─────────────────┘
```

### Firewall Rules

- **PROD to Internet**: ALLOW
- **DEV to Internet**: ALLOW
- **PROD to DEV**: BLOCK
- **DEV to PROD**: BLOCK
- **Intra-VLAN traffic**: ALLOW

---

## Alternatives Considered

### 1. Separate Physical Networks
- **Pros**: True air-gap isolation
- **Cons**: Requires more hardware (switches, NICs), higher cost, more complexity
- **Rejected because**: VLAN isolation is sufficient for this use case; not running government secrets

### 2. Kubernetes Namespaces Only (No VLANs)
- **Pros**: Simpler setup, no network config needed
- **Cons**: Both environments share the same cluster, blast radius is larger, no infrastructure isolation
- **Rejected because**: We want to test infrastructure changes (Terraform, K8s upgrades) in dev before prod

### 3. /24 Subnets Instead of /16
- **Pros**: More standard subnet size
- **Cons**: Limits growth to 254 hosts per environment
- **Rejected because**: /16 gives room for future expansion (pods, services, additional nodes) without re-IPing

---

## Consequences

### Positive
- Full environment isolation at the network layer
- Can safely destroy/rebuild dev without affecting prod
- Clear separation for compliance/audit purposes
- OPNSense provides centralized firewall logging

### Negative
- Requires OPNSense VM (additional resource overhead)
- VLAN configuration across switch/Proxmox/OPNSense adds complexity
- No easy cross-environment resource sharing (by design)

### Neutral
- Each environment needs its own Harbor registry (no cross-VLAN access)
- Each environment has independent DNS records

---

## Implementation Notes

- NETGEAR GS308EP configured with VLANs 10 and 11
- Trunk ports for OPNSense and Proxmox
- Proxmox bridge `vmbr0` made VLAN-aware
- OPNSense handles DHCP for each VLAN with static mappings for K8s nodes
- See [04-opnsense.md](../04-opnsense.md) for detailed OPNSense configuration
