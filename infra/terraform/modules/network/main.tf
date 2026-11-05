# P2 network (SPEC-P2 Task 4, ADR-0006): one VPC, public worker subnets with an
# Internet Gateway, private DB subnets with no Internet route, no NAT Gateway, and an
# S3 gateway endpoint on the public route table. The default security group is
# adopted with no rules, so nothing that lands in it accepts or sends traffic.

data "aws_caller_identity" "current" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"

  name = var.name
  cidr = var.vpc_cidr
  azs  = var.azs

  # Worker nodes get a public IPv4 for outbound through the IGW (ADR-0006 §2);
  # inbound is closed by security groups, not by the subnet.
  public_subnets          = var.public_subnet_cidrs
  map_public_ip_on_launch = true
  public_subnet_tags = {
    Tier                     = "public"
    "kubernetes.io/role/elb" = "1"
  }

  # DB subnets: own route table, no IGW and no NAT route, plus a DB subnet group
  # ready for a later private RDS (ADR-0006 §4). No RDS is created here.
  database_subnets                       = var.db_subnet_cidrs
  create_database_subnet_route_table     = true
  create_database_subnet_group           = true
  create_database_internet_gateway_route = false
  create_database_nat_gateway_route      = false
  database_subnet_tags = {
    Tier = "db"
  }

  enable_nat_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true
  enable_flow_log      = false

  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []
}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "6.7.3"

  vpc_id = module.vpc.vpc_id
  # Setting region skips the module's endpoint-service lookup; the service name is explicit.
  region = var.region

  endpoints = {
    s3 = {
      service_endpoint = "com.amazonaws.${var.region}.s3"
      service_type     = "Gateway"
      route_table_ids  = module.vpc.public_route_table_ids
      policy           = local.s3_endpoint_policy
      tags             = { Name = "${var.name}-s3-gateway" }
    }
  }
}

# Bounded endpoint policy: traffic through the endpoint may reach only buckets in
# this account, plus read-only access to the buckets that nodes need for image
# layers and packages. The endpoint route wins for all S3 traffic in this Region
# from the public subnets, so other accounts' buckets are denied.
# P3 window 05/11 (DRF-37): quay.io (Argo CD) and registry.k8s.io (kro, pause)
# redirect layer downloads to their own S3 buckets in us-east-1, so those pulls
# failed with 403 through the endpoint. Both buckets are added read-only
# (s3:GetObject): nodes can download layers but cannot write data out.
locals {
  layer_buckets = [
    "prod-${var.region}-starport-layer-bucket", # ECR (AWS)
    "al2023-repos-${var.region}-de612dc2",      # AL2023 packages (AWS)
    "quayio-production-s3",                     # quay.io layers (us-east-1)
    "prod-registry-k8s-io-${var.region}",       # registry.k8s.io layers
  ]

  s3_endpoint_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "OwnAccountBuckets"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:*"
        Resource  = "*"
        Condition = {
          StringEquals = { "aws:ResourceAccount" = data.aws_caller_identity.current.account_id }
        }
      },
      {
        Sid       = "LayerBucketsReadOnly"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = [for b in local.layer_buckets : "arn:aws:s3:::${b}/*"]
      },
    ]
  })
}
