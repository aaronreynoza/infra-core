# Bootstrap Environment
# Creates AWS resources for Terraform state management

terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    # Configure via: terraform init -backend-config=<path-to>/backend.hcl
    # See docs/configuration.md for details
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "backend" {
  source = "../modules/aws-backend"

  bucket_name         = var.bucket_name
  dynamodb_table_name = var.dynamodb_table_name
  tags                = var.tags
}
