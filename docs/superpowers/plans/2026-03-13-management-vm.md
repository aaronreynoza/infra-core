# Management VM (ID 99) Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a management VM (ID 99) with Ansible-automated setup — break-glass access to K8s/VLAN 10, and future Forgejo Actions runner for Terraform automation.

**Architecture:** Manual VM creation in Proxmox (not Terraform-managed), Debian 12 cloud image, dual-homed networking (management + VLAN 10), Ansible playbook for reproducible software setup. The VM must be rebuildable from scratch.

**Tech Stack:** Proxmox, Debian 12, Ansible, ufw, fail2ban

**Spec:** `docs/superpowers/specs/2026-03-13-forgejo-infra-platform-design.md` (Sub-Project 1)

---

## File Structure

| File | Responsibility |
|------|---------------|
| `core/ansible/inventories/mgmt/hosts.ini` (create) | Inventory for management VM |
| `core/ansible/playbooks/setup-mgmt-vm.yml` (create) | Main playbook orchestrating all roles |
| `core/ansible/requirements.yml` (create) | Ansible Galaxy collection dependencies |
| `core/ansible/roles/mgmt-base/tasks/main.yml` (create) | Core packages, timezone, locale, sudoers |
| `core/ansible/roles/mgmt-security/tasks/main.yml` (create) | SSH hardening, ufw, fail2ban |
| `core/ansible/roles/mgmt-security/templates/sshd_config.j2` (create) | SSH config template |
| `core/ansible/roles/mgmt-network/tasks/main.yml` (create) | VLAN 10 tagged interface |
| `core/ansible/roles/mgmt-network/templates/interfaces.j2` (create) | Network config template |
| `core/ansible/roles/mgmt-tools/tasks/main.yml` (create) | terraform, kubectl, talosctl, helm, sops, age, aws CLI, argocd CLI |
| `core/ansible/roles/mgmt-runner/tasks/main.yml` (create) | forgejo-runner install + systemd service |
| `core/ansible/roles/mgmt-runner/templates/forgejo-runner.service.j2` (create) | systemd unit template |
| `docs/runbooks/mgmt-vm-setup.md` (create) | Step-by-step bootstrap runbook |

**Prerequisites:** Before running the playbook, install required Ansible collections:
```bash
cd core/ansible
ansible-galaxy collection install -r requirements.yml
```

---

## Chunk 1: Manual VM Creation and Runbook

### Task 1: Create Bootstrap Runbook

**Files:**
- Create: `docs/runbooks/mgmt-vm-setup.md`

**Context:** This runbook documents every manual step needed to create the VM in Proxmox and get it to a state where Ansible can take over. It's the single source of truth for rebuilding from zero.

- [ ] **Step 1: Create the runbook**

