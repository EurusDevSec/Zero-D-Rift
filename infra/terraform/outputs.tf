# Safe outputs only: no account ID, ARN, endpoint or credential. Network and EKS
# outputs are added with their resources (DRF-8, DRF-9) and reviewed then.
output "region" {
  description = "AWS Region of the PoC."
  value       = var.region
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = var.cluster_name
}

output "kubernetes_version" {
  description = "EKS Kubernetes minor version."
  value       = var.kubernetes_version
}

output "subnet_plan" {
  description = "Planned subnet CIDRs per AZ."
  value = {
    for i, az in var.azs : az => {
      public = local.public_subnet_cidrs[i]
      db     = local.db_subnet_cidrs[i]
    }
  }
}

output "common_tags" {
  description = "Tags applied to every taggable AWS resource."
  value       = local.common_tags
}
