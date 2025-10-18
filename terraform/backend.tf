terraform {
  # S3 backend is configured at runtime with -backend-config flags in CI
  backend "s3" {}
}
