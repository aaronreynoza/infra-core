# ADR-005: DNS, TLS, and Service Exposure Architecture

**Status**: Accepted
**Date**: 2026-03
**Decision Makers**: Aaron, William (shared infrastructure)

---

## Context

With Pangolin deployed on the VPS (ADR-003) and platform services running in the cluster, we need a concrete plan for how subdomains map to services, how TLS certificates are provisioned, and how internal vs external traffic flows. This ADR documents the operational details that ADR-003 left abstract: the specific domain structure under `reynoza.org`, the two TLS strategies available, the split-horizon DNS configuration, and the ownership boundary between Aaron and William.

Key requirements:

- Aaron must be able to add new subdomains without Cloudflare access
- Internal traffic should not leave the home network
- TLS must be automatic (no manual cert management)
- Each service needs a human-readable subdomain instead of raw IPs

---

## Decision

### Domain Structure

The family owns `reynoza.org` (registered and managed in Cloudflare by William). Aaron's homelab services live under the `aaron.reynoza.org` subdomain:

| Subdomain | Service | Access | Notes |
|-----------|---------|--------|-------|
| `aaron.reynoza.org` | Personal website / docs site | Public | Landing page |
| `docs.aaron.reynoza.org` | MkDocs documentation | Public | First app through CI pipeline |
| `argocd.aaron.reynoza.org` | ArgoCD | Private | Pangolin auth via Badger |
| `forgejo.aaron.reynoza.org` | Forgejo | Private | Git source of truth |
| `harbor.aaron.reynoza.org` | Harbor | Private | Container registry |
| `grafana.aaron.reynoza.org` | Grafana | Private | Observability dashboards |
| `zitadel.aaron.reynoza.org` | Zitadel | Private | SSO/OIDC provider |

**Private** means Pangolin's Badger component enforces authentication before traffic reaches the service. **Public** means traffic passes through to the service without Pangolin auth.

### TLS Strategy

**Primary approach (Option A): Pangolin handles TLS**

Pangolin's Traefik instance on the VPS auto-provisions Let's Encrypt certificates for each resource. TLS terminates at the VPS. Traffic then flows encrypted through the WireGuard tunnel to Newt in the cluster. This requires zero cluster-side certificate infrastructure.

**Future option (Option B): cert-manager with Cloudflare DNS-01**

If local HTTPS is needed (internal traffic without the VPS hop), deploy cert-manager in the cluster with a Cloudflare DNS-01 solver for wildcard certs (`*.aaron.reynoza.org`). This requires a Cloudflare API token from William with `Zone:DNS:Edit` permission on `reynoza.org`. Reflector would sync the TLS secret across namespaces, following the pattern in William's setup.

Option A is chosen now because it has zero dependencies on Cloudflare API access and no additional cluster components. Option B is documented as a known upgrade path.

### Split-Horizon DNS via ControlD

ControlD with ctrld on OPNSense provides split-horizon resolution so that internal devices reach services directly:

| Source | Query | Resolves To | Path |
|--------|-------|-------------|------|
| Internet user | `forgejo.aaron.reynoza.org` | `<VPS_IP>` (VPS) | Through Pangolin tunnel |
| VLAN 10 device | `forgejo.aaron.reynoza.org` | `<LB_IP>` (LB IP) | Direct to K8s service |

---

## Architecture

### Traffic Flow: External Access

```
                    USER ON THE INTERNET
                           |
                           v
                   Cloudflare DNS
                   *.reynoza.org -> <VPS_IP>
                           |
                           v
              +---------------------------+
              |      Vultr VPS            |
              |                           |
              |  Traefik (TLS termination)|
              |      Let's Encrypt cert   |
              |           |               |
              |  Badger (auth check)      |
              |      if private resource  |
              |           |               |
              |  Gerbil (WireGuard mgr)   |
              +-----------.---------------+
                          |
                  WireGuard tunnel
                  (outbound from homelab)
                          |
         -----------------+------------------
         HOMELAB NETWORK (VLAN 10)
                          |
              +-----------+-----------+
              |  Newt (K8s pod)       |
              |  Pangolin agent       |
              +-----------+-----------+
                          |
              +-----------+-----------+
              |  K8s Service          |
              |  (e.g., Forgejo)      |
              +-----------------------+
```

