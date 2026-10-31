# Partial S3 backend configuration (ADR-0007). The bucket name and profile are
# private and live in an untracked backend.hcl (copy backend.hcl.example).
#
# Local checks:   terraform init -backend=false
# Backend (DRF-6, separate authority only):
#                 terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {}
}
