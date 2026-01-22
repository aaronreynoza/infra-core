# Bootstrap Environment
# Creates AWS resources for Terraform state management

terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket         = "homelab-terraform-state-REDACTED_ACCOUNT_ID"
    key            = "bootstrap/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "homelab-terraform-locks"
    encrypt        = true
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
