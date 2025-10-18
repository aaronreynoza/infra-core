#!/usr/bin/env bash
# Build tiny cloud-init "cidata" ISOs and upload them to Proxmox "local" storage.
# Robust against missing args/tools and unbound vars.

set -euo pipefail

# ---------- Usage ----------
# ./scripts/build_cidata.sh \
#   --pm-ssh "root@REDACTED_IP" \
#   --cluster-endpoint "https://192.168.100.101:6443" \
#   --user "talos" \
#   --vms "w1,w2"
#
# Expects Proxmox "local" storage (default path /var/lib/vz/template/iso)
# Produces local:iso/<vm>-cidata.iso for each VM name given.

PM_SSH=""
CLUSTER_ENDPOINT=""
USER_NAME="talos"
VMS_CSV="w1,w2"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pm-ssh)            PM_SSH="${2:-}"; shift 2 ;;
    --cluster-endpoint)  CLUSTER_ENDPOINT="${2:-}"; shift 2 ;;
    --user)              USER_NAME="${2:-}"; shift 2 ;;
    --vms)               VMS_CSV="${2:-}"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$PM_SSH" || -z "$CLUSTER_ENDPOINT" || -z "$USER_NAME" || -z "$VMS_CSV" ]]; then
  cat >&2 <<EOF
ERROR: missing required args.

Required:
  --pm-ssh "<user@host>"
  --cluster-endpoint "https://IP:6443"
  --user "<login>"
  --vms "w1,w2"

Example:
  ./scripts/build_cidata.sh --pm-ssh "root@REDACTED_IP" --cluster-endpoint "https://192.168.100.101:6443" --user "talos" --vms "w1,w2"
EOF
  exit 2
fi

# ---------- tool detection ----------
mkiso() {
  local out_iso="$1"
  local src_dir="$2"

  if command -v xorriso >/dev/null 2>&1; then
    xorriso -as mkisofs -V cidata -J -R -input-charset utf-8 -o "$out_iso" "$src_dir"
    return
  fi
  if command -v genisoimage >/dev/null 2>&1; then
    genisoimage -V cidata -J -R -input-charset utf-8 -o "$out_iso" "$src_dir"
    return
  fi
  if command -v mkisofs >/dev/null 2>&1; then
    mkisofs -V cidata -J -R -input-charset utf-8 -o "$out_iso" "$src_dir"
    return
  fi

  echo "ERROR: Need mkisofs or genisoimage or xorriso installed on the runner." >&2
  exit 3
}

# ---------- build workspace ----------
WORK="$(mktemp -d)"
OUT_DIR="$WORK/isos"
mkdir -p "$OUT_DIR"

IFS=',' read -r -a VM_NAMES <<< "$VMS_CSV"

for VM in "${VM_NAMES[@]}"; do
  VM_DIR="$WORK/${VM}-cidata"
  mkdir -p "$VM_DIR"

  # Minimal cloud-init files (adjust contents to your Talos/OS needs).
  # meta-data
  cat > "${VM_DIR}/meta-data" <<EOF
instance-id: ${VM}
local-hostname: ${VM}
EOF

  # user-data
  cat > "${VM_DIR}/user-data" <<EOF
#cloud-config
users:
  - name: ${USER_NAME}
    lock_passwd: true
    shell: /bin/bash
ssh_authorized_keys: []
write_files:
  - path: /etc/cluster-endpoint
    permissions: '0644'
    content: |
      ${CLUSTER_ENDPOINT}
runcmd:
  - [ bash, -lc, "echo 'cidata for ${VM} applied'" ]
EOF

  ISO_PATH="${OUT_DIR}/${VM}-cidata.iso"
  mkiso "$ISO_PATH" "$VM_DIR"
done

# ---------- upload to Proxmox local storage ----------
# Proxmox "local" storage (content iso) -> /var/lib/vz/template/iso
REMOTE_ISO_DIR="/var/lib/vz/template/iso"
ssh -o StrictHostKeyChecking=no "$PM_SSH" "mkdir -p '$REMOTE_ISO_DIR'"

for VM in "${VM_NAMES[@]}"; do
  ISO_PATH="${OUT_DIR}/${VM}-cidata.iso"
  scp -o StrictHostKeyChecking=no "$ISO_PATH" "${PM_SSH}:${REMOTE_ISO_DIR}/"
done

# Print terraform-friendly output (one per line: vm=local:iso/vm-cidata.iso)
for VM in "${VM_NAMES[@]}"; do
  echo "${VM}=local:iso/${VM}-cidata.iso"
done
