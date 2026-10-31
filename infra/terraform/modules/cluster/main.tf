# P2 EKS bootstrap (SPEC-P2 Task 5, ADR-0003, ADR-0007): EKS 1.35 on standard
# support, one AL2023 system node group, OIDC for later IRSA, access entries only
# (no aws-auth ConfigMap, no creator admin), pinned add-ons and AMI release.

data "aws_caller_identity" "current" {}

locals {
  # Stable role ARN, never an STS session ARN (ADR-0007).
  bootstrap_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.bootstrap_role_name}"

  # The admin association exists only while var.bootstrap_cluster_admin is true,
  # so an apply after the window with the default removes it (DRF-5 AC-04 plan).
  bootstrap_admin_policy = var.bootstrap_cluster_admin ? {
    admin = {
      policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
      access_scope = { type = "cluster" }
    }
  } : {}
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.26.0"

  name               = var.name
  kubernetes_version = var.kubernetes_version
  # Standard support only: extended support costs 0.60 instead of 0.10 USD/hour.
  upgrade_policy = { support_type = "STANDARD" }

  vpc_id                   = var.vpc_id
  subnet_ids               = var.subnet_ids
  control_plane_subnet_ids = var.subnet_ids

  # Private access always on; public access only from the owner's workstation CIDRs.
  endpoint_private_access      = true
  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = false
  access_entries = {
    bootstrap = {
      principal_arn       = local.bootstrap_role_arn
      type                = "STANDARD"
      policy_associations = local.bootstrap_admin_policy
    }
  }

  enable_irsa = true

  # Kubernetes secrets use EKS default envelope encryption with an AWS-owned key;
  # no customer KMS key (1 USD/month each, plus a 7-day deletion wait).
  create_kms_key    = false
  encryption_config = null

  # Control plane logs: audit and authenticator only, kept 3 days (cost guard).
  enabled_log_types                      = ["audit", "authenticator"]
  cloudwatch_log_group_retention_in_days = 3

  addons = {
    vpc-cni = {
      addon_version  = var.addon_versions["vpc-cni"]
      most_recent    = false
      before_compute = true
    }
    kube-proxy = {
      addon_version = var.addon_versions["kube-proxy"]
      most_recent   = false
    }
    coredns = {
      addon_version = var.addon_versions["coredns"]
      most_recent   = false
    }
  }

  eks_managed_node_groups = {
    system = {
      ami_type                       = var.node_ami_type
      ami_release_version            = var.node_ami_release_version
      use_latest_ami_release_version = false
      instance_types                 = [var.node_instance_type]
      capacity_type                  = "ON_DEMAND"

      min_size     = 1
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      labels = { role = "system" }

      # IMDSv2 only, hop limit 1: Pods cannot reach the node's instance metadata.
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
      }
    }
  }
}