### Traffic Flow: Internal Access (Split-Horizon)

```
         DEVICE ON VLAN 10 (e.g., workstation)
                          |
                          v
              OPNSense (ctrld daemon)
              *.aaron.reynoza.org -> 10.10.10.x (LB IP)
                          |
                          v
              +-----------------------+
              |  Cilium LB-IPAM      |
              |  K8s Service          |
              |  (e.g., Forgejo)      |
              +-----------------------+

         No VPS hop. No WireGuard tunnel. No Pangolin.
         Traffic stays entirely on the local network.
```

### Side-by-Side Comparison

```
  EXTERNAL PATH                          INTERNAL PATH
  ============                           =============

  Browser                                Browser
     |                                      |
  Cloudflare DNS                         ctrld on OPNSense
  (*.reynoza.org -> VPS IP)              (*.aaron.reynoza.org -> LB IP)
     |                                      |
  Pangolin VPS                           [direct]
  (TLS + auth + WireGuard)                  |
     |                                      |
  Newt (K8s pod)                            |
     |                                      |
  K8s Service  <-------- same -------->  K8s Service
```

### TLS Options Compared

```
  OPTION A: PANGOLIN TLS (current)       OPTION B: cert-manager (future)
  ================================       ===============================

  Let's Encrypt                          Let's Encrypt
     |                                      |
  Traefik on VPS                         cert-manager in cluster
  (auto-provisions per resource)         (DNS-01 via Cloudflare API)
     |                                      |
  TLS terminates at VPS                  TLS terminates at ingress/gateway
     |                                      |
  WireGuard (encrypted)                  Reflector syncs TLS secrets
  to Newt in cluster                     across namespaces
     |                                      |
  Plaintext to K8s service               HTTPS all the way to the client
  (acceptable: WireGuard is encrypted)   (true end-to-end TLS)

  Pros:                                  Pros:
  - Zero cluster components              - Local HTTPS without VPS
  - No Cloudflare API token needed       - End-to-end TLS
  - Simplest possible setup              - Works if VPS is down

  Cons:                                  Cons:
  - No local HTTPS                       - Needs Cloudflare API token
  - VPS is required for all HTTPS        - More moving parts
  - Internal users go through VPS        - Reflector + cert-manager to maintain
    unless split-horizon is configured
```

---

## Service Mapping

### Cilium LB-IPAM Assignments

| Service | LB IP | Port | Pangolin Resource Domain |
|---------|-------|------|--------------------------|
| ArgoCD | `<LB_IP>` | 443 | `argocd.aaron.reynoza.org` |
| Forgejo | `<LB_IP>` | 3000 | `forgejo.aaron.reynoza.org` |
| Harbor | `<LB_IP>` | 80 | `harbor.aaron.reynoza.org` |
| Grafana | `<LB_IP>` | 80 | `grafana.aaron.reynoza.org` |
| Zitadel | `<LB_IP>` | 8080 | `zitadel.aaron.reynoza.org` |

### Pangolin Resource Configuration

For each service, create a "Resource" in the Pangolin dashboard:

| Setting | Value | Example (ArgoCD) |
|---------|-------|-------------------|
| Domain | The public subdomain | `argocd.aaron.reynoza.org` |
| Site | The Newt-connected site | Aaron Homelab |
| Target | LB IP and port | `http://<LB_IP>:443` |
| Access | Public or Private | Private (Badger auth) |

Newt runs as a pod inside the cluster, so it can reach Cilium LB IPs directly. Alternatively, targets can use cluster-internal DNS if Newt resolves it:

```
# LB IP target (simpler, always works)
http://<LB_IP>:443

# Cluster DNS target (works if Newt uses cluster DNS)
http://argocd-server.argocd.svc.cluster.local:443
```

Pangolin auto-provisions a Let's Encrypt TLS certificate for each resource domain. No manual cert setup required.

### ControlD Split-Horizon Records

Configure these in the ControlD "Aaron-Homelab" profile or via ctrld domain rules on OPNSense:

```
# Split-horizon: internal devices resolve to LB IPs
*.aaron.reynoza.org    -> forward to local resolver

# Specific overrides (if wildcard forwarding is not available)
argocd.aaron.reynoza.org   -> <LB_IP>
forgejo.aaron.reynoza.org  -> <LB_IP>
harbor.aaron.reynoza.org   -> <LB_IP>
grafana.aaron.reynoza.org  -> <LB_IP>
zitadel.aaron.reynoza.org  -> <LB_IP>
```

---

## Ownership Boundaries

### What William Manages

| Component | Details |
|-----------|---------|
| Cloudflare DNS | `reynoza.org` zone, `*.reynoza.org` wildcard A record pointing to `<VPS_IP>` |
| Vultr VPS | Shared NixOS host running Pangolin stack (Traefik, Gerbil, Badger, Pangolin) |
| Pangolin admin | User accounts, global settings |

The wildcard `*.reynoza.org` record is already configured. It resolves ALL subdomains (including `anything.aaron.reynoza.org`) to the VPS. Aaron does not need Cloudflare access for day-to-day operations.

### What Aaron Manages

| Component | Details |
|-----------|---------|
| Pangolin resources | Create/edit subdomain-to-service mappings in Pangolin dashboard |
| Newt | K8s pod in the cluster, maintains WireGuard tunnel to Gerbil |
| ControlD split-horizon | Domain rules so internal traffic bypasses the VPS |
| App configs | Each app's external URL, OIDC redirect URIs, etc. |
| K8s cluster | Services, LB-IPAM assignments, namespaces |

### When Aaron Needs William

| Scenario | Why |
|----------|-----|
| New top-level subdomain (e.g., `william.reynoza.org`) | Cloudflare zone change |
| Cloudflare API token for cert-manager (Option B) | Token with Zone:DNS:Edit on `reynoza.org` |
| VPS goes down | William manages the Vultr host |
| Pangolin upgrade | Shared infrastructure |

Aaron does NOT need William for:
- Adding new subdomains under `*.aaron.reynoza.org` (wildcard handles it)
- Creating Pangolin resources (Aaron has dashboard access)
- Changing which service a subdomain points to
- Adding or removing services from the cluster

---

## Implementation Steps

| Step | Status | Description |
|------|--------|-------------|
| 1 | Done | Deploy Pangolin stack on VPS (ADR-003) |
| 2 | Done | Get Newt online in K8s cluster |
| 3 | Done | Create Pangolin resources for each subdomain |
| 4 | Pending | Configure ControlD split-horizon for internal access |
| 5 | Done | Update app configs for new domains |
| 6 | Pending | Update Zitadel OIDC redirect URLs (`terraform apply`) |
| 7 | Pending | Test external access end-to-end |
| 8 | Pending | Test internal split-horizon access |
| 9 | Future | Deploy cert-manager for local HTTPS (Option B, if needed) |

### Step 3: Create Pangolin Resources — DONE

Resources are managed as IaC via `infra-core/scripts/pangolin/pangolin-resources.py` with config in `prod/pangolin/`. The script syncs desired state from `resources.yaml` against the Pangolin API.

```bash
python3 scripts/pangolin/pangolin-resources.py \
  --config prod/pangolin/config.yaml \
  --resources prod/pangolin/resources.yaml \
  sync --dry-run  # preview changes
  sync             # apply changes
```

Resources can also be created manually in the Pangolin dashboard (Resources → Public → Add Resource).

