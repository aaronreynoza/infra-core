# ADR-004: SOPS + age for Secrets Management

**Status**: Accepted
**Date**: 2026-03
**Decision Makers**: Aaron

---

## Context

The homelab needs a way to manage secrets (API tokens, tunnel credentials) without:
- Storing plaintext in Git (security risk)
- Paying for a managed service (AWS Secrets Manager ~$60/year)
- Running additional infrastructure (HashiCorp Vault, OpenBao)

Previously, Proxmox API credentials were stored in AWS Secrets Manager and fetched at runtime via Terraform's `aws_secretsmanager_secret_version` data source. This worked but added cost and an external dependency for a handful of secrets.

---

## Decision

Use **SOPS** (Secrets OPerationS) with **age** encryption for all secret management.

### How It Works

1. Secrets are encrypted with age and stored in `environments/` (private repo)
2. Terraform decrypts them at plan/apply time via the `carlpett/sops` provider
3. Terraform creates Kubernetes secrets from decrypted values
4. ArgoCD apps reference pre-existing secrets via `existingSecretName`

### Architecture

```
environments/
├── .sops.yaml                          # Encryption rules + age public key
├── prod/secrets/
│   ├── proxmox-creds.yaml              # Encrypted Proxmox API token
│   └── newt-credentials.yaml           # Encrypted Pangolin/Newt creds
└── dev/secrets/                         # (future)
```

**Terraform flow:**
```
SOPS file → data "sops_file" → provider config / kubernetes_secret
```

**ArgoCD flow:**
```
kubernetes_secret (created by TF) → Helm chart existingSecretName
```

### Key Management

- One age keypair per operator
- Private key at `~/.config/sops/age/keys.txt` (never committed)
- Public key in `.sops.yaml` (safe to commit)
- Multiple recipients supported for team access

---

## Alternatives Considered

| Option | Cost | Pros | Cons |
|--------|------|------|------|
| **AWS Secrets Manager** | ~$60/yr | Managed, rotation, audit | Overkill for homelab, external dependency |
| **Sealed Secrets** | $0 | Native K8s | Tied to one cluster, can't decrypt externally |
| **OpenBao (Vault fork)** | $0 | Dynamic secrets, full audit | Another service to manage and back up |
| **Proton Pass** | $0 | Already have account | No K8s/API integration |

---

## Consequences

**Positive:**
- Zero cost
- No external dependencies (works offline)
- Secrets versioned in Git (encrypted)
- Aligns with William's setup (shared Pangolin VPS)
- Simple: one CLI tool, one key file

**Negative:**
- Manual rotation (no automatic rotation like AWS SM)
- Key loss = secret loss (must back up age key)
- Need `SOPS_AGE_KEY_FILE` env var on macOS

**Mitigations:**
- Back up age key securely (Proton Pass, USB drive)
- Pre-commit hook prevents committing unencrypted secrets
- `terraform apply` required after secret changes (no auto-sync)

---

## Implementation

- [x] SOPS + age installed
- [x] Age keypair generated
- [x] `.sops.yaml` configured in environments/
- [x] Proxmox credentials migrated from AWS SM to SOPS
- [x] Newt credentials encrypted with SOPS
- [x] Terraform updated: `carlpett/sops` provider replaces `hashicorp/aws`
- [x] Newt ArgoCD app updated to use `existingSecretName`
- [x] Pre-commit hook for unencrypted secret detection
