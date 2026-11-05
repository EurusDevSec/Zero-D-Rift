# The role ARN contains the account ID, so it is not exported to the root
# outputs; the window runbook reads it with aws iam get-role.
output "role_name" {
  description = "Provider IRSA role name."
  value       = aws_iam_role.this.name
}

output "trust_subject" {
  description = "The only Kubernetes subject the role trusts."
  value       = local.subject
}

output "trust_policy" {
  description = "Trust policy as an object (for tests)."
  value       = local.trust_policy
}

output "permissions_policy" {
  description = "Permissions policy as an object (for tests)."
  value       = local.permissions_policy
}