```markdown
# Management VM Setup Runbook

## Prerequisites
- Proxmox host (daytona) accessible at REDACTED_PVE_IP
- Debian 12 cloud image downloaded
- SSH public key ready (~/.ssh/id_ed25519.pub or similar)

## 1. Download Debian 12 Cloud Image

On the Proxmox host (SSH or web shell):

    cd /var/lib/vz/template/iso
    wget https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2

## 2. Create VM 99 in Proxmox

In the Proxmox web UI (https://REDACTED_PVE_IP:8006):

1. Click **Create VM**
2. **General**: VM ID = `99`, Name = `mgmt`
3. **OS**: Do not use any media (we'll import the disk)
4. **System**: BIOS = Default, SCSI Controller = VirtIO SCSI
5. **Disks**: Delete the default disk (we'll import the cloud image)
6. **CPU**: 2 cores
7. **Memory**: 4096 MB
8. **Network**: Bridge = `vmbr1`, VLAN tag = (leave empty, untagged for management)
9. Click **Finish** (do not start)

## 3. Import Cloud Image Disk

On the Proxmox host shell:

    qm importdisk 99 /var/lib/vz/template/iso/debian-12-generic-amd64.qcow2 local-lvm
    qm set 99 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-99-disk-0
    qm resize 99 scsi0 32G
    qm set 99 --boot order=scsi0
    qm set 99 --serial0 socket --vga serial0

## 4. Configure Cloud-Init

    qm set 99 --ide2 local-lvm:cloudinit
    # First, copy your SSH public key to the Proxmox host
    # From workstation:
    #   scp ~/.ssh/id_ed25519.pub root@REDACTED_PVE_IP:/tmp/mgmt_key.pub

    qm set 99 --ciuser operator
    qm set 99 --sshkeys /tmp/mgmt_key.pub
    qm set 99 --ipconfig0 ip=REDACTED_MGMT_IP/24,gw=REDACTED_MGMT_GW
    qm set 99 --nameserver 1.1.1.1
    qm set 99 --searchdomain local

## 5. Set Auto-Start

    qm set 99 --onboot 1 --startup order=2

## 6. Start the VM

    qm start 99

## 7. Verify SSH Access

From workstation:

    ssh operator@REDACTED_MGMT_IP

If using a non-default key:

    ssh -i ~/.ssh/id_ed25519 operator@REDACTED_MGMT_IP

Expected: Shell prompt as `operator@mgmt`.

## 8. Run Ansible Playbook

From the homelab repo on your workstation:

    cd core/ansible
    ansible-galaxy collection install -r requirements.yml
    ansible-playbook -i inventories/mgmt/hosts.ini playbooks/setup-mgmt-vm.yml

## 9. Manual Post-Ansible Steps

These cannot be automated (contain secrets):

### Copy SOPS age key
    scp ~/.config/sops/age/keys.txt operator@REDACTED_MGMT_IP:~/.config/sops/age/keys.txt

### Copy AWS credentials
    scp ~/.aws/credentials operator@REDACTED_MGMT_IP:~/.aws/credentials

### Clone repos
    ssh operator@REDACTED_MGMT_IP
    git clone https://github.com/aaronreynoza/homelab.git ~/homelab
    git clone <environments-repo-url> ~/environments

### Copy kubeconfig and talosconfig
    scp environments/prod/kubeconfig operator@REDACTED_MGMT_IP:~/.kube/config
    scp environments/prod/talosconfig operator@REDACTED_MGMT_IP:~/.talos/config

## 10. Verify

    ssh operator@REDACTED_MGMT_IP
    kubectl get nodes          # Should see K8s nodes
    talosctl health            # Should report healthy
    terraform version          # Should show installed version
    sops --version             # Should show installed version

## 11. Register Forgejo Actions Runner

**Skip this step until Sub-Project 2 (Forgejo source of truth) is complete.**

    forgejo-runner register \
      --instance http://REDACTED_LB_IP:3000 \
      --token <runner-token-from-forgejo-admin-panel> \
      --labels self-hosted,linux,x64,infra \
      --name mgmt-infra-runner

    sudo systemctl enable --now forgejo-runner
    sudo systemctl status forgejo-runner
```

- [ ] **Step 2: Commit the runbook**

```bash
git add docs/runbooks/mgmt-vm-setup.md
git commit -m "docs: add management VM bootstrap runbook"
```

---

## Chunk 2: Ansible Inventory and Playbook

### Task 2: Create Ansible Inventory for Management VM

**Files:**
- Create: `core/ansible/inventories/mgmt/hosts.ini`

**Context:** The existing inventory at `core/ansible/inventories/local/hosts.ini` targets localhost. The management VM needs its own inventory targeting the VM over SSH.

- [ ] **Step 1: Create inventory file**

```ini
[mgmt]
REDACTED_MGMT_IP ansible_user=operator ansible_ssh_private_key_file=~/.ssh/id_ed25519

[mgmt:vars]
ansible_python_interpreter=/usr/bin/python3
mgmt_ip=REDACTED_MGMT_IP
vlan10_ip=REDACTED_VLAN_IP
vlan10_gateway=10.10.10.1
vlan_id=10
hostname=mgmt
# NIC name — verify after first boot with 'ip link show'. Cloud images on Proxmox
# typically use ens18 but it depends on PCI slot assignment.
primary_nic=ens18
```

---

### Task 3: Create Main Playbook

**Files:**
- Create: `core/ansible/playbooks/setup-mgmt-vm.yml`

**Context:** This is the entry point. It orchestrates all roles in the correct order: base packages first, then networking, security, tools, and finally the runner. Each role is independently useful.

- [ ] **Step 1: Create `core/ansible/requirements.yml`**

```yaml
---
collections:
  - name: community.general
    version: ">=9.0.0"
  - name: ansible.posix
    version: ">=1.5.0"
```

- [ ] **Step 2: Create the playbook**

```yaml
---
- name: Set up management VM
  hosts: mgmt
  become: true

  roles:
    - role: mgmt-base
      tags: [base]
    - role: mgmt-network
      tags: [network]
    - role: mgmt-security
      tags: [security]
    - role: mgmt-tools
      tags: [tools]
    - role: mgmt-runner
      tags: [runner]
```

