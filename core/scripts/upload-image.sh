#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tfvars="${repo_root}/terraform/terraform.tfvars"
workdir="${repo_root}/runner_artifacts"; mkdir -p "$workdir"; cd "$workdir"

tf_get() { local k="$1"; sed -nE "s/^[[:space:]]*${k}[[:space:]]*=[[:space:]]*\"(.*)\"[[:space:]]*$/\1/p" "$tfvars" | head -n1; }

pm_node="$(tf_get pm_node)"
dir_storage="$(tf_get PROXMOX_DIR_STORAGE)"
xz_url="$(tf_get talos_image_url)"
xz_name="$(tf_get talos_image_file_name)"          # ...raw.xz
raw_name="${xz_name%.xz}"                           # ...raw
img_name="${raw_name%.raw}.img"                     # ...img  <-- upload under ISO as .img

endpoint="${PROXMOX_VE_ENDPOINT}"
[[ "$endpoint" =~ ^https?:// ]] || endpoint="https://${endpoint}"
base="${endpoint%/api2/json}"
auth="Authorization: PVEAPIToken=${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN_SECRET}"

# 1) download compressed RAW if needed
[[ -f "$xz_name" ]] || { echo "Downloading: $xz_url"; curl -fSL -o "$xz_name" "$xz_url"; }

# 2) decompress to RAW if needed
[[ -f "$raw_name" ]] || { echo "Decompressing: $xz_name -> $raw_name"; xz -T0 -dv "$xz_name"; }

# 3) rename bytes to .img for ISO upload (same content, accepted extension)
if [[ ! -f "$img_name" ]]; then
  echo "Preparing upload file: $img_name"
  mv -f "$raw_name" "$img_name"
fi

# 4) upload to directory storage as ISO content
echo "Uploading ${img_name} to ${dir_storage}:iso/${img_name}"
curl -fSLk -X POST \
  -H "$auth" \
  -F "content=iso" \
  -F "filename=@${img_name};type=application/octet-stream;filename=${img_name}" \
  "${base}/api2/json/nodes/${pm_node}/storage/${dir_storage}/upload"

# quick verify
"${repo_root}/scripts/check-image.sh"
