# ADR-003: Pangolin + Control D for Service Exposure and DNS Management

**Status**: Accepted
**Date**: 2026-02
**Decision Makers**: Aaron, William (shared infrastructure)

---

## Context

The homelab needs a way to:
- Expose services to the internet (race telemetry app, personal sites, static pages)
- Manage DNS resolution with per-VLAN filtering and policies
- Keep full control over traffic (no third-party inspection)
- Learn real-world DNS and networking patterns applicable to professional environments

The original plan was to use **Cloudflare Tunnel** for service exposure. After discussion, we decided on a self-hosted approach using **Pangolin** (reverse proxy on a VPS) and **Control D** (DNS management with per-VLAN policies).

---

## Decision

Use a three-component architecture:

1. **Pangolin** on a Vultr VPS as the public entry point and reverse proxy
2. **Newt** (Pangolin agent) inside the Talos cluster as a system extension
3. **Control D + ctrld** on OPNsense for DNS resolution with per-VLAN policies

### Domains

Two domains are managed through Pangolin on the shared Vultr VPS -- one for infrastructure management (Pangolin dashboard) and one for public-facing services. Domain names are kept in the private environments repo.

---

## Architecture

### How Traffic Flows (External User Accessing a Service)

```
                        THE INTERNET
                             │
                             │
                   ┌─────────┴─────────┐
                   │   Vultr VPS       │
                   │                   │
                   │  ┌─────────────┐  │
                   │  │  Traefik    │  │  <- TLS termination, routes by domain
                   │  └──────┬──────┘  │
                   │         │         │
                   │  ┌──────┴──────┐  │
                   │  │  Badger     │  │  <- Auth check (if resource is private)
                   │  └──────┬──────┘  │
                   │         │         │
                   │  ┌──────┴──────┐  │
                   │  │  Gerbil     │  │  <- WireGuard tunnel manager
                   │  └──────┬──────┘  │
                   │         │         │
                   │  ┌──────┴──────┐  │
                   │  │  Pangolin   │  │  <- Control plane (dashboard, API)
                   │  └─────────────┘  │
                   └────────┬──────────┘
                            │
                   WireGuard Tunnel
                   (outbound from homelab)
                            │
              ──────────────┼──────────────
              HOMELAB       │       NETWORK
                            │
                   ┌────────┴─────────┐
                   │  Newt (on Talos) │  <- Pangolin agent, system extension
                   │                  │
                   │  Proxies traffic │
                   │  to cluster svc  │
                   └────────┬─────────┘
                            │
                            │
                   ┌────────┴─────────┐
                   │  Your Service    │  <- e.g., static site, telemetry app
                   │  (K8s pod)       │
                   └──────────────────┘
```

**Key point**: No inbound ports are opened on your home network. Newt initiates the tunnel outward to the VPS. The VPS is the only thing with a public IP.

### How DNS Works (Control D + ctrld + Split-Horizon)

```
   ┌─────────────────────────────────────────────────────────────┐
   │                      OPNsense VM                            │
   │                                                             │
   │  ┌───────────────────────────────────────────────────────┐  │
   │  │                    ctrld daemon                       │  │
   │  │                                                       │  │
   │  │  Listens on all interfaces (0.0.0.0:53)              │  │
   │  │                                                       │  │
   │  │  When a DNS query arrives:                           │  │
   │  │    1. Check source IP                                │  │
   │  │    2. Match to a network CIDR                        │  │
   │  │    3. Forward to the assigned upstream               │  │
   │  │                                                       │  │
   │  │  ┌─────────────┐    ┌────────────────────────────┐   │  │
   │  │  │ Source IP in ├───>│ Forward to Control D       │   │  │
   │  │  │ PROD VLAN   │    │ "PROD" profile (strict)    │   │  │
   │  │  │ e.g. 10.x.x│    │ (blocks ads, malware, etc) │   │  │
   │  │  └─────────────┘    └────────────────────────────┘   │  │
   │  │                                                       │  │
   │  │  ┌─────────────┐    ┌────────────────────────────┐   │  │
   │  │  │ Source IP in ├───>│ Forward to Control D       │   │  │
   │  │  │ DEV VLAN    │    │ "DEV" profile (permissive) │   │  │
   │  │  │ e.g. 10.y.x│    │ (minimal filtering)        │   │  │
   │  │  └─────────────┘    └────────────────────────────┘   │  │
   │  └───────────────────────────────────────────────────────┘  │
   └─────────────────────────────────────────────────────────────┘

   All queries are sent over DNS-over-HTTPS3 (encrypted).
   Your ISP cannot see what domains you are resolving.
```

### Split-Horizon DNS (Internal vs External Resolution)

Split-horizon means the same domain resolves differently depending on where you ask from.

```
Example: app.example.com

  EXTERNAL (user on the internet):
    DNS query -> public DNS -> resolves to Vultr VPS public IP
    Traffic: User -> VPS (Pangolin) -> WireGuard -> Newt -> K8s service

  INTERNAL (device on your VLAN):
    DNS query -> ctrld on OPNsense -> resolves to internal cluster IP
    Traffic: Device -> K8s service (direct, no tunnel, no VPS hop)
```

This is configured in ctrld using domain-based rules that route internal domains to a local resolver (e.g., CoreDNS inside the cluster) instead of Control D.

