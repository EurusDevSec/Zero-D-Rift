output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_version" {
  description = "Kubernetes version of the cluster."
  value       = module.eks.cluster_version
}

output "access_entry_keys" {
  description = "Access entries managed by Terraform."
  value       = keys(module.eks.access_entries)
}

output "bootstrap_admin_associations" {
  description = "Number of admin policy associations on the bootstrap entry (0 outside a window)."
  value       = length(local.bootstrap_admin_policy)
}

output "oidc_provider_enabled" {
  description = "Whether the IRSA OIDC provider is managed here."
  value       = module.eks.oidc_provider_arn != null
}
