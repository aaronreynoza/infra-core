# Ansible and Platform Interaction

This document explains how Ansible is used in the homelab and how it interacts with the Kubernetes platform.

## Overview

Ansible serves as the configuration management layer that bridges the gap between Terraform (infrastructure provisioning) and ArgoCD (application deployment). It handles the initial setup of ArgoCD and triggers the GitOps workflow.

## Role in the Deployment Pipeline

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Terraform  │────▶│   Ansible   │────▶│   ArgoCD    │────▶│    Apps     │
│             │     │             │     │             │     │             │
│ Provisions  │     │ Installs    │     │ Syncs from  │     │ Cilium      │
│ VMs & K8s   │     │ ArgoCD &    │     │ Git repo    │     │ Longhorn    │
│ cluster     │     │ Root App    │     │             │     │ etc.        │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
```

## Directory Structure

```
core/ansible/
├── inventories/
│   └── local/
│       └── hosts.ini          # Inventory file
├── group_vars/
│   └── all.yml                # Global variables
├── playbooks/
│   ├── install-argocd.yml     # ArgoCD installation
│   └── install-apps.yml       # Root app deployment
└── roles/                     # (Future: custom roles)
```

## Inventory Configuration

### hosts.ini

```ini
[local]
localhost ansible_connection=local
```

The inventory uses localhost because Ansible interacts with the Kubernetes cluster via `kubectl`, not SSH.

### group_vars/all.yml

```yaml
# Kubeconfig path - update after Terraform deployment
kubeconfig_path: "~/kubeconfig.yaml"

# ArgoCD Helm configuration
argocd_helm_repo: "https://argoproj.github.io/argo-helm"
argocd_chart_name: "argo-cd"
argocd_chart_version: ""  # Empty uses latest
argocd_namespace: "argocd"
argocd_release_name: "argocd"
```

## Playbooks

### install-argocd.yml

Installs ArgoCD using Helm with custom values.

**Tasks:**
1. Add ArgoCD Helm repository
2. Create argocd namespace
3. Install/upgrade ArgoCD Helm chart
4. Wait for ArgoCD server to be ready

**Usage:**
```bash
cd core/ansible
ansible-playbook -i inventories/local/hosts.ini playbooks/install-argocd.yml
```

**Key Features:**
- Idempotent - safe to run multiple times
- Uses Helm for installation (industry standard)
- Applies custom values from `core/charts/platform/argocd/values.yaml`
- Waits for deployment readiness before completing

### install-apps.yml

Deploys the root ArgoCD Application which triggers the app-of-apps pattern.

**Tasks:**
1. Apply root Application manifest
2. Wait for child applications to sync and become healthy

**Usage:**
```bash
ansible-playbook -i inventories/local/hosts.ini playbooks/install-apps.yml
```

**Variables:**
```yaml
vars:
  argocd_namespace: "argocd"
  root_app_file: "{{ (playbook_dir | dirname | dirname) ~ '/apps/cluster/root.yaml' }}"
  child_apps: [cilium-namespace, cilium, longhorn-namespace, longhorn]
```

## How Ansible Interacts with Kubernetes

### kubernetes.core Collection

Ansible uses the `kubernetes.core` collection for Kubernetes operations:

```yaml
- name: Apply manifest
  kubernetes.core.k8s:
    state: present
    namespace: "{{ namespace }}"
    kubeconfig: "{{ kubeconfig_path | expanduser }}"
    definition: "{{ lookup('file', manifest_path) }}"
```

### Helm Operations

```yaml
- name: Install Helm chart
  kubernetes.core.helm:
    name: "{{ release_name }}"
    chart_ref: "{{ chart_name }}"
    release_namespace: "{{ namespace }}"
    kubeconfig: "{{ kubeconfig_path | expanduser }}"
    values_files:
      - "{{ values_file }}"
```

### Waiting for Resources

```yaml
- name: Wait for deployment
  kubernetes.core.k8s_info:
    api_version: apps/v1
    kind: Deployment
    namespace: "{{ namespace }}"
    name: "{{ deployment_name }}"
    kubeconfig: "{{ kubeconfig_path | expanduser }}"
  register: deployment
  until:
    - deployment.resources | length > 0
    - deployment.resources[0].status.readyReplicas is defined
    - deployment.resources[0].status.readyReplicas == deployment.resources[0].spec.replicas
  retries: 30
  delay: 10
