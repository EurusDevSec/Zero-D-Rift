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