- [ ] **Step 3: Commit inventory, requirements, and playbook**

```bash
git add core/ansible/inventories/mgmt/hosts.ini core/ansible/requirements.yml core/ansible/playbooks/setup-mgmt-vm.yml
git commit -m "feat: add management VM Ansible inventory and playbook"
```

---

## Chunk 3: Ansible Roles

### Task 4: Create mgmt-base Role

**Files:**
- Create: `core/ansible/roles/mgmt-base/tasks/main.yml`

**Context:** Installs core packages, sets hostname, timezone, locale, and enables unattended-upgrades. This is the foundation all other roles depend on.

- [ ] **Step 1: Create the role**

```yaml
---
- name: Set hostname
  ansible.builtin.hostname:
    name: "{{ hostname }}"

- name: Update apt cache
  ansible.builtin.apt:
    update_cache: true
    cache_valid_time: 3600

- name: Upgrade all packages
  ansible.builtin.apt:
    upgrade: dist

- name: Install core packages
  ansible.builtin.apt:
    name:
      - git
      - tmux
      - curl
      - wget
      - jq
      - unzip
      - dnsutils
      - traceroute
      - htop
      - unattended-upgrades
      - apt-transport-https
      - ca-certificates
      - gnupg
      - python3-pip
      - python3-venv
      - ifupdown
      - vlan
      - sudo
    state: present

- name: Ensure operator has passwordless sudo
  ansible.builtin.copy:
    content: "operator ALL=(ALL) NOPASSWD: ALL\n"
    dest: /etc/sudoers.d/operator
    mode: "0440"
    validate: visudo -cf %s

- name: Set timezone
  community.general.timezone:
    name: UTC

- name: Enable unattended-upgrades
  ansible.builtin.debconf:
    name: unattended-upgrades
    question: unattended-upgrades/enable_auto_updates
    value: "true"
    vtype: boolean

- name: Create directories for credentials
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
    owner: operator
    group: operator
    mode: "0700"
  loop:
    - /home/operator/.config/sops/age
    - /home/operator/.aws
    - /home/operator/.kube
    - /home/operator/.talos
```

- [ ] **Step 2: Commit**

```bash
git add core/ansible/roles/mgmt-base/tasks/main.yml
git commit -m "feat: add mgmt-base Ansible role"
```

---

### Task 5: Create mgmt-network Role

**Files:**
- Create: `core/ansible/roles/mgmt-network/tasks/main.yml`
- Create: `core/ansible/roles/mgmt-network/templates/interfaces.j2`

**Context:** Configures the VLAN 10 tagged interface so the VM can reach K8s nodes, Forgejo, Harbor, etc. on 10.10.10.0/16. The management network (untagged, REDACTED_MGMT_CIDR) is already configured by cloud-init. The VLAN interface is added on top.

Debian 12 uses `/etc/network/interfaces` for network config. The cloud-init config handles the primary interface (ens18 or similar). We add a VLAN sub-interface.

- [ ] **Step 1: Create the interfaces template**

```jinja2
# VLAN 10 tagged interface for K8s/PROD network access
# Primary interface (management network) is configured by cloud-init
auto {{ primary_nic }}.{{ vlan_id }}
iface {{ primary_nic }}.{{ vlan_id }} inet static
    address {{ vlan10_ip }}/16
    vlan-raw-device {{ primary_nic }}
```

- [ ] **Step 2: Create the role tasks**

```yaml
---
- name: Load 8021q kernel module
  community.general.modprobe:
    name: 8021q
    state: present

- name: Persist 8021q module on boot
  ansible.builtin.lineinfile:
    path: /etc/modules-load.d/8021q.conf
    line: 8021q
    create: true
    mode: "0644"

- name: Configure VLAN 10 interface
  ansible.builtin.template:
    src: interfaces.j2
    dest: /etc/network/interfaces.d/vlan10
    mode: "0644"
  register: vlan_config

- name: Bring up VLAN interface
  ansible.builtin.command: ifup {{ primary_nic }}.{{ vlan_id }}
  when: vlan_config.changed
  changed_when: true
```

- [ ] **Step 3: Commit**

```bash
git add core/ansible/roles/mgmt-network/tasks/main.yml core/ansible/roles/mgmt-network/templates/interfaces.j2
git commit -m "feat: add mgmt-network Ansible role for VLAN 10"
```

---

### Task 6: Create mgmt-security Role

