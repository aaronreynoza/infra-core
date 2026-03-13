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
    qm set 99 --ipconfig0 ip=REDACTED_MGMT_IP/24,gw=192.168.1.1
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
