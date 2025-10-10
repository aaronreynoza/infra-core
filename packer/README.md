# Packer: Talos Template (Proxmox)

This builds a reusable **Talos** VM template on Proxmox using the Talos **NoCloud** disk image.

## Prerequisites
- Self-hosted GitHub Actions runner (on your Proxmox network).
- Proxmox API token stored as **repo secrets**:
  - `PROXMOX_URL` — e.g. `https://pve.your.lan:8006/api2/json`
  - `PROXMOX_TOKEN_ID` — e.g. `root@pam!gh-runner`
  - `PROXMOX_TOKEN_SECRET`
  - `PROXMOX_NODE` — e.g. `pve`
  - Optional: `PROXMOX_STORAGE` (default `local-lvm`), `PROXMOX_BRIDGE` (default `vmbr0`)
- **Repo variables** (optional):
  - `TALOS_VERSION` (default `v1.7.4`)
  - `TALOS_IMAGE_URL` (defaults to matching NoCloud image for TALOS_VERSION)

## Run
Trigger the **packer-build** workflow. It will create a template named:
