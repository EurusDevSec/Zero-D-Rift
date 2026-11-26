# P4 workload identities (SPEC-P4 P4-T2.2 B, D4-D7, ADR-0008 §4). Terraform
# creates every P4 IAM role before any request; nothing in the request path gets
# an IAM right (no provider-aws-iam).
#
# Five roles, all IRSA (web identity from the cluster OIDC issuer, audience
# sts.amazonaws.com):
#   zero-drift-rag-db-admin      SA zdr-platform/rag-db-admin (exact)
#   zero-drift-rag-bootstrap     SA zdr-platform/rag-bootstrap (exact)
#   zero-drift-rag-tenant-a/-b   SA <tenant>/rag-* (StringLike, D6)
#   zero-drift-rag-crossplane-s3 SA crossplane-system/provider-aws-s3 (exact)
#
# Every statement has an exact action list and names its resources; no action
# or resource is "*", no IAM or STS action. P3 lesson: arn:aws:s3:::<prefix>*
# also matches object ARNs, so bucket statements hold bucket-level actions only.
# Secrets Manager adds a random 6-character suffix to every secret ARN, so a
# fixed secret is named "<name>-??????" (exactly six characters, AWS guidance).
# Policies are built with jsonencode so the mocked tests can read them.

data "aws_caller_identity" "this" {}

