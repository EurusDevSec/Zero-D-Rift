output "names" {
  description = "Names for the Helm values and EC2NodeClass (no ARN)."
  value = {
    controller_role    = aws_iam_role.controller.name
    node_role          = aws_iam_role.node.name
    instance_profile   = aws_iam_instance_profile.node.name
    interruption_queue = aws_sqs_queue.interruption.name
  }
}

output "controller_role_arn" {
  description = "Controller role ARN for the ServiceAccount annotation (holds the account ID)."
  value       = aws_iam_role.controller.arn
  sensitive   = true
}

output "controller_trust" {
  description = "Controller trust policy object (for tests)."
  value       = local.controller_trust
}

output "statements" {
  description = "Inline policy name -> statements (for tests and tests/p6_approved_policies.json)."
  value       = { karpenter-controller = local.controller_statements }
}

output "node_policies" {
  description = "Managed policies attached to the node role."
  value       = local.node_policies
}

output "rules" {
  description = "EventBridge rule key -> source and detail type."
  value       = local.rules
}

output "access_entry_type" {
  description = "Access entry type of the node role."
  value       = aws_eks_access_entry.node.type
}
