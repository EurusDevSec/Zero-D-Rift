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

  # Bucket-level actions only, on bucket ARNs with the approved prefix. There is
  # no object ARN (bucket/*), so object actions (GetObject, PutObject) never match.
  # s3:Get*/s3:List* cover the many bucket sub-resources the provider reads on
  # every refresh (ACL, CORS, website, versioning, lifecycle, logging, ...).
  permissions_policy = {
    Version = "2012-10-17"
    Statement = [{
      Sid    = "P3BucketsOnly"
      Effect = "Allow"
      Action = [
        "s3:CreateBucket",
        "s3:DeleteBucket",
        "s3:PutBucketTagging",
        "s3:Get*",
        "s3:List*",
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
