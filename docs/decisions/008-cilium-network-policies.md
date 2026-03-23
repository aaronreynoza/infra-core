# ADR-008: Cilium Network Policies for Intra-Cluster Traffic

**Status**: Accepted
**Date**: 2026-03-22
**Related**: [HOMELAB-141](https://plane.aaron.reynoza.org), [ADR-001 VLAN Architecture](001-vlan-architecture.md), HOMELAB-134 (OPNSense IaC research)

## Context

The homelab cluster runs on VLAN 10 (10.10.10.0/16) with Cilium 1.16.5 as the
CNI. OPNSense (VM 100) handles WAN routing, inter-VLAN isolation, DHCP, and DNS
forwarding. Currently, **zero network policies** exist in GitOps — all pod-to-pod
traffic within the cluster is unrestricted.

HOMELAB-134 established that OPNSense should keep WAN/VLAN responsibilities while
Cilium handles pod-to-pod traffic control within the cluster. This ADR evaluates
which traffic rules are candidates for CiliumNetworkPolicy CRDs.

## Decision

Adopt a **layered network security model**:

| Layer | Tool | Scope |
|-------|------|-------|
| WAN / Internet | OPNSense | Ingress/egress firewall, NAT, VPN |
| Inter-VLAN | OPNSense | VLAN 10 ↔ VLAN 11 isolation (fully blocked) |
| Node-level / host | OPNSense | Node-to-external traffic, management access |
| Pod-to-pod | **Cilium** | Namespace isolation, service-to-service rules |
| L7 / API | Cilium (future) | HTTP-aware policies, DNS-aware egress filtering |

### What stays in OPNSense

These rules **cannot** move to Cilium:

1. **WAN firewall rules** — Cilium has no visibility into WAN traffic; OPNSense
   sits at the network edge.
2. **Inter-VLAN isolation** — VLAN 10 (prod) and VLAN 11 (dev) are isolated at
   the switch/router level. Cilium operates within a single VLAN.
3. **Node-to-external rules** — Traffic from node IPs (10.10.10.10/20/21) to
   external services (Proxmox API, NFS, management network). Cilium host firewall
   policies are **ignored on tagged VLANs** (see VLAN Limitation below).
4. **DHCP / DNS forwarding** — Infrastructure services outside the cluster.
5. **Management VM access** — SSH/HTTPS rules for VM 110 (management).

### What moves to Cilium

These rules are candidates for CiliumNetworkPolicy / CiliumClusterwideNetworkPolicy:

1. **Default deny ingress** — Baseline zero-trust: deny all ingress to workload
   namespaces unless explicitly allowed. Exempts system namespaces.
2. **DNS allowlist** — All pods need DNS resolution. A clusterwide policy allows
   UDP/TCP 53 to kube-dns, preventing DNS breakage from default deny.
3. **Monitoring scrape access** — Prometheus in the `monitoring` namespace needs
   to reach pods across all namespaces on their metrics ports.
4. **System namespace protection** — Restrict ingress to protected namespaces
   (kube-system, cilium-system, argocd, cert-manager, longhorn-system, monitoring,
   velero, zitadel, forgejo, harbor) to only known consumers.
5. **Namespace isolation** (future) — Per-app policies allowing only expected
   service-to-service traffic (e.g., only Forgejo runner → Forgejo, only Langfuse
   web → Langfuse ClickHouse/Redis/S3).

## VLAN Limitation

**cilium/cilium#40247**: Cilium host firewall policies are ignored on tagged VLANs.

This directly affects our setup:
- All cluster nodes are on VLAN 10 (tagged 802.1Q)
- Cilium's `hostFirewall` feature would not enforce policies on VLAN-tagged interfaces
- **Impact**: Cilium cannot replace OPNSense for host-level (node IP) firewall rules
- **Workaround**: None — this is a known Cilium limitation
- **Mitigation**: Keep all host/node-level rules in OPNSense; use Cilium only for
  pod-to-pod traffic (which uses the Cilium-managed veth interfaces, unaffected by
  the VLAN bug)

The host firewall is currently disabled in our Cilium config (`hostFirewall` not set),
which is the correct configuration given this limitation.

## Sample Manifests

Sample CiliumNetworkPolicy and CiliumClusterwideNetworkPolicy manifests are
provided in `core/manifests/network-policies/`. These are **not deployed by default**
— they serve as a starting point for when network policies are rolled out.

Manifests included:
- `baseline-deny-all.yaml` — Default deny ingress for non-system namespaces
- `allow-dns.yaml` — Allow DNS to kube-dns from all pods
- `allow-monitoring.yaml` — Allow Prometheus scraping from monitoring namespace
- `protect-system-namespaces.yaml` — Restrict ingress to protected namespaces

## Rollout Considerations

When deploying these policies:

1. **Start with monitoring mode** — Use Cilium's policy audit mode (`spec.audit: true`
   on Cilium 1.14+) or Hubble flow logs to observe what would be blocked before
   enforcing.
2. **Deploy incrementally** — Start with `allow-dns` and `allow-monitoring` (additive),
   then `baseline-deny-all` (restrictive), then per-namespace policies.
3. **Test in dev first** — VLAN 11 cluster (when provisioned) should get policies
   before prod.
4. **Hubble visibility** — Hubble is already enabled; use `hubble observe` to verify
   policy decisions in real time.

## Consequences

- Pod-to-pod traffic will be controlled via GitOps (CiliumNetworkPolicy in infra-core)
- OPNSense remains the sole control plane for VLAN, WAN, and host-level rules
- No changes to OPNSense configuration required
- Network policies add latency-free security (Cilium enforces via eBPF in kernel)
- Ongoing maintenance: new namespaces/services need corresponding allow policies