### Step 5: Update App Configs

Each application needs its external URL updated in its Helm values. These live in the `prod/values/` directory:

| App | Config Key | New Value |
|-----|-----------|-----------|
| Forgejo | `ROOT_URL` | `https://forgejo.aaron.reynoza.org` |
| Harbor | `externalURL` | `https://harbor.aaron.reynoza.org` |
| Zitadel | `ExternalDomain` | `zitadel.aaron.reynoza.org` |
| Grafana | `root_url` | `https://grafana.aaron.reynoza.org` |
| ArgoCD | `server.url` | `https://argocd.aaron.reynoza.org` |

### Step 6: Update Zitadel OIDC Redirect URLs

All four SSO-integrated apps (ArgoCD, Forgejo, Grafana, Harbor) have OIDC redirect URIs configured in Zitadel via Terraform. Update the redirect URIs from IP-based URLs to subdomain-based URLs:

```
# Old (IP-based)
https://forgejo.aaron.reynoza.org/user/oauth2/Zitadel/callback

# New (subdomain-based)
https://forgejo.aaron.reynoza.org/user/oauth2/Zitadel/callback
```

---

## Key Insight: Zero-Touch Subdomain Provisioning

The `*.reynoza.org` wildcard in Cloudflare combined with Pangolin means Aaron can expose new services without touching Cloudflare or the VPS configuration:

```
1. Deploy a new service in K8s (gets a Cilium LB IP)
2. Create a Pangolin resource:
   - Domain: newservice.aaron.reynoza.org
   - Target: http://<LB-IP>:<port>
3. Pangolin auto-provisions a Let's Encrypt cert
4. Add a ControlD split-horizon record for internal access
5. Done. HTTPS works externally and internally.
```

No DNS changes. No Cloudflare edits. No VPS configuration. No certificate management. The wildcard record and Pangolin's auto-cert handle everything.

---

## Consequences

### Positive

- Human-readable URLs replace raw IPs for all services
- Automatic TLS via Pangolin (zero cert management overhead)
- Internal traffic stays local via split-horizon (no unnecessary VPS hops)
- Aaron can add subdomains independently (no Cloudflare access needed)
- Clean upgrade path to cert-manager if local HTTPS becomes necessary
- Professional-grade DNS architecture (mirrors Route53 + ALB patterns)

### Negative

- Internal HTTPS requires either the VPS hop (Option A) or cert-manager (Option B)
- Pangolin resources managed via Python script + API (not fully GitOps yet — no CI trigger)
- Split-horizon requires maintaining ControlD records in sync with LB-IPAM assignments
- VPS is a single point of failure for external access

### Neutral

- Existing IP-based access continues to work alongside subdomain access
- Zitadel redirect URI updates are a one-time migration
- Brother's cert-manager setup serves as a proven reference if Option B is needed

---

## Relationship to Other ADRs

| ADR | Relationship |
|-----|-------------|
| [ADR-001: VLAN Architecture](001-vlan-architecture.md) | Split-horizon DNS depends on VLAN segmentation |
| [ADR-003: Pangolin + ControlD](003-pangolin-controld-architecture.md) | This ADR operationalizes the architecture defined in ADR-003 |
| [ADR-004: SOPS Secrets](004-sops-secrets-management.md) | Cloudflare API token (Option B) would be SOPS-encrypted |

---

## References

- [ADR-003: Pangolin + Control D Architecture](003-pangolin-controld-architecture.md)
- [Pangolin Documentation](https://docs.pangolin.net/)
- [cert-manager DNS-01 with Cloudflare](https://cert-manager.io/docs/configuration/acme/dns01/cloudflare/)
- [Reflector](https://github.com/emberstack/kubernetes-reflector)
- [Let's Encrypt Rate Limits](https://letsencrypt.org/docs/rate-limits/)
- [ControlD](https://controld.com/)

---

**Last Updated:** 2026-03-16