**Files:**
- Create: `core/ansible/roles/mgmt-security/tasks/main.yml`
- Create: `core/ansible/roles/mgmt-security/templates/sshd_config.j2`

**Context:** Hardens SSH (key-only, no root login, AllowUsers), sets up ufw (SSH from management net only), and enables fail2ban. This is a security-critical role.

- [ ] **Step 1: Create the SSH config template**

```jinja2
# Managed by Ansible — do not edit manually
Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key

# Authentication
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM yes

# Restrict to operator user from management network
AllowUsers operator@{{ mgmt_ssh_allow_pattern }}

# Security
X11Forwarding no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
```

- [ ] **Step 2: Create the role tasks**

```yaml
---
- name: Install security packages
  ansible.builtin.apt:
    name:
      - ufw
      - fail2ban
    state: present

- name: Configure SSH
  ansible.builtin.template:
    src: sshd_config.j2
    dest: /etc/ssh/sshd_config
    mode: "0644"
    validate: sshd -t -f %s
  notify: restart sshd

- name: Set UFW default deny incoming
  community.general.ufw:
    direction: incoming
    default: deny

- name: Set UFW default allow outgoing
  community.general.ufw:
    direction: outgoing
    default: allow

- name: Allow SSH from management network
  community.general.ufw:
    rule: allow
    port: "22"
    proto: tcp
    src: "{{ mgmt_network_cidr }}"

- name: Enable UFW
  community.general.ufw:
    state: enabled

- name: Enable fail2ban
  ansible.builtin.systemd:
    name: fail2ban
    enabled: true
    state: started
```

- [ ] **Step 3: Create handlers file**

Create `core/ansible/roles/mgmt-security/handlers/main.yml`:

```yaml
---
- name: restart sshd
  ansible.builtin.systemd:
    name: sshd
    state: restarted
```

- [ ] **Step 4: Commit**

```bash
git add core/ansible/roles/mgmt-security/tasks/main.yml core/ansible/roles/mgmt-security/templates/sshd_config.j2 core/ansible/roles/mgmt-security/handlers/main.yml
git commit -m "feat: add mgmt-security Ansible role"
```

---

### Task 7: Create mgmt-tools Role

**Files:**
- Create: `core/ansible/roles/mgmt-tools/tasks/main.yml`

**Context:** Installs all the DevOps tools needed for infrastructure management. Each tool is installed from its official source with a pinned version. The versions should match what the user is currently running on their workstation (from the version check earlier).

Tool versions to install (pinned to match cluster/workstation):
- terraform: 1.9.8
- kubectl: 1.31.1
- talosctl: 1.12.5 (must match cluster version)
- helm: 3.16.1
- sops: 3.12.1
- age: from apt
- aws CLI: v2 from official installer
- argocd CLI: 2.14.11
- yq: 4.45.4

- [ ] **Step 1: Create the role**

