locals {
  # Derive filename from a Talos image URL
  # Strips .raw.zst / .raw.xz / .zst to produce .img
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

  # Collect unique worker image URLs (only those that differ from the default)
  worker_image_overrides = toset([
    for w in var.workers : w.image_url if w.image_url != null
  ])

  # Map each worker to its resolved image ID
  worker_image_ids = {
    for w in var.workers : w.name => (
      w.image_url != null
      ? proxmox_virtual_environment_download_file.worker_image[w.image_url].id
      : proxmox_virtual_environment_download_file.talos_image.id
    )
  }
}
