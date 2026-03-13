# Forgejo Infrastructure Platform Design

**Goal:** Establish Forgejo as the Git source of truth with CI/CD automation — management VM for Terraform, Kaniko-based K8s runner for container builds, GitHub as read-only mirror. The entire infrastructure must be reproducible enough to destroy and rebuild from zero.

**Architecture:** Three sequential sub-projects: (1) Management VM for break-glass access and infra automation, (2) Forgejo as source of truth with GitHub mirror, (3) Forgejo Actions CI/CD with dual runners.

**Tech Stack:** Forgejo, Forgejo Actions (act_runner), Kaniko, Harbor, ArgoCD, Ansible, Debian 12

---

## Sub-Project 1: Management VM (ID 99)

### Purpose

Dual-purpose: Forgejo Actions runner for Terraform/infra automation + break-glass SSH access when K8s or OPNSense is down. NOT managed by Terraform — this is the bootstrap node.

### Specification

| Setting | Value |
|---------|-------|
| VM ID | 99 |
| Name | mgmt |
| OS | Debian 12 minimal (cloud image) |
| CPU | 2 vCPU |
| RAM | 4 GB |
| Disk | 32 GB on local-lvm (SSD) |
| NIC | vmbr1 (VLAN-aware bridge) |
| Management IP | REDACTED_MGMT_IP (static, untagged) |
| VLAN 10 IP | REDACTED_VLAN_IP (static, tagged) |
| Auto-start | Yes, order 2 (after OPNSense=1, before K8s=3) |

### Network Design

```
Workstation (192.168.1.x)
    |
    | SSH (management network, no OPNSense dependency)
    v
Management VM (REDACTED_MGMT_IP)
    |
    | Direct L2 (VLAN 10 tagged interface)
    v
K8s nodes (10.10.10.x), Forgejo, Harbor, ArgoCD
```

### Installed Software

- Core: git, tmux, curl, jq, yq, dig, traceroute
- IaC: terraform, ansible
- K8s: kubectl, talosctl, helm, argocd CLI
- Secrets: sops, age, aws CLI
- Security: fail2ban, ufw, unattended-upgrades
- CI: Forgejo Actions runner (`act_runner`)

### What Does NOT Go Here

- Docker / container runtime (attack surface — container builds use Kaniko in K8s)
- Databases or stateful services
- Monitoring agents

### Security

- SSH: key-only, AllowUsers=operator, from 192.168.1.0/24 only
- Firewall (ufw): SSH inbound from mgmt net only
- Credentials: file permissions 600, dedicated non-root user for runner
- Age key at ~/.config/sops/age/keys.txt
- AWS creds at ~/.aws/credentials

### Ansible Playbook

Create `core/ansible/playbooks/setup-mgmt-vm.yml` for reproducible setup. This is critical — the entire VM must be rebuildable from scratch by running the playbook.

### Bootstrap Procedure (Manual)

1. Download Debian 12 cloud image to Proxmox
2. Create VM 99 in Proxmox UI (specs above)
3. Boot, set hostname=mgmt, configure static IPs
4. Run Ansible playbook from workstation
5. Manually copy age private key + AWS credentials
6. Clone homelab + environments repos
7. Register Forgejo Actions runner (after Sub-Project 2)

---

## Sub-Project 2: Forgejo as Source of Truth

### Current State

- Source of truth: github.com/aaronreynoza/homelab
- ArgoCD watches: GitHub main branch
- Forgejo: deployed at REDACTED_LB_IP:3000, running, healthy, but empty

### Target State

- Source of truth: Forgejo at REDACTED_LB_IP:3000
- ArgoCD watches: Forgejo internal URL (LAN, no internet dependency)
- GitHub: read-only push mirror for portfolio visibility
- Workstation git remote: Forgejo as origin, GitHub as backup

### Migration Steps

1. Create `aaron` user and `homelab` repo in Forgejo
2. Push all branches to Forgejo
3. Configure push mirror (Forgejo → GitHub) with GitHub PAT
4. Update ArgoCD Application manifests to use Forgejo repoURL
5. Update root-app.yaml and nginx-test.yaml (only ones referencing GitHub directly)
6. Update docs-site.yaml (created earlier in this session)
7. Update workstation git remotes
8. Verify ArgoCD syncs from Forgejo
9. Update GitHub README with mirror notice

### ArgoCD repoURL Change

```yaml
# Before (in root-app.yaml, nginx-test.yaml, docs-site.yaml)
repoURL: https://github.com/aaronreynoza/homelab.git

# After
repoURL: http://REDACTED_LB_IP:3000/aaron/homelab.git
```

Note: Using IP address because internal DNS (ctrld) is not configured yet. Will change to `forgejo.internal` when DNS is set up.

### Forgejo Configuration Updates

The current Forgejo config has:
```yaml
server:
  DOMAIN: localhost
  ROOT_URL: http://localhost:3000
```

