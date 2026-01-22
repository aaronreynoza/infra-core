# Terraform Backend Setup Runbook

**Purpose**: Set up remote state storage for Terraform to avoid single points of failure.

---

## Why Remote State?

**Local state is a critical risk:**
- If you lose your computer, you lose the state file
- Terraform won't know what resources exist
- You'd have to manually import every resource or risk duplicates/conflicts
- No state locking = potential corruption with multiple users

**Remote state (S3 + DynamoDB) provides:**
- State persisted in the cloud, survives local machine loss
- State locking prevents concurrent modifications
- Versioning allows rollback if state gets corrupted
- Team collaboration without passing files around

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      AWS Account                         │
│                                                          │
│  ┌─────────────────────┐    ┌─────────────────────────┐ │
│  │        S3           │    │       DynamoDB          │ │
│  │                     │    │                         │ │
│  │ homelab-terraform-  │    │ homelab-terraform-locks │ │
│  │ state-<account-id>  │    │                         │ │
│  │                     │    │  - LockID (hash key)    │ │
│  │ /bootstrap/         │    │  - Prevents concurrent  │ │
│  │ /network/           │    │    modifications        │ │
│  │ /prod/              │    │                         │ │
│  │ /dev/               │    │                         │ │
│  └─────────────────────┘    └─────────────────────────┘ │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

---

## Initial Bootstrap Process

The bootstrap is a chicken-and-egg problem: you need a backend to store state, but the backend doesn't exist yet.

### Step 1: Create Bootstrap with Local State (Temporary)

```hcl
# core/terraform/bootstrap/main.tf (initial version)
terraform {
  # No backend block = local state
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

module "backend" {
  source = "../modules/aws-backend"
  bucket_name         = "homelab-terraform-state-<account-id>"
  dynamodb_table_name = "homelab-terraform-locks"
}
```

### Step 2: Apply to Create AWS Resources

```bash
cd core/terraform/bootstrap
terraform init
terraform apply
```

### Step 3: Migrate State to S3 (Critical!)

**Do not skip this step.** Add the S3 backend configuration:

```hcl
# core/terraform/bootstrap/main.tf (final version)
terraform {
  backend "s3" {
    bucket         = "homelab-terraform-state-<account-id>"
    key            = "bootstrap/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "homelab-terraform-locks"
    encrypt        = true
  }
  # ... rest of config
}
```

Then migrate:

```bash
terraform init -migrate-state
```

### Step 4: Verify and Clean Up

```bash
# Verify state is in S3
aws s3 ls s3://homelab-terraform-state-<account-id>/ --recursive

# Remove local state files (now redundant)
rm -f terraform.tfstate terraform.tfstate.backup
```

---

## Adding New Environments

When creating a new terraform configuration (e.g., network, prod, dev):

```hcl
terraform {
  backend "s3" {
    bucket         = "homelab-terraform-state-<account-id>"
    key            = "<environment>/terraform.tfstate"  # e.g., "network/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "homelab-terraform-locks"
    encrypt        = true
  }
}
```

---

## Disaster Recovery

### Lost Local Machine
No action needed - state is in S3. Just:
1. Clone the repo on new machine
2. Configure AWS CLI (`aws configure`)
3. Run `terraform init` in any environment
4. Terraform pulls state from S3 automatically

### Corrupted State
S3 versioning is enabled. To recover:
```bash
# List versions
aws s3api list-object-versions --bucket homelab-terraform-state-<account-id> --prefix <env>/terraform.tfstate

# Restore previous version
aws s3api copy-object \
  --bucket homelab-terraform-state-<account-id> \
  --copy-source homelab-terraform-state-<account-id>/<env>/terraform.tfstate?versionId=<version-id> \
  --key <env>/terraform.tfstate
```

### Accidental State Deletion
Same as corrupted state - restore from S3 versioning.

---

## Current State Paths

| Environment | S3 Key |
|-------------|--------|
| Bootstrap | `bootstrap/terraform.tfstate` |
| Network | `network/terraform.tfstate` |
| Prod | `prod/terraform.tfstate` |
| Dev | `dev/terraform.tfstate` |

---

## Key Principles

1. **Never use local state for anything permanent** - bootstrap only uses local state temporarily during initial creation
2. **Always migrate bootstrap state to S3** immediately after creating the backend
3. **Delete local state files** after migration to avoid confusion
4. **One state file per environment** - keeps blast radius small
5. **State locking is mandatory** - DynamoDB prevents concurrent runs
