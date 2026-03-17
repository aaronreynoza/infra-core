# LLM Stack Design

**Date**: 2026-03-17
**Status**: Approved
**Author**: Aaron + Claude

---

## Goal

Self-hosted LLM platform with GPU acceleration, a chat UI, WhatsApp integration, and Claude API access — all behind a unified API gateway.

## Components

| Component | Purpose | GPU | Exposed |
|-----------|---------|-----|---------|
| **Ollama** | Local LLM inference (RTX 3060, 12GB VRAM) | Yes | No (internal) |
| **LiteLLM** | API proxy — routes to Ollama or Claude, cost tracking | No | No (internal) |
| **Open WebUI** | Chat interface (ChatGPT-like UI) | No | Yes → `chat.aaron.reynoza.org` |
| **OpenClaw** | AI agent — WhatsApp bridge, task execution | No | No (outbound only) |

## Architecture

```
┌─────────────┐     ┌─────────────┐
│  Open WebUI │     │  OpenClaw   │
│  (chat UI)  │     │  (WhatsApp) │
└──────┬──────┘     └──────┬──────┘
       │                   │
       └───────┬───────────┘
               │
        ┌──────┴──────┐
        │   LiteLLM   │
        │  (API proxy) │
        └──┬───────┬──┘
           │       │
    ┌──────┴──┐ ┌──┴──────────┐
    │ Ollama  │ │ Claude API  │
    │ (GPU)   │ │ (Anthropic) │
    └─────────┘ └─────────────┘
```

All components deploy to the `ai` namespace.

## GPU Passthrough

### Hardware
- GPU: EVGA RTX 3060 12GB (PCI 02:00.0 + 02:00.1)
- Device IDs: `10de:2487` (VGA), `10de:228b` (Audio)
- Host: daytona — IOMMU/VFIO already configured (2026-03-13)

### Proxmox (VM 510 — prod-wk-01)

**Important:** VM 510 is Terraform-managed. These changes will cause Terraform drift.
The Terraform proxmox-vm module needs to be extended with `hostpci`, `machine`, and
per-worker memory/disk overrides before running `terraform apply` again.

**Option A (recommended):** Update the Terraform module to support GPU passthrough, then apply.
**Option B (quick start):** Apply manually now, update Terraform later. Accept drift.

If the VM was created with `i440fx` machine type (Terraform default), changing to `q35` requires
recreating the VM. Check current machine type first: `qm config 510 | grep machine`.

```bash
# Check current machine type
qm config 510 | grep machine

# Check current disk interface
qm config 510 | grep -E "virtio|scsi|ide"

# Assign GPU (both VGA + audio in same IOMMU group)
qm set 510 --hostpci0 0000:02:00,pcie=1,x-vga=0

# Bump resources (adjust interface name based on check above)
qm set 510 --memory 24576    # 24GB RAM
# qm resize 510 virtio0 +80G  # if virtio — verify first!
```

### Talos (prod-wk-01 only)

