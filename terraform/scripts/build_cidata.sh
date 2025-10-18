#!/usr/bin/env bash
#
# build_cidata.sh
# ----------------
# Create cloud-init "CIDATA" ISOs for one or more nodes and upload them
# to a Proxmox host's ISO storage.
#
# Usage:
#   build_cidata.sh <user@proxmox-host> <kube_api_url> <cluster_name> [nodes]
#
# Args:
#   1) user@host          SSH target to your Proxmox node (e.g., root@REDACTED_MGMT_IP)
#   2) kube_api_url       (kept for compatibility; not strictly needed here)
#   3) cluster_name       (kept for compatibility; used in metadata only)
#   4) nodes              OPTIONAL. Comma-separated list (e.g., "w1,w2").
#                         Defaults to "w1,w2" if omitted/empty.
#
# Output:
#   Prints lines like "local:iso/<node>-cidata.iso" for each generated ISO.
#
# Notes:
#   - This script purposefully does NOT assume Talos needs cloud-init. The ISOs
#     simply include minimal meta-data/user-data so Proxmox can attach them.
#   - If you want to inject real configs, replace the USER_DATA content below.
#   - Requires mkisofs OR genisoimage OR xorriso on the local runner.
#   - Needs passwordless SSH or an ssh-agent loaded with a key that can sudo on the remote.
#
set -euo pipefail

#######################################
# Args & defaults
#######################################
PM_SSH_TARGET=${1:?usage: $0 <user@host> <kube_api_url> <cluster_name> [nodes]}
KUBE_API_URL=${2:?kube_api_url required}
CLUSTER_NAME=${3:?cluster_name required}
NODES_ARG=${4:-}

# Default nodes list if none provided
if [[ -z "${NODES_ARG}" ]]; then
  NODES_ARG="w1,w2"
fi

# Convert comma-separated to array
IFS=',' read -r -a NODES <<< "${NODES_ARG}"

#######################################
# Locate ISO tool
#######################################
have_cmd() { command -v "$1" >/dev/null 2>&1; }

ISO_TOOL=""
if have_cmd mkisofs; then
  ISO_TOOL="mkisofs"
elif have_cmd genisoimage; then
  ISO_TOOL="genisoimage"
elif have_cmd xorriso; then
  # xorriso fallback uses -as mkisofs compatibility mode
  ISO_TOOL="xorriso"
else
  echo "ERROR: Need mkisofs or genisoimage or xorriso installed on the runner." >&2
  exit 1
fi

#######################################
# Remote prep
#######################################
REMOTE_ISO_DIR="/var/lib/vz/template/iso"
# Make sure the ISO dir exists on Proxmox
ssh -o StrictHostKeyChecking=accept-new "${PM_SSH_TARGET}" "sudo mkdir -p '${REMOTE_ISO_DIR}' && sudo chown root:root '${REMOTE_ISO_DIR}'"

#######################################
# Work dir
#######################################
WORKDIR="$(mktemp -d -t cidata-XXXXXXXX)"
cleanup() {
  rm -rf "${WORKDIR}" || true
}
trap cleanup EXIT

#######################################
# Helper: build a single node’s ISO
#######################################
build_one() {
  local node="$1"
  local node_dir="${WORKDIR}/${node}"
  mkdir -p "${node_dir}"

  # Minimal meta-data & user-data. Adjust to your needs.
  # meta-data: set hostname & instance-id (helps cloud-init consumers; harmless otherwise)
  cat > "${node_dir}/meta-data" <<EOF
instance-id: ${node}
local-hostname: ${node}
cluster-name: ${CLUSTER_NAME}
EOF

  # user-data: empty but valid YAML to keep cloud-init happy if present
  # Replace with real content if you want to inject anything.
  cat > "${node_dir}/user-data" <<'EOF'
#cloud-config
# Intentionally minimal. Extend as needed.
EOF

  local iso_name="${node}-cidata.iso"
  local iso_path="${WORKDIR}/${iso_name}"

  if [[ "${ISO_TOOL}" == "xorriso" ]]; then
    # xorriso (mkisofs compat mode)
    xorriso -as mkisofs -volid cidata -joliet -rock \
      -output "${iso_path}" \
      "${node_dir}/user-data" "${node_dir}/meta-data"
  else
    # mkisofs / genisoimage
    "${ISO_TOOL}" -volid cidata -joliet -rock \
      -output "${iso_path}" \
      "${node_dir}/user-data" "${node_dir}/meta-data"
  fi

  # Upload: scp to /tmp then move with sudo into the ISO store
  local remote_tmp="/tmp/${iso_name}"
  scp -o StrictHostKeyChecking=accept-new "${iso_path}" "${PM_SSH_TARGET}:${remote_tmp}"
  ssh -o StrictHostKeyChecking=accept-new "${PM_SSH_TARGET}" "sudo mv '${remote_tmp}' '${REMOTE_ISO_DIR}/${iso_name}' && sudo chmod 0644 '${REMOTE_ISO_DIR}/${iso_name}'"

  # Print the Proxmox storage reference path expected by Terraform
  echo "local:iso/${iso_name}"
}

#######################################
# Build all requested nodes
#######################################
for n in "${NODES[@]}"; do
  # Trim whitespace just in case
  n="$(echo "${n}" | awk '{$1=$1;print}')"
  [[ -z "${n}" ]] && continue
  build_one "${n}"
done