This needs to be updated to reflect the actual LB IP so push mirrors and webhooks work correctly:
```yaml
server:
  DOMAIN: REDACTED_LB_IP
  ROOT_URL: http://REDACTED_LB_IP:3000
```

### What We Lose (and mitigations)

| Lost | Mitigation |
|------|------------|
| GitHub Issues/PRs | Forgejo has both |
| Dependabot | Renovate later (or manual updates) |
| GitHub Actions marketplace | Most actions work in Forgejo Actions |
| Discoverability | Mirror still shows code, README links to docs site |

---

## Sub-Project 3: Forgejo Actions CI/CD

### Architecture

```
Forgejo Actions
├── mgmt VM runner [self-hosted, infra]     → terraform plan/apply
│   - Labels: self-hosted, linux, x64, infra
│   - Has: age key, AWS creds, terraform, kubectl, talosctl
│   - No Docker daemon
│
└── K8s runner pod [self-hosted, builder]    → kaniko → Harbor push
    - Labels: self-hosted, linux, x64, builder
    - Has: kaniko executor, Harbor credentials
    - No privileged containers
    - Namespace: forgejo-runners
```

### Why Kaniko (Expert Team Consensus)

All four experts (Container Build, Kubernetes, CI/CD, Security) unanimously recommended Kaniko:

| Criterion | DinD | Kaniko |
|-----------|------|--------|
| Privileged container | Required | Not needed |
| Talos compatibility | Fights the security model | Aligns with it |
| Harbor HTTP support | Requires daemon.json config | Native `--insecure` flag |
| Build cache | Needs PVC | Remote cache in Harbor |
| Resource usage | Idle daemon overhead | On-demand only |
| Container escape risk | HIGH (production cluster with paying clients) | LOW |
| Multi-stage Dockerfile | Full support | Full support |

### K8s Runner Pod (Kaniko Builder)

**Namespace:** `forgejo-runners`

**Runner image:** Custom image containing:
- `act_runner` binary (Forgejo Actions runner)
- `/kaniko/executor` binary
- `git`

**Pod spec highlights:**
- No privileged securityContext
- `runAsNonRoot: false` (Kaniko needs root inside container for RUN instructions)
- Volume: `emptyDir` for workspace
- Secret mount: Harbor auth at `/kaniko/.docker/config.json`
- Resources: requests 500m/512Mi, limits 2/2Gi (builds are bursty)
- Managed by Deployment (replicas: 1)

**Harbor authentication:**
- K8s Secret `harbor-registry-auth` containing Docker `config.json`
- Mounted into runner pod for Kaniko to pick up automatically

### Kaniko Build Flags

```bash
/kaniko/executor \
  --context=. \
  --dockerfile=Dockerfile.docs \
  --destination=REDACTED_LB_IP/platform/docs:${COMMIT_SHA} \
  --destination=REDACTED_LB_IP/platform/docs:latest \
  --insecure \
  --cache=true \
  --cache-repo=REDACTED_LB_IP/cache/docs \
  --snapshot-mode=redo
```

### Mgmt VM Runner (Infra)

Registered with Forgejo after Sub-Project 2 is complete:
```bash
act_runner register \
  --instance http://REDACTED_LB_IP:3000 \
  --token <runner-token-from-forgejo> \
  --labels self-hosted,linux,x64,infra \
  --name mgmt-infra-runner
```

Runs as a systemd service under a dedicated non-root user.

### CI Pipelines

**Docs Build (first pipeline):**
```yaml
# .forgejo/workflows/docs-build.yml
name: Build Docs
on:
  push:
    branches: [main]
    paths:
      - 'docs/**'
      - 'mkdocs.yml'
      - 'Dockerfile.docs'
      - 'Caddyfile'

jobs:
  build:
    runs-on: [self-hosted, builder]
    steps:
      - uses: actions/checkout@v4
      - name: Build and push docs image
        run: |
          /kaniko/executor \
            --context=${{ github.workspace }} \
            --dockerfile=Dockerfile.docs \
            --destination=REDACTED_LB_IP/platform/docs:${{ github.sha }} \
            --destination=REDACTED_LB_IP/platform/docs:latest \
            --insecure \
            --cache=true \
            --cache-repo=REDACTED_LB_IP/cache/docs
```

**Terraform Plan (on PR):**
```yaml
# .forgejo/workflows/terraform-plan.yml
name: Terraform Plan
on:
  pull_request:
    paths:
      - 'core/terraform/**'

jobs:
  plan:
    runs-on: [self-hosted, infra]
    steps:
      - uses: actions/checkout@v4
      - name: Terraform Plan
        run: |
          cd core/terraform/live/prod-cluster
          terraform init -backend-config=../../../../environments/prod/backend.hcl
          terraform plan -var-file=../../../../environments/prod/terraform.tfvars -no-color
        env:
          SOPS_AGE_KEY_FILE: /home/runner/.config/sops/age/keys.txt
```

