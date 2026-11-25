# P6 batch platform (SPEC-P6 P6-T3 A, D2, D3, D8). Terraform owns the shared
# queue, its dead-letter queue and every batch IAM role; Crossplane owns only
# the per-request checkpoint bucket (ADR-0003, ADR-0008). Created only in an
# approved batch window (enable_batch_platform) and destroyed with it.
#
# Four IRSA roles (web identity from the cluster OIDC issuer, audience
# sts.amazonaws.com, one exact ServiceAccount each, StringEquals):
#   zero-drift-batch-keda       keda/keda-operator     GetQueueAttributes only
#   zero-drift-batch-submit     zdr-platform/batch-submit
#                               send; put only the two submit markers; list only
#                               with s3:prefix runs/*/submitted; no GetObject
#   zero-drift-batch-tenant-a/b <tenant>/batch-train   receive, delete, change
#                               visibility; own zero-drift-batch-<tenant>-* only
#
# ARNs are built from names and the account so every policy is known in the
# first plan (plan_assert.sh check 19 compares them with the approved file
# tests/p6_approved_policies.json). Lists are sorted in that file's order.

data "aws_caller_identity" "this" {}

locals {
  issuer_host = trimprefix(var.oidc_issuer_url, "https://")
  account     = data.aws_caller_identity.this.account_id
  queue_arn   = "arn:aws:sqs:${var.region}:${local.account}:${var.queue_name}"
  dlq_arn     = "arn:aws:sqs:${var.region}:${local.account}:${var.queue_name}-dlq"
  buckets     = "arn:aws:s3:::${var.bucket_prefix}"

  roles = merge(
    {
      keda = {
        name    = "zero-drift-batch-keda"
        subject = "system:serviceaccount:${var.keda_namespace}:${var.keda_service_account}"
      }
      submit = {
        name    = "zero-drift-batch-submit"
        subject = "system:serviceaccount:${var.platform_namespace}:${var.submit_service_account}"
      }
    },
    { for t in var.tenants : t => {
      name    = "zero-drift-batch-${t}"
      subject = "system:serviceaccount:${t}:${var.train_service_account}"
    } }
  )

  trust_policies = { for k, r in local.roles : k => {
    Version = "2012-10-17"
    Statement = [{
      Sid       = "ServiceAccountOnly"
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.issuer_host}:aud" = "sts.amazonaws.com"
          "${local.issuer_host}:sub" = r.subject
        }
      }
    }]
  } }

  # Role key -> statements of its one inline policy (batch-<key>).
  policies = merge(
    {
      keda = [{
        Sid      = "ReadQueueDepth"
        Effect   = "Allow"
        Action   = ["sqs:GetQueueAttributes"]
        Resource = [local.queue_arn]
      }]
      submit = [
        {
          Sid      = "SendToQueue"
          Effect   = "Allow"
          Action   = ["sqs:SendMessage"]
          Resource = [local.queue_arn]
        },
        {
          Sid      = "WriteSubmitMarkers"
          Effect   = "Allow"
          Action   = ["s3:PutObject"]
          Resource = ["${local.buckets}*/runs/*/submit-started", "${local.buckets}*/runs/*/submitted"]
        },
        {
          # The marker check lists exactly runs/<id>/<attempt>/submitted; the
          # condition stops the role from listing tenant object names.
          Sid       = "ListSubmittedMarkerOnly"
          Effect    = "Allow"
          Action    = ["s3:ListBucket"]
          Resource  = ["${local.buckets}*"]
          Condition = { StringLike = { "s3:prefix" = ["runs/*/submitted"] } }
        },
      ]
    },
    { for t in var.tenants : t => [
      {
        Sid      = "UseSharedQueue"
        Effect   = "Allow"
        Action   = ["sqs:ChangeMessageVisibility", "sqs:DeleteMessage", "sqs:ReceiveMessage"]
        Resource = [local.queue_arn]
      },
      {
        Sid      = "ListOwnBuckets"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = ["${local.buckets}${t}-*"]
      },
      {
        Sid      = "OwnObjects"
        Effect   = "Allow"
        Action   = ["s3:DeleteObject", "s3:GetObject", "s3:PutObject"]
        Resource = ["${local.buckets}${t}-*/*"]
      },
    ] }
  )

  # Both queues refuse plain HTTP; neither has an Allow for any principal, so
  # only identities in this account with an IAM allow can use them.
  tls_only = { for k, arn in { main = local.queue_arn, dlq = local.dlq_arn } : k => {
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "sqs:*"
      Resource  = arn
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  } }
}

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.queue_name}-dlq"
  message_retention_seconds = var.retention_seconds
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "main" {
  name                       = var.queue_name
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.retention_seconds
  sqs_managed_sse_enabled    = true
  # Built ARN (= aws_sqs_queue.dlq.arn) so the plan shows the redrive policy.
  redrive_policy = jsonencode({
    deadLetterTargetArn = local.dlq_arn
    maxReceiveCount     = var.max_receive_count
  })
  depends_on = [aws_sqs_queue.dlq]
}

resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [local.queue_arn]
  })
}

resource "aws_sqs_queue_policy" "tls_only" {
  for_each = { main = aws_sqs_queue.main.id, dlq = aws_sqs_queue.dlq.id }

  queue_url = each.value
  policy    = jsonencode(local.tls_only[each.key])
}

resource "aws_iam_role" "this" {
  for_each = local.roles

  name                 = each.value.name
  description          = "P6 batch IRSA role for ${each.value.subject} (SPEC-P6 D2, ADR-0008)."
  assume_role_policy   = jsonencode(local.trust_policies[each.key])
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "this" {
  for_each = local.policies

  name = "batch-${each.key}"
  role = aws_iam_role.this[each.key].id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = each.value
  })
}
