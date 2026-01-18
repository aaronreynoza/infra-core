# Security Features and Improvements

This document outlines the security features implemented in the homelab infrastructure and identifies areas for improvement in future releases.

## Current Security Features

### 1. Network Isolation

#### VLAN Segmentation
- **Production (VLAN 10)**: Isolated network for client-facing workloads
- **Development (VLAN 11)**: Separate network for testing
- **No inter-VLAN routing**: Traffic between prod and dev is blocked at the firewall level

```
┌─────────────────┐          ┌─────────────────┐
│   PROD VLAN     │    ✗     │    DEV VLAN     │
│   10.10.10.0/16 │◄────────►│   10.11.10.0/16 │
│                 │ ISOLATED  │                 │
└─────────────────┘          └─────────────────┘
```

**Benefits:**
- Blast radius containment
- Dev environment cannot impact production
- Easier compliance and auditing

### 2. Immutable Infrastructure

#### Talos Linux
- **Read-only root filesystem**: Cannot be modified at runtime
- **No SSH access**: Reduces attack surface
- **API-driven management**: All changes through authenticated API
- **Automatic updates**: Controlled, atomic OS updates

**Security Properties:**
- No shell access for attackers to exploit
- Configuration drift impossible
- Tamper-evident system

### 3. Kubernetes Security

#### Cilium CNI
- **Network Policies**: L3/L4 and L7 network segmentation
- **Encryption**: WireGuard-based pod-to-pod encryption (optional)
- **Hubble**: Network observability and flow logging

#### Pod Security Standards
Namespace labels enforce security policies:
```yaml
metadata:
  labels:
    pod-security.kubernetes.io/enforce: "privileged"  # For system namespaces
    pod-security.kubernetes.io/enforce: "restricted"  # For application namespaces
```

### 4. Secrets Management

#### Current Implementation
- Terraform state encrypted in S3
- Kubernetes secrets stored in etcd (encrypted at rest via Talos)
- No secrets in Git repository

#### Planned: External Secrets Operator
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-secrets
spec:
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: app-secrets
  data:
    - secretKey: database-password
      remoteRef:
        key: prod/database
        property: password
```

### 5. Access Control

#### Proxmox
- API tokens with minimal permissions
- Separate tokens per use case (Terraform, monitoring)

#### Kubernetes RBAC
- ArgoCD manages deployments (service account)
- Human access via kubeconfig (to be integrated with SSO)

### 6. GitOps Security

#### ArgoCD
- Git as single source of truth
- All changes auditable via Git history
- No direct cluster modifications

**Sync Policies:**
```yaml
syncPolicy:
  automated:
    prune: true      # Remove resources deleted from Git
    selfHeal: true   # Revert manual changes
```

### 7. Backup and Disaster Recovery

#### Longhorn
- Volume snapshots and replication
- Backup target: AWS S3 (encrypted)

#### Velero (Planned)
- Cluster state backups
- Scheduled backups with retention policies
- Tested restore procedures

---

## Security Improvements Roadmap

### High Priority

#### 1. Identity Provider Integration (Zitadel)

**Current State:** No centralized authentication
**Target State:** SSO for all services

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   User      │────▶│   Zitadel   │────▶│   Services  │
│             │     │   (OIDC)    │     │             │
│             │     │             │     │ - ArgoCD    │
│             │     │             │     │ - Grafana   │
│             │     │             │     │ - Harbor    │
└─────────────┘     └─────────────┘     └─────────────┘
```

**Benefits:**
- Single sign-on across all services
- Centralized user management
- MFA enforcement
- Audit logging

#### 2. Cloudflare Tunnel (Zero Trust Access)

**Current State:** Services not publicly accessible
**Target State:** Secure public access without exposed ports

```
Internet ──▶ Cloudflare ──▶ Tunnel ──▶ Kubernetes Services
                │
                ▼
        Cloudflare Access
        (Authentication)
```

**Benefits:**
- No public IP required
- No port forwarding
- DDoS protection included
- Zero Trust authentication

#### 3. Network Policies

**Current State:** Flat network within cluster
**Target State:** Micro-segmentation with Cilium

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-frontend-to-backend
spec:
  endpointSelector:
    matchLabels:
      app: backend
  ingress:
    - fromEndpoints:
        - matchLabels:
            app: frontend
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
```

### Medium Priority

#### 4. Container Image Signing

**Goal:** Ensure only trusted images run in the cluster

**Implementation Options:**
- Sigstore/Cosign for signing
- Kyverno or OPA Gatekeeper for admission control

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-image-signature
spec:
  validationFailureAction: enforce
  rules:
    - name: verify-signature
      match:
        resources:
          kinds:
            - Pod
      verifyImages:
        - image: "harbor.prod.homelab.local/*"
          key: |-
            -----BEGIN PUBLIC KEY-----
            ...
            -----END PUBLIC KEY-----
```

