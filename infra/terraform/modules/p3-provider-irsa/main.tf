# P3 Crossplane provider identity (SPEC-P3 Task 4, D4, ADR-0003). Terraform owns
# this IAM role; Crossplane owns the buckets. The provider-aws-s3 Pod assumes the
# role through IRSA: the EKS OIDC issuer signs a token for exactly one Kubernetes
# ServiceAccount, and the role trusts only that subject and audience.
# Policies are built with jsonencode (not aws_iam_policy_document) so the
# mocked tests can read and assert their content.

locals {
  issuer_host = trimprefix(var.oidc_issuer_url, "https://")
  subject     = "system:serviceaccount:${var.namespace}:${var.service_account}"

  trust_policy = {
    Version = "2012-10-17"
    Statement = [{
      Sid       = "ProviderServiceAccountOnly"
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.issuer_host}:sub" = local.subject
          "${local.issuer_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  }

  # Bucket-level actions only. The resource arn:aws:s3:::<prefix>* ALSO matches
  # object ARNs (<bucket>/<key>), because * crosses "/" (found by the IAM
  # simulation on 05/11: s3:Get* allowed GetObject). So no s3:Get*/s3:List*:
  # s3:GetBucket* names only bucket sub-resources (ACL, CORS, website,
  # versioning, logging, tagging, policy, location, ...); the few bucket reads
  # that do not start with GetBucket are listed one by one.
  permissions_policy = {
    Version = "2012-10-17"
    Statement = [{
      Sid    = "P3BucketsOnly"
      Effect = "Allow"
      Action = [
        "s3:CreateBucket",
        "s3:DeleteBucket",
        "s3:ListBucket",
        "s3:PutBucketTagging",
        "s3:GetBucket*",
        "s3:GetAccelerateConfiguration",
        "s3:GetEncryptionConfiguration",
        "s3:GetLifecycleConfiguration",
        "s3:GetReplicationConfiguration",
      ]
      Resource = ["arn:aws:s3:::${var.bucket_prefix}*"]
    }]
  }
}

resource "aws_iam_role" "this" {
  name                 = var.role_name
  description          = "Crossplane provider-aws-s3 via IRSA; buckets ${var.bucket_prefix}* only (SPEC-P3 Task 4)."
  assume_role_policy   = jsonencode(local.trust_policy)
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "buckets" {
  name   = "p3-buckets"
  role   = aws_iam_role.this.id
  policy = jsonencode(local.permissions_policy)
}