```yaml
---
# --- Terraform ---
- name: Add HashiCorp GPG key
  ansible.builtin.get_url:
    url: https://apt.releases.hashicorp.com/gpg
    dest: /usr/share/keyrings/hashicorp-archive-keyring.asc
    mode: "0644"

- name: Add HashiCorp apt repository
  ansible.builtin.apt_repository:
    repo: "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.asc] https://apt.releases.hashicorp.com bookworm main"
    filename: hashicorp

- name: Install Terraform
  ansible.builtin.apt:
    name: terraform=1.9.8-1
    state: present
    update_cache: true

# --- kubectl ---
- name: Add Kubernetes GPG key
  ansible.builtin.get_url:
    url: https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key
    dest: /usr/share/keyrings/kubernetes-apt-keyring.asc
    mode: "0644"

- name: Add Kubernetes apt repository
  ansible.builtin.apt_repository:
    repo: "deb [signed-by=/usr/share/keyrings/kubernetes-apt-keyring.asc] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /"
    filename: kubernetes

- name: Install kubectl
  ansible.builtin.apt:
    name: kubectl=1.31.1-1.1
    state: present
    update_cache: true

# --- talosctl (must match cluster version) ---
- name: Install talosctl
  ansible.builtin.get_url:
    url: "https://github.com/siderolabs/talos/releases/download/v1.12.5/talosctl-linux-amd64"
    dest: /usr/local/bin/talosctl
    mode: "0755"

# --- Helm ---
- name: Install Helm
  ansible.builtin.unarchive:
    src: "https://get.helm.sh/helm-v3.16.1-linux-amd64.tar.gz"
    dest: /tmp
    remote_src: true

- name: Move Helm binary
  ansible.builtin.copy:
    src: /tmp/linux-amd64/helm
    dest: /usr/local/bin/helm
    mode: "0755"
    remote_src: true

# --- SOPS ---
- name: Install SOPS
  ansible.builtin.get_url:
    url: "https://github.com/getsops/sops/releases/download/v3.12.1/sops-v3.12.1.linux.amd64"
    dest: /usr/local/bin/sops
    mode: "0755"

# --- age ---
- name: Install age
  ansible.builtin.apt:
    name: age
    state: present

# --- AWS CLI v2 ---
- name: Download AWS CLI v2
  ansible.builtin.unarchive:
    src: "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
    dest: /tmp
    remote_src: true

- name: Install AWS CLI v2
  ansible.builtin.command: /tmp/aws/install --update
  changed_when: true

# --- ArgoCD CLI (pinned) ---
- name: Install ArgoCD CLI
  ansible.builtin.get_url:
    url: "https://github.com/argoproj/argo-cd/releases/download/v2.14.11/argocd-linux-amd64"
    dest: /usr/local/bin/argocd
    mode: "0755"

# --- yq (pinned) ---
- name: Install yq
  ansible.builtin.get_url:
    url: "https://github.com/mikefarah/yq/releases/download/v4.45.4/yq_linux_amd64"
    dest: /usr/local/bin/yq
    mode: "0755"

# --- AWS CLI v2 ---
- name: Check if AWS CLI is installed
  ansible.builtin.stat:
    path: /usr/local/bin/aws
  register: aws_cli_check

- name: Download AWS CLI v2
  ansible.builtin.unarchive:
    src: "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
    dest: /tmp
    remote_src: true
  when: not aws_cli_check.stat.exists

- name: Install AWS CLI v2
  ansible.builtin.command: /tmp/aws/install
  when: not aws_cli_check.stat.exists
  changed_when: true

# --- Ansible (in virtualenv to avoid PEP 668) ---
- name: Install Ansible in virtualenv
  ansible.builtin.pip:
    name: ansible
    virtualenv: /opt/ansible-venv
    virtualenv_command: python3 -m venv

- name: Symlink ansible binaries
  ansible.builtin.file:
    src: "/opt/ansible-venv/bin/{{ item }}"
    dest: "/usr/local/bin/{{ item }}"
    state: link
  loop:
    - ansible
    - ansible-playbook
    - ansible-galaxy
```

- [ ] **Step 2: Commit**

```bash
git add core/ansible/roles/mgmt-tools/tasks/main.yml
git commit -m "feat: add mgmt-tools Ansible role"
```

---

### Task 8: Create mgmt-runner Role

**Files:**
- Create: `core/ansible/roles/mgmt-runner/tasks/main.yml`
- Create: `core/ansible/roles/mgmt-runner/templates/forgejo-runner.service.j2`

**Context:** Installs the Forgejo Actions runner (`forgejo-runner`) binary and sets up a systemd service. The runner is NOT registered or started here — registration requires Forgejo to have the repo (Sub-Project 2). This role just gets the binary and service file in place.

- [ ] **Step 1: Create the systemd service template**

```jinja2
[Unit]
Description=Forgejo Actions Runner
After=network.target

[Service]
Type=simple
User=operator
Group=operator
WorkingDirectory=/home/operator
ExecStart=/usr/local/bin/forgejo-runner daemon
Restart=on-failure
RestartSec=10
Environment=SOPS_AGE_KEY_FILE=/home/operator/.config/sops/age/keys.txt

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 2: Create the role tasks**

```yaml
---
- name: Get latest forgejo-runner release URL
  ansible.builtin.uri:
    url: https://code.forgejo.org/api/v1/repos/forgejo/runner/releases/latest
    return_content: true
  register: runner_release

- name: Set forgejo-runner download URL
  ansible.builtin.set_fact:
    runner_url: "{{ runner_release.json.assets | selectattr('name', 'search', 'forgejo-runner-.*-linux-amd64$') | map(attribute='browser_download_url') | first }}"

- name: Download forgejo-runner
  ansible.builtin.get_url:
    url: "{{ runner_url }}"
    dest: /usr/local/bin/forgejo-runner
    mode: "0755"

- name: Install forgejo-runner systemd service
  ansible.builtin.template:
    src: forgejo-runner.service.j2
    dest: /etc/systemd/system/forgejo-runner.service
    mode: "0644"
  notify: reload systemd

