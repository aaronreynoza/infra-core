#!/usr/bin/env bash
set -euo pipefail

# Accept BOTH flag-style and positional args:
#   Flags:      --pm-ssh user@host  --api-server https://IP:6443  --cluster-name talos
#   Positionals: <pm-ssh> <api-server> <cluster-name>
#
# This avoids "Unknown arg: user@host" errors from Terraform local-exec.

pm_ssh="${PM_SSH:-}"
api_server="${API_SERVER:-}"
cluster_name="${CLUSTER_NAME:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pm-ssh)       pm_ssh="${2:-}"; shift 2 ;;
    --api-server)   api_server="${2:-}"; shift 2 ;;
    --cluster-name) cluster_name="${2:-}"; shift 2 ;;
    --*)            echo "Unknown flag: $1" >&2; exit 1 ;;
    *)              # collect leftover positionals in order
                    if [[ -z "${pm_ssh}" ]]; then
                      pm_ssh="$1"
                    elif [[ -z "${api_server}" ]]; then
                      api_server="$1"
                    elif [[ -z "${cluster_name}" ]]; then
                      cluster_name="$1"
                    else
                      echo "Unexpected extra arg: $1" >&2; exit 1
                    fi
                    shift ;;
  esac
done

if [[ -z "${pm_ssh}" || -z "${api_server}" || -z "${cluster_name}" ]]; then
  cat >&2 <<EOF
Usage:
  $(basename "$0") --pm-ssh user@host --api-server https://IP:6443 --cluster-name NAME
  (or) $(basename "$0") <user@host> <https://IP:6443> <NAME>
EOF
  exit 1
fi

# Workspace
workdir="$(mktemp -d)"
cleanup() { rm -rf "${workdir}"; }
trap cleanup EXIT

seed_dir="${workdir}/cidata"
mkdir -p "${seed_dir}"

# Minimal Cloud-Init seed; content can be expanded as needed.
# meta-data can be empty; user-data sets hostname and drops a note with the API server.
cat > "${seed_dir}/meta-data" <<EOF
instance-id: ${cluster_name}
local-hostname: ${cluster_name}
EOF

cat > "${seed_dir}/user-data" <<EOF
#cloud-config
hostname: ${cluster_name}
write_files:
  - path: /etc/kubernetes/api-endpoint.txt
    permissions: '0644'
    owner: root:root
    content: |
      ${api_server}
EOF

iso="${workdir}/${cluster_name}-cidata.iso"

# Pick an ISO creator available on the runner
iso_tool=""
if command -v mkisofs >/dev/null 2>&1; then
  iso_tool="mkisofs -J -R -V cidata -o \"${iso}\" \"${seed_dir}\""
elif command -v genisoimage >/dev/null 2>&1; then
  iso_tool="genisoimage -J -R -V cidata -o \"${iso}\" \"${seed_dir}\""
elif command -v xorriso >/dev/null 2>&1; then
  # xorriso needs different flags to mimic genisoimage
  iso_tool="xorriso -as genisoimage -J -R -V cidata -o \"${iso}\" \"${seed_dir}\""
else
  echo "ERROR: Need mkisofs or genisoimage or xorriso installed on the runner." >&2
  exit 1
fi

eval ${iso_tool}

# Push ISO to Proxmox default ISO directory
# Adjust the path if you keep ISOs elsewhere.
remote_iso_dir="/var/lib/vz/template/iso"
ssh -o StrictHostKeyChecking=no "${pm_ssh}" "mkdir -p '${remote_iso_dir}'"
scp -o StrictHostKeyChecking=no "${iso}" "${pm_ssh}:${remote_iso_dir}/"

echo "OK: Uploaded $(basename "${iso}") to ${pm_ssh}:${remote_iso_dir}/"
