# Aaron's Homelab

A self-hosted infrastructure platform running on bare-metal hardware, designed to showcase DevOps and Platform Engineering skills while hosting production workloads.

## What's Running

| Service | Purpose |
|---------|---------|
| **Talos Linux** | Immutable Kubernetes OS |
| **Cilium** | CNI with L2 load balancing |
| **ArgoCD** | GitOps continuous delivery |
| **Longhorn** | Distributed block storage |
| **CloudNativePG** | PostgreSQL operator |
| **Forgejo** | Self-hosted Git (source of truth) |
| **Harbor** | Container registry |
| **Zitadel** | Identity & SSO |
| **Grafana + Prometheus** | Monitoring & alerting |
| **Loki + Tempo** | Logs & traces |
| **Velero** | Backup & disaster recovery |
| **Pangolin** | Public ingress via WireGuard tunnel |

## Architecture

Two fully isolated VLAN environments (prod + dev) on Proxmox, with OPNSense providing routing and firewall. All infrastructure is codified — Terraform for VMs, ArgoCD for Kubernetes workloads, SOPS for secrets.

See [Architecture](architecture.md) for diagrams and details.

## Cost

Running this entire platform costs ~$43/month. The cloud equivalent would be ~$253/month.
See [Cloud Comparison](cloud-comparison.md) for the breakdown.

## Source Code

This project is open source. The reusable infrastructure modules live in the public repository, while environment-specific configuration (credentials, IPs) is kept in a separate private repository.
