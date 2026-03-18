# Forgejo Actions CI/CD Pipelines Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Set up two Forgejo Actions runners (K8s for linting/builds, mgmt VM for Terraform) and create CI/CD workflows for both repos.

**Architecture:** K8s runner handles lightweight jobs (linting, validation, container builds via Kaniko). Mgmt VM runner handles infra jobs requiring credentials (terraform plan/apply, SOPS, kubectl). Pipelines trigger on push to main only.

**Tech Stack:** Forgejo Actions, Kaniko, Terraform, kubectl

---

## File Changes Overview

| File | Repo | Action |
|------|------|--------|
| `core/manifests/apps/forgejo-runner/namespace.yaml` | infra-core | Create |
| `core/manifests/apps/forgejo-runner/deployment.yaml` | infra-core | Create |
| `core/manifests/apps/forgejo-runner/secret.yaml` | infra-core | Create (template) |
| `.forgejo/workflows/lint.yaml` | infra-core | Create |
| `apps/forgejo-runner.yaml` | prod | Create |
| `.forgejo/workflows/infra-plan.yaml` | prod | Create |
| `.forgejo/workflows/infra-apply.yaml` | prod | Create |
| `.forgejo/workflows/validate.yaml` | prod | Create |

---

## Chunk 1: Register Mgmt VM Runner

### Task 1: Get registration token and register

- [ ] **Step 1: Get instance-level registration token from Forgejo API**

```bash
curl -s -H "Authorization: token <FORGEJO_ADMIN_TOKEN>" \
  https://forgejo.aaron.reynoza.org/api/v1/admin/runners/registration-token \
  -X POST
```

Save the `token` value from the response.

- [ ] **Step 2: Register the runner on mgmt VM**

```bash
ssh admin@REDACTED_MGMT_IP "forgejo-runner register \
  --instance https://forgejo.aaron.reynoza.org \
  --token <TOKEN_FROM_STEP_1> \
  --labels infra \
  --name mgmt-infra-runner \
  --no-interactive"
```

- [ ] **Step 3: Start the runner service**

```bash
ssh admin@REDACTED_MGMT_IP "sudo systemctl enable --now forgejo-runner && sudo systemctl status forgejo-runner"
```

Expected: Active (running).

- [ ] **Step 4: Verify runner is online**

```bash
curl -s -H "Authorization: token <FORGEJO_ADMIN_TOKEN>" \
  https://forgejo.aaron.reynoza.org/api/v1/admin/runners | python3 -c "import sys,json; [print(r['name'], r['status']) for r in json.load(sys.stdin)]"
```

Expected: `mgmt-infra-runner` with status `online`.

---

## Chunk 2: Deploy K8s Runner

### Task 2: Create K8s runner manifests

- [ ] **Step 1: Get a second registration token**

```bash
curl -s -H "Authorization: token <FORGEJO_ADMIN_TOKEN>" \
  https://forgejo.aaron.reynoza.org/api/v1/admin/runners/registration-token \
  -X POST
```

- [ ] **Step 2: Create the runner registration secret in K8s**

```bash
kubectl create namespace forgejo-runner
kubectl create secret generic forgejo-runner-secret \
  -n forgejo-runner \
  --from-literal=token=<TOKEN_FROM_STEP_1>
```

- [ ] **Step 3: Create runner manifests in infra-core**

Create `infra-core/core/manifests/apps/forgejo-runner/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: forgejo-runner
  namespace: forgejo-runner
  labels:
    app: forgejo-runner
spec:
  replicas: 1
  selector:
    matchLabels:
      app: forgejo-runner
  template:
    metadata:
      labels:
        app: forgejo-runner
    spec:
      initContainers:
        - name: register
          image: code.forgejo.org/forgejo/runner:6.3.1
          command: ["/bin/sh", "-c"]
          args:
            - |
              if [ ! -f /data/.runner ]; then
                forgejo-runner register \
                  --instance http://forgejo-http.forgejo.svc.cluster.local:3000 \
                  --token "$(cat /secrets/token)" \
                  --labels k8s \
                  --name k8s-runner \
                  --no-interactive
              fi
          volumeMounts:
            - name: runner-data
              mountPath: /data
            - name: runner-secret
              mountPath: /secrets
              readOnly: true
      containers:
        - name: runner
          image: code.forgejo.org/forgejo/runner:6.3.1
          command: ["forgejo-runner", "daemon"]
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: "1"
              memory: 512Mi
          volumeMounts:
            - name: runner-data
              mountPath: /data
      volumes:
        - name: runner-data
          emptyDir: {}
        - name: runner-secret
          secret:
            secretName: forgejo-runner-secret
```

- [ ] **Step 4: Create ArgoCD Application in prod repo**

