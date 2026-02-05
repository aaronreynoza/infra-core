# ADR-002: TrueNAS Storage for Media Files

**Status:** Proposed
**Date:** 2026-02-01
**Author:** Aaron Valdez

## Context

Currently, all persistent storage in the homelab uses Longhorn volumes on Talos nodes. This works well for databases and application configs, but creates problems for media files:

**Problems with Longhorn-only storage:**
1. **No easy file access**: Can't browse/upload files without kubectl exec
2. **Phone upload impossible**: No way to upload music/videos from mobile devices
3. **No web UI for file management**: Must use CLI tools
4. **Single-node limitation**: All data on one disk, no redundancy
5. **Not designed for large files**: Longhorn is optimized for database workloads, not media streaming

**What we want:**
- Upload music from phone to Jellyfin library
- Browse and manage media files via web UI
- Access files from any device on the network
- Keep Kubernetes apps working seamlessly

## Decision

Implement a **hybrid storage model** using:

1. **TrueNAS** (VM or dedicated hardware) for media/large files
2. **Longhorn** for app configs and databases
3. **NFS CSI** or static NFS PVs for Kubernetes to access TrueNAS

This matches William's proven approach in his homelab.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     User Access                              │
├─────────────────────────────────────────────────────────────┤
│  Phone/Tablet    │   Desktop      │   Kubernetes Pods       │
│  (TrueNAS App)   │  (SMB/Web UI)  │   (NFS mounts)          │
└────────┬─────────┴───────┬────────┴────────────┬────────────┘
         │                 │                      │
         ▼                 ▼                      ▼
┌─────────────────────────────────────────────────────────────┐
│                      TrueNAS                                 │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  ZFS Pool (tank)                                      │   │
│  │  ├── media/           (movies, music, videos)        │   │
│  │  ├── downloads/       (staging area)                 │   │
│  │  └── backups/         (Velero backup target)         │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  Shares:                                                     │
│  • NFS → Kubernetes (10.10.10.0/16)                         │
│  • SMB → Desktop/Laptop                                      │
│  • WebDAV → Phone (or TrueNAS mobile app)                   │
└─────────────────────────────────────────────────────────────┘
         │
         │ NFS
         ▼
┌─────────────────────────────────────────────────────────────┐
│                   Kubernetes (Talos)                         │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Jellyfin Pod                                          │ │
│  │  ├── /config      → Longhorn PVC (app database)       │ │
│  │  └── /media       → NFS PVC (TrueNAS media share)     │ │
│  └────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  *arr Stack (Radarr, Sonarr, etc.)                     │ │
│  │  ├── /config      → Longhorn PVC                       │ │
│  │  ├── /media       → NFS PVC (TrueNAS media share)     │ │
│  │  └── /downloads   → NFS PVC (TrueNAS downloads share) │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Storage Split

| Data Type | Storage | Why |
|-----------|---------|-----|
| App configs (SQLite, settings) | Longhorn | Fast local block storage, snapshotable |
| Databases (PostgreSQL, etc.) | Longhorn | Block storage required, single-writer |
| Media files (movies, music) | TrueNAS NFS | Easy access, multi-reader, large files |
| Downloads (staging) | TrueNAS NFS | Shared between arr apps |
| Backups (Velero) | TrueNAS NFS | Large sequential writes |
| Photos (Immich) | TrueNAS NFS | Easy access from phone |

## Implementation Options

### Option A: TrueNAS VM on Proxmox (Recommended)

**Pros:**
- No additional hardware needed
- Easy to set up and manage
- Can pass through HBA for direct disk access
- Snapshot VM for easy recovery

**Cons:**
- Shares Proxmox host resources
- Single point of failure if Proxmox host dies