```

## Environment-Specific Configuration

To run Ansible for different environments, update the `kubeconfig_path`:

```bash
# For production
ansible-playbook -i inventories/local/hosts.ini playbooks/install-argocd.yml \
  -e "kubeconfig_path=/path/to/prod/kubeconfig.yaml"

# For development
ansible-playbook -i inventories/local/hosts.ini playbooks/install-argocd.yml \
  -e "kubeconfig_path=/path/to/dev/kubeconfig.yaml"
```

## Common Tasks

### Check ArgoCD Status

```bash
ansible -i inventories/local/hosts.ini localhost -m kubernetes.core.k8s_info \
  -a "api_version=v1 kind=Pod namespace=argocd kubeconfig=~/kubeconfig.yaml"
```

### Run Ad-hoc Commands

```bash
# Get all namespaces
ansible localhost -m kubernetes.core.k8s_info \
  -a "api_version=v1 kind=Namespace kubeconfig=~/kubeconfig.yaml"

# Apply a manifest
ansible localhost -m kubernetes.core.k8s \
  -a "state=present src=/path/to/manifest.yaml kubeconfig=~/kubeconfig.yaml"
```

## Extending Ansible

### Adding Custom Roles

Create roles for additional configuration:

```
core/ansible/roles/
├── monitoring/
│   ├── tasks/
│   │   └── main.yml
│   └── templates/
│       └── grafana-config.yml.j2
└── backup/
    ├── tasks/
    │   └── main.yml
    └── vars/
        └── main.yml
```

### Example Role Structure

```yaml
# roles/monitoring/tasks/main.yml
---
- name: Create monitoring namespace
  kubernetes.core.k8s:
    state: present
    definition:
      apiVersion: v1
      kind: Namespace
      metadata:
        name: monitoring

- name: Deploy Grafana configuration
  kubernetes.core.k8s:
    state: present
    namespace: monitoring
    kubeconfig: "{{ kubeconfig_path }}"
    template: grafana-config.yml.j2
```

## Integration with GitOps

Ansible's role is intentionally minimal - it only:
1. Bootstraps ArgoCD
2. Applies the root Application

After this, ArgoCD takes over all application management via GitOps:

```
┌─────────────────────────────────────────────────────────────────┐
│                        Git Repository                           │
│  environments/prod/apps/                                        │
│    ├── root.yaml          ◄─── Applied by Ansible (once)       │
│    ├── cilium.yaml        ◄─── Synced by ArgoCD (continuous)   │
│    ├── longhorn.yaml      ◄─── Synced by ArgoCD (continuous)   │
│    └── ...                                                      │
└─────────────────────────────────────────────────────────────────┘
```

## Troubleshooting

### Kubeconfig Issues

```bash
# Test kubeconfig
kubectl --kubeconfig=/path/to/kubeconfig.yaml get nodes

# Verify Ansible can access cluster
ansible localhost -m kubernetes.core.k8s_info \
  -a "api_version=v1 kind=Node kubeconfig=/path/to/kubeconfig.yaml"
```

### Collection Not Found

```bash
# Install kubernetes.core collection
ansible-galaxy collection install kubernetes.core

# Or add to requirements.yml
cat > requirements.yml << EOF
collections:
  - name: kubernetes.core
    version: ">=2.4.0"
EOF
ansible-galaxy collection install -r requirements.yml
```

### Helm Chart Failures

```bash
# Check Helm release status
helm list -n argocd --kubeconfig=/path/to/kubeconfig.yaml

# View Helm history
helm history argocd -n argocd --kubeconfig=/path/to/kubeconfig.yaml

# Rollback if needed
helm rollback argocd 1 -n argocd --kubeconfig=/path/to/kubeconfig.yaml
```

## Best Practices

1. **Keep playbooks simple** - Let ArgoCD handle application complexity
2. **Use variables** - Don't hardcode paths or values
3. **Idempotency** - Ensure playbooks can run multiple times safely
4. **Wait conditions** - Always wait for resources to be ready
5. **Error handling** - Use `block/rescue` for critical operations
6. **Version control** - Keep all Ansible code in the repository