locals {
  issuer_host = trimprefix(var.oidc_issuer_url, "https://")
  account     = data.aws_caller_identity.this.account_id
  secret_arn  = "arn:aws:secretsmanager:${var.region}:${local.account}:secret:"

  bootstrap_secret = "${local.secret_arn}${var.secret_prefix}platform/bootstrap-??????"
  tenant_secrets   = { for t in var.tenants : t => "${local.secret_arn}${var.secret_prefix}${t}/*" }

  # Bucket prefixes the Crossplane S3 role may manage: RAG always, plus the P6
  # checkpoint buckets in a batch window (SPEC-P6 A7, DRF-77).
  crossplane_prefixes = concat([var.bucket_prefix], var.extra_bucket_prefixes)

  # name, Kubernetes subject, condition operator for the subject
  roles = merge(
    {
      db-admin = {
        name     = "zero-drift-rag-db-admin"
        subject  = "system:serviceaccount:${var.platform_namespace}:rag-db-admin"
        operator = "StringEquals"
      }
      bootstrap = {
        name     = "zero-drift-rag-bootstrap"
        subject  = "system:serviceaccount:${var.platform_namespace}:rag-bootstrap"
        operator = "StringEquals"
      }
      crossplane-s3 = {
        name     = "zero-drift-rag-crossplane-s3"
        subject  = "system:serviceaccount:${var.crossplane_namespace}:${var.crossplane_service_account}"
        operator = "StringEquals"
      }
    },
    { for t in var.tenants : t => {
      name     = "zero-drift-rag-${t}"
      subject  = "system:serviceaccount:${t}:rag-*"
      operator = "StringLike"
    } }
  )

  trust_policies = { for k, r in local.roles : k => {
    Version = "2012-10-17"
    Statement = [{
      Sid       = "ServiceAccountOnly"
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      # Exact subjects use StringEquals for both keys; the tenant pattern
      # rag-* needs StringLike for sub, and aud stays StringEquals.
      Condition = merge(
        {
          StringEquals = merge(
            { "${local.issuer_host}:aud" = "sts.amazonaws.com" },
            r.operator == "StringEquals" ? { "${local.issuer_host}:sub" = r.subject } : {},
          )
        },
        r.operator == "StringLike" ? { StringLike = { "${local.issuer_host}:sub" = r.subject } } : {},
      )
    }]
  } }

  # Inline policies: role key -> policy name -> statements. The master secret
  # ARN is only known after the instance exists, so it has its own policy and
  # the rest of db-admin's policy stays readable in a first plan.
  policies = merge(
    {
      db-admin = {
        rag-db-admin = [{
          Sid      = "WriteBootstrapSecret"
          Effect   = "Allow"
          Action   = ["secretsmanager:CreateSecret", "secretsmanager:GetSecretValue", "secretsmanager:TagResource"]
          Resource = [local.bootstrap_secret]
        }]
        rag-db-admin-master = [{
          Sid      = "ReadMasterSecret"
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue"]
          Resource = [var.master_secret_arn]
        }]
      }
      bootstrap = {
        rag-bootstrap = [
          {
            Sid      = "ReadBootstrapSecret"
            Effect   = "Allow"
            Action   = ["secretsmanager:GetSecretValue"]
            Resource = [local.bootstrap_secret]
          },
          {
            Sid      = "ManageSandboxSecrets"
            Effect   = "Allow"
            Action   = ["secretsmanager:CreateSecret", "secretsmanager:DeleteSecret", "secretsmanager:GetSecretValue", "secretsmanager:TagResource"]
            Resource = [for t in var.tenants : local.tenant_secrets[t]]
          },
        ]
      }
      crossplane-s3 = {
        rag-crossplane-s3 = [
          {
            # Bucket-level only, no wildcard (ADR-0008 rule 3). One action per S3
            # read in the provider's aws_s3_bucket Read (upbound fork d7cd6f2fe022,
            # used by provider-aws-s3 v2.8.1): AccessDenied on any of them fails
            # the observe. ListBucket covers HeadBucket. GetBucketTagging (tags) and
            # GetBucketLocation (region) are kept from the P3 set. ListBucketVersions
            # and the object deletes below are for forceDestroy.
            Sid    = "RagBuckets"
            Effect = "Allow"
            Action = [
              "s3:CreateBucket",
              "s3:DeleteBucket",
              "s3:GetAccelerateConfiguration",
              "s3:GetBucketAcl",
              "s3:GetBucketCORS",
              "s3:GetBucketLocation",
              "s3:GetBucketLogging",
              "s3:GetBucketObjectLockConfiguration",
              "s3:GetBucketPolicy",
              "s3:GetBucketRequestPayment",
              "s3:GetBucketTagging",
              "s3:GetBucketVersioning",
              "s3:GetBucketWebsite",
              "s3:GetEncryptionConfiguration",
              "s3:GetLifecycleConfiguration",
              "s3:GetReplicationConfiguration",
              "s3:ListBucket",
              "s3:ListBucketVersions",
              "s3:PutBucketTagging",
            ]
            Resource = [for p in local.crossplane_prefixes : "arn:aws:s3:::${p}*"]
          },
          {
            # D7: forceDestroy empties a sandbox bucket before deleting it.
            Sid      = "ForceDestroyObjects"
            Effect   = "Allow"
            Action   = ["s3:DeleteObject", "s3:DeleteObjectVersion"]
            Resource = [for p in local.crossplane_prefixes : "arn:aws:s3:::${p}*/*"]
          },
        ]
      }
    },
    { for t in var.tenants : t => {
      "rag-${t}" = [
        {
          Sid      = "OwnSecrets"
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue"]
          Resource = [local.tenant_secrets[t]]
        },
        {
          # HeadBucket needs ListBucket; bucket-level only.
          Sid      = "OwnBuckets"
          Effect   = "Allow"
          Action   = ["s3:ListBucket"]
          Resource = ["arn:aws:s3:::${var.bucket_prefix}${t}-*"]
        },
        {
          Sid      = "ReadOwnObjects"
          Effect   = "Allow"
          Action   = ["s3:GetObject"]
          Resource = ["arn:aws:s3:::${var.bucket_prefix}${t}-*/*"]
        },
      ]
    } }
  )

  inline = merge([for k, ps in local.policies : {
    for name, statements in ps : name => { role = k, statements = statements }
  }]...)
}

resource "aws_iam_role" "this" {
  for_each = local.roles

  name                 = each.value.name
  description          = "P4 RAGSandbox IRSA role for ${each.value.subject} (SPEC-P4 D6, ADR-0008)."
  assume_role_policy   = jsonencode(local.trust_policies[each.key])
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "this" {
  for_each = local.inline

  name = each.key
  role = aws_iam_role.this[each.value.role].id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = each.value.statements
  })
}