**Requirements:**
- Dedicated disks for ZFS (don't use Proxmox boot drive)
- 8GB+ RAM for TrueNAS VM
- Ideally HBA passthrough for ZFS

### Option B: Dedicated TrueNAS Hardware

**Pros:**
- Dedicated resources
- True storage appliance
- Better isolation

**Cons:**
- Requires additional hardware
- More power/space

### Option C: Synology/QNAP NAS

**Pros:**
- Polished mobile apps
- Easy setup

**Cons:**
- Expensive
- Less flexible than TrueNAS

## Recommended Approach: Option A (TrueNAS VM)

### Phase 1: Deploy TrueNAS VM

1. Create TrueNAS VM on your Proxmox host
2. Allocate dedicated disk(s) for ZFS pool
3. Configure network (VLAN 10 for prod access)
4. Create ZFS datasets:
   - `tank/media` (movies, music, videos)
   - `tank/downloads`
   - `tank/backups`

### Phase 2: Configure Shares

1. **NFS shares** for Kubernetes:
   - `/mnt/tank/media` → `nfs://truenas/media`
   - `/mnt/tank/downloads` → `nfs://truenas/downloads`
   - Configure `all_squash` with UID/GID matching pod security context

2. **SMB shares** for desktop access:
   - `/mnt/tank/media` → `\\truenas\media`

3. **WebDAV or TrueNAS app** for phone access

### Phase 3: Kubernetes Integration

Create NFS PersistentVolumes and PersistentVolumeClaims:

```yaml
# nfs-media-pv.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-media
spec:
  capacity:
    storage: 1Ti
  accessModes:
    - ReadWriteMany
  nfs:
    server: 10.10.10.X  # TrueNAS IP
    path: /mnt/tank/media
  mountOptions:
    - nfsvers=4.1
    - hard
    - noatime
---
# nfs-media-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-media
  namespace: media
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  volumeName: nfs-media
  resources:
    requests:
      storage: 1Ti
```

### Phase 4: Migrate Jellyfin

1. Keep `/config` on Longhorn (database)
2. Mount `/media` from NFS
3. Update Jellyfin deployment:

```yaml
volumes:
  - name: config
    persistentVolumeClaim:
      claimName: jellyfin-config  # Longhorn
  - name: media
    persistentVolumeClaim:
      claimName: nfs-media        # TrueNAS NFS

volumeMounts:
  - name: config
    mountPath: /config
  - name: media
    mountPath: /media
```

## Phone Access Options

### Option 1: TrueNAS SCALE Mobile App (Recommended)

TrueNAS SCALE has official mobile apps for iOS/Android that can:
- Browse files
- Upload photos/music
- Stream media

### Option 2: WebDAV + Phone File Manager

Configure WebDAV share on TrueNAS, use any WebDAV-capable file manager app (Files on iOS, Solid Explorer on Android).

### Option 3: Syncthing

Run Syncthing on TrueNAS and phone for automatic folder sync.

### Option 4: Nextcloud on TrueNAS

Deploy Nextcloud app on TrueNAS for full file sync solution.

## Answering Your Question

> "That way I could just open the TrueNAS application from my phone and upload things to the folder that is being used to serve the media, right?"

**Yes, exactly.** Here's the flow:

1. Open TrueNAS app on phone
2. Navigate to `media/music/`
3. Upload music files
4. Jellyfin sees the new files (NFS mount)
5. Jellyfin library scan picks them up

No kubectl, no complex setup, just upload and play.

## Alternatives Considered

### Alternative 1: Longhorn + NFS Gateway Pod

Run an NFS server pod that exposes Longhorn volumes.

**Rejected because:**
- Adds complexity (another pod to manage)
- Performance overhead
- Longhorn still not designed for large files

### Alternative 2: MinIO for Object Storage

Use S3-compatible storage.

**Rejected because:**
- Requires app changes (S3 API instead of filesystem)
- Jellyfin doesn't natively support S3
- Overkill for homelab

### Alternative 3: Direct Disk Mount on Talos

Mount a disk directly on Talos and share via NFS.

**Rejected because:**
- Talos is immutable, can't install NFS server
- No web UI for management
- Defeats purpose of easy access

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| TrueNAS VM failure | Regular ZFS snapshots, Proxmox VM backups |
| NFS connectivity issues | TrueNAS on same VLAN as K8s nodes |
| Permission problems | Use `all_squash` with consistent UID/GID |
| Storage capacity | ZFS compression, start with available disks |

## Success Criteria

- [ ] TrueNAS VM deployed and accessible
- [ ] NFS shares working from Kubernetes
- [ ] Jellyfin serving media from NFS
- [ ] Can upload music from phone via TrueNAS app
- [ ] Longhorn still used for app configs

## Next Steps

1. **Decide** on storage hardware (existing disks? new drives?)
2. **Deploy** TrueNAS VM on Proxmox
3. **Configure** ZFS pool and NFS shares
4. **Test** NFS from a Kubernetes pod
5. **Migrate** Jellyfin media to NFS

---

**References:**
- [William's NFS Storage Docs](../william-infra/docs/services/nfs-storage.md)
- [TrueNAS SCALE Documentation](https://www.truenas.com/docs/scale/)
- [Kubernetes NFS Volumes](https://kubernetes.io/docs/concepts/storage/volumes/#nfs)
