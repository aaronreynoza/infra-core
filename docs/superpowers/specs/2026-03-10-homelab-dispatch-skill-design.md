# Homelab Dispatch Skill Design

**Date**: 2026-03-10
**Status**: Approved

## Overview

A single dispatcher skill (`homelab-dispatch`) that receives implementation tasks and spins up domain-specific expert subagents. Implementation-focused — experts write code against existing plans, not advisory.

## Structure

- **Location**: `~/.claude/skills/homelab-dispatch/SKILL.md`
- **Triggering**: Auto-triggers on homelab implementation tasks (deploying VMs, configuring storage, bootstrapping clusters, deploying apps, networking setup)
- **No bundled resources**: All expert context inline in SKILL.md (<500 lines)

## Expert Roster (8 experts)

| Expert | Domain | Trigger Keywords |
|--------|--------|-----------------|
| Proxmox | VM provisioning, disk passthrough, Terraform provider | VM, disk, passthrough, proxmox, qm |
| TrueNAS | ZFS pools, NFS/SMB shares, storage config | ZFS, NFS, pool, tank, share, truenas |
| Talos | Cluster bootstrap, machine configs, upgrades | talos, machineconfig, talosctl, kubeconfig |
| Kubernetes | Workloads, services, networking, RBAC | pod, deployment, service, namespace, kubectl |
| Helm | Chart values, dependencies, templating | chart, values, helm, release |
| ArgoCD | App-of-apps, sync policies, GitOps patterns | argocd, app-of-apps, sync, gitops |
| Networking | Cilium, VLANs, DNS, Pangolin/Newt | vlan, cilium, pangolin, newt, controld, dns, ingress |
| Terraform | Module patterns, state management, providers | terraform, module, state, backend, provider |

## Expert Definitions

### Proxmox
- **Iron laws**: Always use Terraform provider for repeatable work. VM IDs follow scheme (100=OPNSense, 101=TrueNAS, 200+=K8s).
- **Conventions**: Modules in `core/terraform/modules/`, live configs in `core/terraform/live/`.

### TrueNAS
- **Iron laws**: ZFS pool named "tank". NFS shares for K8s use. Never mix boot disk with data disks.
- **Conventions**: Post-install manual config (pool, shares, permissions).

### Talos
- **Iron laws**: Use machine configs, never SSH. Immutable OS — no manual changes. Newt as system extension.
- **Conventions**: `talosctl` for all operations, configs in `environments/`.

### Kubernetes
- **Iron laws**: Namespaced workloads. Resource limits on everything. No `latest` tags.
- **Conventions**: Cilium CNI, Longhorn storage class.

### Helm
- **Iron laws**: Values files in `core/charts/`, no inline overrides. Pin chart versions.
- **Conventions**: Platform charts vs app charts separation.

### ArgoCD
- **Iron laws**: App-of-apps pattern. Auto-sync for dev, manual sync for prod.
- **Conventions**: Manifests in `core/manifests/`, health checks required.

### Networking
- **Iron laws**: Pangolin for ingress (not Cloudflare Tunnel). ControlD for DNS. VLAN isolation is sacred.
- **Conventions**: PROD=VLAN10 (10.10.10.0/16), DEV=VLAN11 (10.11.10.0/16), never cross.

### Terraform
- **Iron laws**: S3 backend always. No local state. Modules parameterized, secrets in `environments/`.
- **Conventions**: `backend.hcl` + `terraform.tfvars` pattern.

## Dispatch Logic

1. Receive task
2. Parse for domain keywords → select expert(s)
3. Independent experts → parallel subagents. Dependent → sequential.
4. Each subagent gets: persona, iron laws, task, project context, instruction to write code
5. Collect results, present summary

## Multi-Expert Dispatch

Tasks crossing domains (e.g., "deploy TrueNAS VM") dispatch multiple experts in parallel. Each works on its piece — Terraform writes the module, Proxmox handles VM config, TrueNAS documents post-install steps.
