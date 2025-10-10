# Self-Hosted GitHub Actions Runner on Proxmox

This guide sets up a **persistent self-hosted runner** on your Proxmox host (via a small Ubuntu VM/LXC). It’s designed so the runner can build images with **Packer**, talk to **Proxmox API**, apply **Terraform** with **S3/DynamoDB** backend, and run **kubectl/helm** against your Talos cluster.

> Everything here is either **fully automated** (via the provided script) or **documented** step-by-step.

---

## 0. Prerequisites

- **Proxmox** access with a user that has API permissions to create/modify VMs.
- A network with internet egress for the runner VM/LXC.
- A GitHub repository where you will register the runner.
- AWS S3 bucket and DynamoDB table (for Terraform remote state/locks).
- Optional: Docker access (useful when steps build in containers).

---

## 1. Create a small VM (recommended) or LXC

**Recommended VM sizing**  
- Name: `gh-runner`  
- 2 vCPU, 4–8 GB RAM, 20–40 GB disk  
- Network: bridge with DHCP or static IP  
- OS: Ubuntu Server 22.04/24.04 LTS

**Proxmox UI (VM quick steps)**
1. `Create VM` → pick node/storage → mount Ubuntu ISO.
2. UEFI+SCSI (VirtIO SCSI) is fine. Enable QEMU Agent if you use it.
3. Finish install, set a user (e.g., `github`) with sudo, and SSH in.

**CLI example (optional)**
```bash
# === Simple automated VM creation for a GH Actions runner ===
# Downloads latest Ubuntu 24.04.x live-server ISO, verifies it, and boots the VM.

# --- Config (tweak if you want) ---
VMID=9000
VMNAME=gh-runner
MEMORY=4096
CORES=2
BRIDGE=vmbr0
DISK_STORAGE=local-lvm     # where the VM disk lives
DISK_SIZE=32               # GB
ISO_STORAGE_ID=local       # Proxmox storage id that maps to /var/lib/vz

# --- Get latest ISO and verify ---
mkdir -p /var/lib/vz/template/iso
cd /var/lib/vz/template/iso

LATEST=$(curl -fsSL https://releases.ubuntu.com/24.04/ \
  | grep -oE 'ubuntu-24\.04\.[0-9]+-live-server-amd64\.iso' \
  | sort -V | tail -1)

wget -q "https://releases.ubuntu.com/24.04/${LATEST}"
wget -q "https://releases.ubuntu.com/24.04/SHA256SUMS"
grep "${LATEST}" SHA256SUMS | sha256sum -c -

# --- Create VM and attach ISO ---
qm create "$VMID" --name "$VMNAME" --memory "$MEMORY" --cores "$CORES" --net0 virtio,bridge="$BRIDGE"
qm set "$VMID" --scsihw virtio-scsi-pci --scsi0 "${DISK_STORAGE}:${DISK_SIZE}"
qm set "$VMID" --ide2 "${ISO_STORAGE_ID}:iso/${LATEST}",media=cdrom
qm set "$VMID" --boot order="ide2;scsi0"
qm start "$VMID"

echo "VM $VMID ($VMNAME) starting with ISO ${LATEST}. Open the console to install Ubuntu."

```

---

## 2. (Automated) Install & Register the Runner

This repo includes a script that:
- Installs dependencies (curl, git, unzip, jq, docker)
- Downloads the GitHub Actions Runner
- Registers it to **your repo**
- Installs/starts a **systemd** service
- Applies useful **labels** (`self-hosted,proxmox,talos,terraform`)

> File: `runner/install-runner.sh`  
> Make it executable and run it on the VM.

```bash
# On the runner VM
sudo apt-get update -y && sudo apt-get install -y git
# copy the content of install-runner.sh from this repo into your VM
chmod +x install-runner.sh
sudo ./install-runner.sh
```

During the script:
- You’ll need a **runner registration token**.  
  Get it from **GitHub → Repo → Settings → Actions → Runners → New self-hosted runner**.

**Script variables (what it expects or sets)**
- `REPO_URL` — your GitHub repo URL.
- `REG_TOKEN` — the registration token you copied.
- Labels: `self-hosted,proxmox,talos,terraform` (edit inside the script if you want more).

> If you prefer **organization-level** runners, use the org URL instead of repo URL when running `config.sh`.

---

## 3. (Manual) Runner install — if you don’t use the script

```bash
# Create user & deps
sudo useradd -m -s /bin/bash -U github || true
sudo apt-get update -y
sudo apt-get install -y jq curl unzip git docker.io

# (optional) Docker for this user
sudo usermod -aG docker github
sudo systemctl enable --now docker

# Prepare runner dir
sudo mkdir -p /opt/actions-runner
sudo chown -R github:github /opt/actions-runner
cd /opt/actions-runner

# Download runner (update version as needed)
sudo -u github bash -lc '
  RUNNER_VERSION="2.319.1"
  curl -fsSL -o actions-runner.tar.gz     https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
  tar xzf actions-runner.tar.gz && rm actions-runner.tar.gz
'

# Configure runner
REPO_URL="https://github.com/<org-or-user>/<repo>"
REG_TOKEN="<GITHUB_RUNNER_REG_TOKEN>"

sudo -u github bash -lc "./config.sh --unattended   --url ${REPO_URL}   --token ${REG_TOKEN}   --labels self-hosted,proxmox,talos,terraform   --replace   --name gh-runner-1"

# Install as a service
sudo ./svc.sh install github
sudo ./svc.sh start
```

**Verify**
```bash
sudo systemctl status actions.runner.*.service
tail -f /opt/actions-runner/_diag/*.log
```

GitHub → Repo → Settings → Actions → Runners should show **Online**.

---

## 4. Credentials & Access

### 4.1 Proxmox API
Create a Proxmox **API token** with limited scope (VM/template operations).  
Save in GitHub as **Repository Secrets**:
- `PROXMOX_URL` (e.g., `https://proxmox.lan:8006/api2/json`)
- `PROXMOX_TOKEN_ID` (e.g., `root@pam!gh-runner`)
- `PROXMOX_TOKEN_SECRET`
- Optionally: `PROXMOX_NODE`, `PROXMOX_STORAGE`, `PROXMOX_BRIDGE`

### 4.2 AWS for Terraform backend
In GitHub **Repository Secrets**:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

In GitHub **Repository Variables** (non-secret):
- `AWS_REGION` (e.g., `us-east-2`)

> Ensure your IAM policy has S3 (bucket/key) and DynamoDB (table) permissions.

### 4.3 Optional: Kube/Talos artifacts
If some jobs need to run `kubectl/helm` outside Terraform:
- Store a short-lived kubeconfig as a GitHub **secret** (e.g., `KUBECONFIG_B64`).
- Most automation fetches kubeconfig via the **Talos provider**, so this is optional.

---
