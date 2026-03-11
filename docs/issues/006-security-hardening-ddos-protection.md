# Security Hardening & DDoS Protection

**Priority**: Medium
**Labels**: security, networking, production
**Depends on**: Pangolin + Control D stack deployed, prod cluster running

## Problem

The Pangolin VPS is directly exposed to the internet with a public IP. While Pangolin handles authentication and WireGuard encryption, there is no protection against volumetric DDoS attacks, bot traffic, or application-layer attacks targeting the VPS or exposed services (especially the race telemetry app with paying clients).

## Goal

Add layered security to the public-facing infrastructure without replacing the Pangolin + Control D architecture.

## Implementation Ideas

1. **Cloudflare as CDN/WAF in front of the VPS**
   - Point DNS through Cloudflare in proxy mode (orange cloud)
   - Cloudflare absorbs DDoS before traffic reaches Vultr VPS
   - WAF rules filter malicious requests (SQLi, XSS, bot traffic)
   - Does NOT replace Pangolin — Cloudflare just sits in front as a shield
   - Free tier provides basic DDoS protection; Pro ($20/mo) adds WAF rules

2. **VPS-level hardening**
   - fail2ban on the Vultr VPS
   - UFW/iptables: only allow ports 443, 80, 51820 (WireGuard), 21820 (Olm)
   - Rate limiting on Traefik (Pangolin's reverse proxy)
   - Disable SSH password auth, key-only access

3. **Pangolin-level security**
   - Enable Badger (identity-aware proxy) for sensitive services
   - Enforce 2FA for admin access
   - Audit access logs

4. **Network-level (OPNsense)**
   - IDS/IPS rules (Suricata) on OPNsense for internal traffic
   - Control D malware filtering profiles per VLAN
   - DNS sinkholing for known malicious domains

## Acceptance Criteria

- [ ] VPS is not directly reachable by IP (hidden behind Cloudflare or similar)
- [ ] DDoS mitigation tested (basic load test)
- [ ] WAF rules active for public-facing services
- [ ] fail2ban + firewall rules on VPS
- [ ] Security audit runbook created
- [ ] Pangolin admin access requires 2FA
