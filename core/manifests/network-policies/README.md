# Network Policies

Sample CiliumNetworkPolicy and CiliumClusterwideNetworkPolicy manifests for
intra-cluster traffic control.

## Status

These manifests are **samples only** — they are not deployed by ArgoCD. They serve
as a starting point for network policy rollout. See
[ADR-008](../../../docs/decisions/008-cilium-network-policies.md) for the full
assessment.

## Manifests

| File | Type | Purpose |
|------|------|---------|
| `baseline-deny-all.yaml` | CiliumClusterwideNetworkPolicy | Default deny ingress for workload namespaces |
| `allow-dns.yaml` | CiliumClusterwideNetworkPolicy | Allow DNS resolution from all pods |
| `allow-monitoring.yaml` | CiliumClusterwideNetworkPolicy | Allow Prometheus scraping from monitoring namespace |
| `protect-system-namespaces.yaml` | CiliumClusterwideNetworkPolicy | Restrict ingress to protected system namespaces |

## Deployment Order

When ready to deploy:

1. `allow-dns.yaml` — Ensure DNS works under deny-all
2. `allow-monitoring.yaml` — Ensure Prometheus can scrape
3. `baseline-deny-all.yaml` — Enable default deny
4. `protect-system-namespaces.yaml` — Lock down system namespaces

## VLAN Limitation

Cilium host firewall policies are ignored on tagged VLANs (cilium/cilium#40247).
These policies only affect pod-to-pod traffic, which is unaffected by the VLAN bug.
Host/node-level rules remain in OPNSense.
