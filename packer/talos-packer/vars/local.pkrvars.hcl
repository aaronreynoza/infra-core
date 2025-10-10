# Non-secret, repo-safe values
proxmox_storage        = "local-lvm"          # where the VM disk lives
cloudinit_storage_pool = "local-lvm"          # where the cloud-init disk lives
vm_id                  = "9702"               # pick an unused ID
cpu_type               = "host"               # or "kvm64"
cores                  = "2"                  # must be a string in this template
talos_version          = "v1.10.4"            # or whatever you want
base_iso_file          = "local:iso/archlinux-2024.06.01-x86_64.iso"  # matches your uploaded ISO
