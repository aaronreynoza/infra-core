#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tfvars="${repo_root}/terraform/terraform.tfvars"

tf_get() {
  local key="$1"
  sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"(.*)\"[[:space:]]*$/\1/p" "$tfvars" | head -n1
}

pm_node="$(tf_get pm_node)"
dir_storage="$(tf_get PROXMOX_DIR_STORAGE)"
xz_name="$(tf_get talos_image_file_name)"
raw_name="${xz_name%.xz}"

endpoint="${PROXMOX_VE_ENDPOINT}"

auth="Authorization: PVEAPIToken=${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN_SECRET}"

resp="$(curl -fSLk -H "$auth" \
  "${endpoint}/nodes/${pm_node}/storage/${dir_storage}/content?content=iso")"

match="${dir_storage}:iso/${raw_name}"
present="$(echo "$resp" | jq -r '.data[].volid // empty' | grep -Fx "${match}" || true)"

if [[ -n "$present" ]]; then
  echo "Found image: ${match}"
  echo "image_present=true" >> "$GITHUB_OUTPUT"
else
  echo "Image not found: ${match}"
  echo "image_present=false" >> "$GITHUB_OUTPUT"
fi
