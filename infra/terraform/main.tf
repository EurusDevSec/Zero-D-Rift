# Root of the P2 bootstrap. Resources arrive by issue, keeping the TF-T01 module
# boundary (network outputs -> cluster inputs):
#   DRF-8: module "network" (VPC 6.7.3, public/DB subnets, S3 gateway endpoint, no NAT)
#   DRF-9: module "cluster" (EKS 21.26.0, AL2023 system nodes, OIDC, access entries)

module "network" {
  source = "./modules/network"

  name                = var.cluster_name
  region              = var.region
  vpc_cidr            = var.vpc_cidr
  azs                 = var.azs
  public_subnet_cidrs = local.public_subnet_cidrs
  db_subnet_cidrs     = local.db_subnet_cidrs
}

module "cluster" {
  source = "./modules/cluster"

  name                         = var.cluster_name
  kubernetes_version           = var.kubernetes_version
  vpc_id                       = module.network.vpc_id
  subnet_ids                   = module.network.public_subnet_ids
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs
  bootstrap_role_name          = var.bootstrap_role_name
  bootstrap_cluster_admin      = var.bootstrap_cluster_admin
  addon_versions               = var.addon_versions
  node_ami_type                = var.system_node_ami_type
  node_ami_release_version     = var.system_node_ami_release_version
  node_instance_type           = var.system_node_instance_type
  node_desired_size            = var.system_node_desired_size
  node_max_size                = var.system_node_max_size
}

# DRF-36 (SPEC-P3 Task 4): Crossplane provider IRSA role, created only for the
# approved P3 window (enable_p3_provider_role = true in the window tfvars).
module "p3_provider_irsa" {
  source = "./modules/p3-provider-irsa"
  count  = var.enable_p3_provider_role ? 1 : 0

  role_name         = "zero-drift-p3-crossplane-s3"
  oidc_provider_arn = module.cluster.oidc_provider_arn
  oidc_issuer_url   = module.cluster.oidc_issuer_url
  bucket_prefix     = "zero-drift-p3-"
}

# DRF-46 (SPEC-P4 P4-T2.2, D1, ADR-0008): the shared RDS instance and the five
# P4 IRSA roles, created only for an approved P4 window
# (enable_rag_platform = true in the window tfvars) and destroyed with it.
module "shared_rds" {
  source = "./modules/shared-rds"
  count  = var.enable_rag_platform ? 1 : 0

  vpc_id                 = module.network.vpc_id
  db_subnet_group_name   = module.network.db_subnet_group_name
  node_security_group_id = module.cluster.node_security_group_id
}

module "rag_identity" {
  source = "./modules/rag-identity"
  count  = var.enable_rag_platform ? 1 : 0

  oidc_provider_arn = module.cluster.oidc_provider_arn
  oidc_issuer_url   = module.cluster.oidc_issuer_url
  region            = var.region
  master_secret_arn = module.shared_rds[0].master_secret_arn
}