#### 5. Runtime Security Monitoring

**Options:**
- Falco for runtime threat detection
- Cilium Tetragon for eBPF-based security

**Example Falco Rule:**
```yaml
- rule: Unauthorized Process
  desc: Detect unauthorized process execution
  condition: >
    spawned_process and
    container and
    not proc.name in (allowed_processes)
  output: "Unauthorized process started (user=%user.name command=%proc.cmdline)"
  priority: WARNING
```

#### 6. Vulnerability Scanning

**Components:**
- Harbor Trivy integration (container images)
- Kube-bench (CIS benchmarks)
- Regular CVE scanning

**Harbor Configuration:**
```yaml
trivy:
  enabled: true
  scanOnPush: true
  severity: "CRITICAL,HIGH"
```

### Lower Priority

#### 7. Audit Logging

**Kubernetes Audit Policy:**
```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: Metadata
    resources:
      - group: ""
        resources: ["secrets", "configmaps"]
  - level: RequestResponse
    resources:
      - group: ""
        resources: ["pods"]
    verbs: ["create", "delete"]
```

**Log Destinations:**
- Centralized logging (Loki/Elasticsearch)
- Long-term retention in S3

#### 8. Secret Rotation

**Automated rotation for:**
- Database credentials
- API keys
- TLS certificates

**Implementation:**
- External Secrets Operator with rotation
- Cert-manager for TLS
- Vault (alternative to AWS Secrets Manager)

#### 9. Encryption in Transit

**Pod-to-Pod Encryption with Cilium:**
```yaml
# In Cilium Helm values
encryption:
  enabled: true
  type: wireguard
```

---

## Security Checklist

### Infrastructure Layer

- [x] VLAN segmentation
- [x] Immutable OS (Talos)
- [x] Encrypted Terraform state
- [ ] OPNSense hardening
- [ ] Regular firmware updates

### Kubernetes Layer

- [x] Cilium CNI deployed
- [x] Pod Security Standards
- [ ] Network Policies defined
- [ ] Admission controllers
- [ ] Audit logging enabled

### Application Layer

- [x] ArgoCD for GitOps
- [ ] SSO integration (Zitadel)
- [ ] Container image signing
- [ ] Runtime security monitoring
- [ ] Vulnerability scanning

### Access Control

- [x] Minimal Proxmox API permissions
- [ ] Centralized identity (Zitadel)
- [ ] MFA enforcement
- [ ] Regular access reviews

### Data Protection

- [x] Etcd encryption (Talos default)
- [x] S3 state encryption
- [ ] Backup encryption
- [ ] Secret rotation

### Monitoring & Response

- [ ] Security alerting
- [ ] Incident response plan
- [ ] Regular security assessments
- [ ] Penetration testing

---

## Implementation Priority Matrix

| Feature | Security Impact | Effort | Priority |
|---------|-----------------|--------|----------|
| Zitadel SSO | High | Medium | P1 |
| Network Policies | High | Low | P1 |
| Cloudflare Tunnel | High | Low | P1 |
| External Secrets | Medium | Low | P2 |
| Image Signing | Medium | Medium | P2 |
| Vulnerability Scanning | Medium | Low | P2 |
| Runtime Monitoring | Medium | High | P3 |
| Audit Logging | Low | Medium | P3 |

---

## Compliance Considerations

While this is a homelab, following security best practices helps with:

1. **Learning**: Understanding enterprise security patterns
2. **Portfolio**: Demonstrating security awareness
3. **Production Readiness**: The race telemetry app serves real clients

### Relevant Frameworks

- **CIS Kubernetes Benchmark**: Hardening guidelines
- **NIST Cybersecurity Framework**: Risk management
- **SOC 2**: If handling customer data

---

## Regular Security Tasks

### Weekly
- Review ArgoCD sync status
- Check for failed deployments
- Review Hubble network flows

### Monthly
- Update Talos Linux
- Update Helm chart versions
- Review access permissions
- Backup verification

### Quarterly
- Full security assessment
- Penetration testing (self)
- Disaster recovery drill
- Access review and cleanup