**Terraform Apply (manual trigger):**
```yaml
# .forgejo/workflows/terraform-apply.yml
name: Terraform Apply
on:
  workflow_dispatch:

jobs:
  apply:
    runs-on: [self-hosted, infra]
    steps:
      - uses: actions/checkout@v4
      - name: Terraform Apply
        run: |
          cd core/terraform/live/prod-cluster
          terraform init -backend-config=../../../../environments/prod/backend.hcl
          terraform apply -var-file=../../../../environments/prod/terraform.tfvars -auto-approve
        env:
          SOPS_AGE_KEY_FILE: /home/runner/.config/sops/age/keys.txt
```

### Image Update Strategy

After Kaniko pushes a new image to Harbor, the K8s deployment needs to pick it up. Options:

- **ArgoCD Image Updater** — watches Harbor for new tags, updates manifests automatically
- **Workflow updates manifest** — the CI pipeline commits the new image tag to Git, ArgoCD syncs
- **`latest` tag + restart** — simplest, pod restart pulls new `latest` image

Recommended: Workflow commits new image tag to Git. This keeps Git as the source of truth (GitOps) and creates an audit trail. ArgoCD Image Updater is a future enhancement.

---

## Reproducibility: Destroy and Rebuild

The user plans to destroy and rebuild the entire infrastructure from zero to verify reproducibility. This means:

### What Must Be Reproducible

| Component | How |
|-----------|-----|
| OPNSense VM | Terraform + manual post-config (documented in runbook) |
| K8s cluster | Terraform (talos-cluster module) |
| Platform apps | ArgoCD app-of-apps (auto-syncs from Git) |
| K8s secrets | Terraform + SOPS (encrypted in environments/) |
| Management VM | Manual create + Ansible playbook |
| Forgejo repo | `git push` to fresh Forgejo instance |
| Forgejo → GitHub mirror | Manual config in Forgejo UI |
| Runner registration | Manual `act_runner register` (documented in runbook) |
| Harbor projects | Created by CI pipeline or API call in bootstrap script |
| Container images | Rebuilt by CI pipeline on first push |

### What's Manual (and must be documented in runbooks)

1. Proxmox VM creation (OPNSense, mgmt VM — not Terraform-managed)
2. OPNSense VLAN/firewall configuration
3. Copy age private key and AWS credentials to mgmt VM
4. Forgejo: create user, create repo, configure mirror
5. Register Forgejo Actions runners (both mgmt VM and K8s)
6. Create Pangolin resources in dashboard
7. DNS configuration (ControlD or registrar)

### Rebuild Order

1. OPNSense VM (Terraform) → configure VLANs
2. Management VM (manual + Ansible)
3. K8s cluster (Terraform)
4. ArgoCD bootstraps (Ansible playbook)
5. ArgoCD syncs all platform apps from Git (automatic)
6. Push repo to Forgejo, configure mirror
7. Register runners, CI builds container images
8. Create Pangolin resources for public apps
9. Verify end-to-end: push a docs change → CI builds → Harbor → ArgoCD deploys → public access works

---

## Files to Create/Modify

### New Files

| File | Purpose |
|------|---------|
| `core/ansible/playbooks/setup-mgmt-vm.yml` | Ansible playbook for management VM setup |
| `core/ansible/roles/mgmt-vm/` | Role: packages, security, runner setup |
| `core/manifests/apps/forgejo-runner/deployment.yaml` | K8s runner pod (Kaniko builder) |
| `core/manifests/apps/forgejo-runner/service-account.yaml` | ServiceAccount for runner |
| `core/manifests/apps/forgejo-runner/harbor-auth-secret.yaml` | Harbor registry credentials |
| `core/manifests/argocd/apps/forgejo-runner.yaml` | ArgoCD Application for K8s runner |
| `.forgejo/workflows/docs-build.yml` | Docs site CI pipeline |
| `.forgejo/workflows/terraform-plan.yml` | Terraform plan on PR |
| `.forgejo/workflows/terraform-apply.yml` | Terraform apply (manual) |
| `docs/runbooks/mgmt-vm-setup.md` | Management VM bootstrap runbook |
| `docs/runbooks/forgejo-migration.md` | Forgejo migration runbook |
| `docs/decisions/005-kaniko-container-builds.md` | ADR: Kaniko over DinD |

### Modified Files

| File | Change |
|------|--------|
| `core/manifests/argocd/root-app.yaml` | repoURL → Forgejo |
| `core/manifests/argocd/apps/nginx-test.yaml` | repoURL → Forgejo |
| `core/manifests/argocd/apps/docs-site.yaml` | repoURL → Forgejo |
| `core/manifests/argocd/apps/forgejo.yaml` | Update DOMAIN/ROOT_URL to LB IP |
| `CLAUDE.md` | Update work status, add Forgejo/CI info |
