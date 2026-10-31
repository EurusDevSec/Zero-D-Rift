# Exact pins approved in docs/evidence/p2/P2_T1_DECISION_REVIEW.md.
# Never widen a pin or run `init -upgrade` to repair a failed init.
terraform {
  required_version = "= 1.16.4"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.67.0"
    }
    # Required transitively by terraform-aws-modules/eks 21.26.0 (root and
    # _user_data). Pinned here so the lockfile records the approved builds.
    tls = {
      source  = "hashicorp/tls"
      version = "= 4.4.1"
    }
    time = {
      source  = "hashicorp/time"
      version = "= 0.14.2"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "= 2.4.1"
    }
    null = {
      source  = "hashicorp/null"
      version = "= 3.3.2"
    }
  }
}

# Module pins (the lockfile does not record modules; scripts/check.sh enforces these):
#   terraform-aws-modules/vpc/aws                        6.7.3  (DRF-8 network)
#   terraform-aws-modules/vpc/aws//modules/vpc-endpoints 6.7.3  (S3 gateway endpoint)
#   terraform-aws-modules/eks/aws                        21.26.0 (DRF-9 EKS)
#   terraform-aws-modules/kms/aws                        4.0.0  (transitive from EKS)
