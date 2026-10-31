# Safe outputs only: no account ID, ARN, endpoint or credential.
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

output "vpc_id" {
  description = "VPC ID."
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "Public worker subnet IDs."
  value       = module.network.public_subnet_ids
}

output "db_subnet_group_name" {
  description = "DB subnet group for a later private RDS."
  value       = module.network.db_subnet_group_name
}

output "nat_gateway_count" {
  description = "Number of NAT Gateways; must stay 0 (ADR-0006)."
  value       = module.network.nat_gateway_count
}

output "bootstrap_admin_associations" {
  description = "Admin associations on the bootstrap access entry; 0 outside an approved window."
  value       = module.cluster.bootstrap_admin_associations
}

output "access_entry_keys" {
  description = "Access entries managed by Terraform."
  value       = module.cluster.access_entry_keys
}
