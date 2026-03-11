#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tfvars="${repo_root}/terraform/terraform.tfvars"

tf_get() { local k="$1"; sed -nE "s/^[[:space:]]*${k}[[:space:]]*=[[:space:]]*\"(.*)\"[[:space:]]*$/\1/p" "$tfvars" | head -n1; }

pm_node="$(tf_get pm_node)"
dir_storage="$(tf_get PROXMOX_DIR_STORAGE)"
xz_name="$(tf_get talos_image_file_name)"          # ...raw.xz
raw_name="${xz_name%.xz}"                           # ...raw
img_name="${raw_name%.raw}.img"                     # ...img  <-- what we look for in ISO storage

endpoint="${PROXMOX_VE_ENDPOINT}"
[[ "$endpoint" =~ ^https?:// ]] || endpoint="https://${endpoint}"
auth="Authorization: PVEAPIToken=${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN_SECRET}"

resp="$(curl -fSLk -H "$auth" "${endpoint%/}/nodes/${pm_node}/storage/${dir_storage}/content?content=iso")"

match="${dir_storage}:iso/${img_name}"
present="$(echo "$resp" | jq -r '.data[]?.volid // empty' | grep -Fx "${match}" || true)"

if [[ -n "$present" ]]; then
  echo "Found image: ${match}"
  [[ -n "${GITHUB_OUTPUT:-}" ]] && echo "image_present=true" >> "$GITHUB_OUTPUT"
else
  echo "Image not found: ${match}"
  [[ -n "${GITHUB_OUTPUT:-}" ]] && echo "image_present=false" >> "$GITHUB_OUTPUT"
fi