Generate NVIDIA schematic for v1.12.5:
- Extensions: i915-ucode, iscsi-tools, qemu-guest-agent, nvidia-open-gpu-kernel-modules-lts, nvidia-container-toolkit-lts
- Pin extension versions to match Talos 1.12.5 kernel (check https://factory.talos.dev for compatible versions)

**Drain plan:** With only 2 workers, draining prod-wk-01 puts ALL workloads on prod-wk-02 (8 cores, 16GB RAM). Plan for a brief service degradation window. Non-essential apps may be evicted if resources are tight.

```bash
kubectl cordon prod-wk-01
kubectl drain prod-wk-01 --ignore-daemonsets --delete-emptydir-data
talosctl upgrade --nodes <wk-01-ip> \
  --image factory.talos.dev/installer/<NVIDIA_SCHEMATIC_ID>:v1.12.5 \
  --preserve
kubectl uncordon prod-wk-01
```

Machine config patch (GPU worker only):
```yaml
machine:
  kernel:
    modules:
      - name: nvidia
      - name: nvidia_uvm
      - name: nvidia_drm
      - name: nvidia_modeset
```

### Kubernetes
- NVIDIA device plugin (Helm chart via ArgoCD)
- Time-slicing: 2 GPU replicas (conservative for 12GB VRAM — LLMs consume 6-10GB each)
- Node label: `homelab.aaron.reynoza.org/gpu=rtx3060`
- No taints (only 2 workers, can't waste scheduling capacity)

## LiteLLM Model Routing

RTX 3060 has 12GB VRAM. Ollama swaps models in/out of VRAM on demand (only one loaded at a time).

| Alias | Provider | Model | VRAM | Use Case |
|-------|----------|-------|------|----------|
| `fast` | Ollama | llama3.1:8b-q4 | ~5GB | Default — daily tasks, quick questions |
| `code` | Ollama | qwen2.5-coder:14b-q4 | ~9GB | Code review, debugging |
| `smart` | Anthropic | claude-sonnet-4-20250514 | N/A | Complex reasoning, long context |

Budget strategy: local models by default, Claude only when explicitly requested or for tasks requiring strong reasoning. LiteLLM provides cost tracking per-model.

Note: Only one local model is loaded in VRAM at a time. Ollama automatically unloads/loads as needed (~5-15s swap time).

## Resource Specs

| Component | CPU req/lim | Memory req/lim | Storage | Node |
|-----------|-------------|----------------|---------|------|
| Ollama | 2/4 cores | 8Gi/16Gi | 50Gi PVC (models, Longhorn) | GPU node (nodeSelector + `nvidia.com/gpu: 1`) |
| LiteLLM | 100m/500m | 128Mi/256Mi | None (stateless) | Any |
| Open WebUI | 100m/500m | 256Mi/512Mi | 5Gi PVC (chat history) | Any |
| OpenClaw | 100m/500m | 256Mi/512Mi | 5Gi PVC (memory/config) | Any |

Ollama container MUST request `nvidia.com/gpu: 1` — without this, the NVIDIA device plugin won't mount the GPU device and inference falls back to CPU silently.

## GitOps Structure

Follows the established multi-source pattern (base values in infra-core, overrides in prod).

### infra-core (public, reusable) — files to create
```
core/charts/apps/ollama/values.yaml          # Base: persistence, resources, service
core/charts/apps/open-webui/values.yaml      # Base: persistence, resources, service
core/charts/apps/litellm/values.yaml         # Base: resources, config structure
core/charts/apps/openclaw/values.yaml        # Base: resources, persistence
core/charts/platform/nvidia-device-plugin/values.yaml  # Base: time-slicing config
```

### prod (private, env-specific) — files to create
```
prod/apps/ollama.yaml                        # ArgoCD Application (multi-source)
prod/apps/open-webui.yaml                    # ArgoCD Application (multi-source)
prod/apps/litellm.yaml                       # ArgoCD Application (multi-source)
prod/apps/openclaw.yaml                      # ArgoCD Application (multi-source)
prod/apps/nvidia-device-plugin.yaml          # ArgoCD Application (multi-source)
prod/values/ollama/values.yaml               # GPU request, nodeSelector
prod/values/open-webui/values.yaml           # LiteLLM URL, Zitadel OIDC
prod/values/litellm/values.yaml              # Anthropic key ref, model config
prod/values/openclaw/values.yaml             # WhatsApp creds, LiteLLM URL
prod/values/nvidia-device-plugin/values.yaml # nodeSelector for GPU node
```

## Secrets (SOPS → Terraform → K8s)

| Secret | Namespace | Keys |
|--------|-----------|------|
| `anthropic-api-key` | ai | `api-key` |
| `openclaw-credentials` | ai | WhatsApp bridge token, config |
| `litellm-master-key` | ai | `master-key` (LiteLLM admin) |

## OpenClaw + WhatsApp

[OpenClaw](https://github.com/openclaw/openclaw) is a Node.js AI agent runtime that bridges messaging platforms to LLM providers.

**WhatsApp integration options:**
- **Meta Cloud API** (official) — requires Facebook business verification, more reliable
- **whatsmeow bridge** (unofficial) — simpler setup, but fragile (breaks with WhatsApp updates)

Recommend starting with Meta Cloud API if Aaron has a business account, otherwise whatsmeow for quick start with the understanding it may need maintenance.

OpenClaw connects to LiteLLM as its LLM backend:
```bash
openclaw onboard --non-interactive \
  --auth-choice litellm-api-key \
  --litellm-api-key "<master-key>" \
  --custom-base-url "http://litellm.ai.svc.cluster.local:4000"
```

## Networking

| Component | Service Type | Pangolin | Zitadel SSO |
|-----------|-------------|----------|-------------|
| Ollama | ClusterIP | No | No |
| LiteLLM | ClusterIP | No | No |
| Open WebUI | LoadBalancer | `chat.aaron.reynoza.org` | Yes |
| OpenClaw | ClusterIP | No | No |

## Implementation Order

| Step | What | Depends On |
|------|------|------------|
| 1 | Proxmox: verify machine type, assign GPU to VM 510, bump resources | None |
| 2 | Talos: generate NVIDIA schematic, drain + upgrade prod-wk-01 | Step 1 |
| 3 | K8s: deploy NVIDIA device plugin, verify `nvidia-smi` in test pod | Step 2 |
| 4 | Deploy Ollama (GPU pod), pull llama3.1:8b-q4 | Step 3 |
| 5 | Deploy LiteLLM with model routing config | Step 4 |
| 6 | Deploy Open WebUI, connect to LiteLLM | Step 5 |
| 7 | Create Pangolin resource for chat.aaron.reynoza.org | Step 6 |
| 8 | Configure Zitadel OIDC for Open WebUI | Step 7 |
| 9 | Deploy OpenClaw, connect to LiteLLM + WhatsApp | Step 5 |
| 10 | Test end-to-end: chat UI + WhatsApp + local + Claude | Step 9 |

Steps 6-8 and step 9 can run in parallel (both depend on step 5).

## Terraform Considerations

The Proxmox VM module (`core/terraform/modules/proxmox-vm/`) currently does not support:
- `hostpci` (GPU passthrough)
- Per-worker `machine` type override
- Per-worker memory/disk overrides (single variable for all workers)

These need to be added to avoid drift between Terraform state and manual `qm set` commands.
Can be done as part of step 1 or deferred as tech debt.

## Success Criteria

- [ ] `nvidia-smi` shows RTX 3060 inside a K8s pod on prod-wk-01
- [ ] Ollama responds to API calls with GPU-accelerated inference
- [ ] LiteLLM routes `fast` to Ollama, `smart` to Claude
- [ ] Open WebUI accessible at `https://chat.aaron.reynoza.org` with Zitadel SSO
- [ ] OpenClaw responds to WhatsApp messages using local models
- [ ] OpenClaw uses Claude when explicitly asked for complex tasks
