locals {
  # Extract filename from URL for the Talos image.
  # The URL should end in .raw.zst — we strip the compression suffix to get .img
  # which avoids "wrong file extension" issues on Proxmox < 8.4.
  talos_image_filename = replace(
    replace(
      replace(
        basename(var.talos_image_url),
        ".raw.zst", ".img"
      ),
      ".raw.xz", ".img"
    ),
    ".zst", ".img"
  )
}
