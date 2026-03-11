# Bootstrap Outputs

output "s3_bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  value       = module.backend.bucket_name
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = module.backend.bucket_arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table for state locking"
  value       = module.backend.dynamodb_table_name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = module.backend.dynamodb_table_arn
}

output "backend_config" {
  description = "Backend configuration to use in other environments"
  value       = <<-EOT
    # Add this to your terraform block in other environments:
    backend "s3" {
      bucket         = "${module.backend.bucket_name}"
      key            = "<environment>/terraform.tfstate"  # e.g., "network/terraform.tfstate"
      region         = "us-east-1"
      dynamodb_table = "${module.backend.dynamodb_table_name}"
      encrypt        = true
    }
  EOT
}