### Full Path: From Domain Purchase to Request Served

```
  1. DOMAIN SETUP
     example.com DNS records:
       *.example.com  ->  A record  ->  Vultr VPS public IP
       example.com    ->  A record  ->  Vultr VPS public IP

  2. PANGOLIN CONFIGURATION
     In Pangolin dashboard (pangolin.infra.example.net):
       - Create a "Site" (your homelab, connected via Newt)
       - Create a "Resource": app.example.com -> forwards to <cluster-service-ip>:<port>
       - Pangolin auto-provisions Let's Encrypt TLS certificate

  3. TALOS CLUSTER
     Talos image includes Newt system extension.
     Newt establishes:
       - WebSocket to Pangolin (control plane coordination)
       - WireGuard tunnel to Gerbil (encrypted data transport)
     Newt proxies traffic to K8s services inside the cluster.

  4. DNS RESOLUTION (ctrld on OPNsense)
     ctrld replaces Unbound on OPNsense.
     DHCP on each VLAN hands out OPNsense as the DNS server.
     Queries are forwarded to Control D profiles over DoH3:
       - PROD VLAN -> "PROD" profile (strict filtering)
       - DEV VLAN  -> "DEV" profile (permissive)
     Internal domains (*.example.com from inside the VLAN)
       -> resolved via split-horizon to internal cluster IPs

  5. REQUEST LIFECYCLE (external user)
     User types: app.example.com
       -> DNS resolves to Vultr VPS IP
       -> HTTPS request hits Traefik on VPS (port 443)
       -> Traefik routes based on domain -> app.example.com
       -> Badger checks auth (if private resource)
       -> Gerbil forwards through WireGuard tunnel
       -> Newt (on Talos node) receives traffic
       -> Newt proxies to K8s service (e.g., nginx pod serving static site)
       -> Response travels back the same path
       -> User sees the site with valid TLS certificate
```

---

## Why Not Cloudflare Tunnel (Alternatives Considered)

### Cloudflare Tunnel
- **Pros**: Free, zero infrastructure, massive edge network (300+ PoPs), built-in DDoS protection
- **Cons**: Cloudflare owns and inspects all traffic, DNS must go through Cloudflare, no per-VLAN DNS policies, teaches you very little about DNS/networking, vendor lock-in
- **Rejected because**: Conflicts with goals of learning DNS architecture, controlling traffic path, and building a professional-grade setup

### Direct Port Forwarding
- **Pros**: Simplest possible approach
- **Cons**: Requires static IP or DDNS, exposes home network directly, no TLS management, no auth layer
- **Rejected because**: Insecure and impractical without a static IP

### Tailscale / Headscale
- **Pros**: Mesh VPN, easy setup, works well for private access
- **Cons**: Not designed for public-facing services, no reverse proxy / domain routing
- **Rejected because**: Doesn't solve the "expose services publicly" problem

---

## Consequences

### Positive
- Full ownership of the traffic path (no third-party inspection)
- Per-VLAN DNS policies with analytics and filtering
- Encrypted DNS (DoH3) — ISP cannot see queries
- Split-horizon DNS — internal traffic stays internal
- Professional-grade architecture (mirrors Route53 + ALB patterns in AWS)
- Learning opportunity: DNS, WireGuard, reverse proxying, network segmentation
- Shared infrastructure with William reduces cost

### Negative
- More moving parts to maintain (VPS + Pangolin + ctrld + Control D)
- VPS is a single point of failure for external access (no edge network like Cloudflare)
- No built-in DDoS protection (see `docs/issues/006-security-hardening-ddos-protection.md` for future mitigation)
- Control D is a paid service for full features (~$2-3/mo)
- Depends on William's Vultr VPS (shared infrastructure)

### Neutral
- Newt requires a custom Talos Factory image (new schematic with the extension)
- Pangolin dashboard is shared with William (separate user accounts)
- Can add Cloudflare CDN/WAF in front of VPS later without changing the architecture

---

## Implementation Plan

1. ~~**Deploy Pangolin stack on Vultr VPS**~~ ✅ — Traefik, Gerbil, Badger, Pangolin deployed (shared VPS with William)
2. ~~**Configure Control D profiles**~~ ✅ — PROD and DEV profiles created, "Aaron-Homelab" endpoint provisioned
3. ~~**Create Pangolin site**~~ ✅ — Homelab site created in Pangolin dashboard
4. **Add Newt extension to Talos image** — Create new Factory schematic, update `talos_image_url`
5. **Install ctrld on OPNsense** — Replace Unbound, configure per-VLAN policies
6. **Deploy static site** — First Pangolin resource to validate the full path
7. **Configure split-horizon** — Internal domains resolve locally via ctrld rules
8. **Migrate race telemetry app** — Expose via Pangolin once deployed

---

## References

- [Pangolin Documentation](https://docs.pangolin.net/)
- [Newt Talos Extension](https://github.com/siderolabs/extensions/pkgs/container/newt)
- [Control D](https://controld.com/)
- [ctrld GitHub](https://github.com/Control-D-Inc/ctrld)
- [ADR-001: VLAN Architecture](001-vlan-architecture.md)
- [Issue #006: Security Hardening & DDoS Protection](../issues/006-security-hardening-ddos-protection.md)
