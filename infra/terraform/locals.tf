locals {
  # Mandatory tags (docs/finops/COST_PLAN.md §10), applied through provider default_tags.
  common_tags = {
    Project     = "Zero-D-Rift"
    Owner       = "HoangLV"
    Environment = "PoC"
    ManagedBy   = "Terraform"
    RunId       = var.run_id
    ExpiresAt   = var.expires_at
  }

  # One public and one DB /24 per AZ, same layout as the TF-T01 lab.
  public_subnet_cidrs = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 8, i)]
  db_subnet_cidrs     = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 8, i + 10)]
}