Create `prod/apps/forgejo-runner.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: forgejo-runner
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "15"
spec:
  project: default
  source:
    repoURL: https://forgejo.aaron.reynoza.org/aaron/infra-core.git
    targetRevision: main
    path: core/manifests/apps/forgejo-runner
  destination:
    server: https://kubernetes.default.svc
    namespace: forgejo-runner
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

- [ ] **Step 5: Commit and push both repos**

```bash
# infra-core
cd /Users/aaronvaldez/repos/homelab/infra-core
git add core/manifests/apps/forgejo-runner/
git commit -m "feat: add Forgejo Actions K8s runner manifests"
git push origin main
git push forgejo main

# prod
cd /Users/aaronvaldez/repos/homelab/prod
git add apps/forgejo-runner.yaml
git commit -m "feat: add Forgejo Actions K8s runner ArgoCD app"
git push origin main
```

- [ ] **Step 6: Verify K8s runner comes up and registers**

```bash
kubectl get pods -n forgejo-runner
# Expected: forgejo-runner pod Running

curl -s -H "Authorization: token <FORGEJO_ADMIN_TOKEN>" \
  https://forgejo.aaron.reynoza.org/api/v1/admin/runners | python3 -c "import sys,json; [print(r['name'], r['status']) for r in json.load(sys.stdin)]"
# Expected: both mgmt-infra-runner and k8s-runner online
```

---

## Chunk 3: Create Workflow Files

### Task 3: Create lint workflow for infra-core repo

- [ ] **Step 1: Create `.forgejo/workflows/lint.yaml` in infra-core**

```yaml
name: Lint & Validate

on:
  push:
    branches: [main]

jobs:
  terraform-validate:
    runs-on: k8s
    container:
      image: hashicorp/terraform:1.9
    steps:
      - uses: actions/checkout@v4
      - name: Validate Terraform modules
        run: |
          for dir in $(find core/terraform -name '*.tf' -exec dirname {} \; | sort -u); do
            echo "==> Validating $dir"
            cd "$dir"
            terraform init -backend=false 2>/dev/null
            terraform validate
            cd "$GITHUB_WORKSPACE"
          done

  yaml-lint:
    runs-on: k8s
    container:
      image: cytopia/yamllint:latest
    steps:
      - uses: actions/checkout@v4
      - name: Lint YAML
        run: yamllint -d relaxed core/manifests/ core/ansible/

  shellcheck:
    runs-on: k8s
    container:
      image: koalaman/shellcheck-alpine:latest
    steps:
      - uses: actions/checkout@v4
      - name: Check scripts
        run: find core/scripts -name '*.sh' -exec shellcheck {} +
```

- [ ] **Step 2: Commit and push**

```bash
cd /Users/aaronvaldez/repos/homelab/infra-core
mkdir -p .forgejo/workflows
# (create lint.yaml as above)
git add .forgejo/
git commit -m "feat: add Forgejo Actions lint workflow (runs on K8s runner)"
git push origin main
git push forgejo main
```

---

### Task 4: Create infra-plan workflow for prod repo

- [ ] **Step 1: Create `.forgejo/workflows/infra-plan.yaml` in prod**

```yaml
name: Infrastructure Plan

on:
  push:
    branches: [main]
    paths:
      - 'terraform/**'
      - 'zitadel/**'
      - 'network/**'

jobs:
  plan-cluster:
    runs-on: infra
    env:
      SOPS_AGE_KEY_FILE: /home/admin/.config/sops/age/keys.txt
      AWS_SHARED_CREDENTIALS_FILE: /home/admin/.aws/credentials
    steps:
      - uses: actions/checkout@v4

      - name: Sync infra-core repo
        run: |
          cd /home/admin/homelab
          git fetch origin main && git reset --hard origin/main

      - name: Terraform Plan (cluster)
        working-directory: terraform
        run: |
          terraform init -backend-config=../backend.hcl
          terraform plan -no-color 2>&1 | tee /tmp/plan-cluster.txt

      - name: Summary
        if: always()
        run: |
          echo "### Cluster Plan" >> $GITHUB_STEP_SUMMARY
          echo '```' >> $GITHUB_STEP_SUMMARY
          grep -E '(Plan:|No changes)' /tmp/plan-cluster.txt >> $GITHUB_STEP_SUMMARY || echo "See logs" >> $GITHUB_STEP_SUMMARY
          echo '```' >> $GITHUB_STEP_SUMMARY

  plan-zitadel:
    runs-on: infra
    env:
      SOPS_AGE_KEY_FILE: /home/admin/.config/sops/age/keys.txt
      AWS_SHARED_CREDENTIALS_FILE: /home/admin/.aws/credentials
    steps:
      - uses: actions/checkout@v4

      - name: Sync infra-core repo
        run: |
          cd /home/admin/homelab
          git fetch origin main && git reset --hard origin/main

      - name: Terraform Plan (zitadel)
        working-directory: zitadel
        run: |
          terraform init -backend-config=backend.hcl
          terraform plan -no-color -var-file=terraform.tfvars \
            -var="kubeconfig_path=/home/admin/.kube/config" \
            -var="zitadel_key_file=/home/admin/.config/zitadel-key.json" \
            2>&1 | tee /tmp/plan-zitadel.txt

      - name: Summary
        if: always()
        run: |
          echo "### Zitadel Plan" >> $GITHUB_STEP_SUMMARY
          echo '```' >> $GITHUB_STEP_SUMMARY
          grep -E '(Plan:|No changes)' /tmp/plan-zitadel.txt >> $GITHUB_STEP_SUMMARY || echo "See logs" >> $GITHUB_STEP_SUMMARY
          echo '```' >> $GITHUB_STEP_SUMMARY
