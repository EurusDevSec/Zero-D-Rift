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
  description = "Role key -> all statements of its inline policies (for tests and the IAM matrix)."
  value       = { for k, ps in local.policies : k => flatten(values(ps)) }
}

output "policy_names" {
  description = "Inline policy name -> role key."
  value       = { for name, p in local.inline : name => p.role }
}
