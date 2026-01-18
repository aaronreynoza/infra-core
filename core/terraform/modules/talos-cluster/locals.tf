locals {
  # Extract filename from URL for the Talos image
  talos_image_filename = replace(
    replace(
      basename(var.talos_image_url),
      ".raw.xz", ".img"
    ),
    ".xz", ".img"
  )
}
