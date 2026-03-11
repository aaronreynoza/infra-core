# Longhorn Cross-Node Replicas for Production Data

**Priority**: High
**Labels**: storage, high-availability, production
**Depends on**: K8s cluster spanning both nodes (Phase 3)

## Problem

Production application databases must survive a full node failure. Longhorn needs to be configured with replica count >= 2, with replicas on different nodes, so that if one node dies the data is still available on the other.

## Goal

All production PVCs use Longhorn with replica=2, scheduled across both primary-host and secondary-host nodes. When a node dies, K8s reschedules the pod to the surviving node and Longhorn serves the existing replica — zero data loss.

## Implementation Steps

1. **Configure Longhorn StorageClasses**
   ```yaml
   # Default production storage class
   apiVersion: storage.k8s.io/v1
   kind: StorageClass
   metadata:
     name: longhorn-prod
   provisioner: driver.longhorn.io
   parameters:
     numberOfReplicas: "2"
     dataLocality: "disabled"  # allow replicas on different nodes
     staleReplicaTimeout: "30"
   reclaimPolicy: Retain

   # Fast storage for databases
   apiVersion: storage.k8s.io/v1
   kind: StorageClass
   metadata:
     name: longhorn-prod-fast
   provisioner: driver.longhorn.io
   parameters:
     numberOfReplicas: "2"
     dataLocality: "best-effort"
   reclaimPolicy: Retain
   ```

2. **Configure Longhorn default settings**
   - Default replica count: 2
   - Replica auto-balance: best-effort
   - Node drain policy: allow-if-replica-is-stopped

3. **Ensure K8s nodes have enough disk space**
   - primary-host: `local-lvm` has ~155GB free — need to plan capacity
   - secondary-host: `local-lvm` has ~3.4TB free — plenty of room
   - Longhorn stores replicas on the node's local storage

4. **Test failover**
   - Create a PVC with replica=2
   - Write data from a pod on primary-host
   - Verify replica exists on secondary-host (Longhorn UI)
   - Cordon/drain primary-host node
   - Verify pod reschedules to secondary-host with data intact

## Storage Capacity Planning

| Node | Available | Longhorn Use |
|------|-----------|-------------|
| primary-host | ~155GB (SSD) | Production replicas (limited) |
| secondary-host | ~3.4TB (NVMe) | Production replicas (plenty) |

Primary-host is the bottleneck. Keep production database PVCs small (most are <1GB). Total Longhorn usage across both nodes should stay under 100GB to leave room for VMs.

## Acceptance Criteria

- [ ] Longhorn StorageClasses created with replica=2
- [ ] At least one PVC tested with cross-node replica
- [ ] Node failure tested: pod reschedules with data intact
- [ ] Capacity monitoring in place (alert when Longhorn disk usage > 80%)
