output "queue_names" {
  description = "Shared queue and dead-letter queue names."
  value       = { main = aws_sqs_queue.main.name, dlq = aws_sqs_queue.dlq.name }
}

output "queue_url" {
  description = "Shared queue URL for ConfigMap batch-config (holds the account ID)."
  value       = aws_sqs_queue.main.url
  sensitive   = true
}

output "queue_settings" {
  description = "Planned queue settings (for tests)."
  value = {
    visibility_timeout = aws_sqs_queue.main.visibility_timeout_seconds
    retention          = aws_sqs_queue.main.message_retention_seconds
    dlq_retention      = aws_sqs_queue.dlq.message_retention_seconds
    sse                = aws_sqs_queue.main.sqs_managed_sse_enabled && aws_sqs_queue.dlq.sqs_managed_sse_enabled
    max_receive_count  = var.max_receive_count
  }
}

output "queue_policies" {
  description = "Queue key -> resource policy object (for tests)."
  value       = local.tls_only
}

output "role_names" {
  description = "Role key -> role name."
  value       = { for k, r in aws_iam_role.this : k => r.name }
}

output "role_arns" {
  description = "Role key -> ARN, for the ServiceAccount annotations (holds the account ID)."
  value       = { for k, r in aws_iam_role.this : k => r.arn }
  sensitive   = true
}

output "subjects" {
  description = "Role key -> trusted Kubernetes subject."
  value       = { for k, r in local.roles : k => r.subject }
}

output "trust_policies" {
  description = "Role key -> trust policy object (for tests)."
  value       = local.trust_policies
}

output "statements" {
  description = "Inline policy name -> statements (for tests and tests/p6_approved_policies.json)."
  value       = { for k, ss in local.policies : "batch-${k}" => ss }
}
