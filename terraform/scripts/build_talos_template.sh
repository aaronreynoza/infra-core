#!/usr/bin/env bash
set -euo pipefail

# Args
PM_SSH_HOST="${1:?usage: $0 <pm_ssh_host> <talos_raw_url> <template_vmid> <template_name> <vm_storage> <bridge>}"
TALOS_RAW_URL="${2:?missing talos_raw_url}"
TEMPLATE_VMID="${3:?missing template_vmid}"
TEMPLATE_NAME="${4:?missing template_name}"
VM_STORAGE="${5:?missing vm_storage}"
BRIDGE="${6:?missing bridge}"

SSH_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=yes"
ISO_DIR="/var/lib/vz/template/iso"
IMG_XZ="$ISO_DIR/talos.raw.xz"
IMG_RAW="$ISO_DIR/talos.raw"

# 1) Fetch & unpack image
ssh $SSH_OPTS "$PM_SSH_HOST" "mkdir -p '$ISO_DIR' && rm -f '$IMG_XZ' '$IMG_RAW' || true"
ssh $SSH_OPTS "$PM_SSH_HOST" "curl -fsSL '$TALOS_RAW_URL' -o '$IMG_XZ'"
ssh $SSH_OPTS "$PM_SSH_HOST" "xz -T0 -f -d '$IMG_XZ' || true"

# 2) Recreate template shell
ssh $SSH_OPTS "$PM_SSH_HOST" "qm stop $TEMPLATE_VMID >/dev/null 2>&1 || true"
ssh $SSH_OPTS "$PM_SSH_HOST" "qm destroy $TEMPLATE_VMID --purge >/dev/null 2>&1 || true"

ssh $SSH_OPTS "$PM_SSH_HOST" \
  "qm create $TEMPLATE_VMID --name '$TEMPLATE_NAME' \
     --memory 2048 --cores 2 --sockets 1 \
     --agent 0 --ostype l26 \
     --net0 virtio,bridge='$BRIDGE' \
     --scsihw virtio-scsi-single \
     --serial0 socket --vga serial0"

# 3) Import disk, set boot, convert to template
ssh $SSH_OPTS "$PM_SSH_HOST" "qm importdisk $TEMPLATE_VMID '$IMG_RAW' '$VM_STORAGE' --format raw"
ssh $SSH_OPTS "$PM_SSH_HOST" "qm set $TEMPLATE_VMID --scsi0 ${VM_STORAGE}:vm-${TEMPLATE_VMID}-disk-0"
ssh $SSH_OPTS "$PM_SSH_HOST" "qm set $TEMPLATE_VMID --boot order=scsi0"
ssh $SSH_OPTS "$PM_SSH_HOST" "qm template $TEMPLATE_VMID"
echo "Template '$TEMPLATE_NAME' ($TEMPLATE_VMID) ready."