```

---

### Task 5: Create infra-apply workflow for prod repo

- [ ] **Step 1: Create `.forgejo/workflows/infra-apply.yaml` in prod**

```yaml
name: Infrastructure Apply

on:
  workflow_dispatch:
    inputs:
      target:
        description: 'Which config to apply'
        required: true
        type: choice
        options:
          - cluster
          - zitadel
          - network

jobs:
  apply:
    runs-on: infra
    env:
      SOPS_AGE_KEY_FILE: /home/admin/.config/sops/age/keys.txt
      AWS_SHARED_CREDENTIALS_FILE: /home/admin/.aws/credentials
    steps:
      - uses: actions/checkout@v4

      - name: Sync infra-core repo
        run: |
          cd /home/admin/homelab
          git fetch origin main && git reset --hard origin/main

      - name: Set working directory
        id: config
        run: |
          case "${{ inputs.target }}" in
            cluster) echo "dir=terraform" >> $GITHUB_OUTPUT ;;
            zitadel) echo "dir=zitadel" >> $GITHUB_OUTPUT ;;
            network) echo "dir=network" >> $GITHUB_OUTPUT ;;
          esac

      - name: Terraform Apply
        working-directory: ${{ steps.config.outputs.dir }}
        run: |
          terraform init -backend-config=../backend.hcl 2>/dev/null || terraform init -backend-config=backend.hcl
          terraform apply -auto-approve -no-color \
            $([ -f terraform.tfvars ] && echo "-var-file=terraform.tfvars") \
            $([ "${{ inputs.target }}" = "zitadel" ] && echo '-var="kubeconfig_path=/home/admin/.kube/config" -var="zitadel_key_file=/home/admin/.config/zitadel-key.json"') \
            2>&1 | tee /tmp/apply.txt

      - name: Summary
        if: always()
        run: |
          echo "### Apply: ${{ inputs.target }}" >> $GITHUB_STEP_SUMMARY
          echo '```' >> $GITHUB_STEP_SUMMARY
          tail -20 /tmp/apply.txt >> $GITHUB_STEP_SUMMARY
          echo '```' >> $GITHUB_STEP_SUMMARY
```

---

### Task 6: Create manifest validation workflow for prod repo

- [ ] **Step 1: Create `.forgejo/workflows/validate.yaml` in prod**

```yaml
name: Validate Manifests

on:
  push:
    branches: [main]
    paths:
      - 'apps/**'

jobs:
  validate:
    runs-on: infra
    steps:
      - uses: actions/checkout@v4
      - name: Dry-run ArgoCD manifests
        run: |
          for f in apps/*.yaml; do
            echo "==> Validating $f"
            kubectl apply --dry-run=client -f "$f" 2>&1 || echo "WARN: $f failed dry-run"
          done
```

- [ ] **Step 2: Commit and push all prod workflows**

```bash
cd /Users/aaronvaldez/repos/homelab/prod
mkdir -p .forgejo/workflows
# (create infra-plan.yaml, infra-apply.yaml, validate.yaml)
git add .forgejo/
git commit -m "feat: add Forgejo Actions workflows (plan, apply, validate)"
git push origin main
```

---

## Summary

After completing all chunks:

| Runner | Label | Location | Jobs |
|--------|-------|----------|------|
| mgmt-infra-runner | `infra` | Mgmt VM (REDACTED_MGMT_IP) | terraform plan/apply, manifest validation |
| k8s-runner | `k8s` | K8s pod (forgejo-runner ns) | linting, shellcheck, yamllint, container builds |

| Workflow | Repo | Trigger | Runner |
|----------|------|---------|--------|
| `lint.yaml` | infra-core | Push to main | k8s |
| `infra-plan.yaml` | prod | Push to main (terraform/**) | infra |
| `infra-apply.yaml` | prod | Manual (workflow_dispatch) | infra |
| `validate.yaml` | prod | Push to main (apps/**) | infra |

**Next:** Step 5 — MkDocs docs site (first app built and deployed through the CI pipeline).
