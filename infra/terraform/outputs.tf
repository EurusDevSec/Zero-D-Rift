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

output "p3_provider_role" {
  description = "P3 provider IRSA role name and trusted subject, or null when disabled (no ARN: it holds the account ID)."
  value = var.enable_p3_provider_role ? {
    name    = module.p3_provider_irsa[0].role_name
    subject = module.p3_provider_irsa[0].trust_subject
  } : null
}

output "rag_platform" {
  description = "P4 names and trusted subjects, or null when disabled. No ARN or endpoint: those are in rag_platform_config."
  value = var.enable_rag_platform ? {
    db_identifier = module.shared_rds[0].identifier
    db_port       = module.shared_rds[0].port
    roles         = module.rag_identity[0].role_names
    subjects      = module.rag_identity[0].subjects
  } : null
}

output "rag_platform_config" {
  description = "Window-only values for platform-config and the ServiceAccount annotations (DB host, master secret ARN, role ARNs). Sensitive: pipe it, never print it."
  sensitive   = true
  value = var.enable_rag_platform ? {
    db_host           = module.shared_rds[0].address
    db_port           = module.shared_rds[0].port
    master_secret_arn = module.shared_rds[0].master_secret_arn
    role_arns         = module.rag_identity[0].role_arns
  } : null
}

output "vpc_cni_configuration" {
  description = "vpc-cni add-on configuration: NetworkPolicy on, standard mode (SPEC-P5 D5)."
  value       = module.cluster.vpc_cni_configuration
}

output "batch_platform" {
  description = "P6 names and trusted subjects, or null when disabled. No ARN or URL: those are in batch_platform_config."
  value = var.enable_batch_platform ? {
    queues    = module.batch_platform[0].queue_names
    roles     = module.batch_platform[0].role_names
    subjects  = module.batch_platform[0].subjects
    karpenter = module.karpenter[0].names
  } : null
}

output "batch_platform_config" {
  description = "Window-only values for ConfigMap batch-config and the ServiceAccount annotations (queue URL, role ARNs). Sensitive: pipe it, never print it."
  sensitive   = true
  value = var.enable_batch_platform ? {
    queue_url                 = module.batch_platform[0].queue_url
    role_arns                 = module.batch_platform[0].role_arns
    karpenter_controller_role = module.karpenter[0].controller_role_arn
  } : null
}
