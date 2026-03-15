terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    # Configure via: terraform init -backend-config=../../../../environments/prod/zitadel/backend.hcl
  }

  required_providers {
    zitadel = {
      source  = "zitadel/zitadel"
      version = ">= 2.10.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0.0"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.0.0"
    }
  }
}
