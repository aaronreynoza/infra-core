#!/usr/bin/env bash
set -euo pipefail

# Args
PM_SSH_HOST="${1:?usage: $0 <pm_ssh_host> <node_name> <machineconfig_path> [iso_dir] [storage_prefix]}"
NODE_NAME="${2:?missing node_name}"
MC_PATH="${3:?missing machineconfig_path}"
ISO_DIR="${4:-/var/lib/vz/template/iso}"
STORAGE_PREFIX="${5:-local:iso}"

SSH_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=yes"
ISO_PATH="$ISO_DIR/${NODE_NAME}-cidata.iso"

# Sanity
[ -f "$MC_PATH" ] || { echo "machineconfig not found: $MC_PATH"; exit 2; }

# Create temp workspace on Proxmox
ssh $SSH_OPTS "$PM_SSH_HOST" "mkdir -p '$ISO_DIR' '/tmp/cidata-$NODE_NAME' && rm -f '$ISO_PATH'"

# meta-data
ssh $SSH_OPTS "$PM_SSH_HOST" "bash -lc 'cat > /tmp/cidata-$NODE_NAME/meta-data <<META
instance-id: $NODE_NAME
local-hostname: $NODE_NAME
META'"

# user-data (Talos YAML) — base64 stream to avoid quoting issues
base64 -w0 < "$MC_PATH" | ssh $SSH_OPTS "$PM_SSH_HOST" "base64 -d > /tmp/cidata-$NODE_NAME/user-data"

# Build ISO
ssh $SSH_OPTS "$PM_SSH_HOST" "genisoimage -quiet -output '$ISO_PATH' -volid cidata -joliet -rock /tmp/cidata-$NODE_NAME/user-data /tmp/cidata-$NODE_NAME/meta-data"

# Cleanup
ssh $SSH_OPTS "$PM_SSH_HOST" "rm -rf '/tmp/cidata-$NODE_NAME'"

# Output attach-id (so you can see/use it easily)
echo "${STORAGE_PREFIX}/${NODE_NAME}-cidata.iso"