- name: Note about registration
  ansible.builtin.debug:
    msg: >
      forgejo-runner is installed but NOT registered.
      Run 'forgejo-runner register' manually after Forgejo has the repo.
      See docs/runbooks/mgmt-vm-setup.md for instructions.
```

- [ ] **Step 3: Create handlers file**

Create `core/ansible/roles/mgmt-runner/handlers/main.yml`:

```yaml
---
- name: reload systemd
  ansible.builtin.systemd:
    daemon_reload: true
```

- [ ] **Step 4: Commit**

```bash
git add core/ansible/roles/mgmt-runner/tasks/main.yml core/ansible/roles/mgmt-runner/templates/forgejo-runner.service.j2 core/ansible/roles/mgmt-runner/handlers/main.yml
git commit -m "feat: add mgmt-runner Ansible role for Forgejo Actions"
```

---

## Chunk 4: Create VM and Run Ansible

### Task 9: Create VM 99 in Proxmox (Manual)

**Context:** This task is done in the Proxmox web UI and host shell. Follow the runbook from Task 1.

- [ ] **Step 1: Follow runbook steps 1-6**

Follow `docs/runbooks/mgmt-vm-setup.md` steps 1 through 6 to:
1. Download Debian 12 cloud image
2. Create VM 99
3. Import disk and resize to 32GB
4. Configure cloud-init (user=operator, SSH key, IP=REDACTED_MGMT_IP)
5. Set auto-start order 2
6. Start the VM

- [ ] **Step 2: Verify SSH access**

Run from workstation: `ssh operator@REDACTED_MGMT_IP 'hostname && ip addr show'`

Expected: Hostname `mgmt`, IP `REDACTED_MGMT_IP` on the primary interface.

---

### Task 10: Run Ansible Playbook

- [ ] **Step 1: Run the playbook**

Run from the homelab repo root:
```bash
cd core/ansible
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventories/mgmt/hosts.ini playbooks/setup-mgmt-vm.yml
```

Expected: All tasks succeed (green/yellow). The VLAN interface comes up, packages install, tools download.

If any tasks fail, fix and re-run. Ansible is idempotent — safe to run multiple times.

- [ ] **Step 2: Verify VLAN 10 connectivity**

```bash
ssh operator@REDACTED_MGMT_IP 'ping -c 3 10.10.10.1'
```

Expected: Pings to OPNSense gateway (10.10.10.1) succeed, confirming VLAN 10 access.

- [ ] **Step 3: Verify K8s access preparation**

```bash
ssh operator@REDACTED_MGMT_IP 'kubectl version --client && talosctl version --client && terraform version && sops --version'
```

Expected: All tools report their versions.

---

### Task 11: Manual Post-Ansible Setup

- [ ] **Step 1: Copy credentials**

Follow runbook step 9:
```bash
scp ~/.config/sops/age/keys.txt operator@REDACTED_MGMT_IP:/home/operator/.config/sops/age/keys.txt
scp ~/.aws/credentials operator@REDACTED_MGMT_IP:/home/operator/.aws/credentials
```

- [ ] **Step 2: Copy kubeconfig and talosconfig**

```bash
scp environments/prod/kubeconfig operator@REDACTED_MGMT_IP:/home/operator/.kube/config
scp environments/prod/talosconfig operator@REDACTED_MGMT_IP:/home/operator/.talos/config
```

- [ ] **Step 3: Verify full access from mgmt VM**

```bash
ssh operator@REDACTED_MGMT_IP
kubectl get nodes
kubectl get pods -n argocd
talosctl --nodes REDACTED_K8S_API health
```

Expected: K8s nodes visible, ArgoCD pods running, Talos reports healthy.

- [ ] **Step 4: Final commit — push all changes**

```bash
git push
```

---

## Summary

After completing all tasks:
- VM 99 (mgmt) running Debian 12 on Proxmox
- Dual-homed: REDACTED_MGMT_IP (management) + REDACTED_VLAN_IP (VLAN 10)
- Hardened: SSH key-only, ufw, fail2ban
- All DevOps tools installed (terraform, kubectl, talosctl, helm, sops, age, aws, argocd)
- act_runner binary installed (not registered — waiting for Sub-Project 2)
- Ansible playbook documented for reproducible rebuild
- Runbook for manual steps

**Next:** Sub-Project 2 — Push repo to Forgejo, configure GitHub mirror, switch ArgoCD.
