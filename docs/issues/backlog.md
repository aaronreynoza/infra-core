# Deferred Work Backlog

Tasks identified during cluster setup that are not needed for the initial deployment but should be addressed for production readiness.

## Priority 1: Ops Maturity (Next Sprint)

### Templatize environment-specific values
- **Why:** Cilium `k8sServiceHost: "REDACTED_K8S_API"` and Pangolin URLs are hardcoded in ArgoCD manifests
- **Fix:** Use `templatefile()` in `environments/prod/terraform/main.tf` to render manifests with env-specific variables, or move manifests to `environments/<env>/manifests/`
- **Blocks:** Dev cluster deployment

### Store Newt credentials in AWS Secrets Manager
- **Why:** Currently in terraform.tfvars (gitignored, but risky)
- **Fix:** Add `data "aws_secretsmanager_secret_version" "newt"` like Proxmox creds
- **Blocks:** Nothing (works as-is, just better practice)

### Automate worker reboot for disk partitioning
- **Why:** `machine.disks` only applies on reboot. Current flow may need manual reboot.
- **Fix:** Add `null_resource` with `talosctl reboot` + readiness poll after config apply
- **Alternative:** Investigate if Talos auto-reboots on disk config change in `auto` apply mode

### Pre-commit hooks
- **Why:** No linting or validation before commits
- **Fix:** Add `terraform fmt`, `terraform validate`, YAML lint, Helm lint
- **Effort:** Half day

## Priority 2: Production Hardening

### TrueNAS VM for NFS storage
- **Decision doc:** `docs/decisions/002-truenas-storage.md`
- **Plan:** `docs/superpowers/plans/` (TrueNAS plan exists)
- **Why deferred:** Longhorn on local disks works for initial deployment

### ctrld on OPNSense for DNS management
- **Decision doc:** `docs/decisions/003-pangolin-controld-architecture.md`
- **Why:** Split-horizon DNS, per-VLAN filtering, encrypted DoH3
- **Why deferred:** DNS works fine with 8.8.8.8 for now. No internal DNS needed yet.
- **Steps:** Install ctrld, configure per-VLAN policies, replace Unbound

### OPNSense API automation
- **Why:** Firewall rules are currently manual via Web UI
- **Fix:** OPNSense has a REST API at `/api/`. Could use Terraform `http` provider or community `browningluke/opnsense` provider
- **Why deferred:** OPNSense is already configured correctly, rules rarely change

### Velero + Longhorn backups to S3
- **Why:** No disaster recovery for persistent data
- **Fix:** Deploy Velero via ArgoCD, configure S3 backend
- **Issue:** `docs/issues/005-velero-cluster-backup.md`

### CARP HA for OPNSense
- **Issue:** `docs/issues/001-opnsense-ha-carp-failover.md`
- **Why deferred:** Requires second OPNSense VM, adds complexity

### Longhorn replica increase
- **Issue:** `docs/issues/003-longhorn-cross-node-replicas.md`
- **Current:** replica: 1 (single-node storage, data loss risk)
- **Fix:** Increase to 2 when 3+ workers with data disks

## Priority 3: Dev Environment

### Deploy dev cluster on VLAN 11
- **Why:** Need isolated testing environment
- **Blocks:** Templatized manifests (Priority 1)
- **Steps:** New `environments/dev/` directory, different IPs, same modules
- **Network:** 10.11.10.0/16, VLAN 11, gateway 10.11.10.1

### Harbor container registry per environment
- **Why:** Private image registry, vulnerability scanning
- **Why deferred:** Public images work fine for initial apps

## Priority 4: Applications

### Race telemetry app
- **Why:** Production workload with paying clients
- **Blocks:** Full traffic path validated (nginx-test)
- **Steps:** ArgoCD Application manifest, Pangolin resource, domain config

### Media services (Jellyfin, etc.)
- **Why:** Personal use
- **Why deferred:** Not urgent, deploy after telemetry app

## Won't Do (Decided Against)

### Ansible for Talos operations
- **Why not:** Talos is immutable and API-driven. No SSH, no shell. `talosctl` and Terraform provider handle everything. Adding Ansible creates unnecessary tool sprawl.
- **Reference:** PM analysis from 2026-03-11 expert review

### Cloudflare Tunnel
- **Why not:** See ADR-003. Conflicts with learning goals and traffic ownership.

---

**Last Updated:** 2026-03-11
