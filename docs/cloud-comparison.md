# Homelab vs Cloud: Component Mapping

Maps each homelab component to its AWS and GCP equivalent.
Shows that this homelab uses the same architectural patterns
as production cloud environments -- just self-hosted.

## Table of Contents
- [Visual Overview](#visual-overview)
- [Request Path Comparison](#request-path-comparison)
- [Compute & Orchestration](#compute--orchestration)
- [Networking](#networking--service-exposure)
- [DNS & Traffic](#dns--traffic-management)
- [Security](#security--access-control)
- [Storage & Backup](#storage--backup)
- [CI/CD & GitOps](#cicd--gitops)
- [Observability](#observability)
- [Full Mapping Table](#full-mapping-table)

---

## Visual Overview

```
  HOMELAB              AWS           GCP
  ───────              ───           ───

  Vultr VPS            ALB/NLB       GCLB
  + Pangolin           + ACM         + Managed
  + Traefik                          SSL Certs
  + Let's Encrypt
       │                  │             │
  WireGuard           Site-to-Site   Cloud VPN
  (Newt)              VPN
       │                  │             │
  Control D +         Route 53 +     Cloud DNS
  ctrld               Resolver       + Policies
  (per-VLAN DNS)      Rules
       │                  │             │
  Cloudflare          CloudFront     Cloud Armor
  CDN/WAF             + AWS WAF      + Cloud CDN
  (future)
       │                  │             │
  Talos Linux         EKS            GKE
  on Proxmox          (managed K8s)  (managed K8s)
  + Cilium                           (Dataplane V2
       │                              = Cilium!)
       │                  │             │
  OPNSense            VPC + SGs      VPC + FW
  + VLANs             + NACLs        Rules
  + Firewall
       │                  │             │
  Longhorn             EBS            Persistent
  (block storage)                     Disk
       │                  │             │
  ArgoCD               ArgoCD/Flux   Config Sync
  (GitOps)                           / ArgoCD
```

---

## Request Path Comparison

Same number of hops, same pattern, same concepts.

```
  HOMELAB:
    User
    -> DNS (Control D -> VPS IP)
    -> Cloudflare CDN/WAF (future)
    -> Vultr VPS (Traefik TLS + Badger auth)
    -> WireGuard tunnel
    -> Newt (Talos extension)
    -> K8s Pod

  AWS (EKS):
    User
    -> DNS (Route 53 -> ALB IP)
    -> CloudFront + AWS WAF
    -> ALB (TLS via ACM + Cognito auth)
    -> Target Group -> EKS node
    -> kube-proxy / Cilium
    -> K8s Pod

  GCP (GKE):
    User
    -> DNS (Cloud DNS -> LB IP)
    -> Cloud Armor + Cloud CDN
    -> GCLB (TLS via managed certs + IAP auth)
    -> NEG -> GKE pod
    -> Dataplane V2
    -> K8s Pod
```

---

## Compute & Orchestration

```
  Homelab          AWS              GCP
  ───────          ───              ───

  Proxmox VE       EC2              Compute
  (hypervisor)     (VMs)            Engine

       |                |               |

  Talos Linux      Bottlerocket     Container-
  (immutable OS,   (EKS-optimized   Optimized OS
   API-driven,     AMI, no SSH)     (GKE image,
   no SSH)                           no SSH)

       |                |               |

  Kubernetes       EKS              GKE
  (self-managed)   (managed)        (managed)

       |                |               |

  Cilium           AWS VPC CNI      Dataplane V2
  + Hubble         (or Cilium)      (= Cilium!)
```

GKE Dataplane V2 is literally Cilium under the hood.
Talos is to your homelab what Bottlerocket is to EKS.

---

## Networking & Service Exposure

```
  NETWORK ISOLATION:

  Homelab          AWS              GCP
  ───────          ───              ───
  OPNSense         VPC              VPC
  + VLANs          + Subnets        + Subnets
  + Firewall       + Security Grps  + FW Rules
  + NAT            + NACLs + NAT GW + Cloud NAT

  VLAN 10 (PROD) and VLAN 11 (DEV) with
  inter-VLAN blocking = two VPCs with no
  peering in AWS/GCP.

  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─

  SERVICE EXPOSURE (INGRESS):

  Homelab          AWS              GCP
  ───────          ───              ───
  Pangolin (VPS)   ALB / NLB        GCLB
  + Traefik        + ACM            + Managed
  + Let's Encrypt  (auto TLS)       SSL Certs
  + WireGuard      + VPN /          + Cloud VPN
    (via Newt)     Direct Connect   / Interconnect

  Pangolin + Newt = ALB in a public subnet
  + Site-to-Site VPN to your on-prem cluster.
  The VPS is your "public subnet."
  WireGuard is your "VPN connection."
```

---

## DNS & Traffic Management

```
  DNS RESOLUTION:

  Homelab          AWS              GCP
  ───────          ───              ───
  Control D        Route 53         Cloud DNS
  (DNS + filter)   (hosted zones)   (managed zones)

  PER-NETWORK DNS POLICIES:

  ctrld on         Route 53         Cloud DNS
  OPNSense         Resolver Rules   Server Policy
  (source-IP       (per-VPC rules,  (per-VPC DNS
   routing)        forwarding)      forwarding)

  PROD -> strict    Prod VPC -> prod  Same pattern
  DEV  -> open      Dev VPC  -> dev

  SPLIT-HORIZON DNS:

  ctrld rules:     Route 53:        Cloud DNS:
  *.example.com    Public hosted    Public zone
  -> local DNS     zone -> ALB IP  -> LB IP
  (external gets   Private hosted   Private zone
   VPS IP via      zone -> internal -> internal IP
   public DNS)     ALB IP

  Same pattern everywhere: internal traffic
  uses internal IPs, external uses public IPs.
```

---

## Security & Access Control

```
  DDoS / WAF:

  Homelab          AWS              GCP
  ───────          ───              ───
  Cloudflare       AWS Shield       Cloud Armor
  CDN/WAF          + AWS WAF        (DDoS + WAF
  (in front of     + CloudFront     + CDN)
   VPS, future)

  IDENTITY & AUTH:

  Zitadel (SSO)    Cognito / IAM    Identity
  + Badger (auth   Identity Center  Platform
   middleware)     (SSO for apps)   + IAP

  SECRET MANAGEMENT:

  AWS Secrets      AWS Secrets      Secret
  Manager          Manager          Manager
  + External       (native with     (native with
   Secrets Op.     IRSA)            Workload ID)

  DNS SECURITY:

  Control D        Route 53         Cloud DNS +
  (malware block,  Resolver DNS     Security
   ad filter,      Firewall         Command Ctr
   per-VLAN)
```

---

## Storage & Backup

```
  BLOCK STORAGE:

  Homelab          AWS              GCP
  ───────          ───              ───
  Longhorn (CSI)   EBS (CSI)        Persistent
  Snapshots: yes   Snapshots: yes   Disk (CSI)
  Replication:     Replication:     Snapshots: yes
   cross-node       cross-AZ        cross-zone

  FILE STORAGE (future):

  TrueNAS (ZFS)    EFS / FSx        Filestore
  NFS shares,      (managed NFS)    (managed NFS)
  media, iSCSI

  BACKUP / DR:

  Velero -> S3     AWS Backup       GKE Backup
  Longhorn -> S3   EBS Snapshots    PD Snapshots
  TrueNAS ZFS      S3 Cross-Region  GCS multi-
  replication      Replication      regional

  TERRAFORM STATE:

  S3 + DynamoDB    S3 + DynamoDB    GCS bucket
  (same as AWS!)   (native TF)      (native TF)
```

---

## CI/CD & GitOps

```
  SOURCE CONTROL:

  Homelab          AWS              GCP
  ───────          ───              ───
  Forgejo          CodeCommit       Cloud Source
  + GitHub mirror  or GitHub        Repos

  CI (Build + Test):

  Forgejo Actions  CodeBuild /      Cloud Build
  (GH Actions      CodePipeline
   compatible)

  CONTAINER REGISTRY:

  Harbor           ECR              Artifact
  (per env)                         Registry

  CD (Deploy to K8s):

  ArgoCD           ArgoCD / Flux    Config Sync
  (GitOps)         (same tools,     or ArgoCD
                    on EKS)

  IaC:

  Terraform        Terraform /      Terraform /
  (Proxmox +       CloudFormation   Deployment
   Talos providers)                  Manager
```

---

## Observability

```
  Homelab          AWS              GCP
  ───────          ───              ───

  Grafana          CloudWatch       Cloud
  (dashboards)     (metrics+dash)   Monitoring

  InfluxDB         CloudWatch       Cloud
  (time-series)    Metrics / AMP    Monitoring/GMP

  Hubble           VPC Flow Logs    VPC Flow Logs
  (network flows)  + Traffic Mirr.  + Packet Mirr.

  Control D        Route 53         Cloud DNS
  (DNS analytics)  Query Logging    Logging
```

---

## Full Mapping Table

| Category | Homelab | AWS | GCP |
|----------|---------|-----|-----|
| **Hypervisor** | Proxmox VE | EC2 | Compute Engine |
| **Cluster OS** | Talos Linux | Bottlerocket | Container-Optimized OS |
| **Kubernetes** | Self-managed | EKS | GKE |
| **CNI** | Cilium | VPC CNI | Dataplane V2 (Cilium) |
| **Network** | OPNSense+VLANs | VPC+SGs | VPC+FW Rules |
| **Firewall** | OPNSense rules | Security Groups | VPC Firewall |
| **NAT** | OPNSense NAT | NAT Gateway | Cloud NAT |
| **Load Balancer** | Pangolin+Traefik | ALB/NLB | GCLB |
| **TLS Certs** | Let's Encrypt | ACM | Managed SSL |
| **VPN/Tunnel** | WireGuard (Newt) | Site-to-Site VPN | Cloud VPN |
| **DNS** | Control D | Route 53 | Cloud DNS |
| **DNS Policies** | ctrld (per-CIDR) | Resolver Rules | DNS Policies |
| **Split-Horizon** | ctrld rules | Pub+Priv zones | Pub+Priv zones |
| **DNS Security** | Control D filter | DNS Firewall | SCC |
| **DDoS** | Cloudflare (future) | AWS Shield | Cloud Armor |
| **WAF** | Cloudflare (future) | AWS WAF | Cloud Armor |
| **CDN** | Cloudflare (future) | CloudFront | Cloud CDN |
| **Auth/SSO** | Zitadel+Badger | Cognito | Identity+IAP |
| **Secrets** | AWS SM+ESO | Secrets Manager | Secret Manager |
| **Block Storage** | Longhorn | EBS | Persistent Disk |
| **File Storage** | TrueNAS (future) | EFS/FSx | Filestore |
| **Backup** | Velero->S3 | AWS Backup | GKE Backup |
| **TF State** | S3+DynamoDB | S3+DynamoDB | GCS |
| **Source Control** | Forgejo | CodeCommit | Cloud Source |
| **CI** | Forgejo Actions | CodeBuild | Cloud Build |
| **Registry** | Harbor | ECR | Artifact Reg. |
| **GitOps** | ArgoCD | ArgoCD/Flux | Config Sync |
| **IaC** | Terraform | TF/CloudForm. | TF/Depl. Mgr |
| **Dashboards** | Grafana | CloudWatch | Cloud Monitor |
| **Metrics** | InfluxDB | CW Metrics/AMP | GMP |
| **Network Obs.** | Hubble | Flow Logs | Flow Logs |
| **DNS Analytics** | Control D | R53 Query Logs | DNS Logging |

---

## Key Takeaway

This homelab runs the **same architectural patterns** used in
production AWS and GCP environments. The only difference is
that managed services (EKS, ALB, Route 53) are replaced with
self-hosted equivalents (Talos, Pangolin, Control D).

In many cases the exact same tools are used (Terraform, ArgoCD,
Cilium, Velero). GKE even uses Cilium natively.

The skills transfer directly: if you can design, deploy, and
troubleshoot this homelab, you can do the same on any cloud
provider -- you just swap the component names.
