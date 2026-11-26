# P6 Karpenter prerequisites (SPEC-P6 P6-T3 B, D6, D7). Only AWS-side objects;
# the controller, NodePools and EC2NodeClass are GitOps (P6-T2.2).
#
# - Node role with the three EKS worker policies (AmazonSSMManagedInstanceCore
#   left out), an instance profile created HERE and named in
#   EC2NodeClass.spec.instanceProfile, and an EC2_LINUX access entry
#   (authentication_mode = API, A9).
# - Interruption queue with four EventBridge rules (scheduled change, Spot
#   interruption, rebalance, instance state change). The release's fifth rule,
#   capacity reservation interruption, is left out: P6 uses no reservation.
# - Controller IRSA role (karpenter/karpenter) with the v1.15.3 release policy
#   reduced per D6: no IAM write; iam:PassRole on the node role only;
#   iam:GetInstanceProfile on the one profile and on the legacy generated name
#   <cluster>_<hash>; iam:ListInstanceProfiles on "*" (read-only; IAM has no
#   resource scope for this list call). The EC2NodeClass finalizer lists its own
#   profile path and reads the legacy name before it deletes launch templates
#   (v1.15.3 nodeclass controller), so without these reads teardown blocks
#   (Codex P6 R1). Every instance-profile write stays denied (P6-T1 evidence §6).
# The discovery tag karpenter.sh/discovery goes on the public subnets and the
# node security group through the network and cluster modules (root main.tf).
#
# ARNs are built from names so the policy is known in the first plan.

data "aws_caller_identity" "this" {}

locals {
  issuer_host      = trimprefix(var.oidc_issuer_url, "https://")
  account          = data.aws_caller_identity.this.account_id
  r                = var.region
  c                = var.cluster_name
  node_role_name   = "${var.cluster_name}-karpenter-node"
  node_role_arn    = "arn:aws:iam::${local.account}:role/${local.node_role_name}"
  profile_name     = "${var.cluster_name}-karpenter-node"
  profile_arn      = "arn:aws:iam::${local.account}:instance-profile/${local.profile_name}"
  queue_name       = "${var.cluster_name}-karpenter"
  queue_arn        = "arn:aws:sqs:${local.r}:${local.account}:${local.queue_name}"
  cluster_arn      = "arn:aws:eks:${local.r}:${local.account}:cluster/${local.c}"
  cluster_tag      = "aws:ResourceTag/kubernetes.io/cluster/${local.c}"
  cluster_req_tag  = "aws:RequestTag/kubernetes.io/cluster/${local.c}"
  tagged_resources = [for t in ["fleet", "instance", "launch-template", "network-interface", "spot-instances-request", "volume"] : "arn:aws:ec2:${local.r}:*:${t}/*"]

  node_policies = ["AmazonEC2ContainerRegistryPullOnly", "AmazonEKSWorkerNodePolicy", "AmazonEKS_CNI_Policy"]

  rules = {
    scheduled-change      = { source = "aws.health", detail_type = "AWS Health Event" }
    spot-interruption     = { source = "aws.ec2", detail_type = "EC2 Spot Instance Interruption Warning" }
    rebalance             = { source = "aws.ec2", detail_type = "EC2 Instance Rebalance Recommendation" }
    instance-state-change = { source = "aws.ec2", detail_type = "EC2 Instance State-change Notification" }
  }

  controller_trust = {
    Version = "2012-10-17"
    Statement = [{
      Sid       = "ServiceAccountOnly"
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.issuer_host}:aud" = "sts.amazonaws.com"
          "${local.issuer_host}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account}"
        }
      }
    }]
  }

  # v1.15.3 cloudformation.yaml, statement by statement, minus the three
  # instance-profile write statements (D6). Sids kept for traceability.
  controller_statements = [
    {
      Sid    = "AllowScopedEC2InstanceAccessActions"
      Effect = "Allow"
      Action = ["ec2:CreateFleet", "ec2:RunInstances"]
      Resource = sort([
        "arn:aws:ec2:${local.r}::image/*",
        "arn:aws:ec2:${local.r}::snapshot/*",
        "arn:aws:ec2:${local.r}:*:security-group/*",
        "arn:aws:ec2:${local.r}:*:subnet/*",
        "arn:aws:ec2:${local.r}:*:capacity-reservation/*",
        "arn:aws:ec2:${local.r}:*:placement-group/*",
      ])
    },
    {
      Sid      = "AllowScopedEC2LaunchTemplateAccessActions"
      Effect   = "Allow"
      Action   = ["ec2:CreateFleet", "ec2:RunInstances"]
      Resource = ["arn:aws:ec2:${local.r}:*:launch-template/*"]
      Condition = {
        StringEquals = { (local.cluster_tag) = "owned" }
        StringLike   = { "aws:ResourceTag/karpenter.sh/nodepool" = "*" }
      }
    },
    {
      Sid      = "AllowScopedEC2InstanceActionsWithTags"
      Effect   = "Allow"
      Action   = ["ec2:CreateFleet", "ec2:CreateLaunchTemplate", "ec2:RunInstances"]
      Resource = local.tagged_resources
      Condition = {
        StringEquals = {
          (local.cluster_req_tag)               = "owned"
          "aws:RequestTag/eks:eks-cluster-name" = local.c
        }
        StringLike = { "aws:RequestTag/karpenter.sh/nodepool" = "*" }
      }
    },
    {
      Sid      = "AllowScopedResourceCreationTagging"
      Effect   = "Allow"
      Action   = ["ec2:CreateTags"]
      Resource = local.tagged_resources
      Condition = {
        StringEquals = {
          (local.cluster_req_tag)               = "owned"
          "aws:RequestTag/eks:eks-cluster-name" = local.c
          "ec2:CreateAction"                    = ["CreateFleet", "CreateLaunchTemplate", "RunInstances"]
        }
        StringLike = { "aws:RequestTag/karpenter.sh/nodepool" = "*" }
      }
    },
    {
      Sid      = "AllowScopedResourceTagging"
      Effect   = "Allow"
      Action   = ["ec2:CreateTags"]
      Resource = ["arn:aws:ec2:${local.r}:*:instance/*"]
      Condition = {
        StringEquals                = { (local.cluster_tag) = "owned" }
        StringLike                  = { "aws:ResourceTag/karpenter.sh/nodepool" = "*" }
        StringEqualsIfExists        = { "aws:RequestTag/eks:eks-cluster-name" = local.c }
        "ForAllValues:StringEquals" = { "aws:TagKeys" = ["Name", "eks:eks-cluster-name", "karpenter.sh/nodeclaim"] }
      }
    },
    {
      Sid      = "AllowScopedDeletion"
      Effect   = "Allow"
      Action   = ["ec2:DeleteLaunchTemplate", "ec2:TerminateInstances"]
      Resource = ["arn:aws:ec2:${local.r}:*:instance/*", "arn:aws:ec2:${local.r}:*:launch-template/*"]
      Condition = {
        StringEquals = { (local.cluster_tag) = "owned" }
        StringLike   = { "aws:ResourceTag/karpenter.sh/nodepool" = "*" }
      }
    },
    {
      Sid       = "AllowPassingInstanceRole"
      Effect    = "Allow"
      Action    = ["iam:PassRole"]
      Resource  = [local.node_role_arn]
      Condition = { StringEquals = { "iam:PassedToService" = "ec2.amazonaws.com" } }
    },
    {
      Sid      = "AllowAPIServerEndpointDiscovery"
      Effect   = "Allow"
      Action   = ["eks:DescribeCluster"]
      Resource = [local.cluster_arn]
    },
    {
      Sid      = "AllowInterruptionQueueActions"
      Effect   = "Allow"
      Action   = ["sqs:DeleteMessage", "sqs:GetQueueUrl", "sqs:ReceiveMessage"]
      Resource = [local.queue_arn]
    },
    {
      Sid       = "AllowZonalShiftStatusReadOnly"
      Effect    = "Allow"
      Action    = ["arc-zonal-shift:GetManagedResource"]
      Resource  = ["*"]
      Condition = { StringEquals = { "arc-zonal-shift:ResourceIdentifier" = local.cluster_arn } }
    },
    {
      Sid    = "AllowRegionalReadActions"
      Effect = "Allow"
      Action = [
        "ec2:DescribeCapacityReservations",
        "ec2:DescribeImages",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeInstanceTypeOfferings",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeInstances",
        "ec2:DescribeLaunchTemplates",
        "ec2:DescribePlacementGroups",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSpotPriceHistory",
        "ec2:DescribeSubnets",
      ]
      Resource  = ["*"]
      Condition = { StringEquals = { "aws:RequestedRegion" = local.r } }
    },
    {
      Sid      = "AllowSSMReadActions"
      Effect   = "Allow"
      Action   = ["ssm:GetParameter"]
      Resource = ["arn:aws:ssm:${local.r}::parameter/aws/service/*"]
    },
    {
      Sid      = "AllowPricingReadActions"
      Effect   = "Allow"
      Action   = ["pricing:GetProducts"]
      Resource = ["*"]
    },
    {
      # Upstream "*", kept: ListInstanceProfiles takes no resource scope, and the
      # finalizer calls it with PathPrefix /karpenter/<region>/<cluster>/<uid>/.
      Sid      = "AllowScopedInstanceProfileListAction"
      Effect   = "Allow"
      Action   = ["iam:ListInstanceProfiles"]
      Resource = ["*"]
    },
    {
      # Upstream instance-profile/*; narrowed to the pre-created profile (D6) and
      # the legacy name <cluster>_<hash> the finalizer reads (NotFound is fine).
      Sid      = "AllowInstanceProfileReadActions"
      Effect   = "Allow"
      Action   = ["iam:GetInstanceProfile"]
      Resource = [local.profile_arn, "arn:aws:iam::${local.account}:instance-profile/${local.c}_*"]
    },
  ]
}

# --- Node role and instance profile -------------------------------------------

resource "aws_iam_role" "node" {
  name        = local.node_role_name
  description = "Karpenter batch node role (SPEC-P6 D6); no SSM."
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "EC2Only"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset(local.node_policies)

  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/${each.value}"
}

resource "aws_iam_instance_profile" "node" {
  name = local.profile_name
  role = aws_iam_role.node.name
}

resource "aws_eks_access_entry" "node" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.node.arn
  type          = "EC2_LINUX"
}

# --- Interruption queue and rules ---------------------------------------------

resource "aws_sqs_queue" "interruption" {
  name                      = local.queue_name
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue_policy" "interruption" {
  queue_url = aws_sqs_queue.interruption.id
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "EC2InterruptionPolicy"
    Statement = [
      {
        Sid       = "AllowEventBridge"
        Effect    = "Allow"
        Principal = { Service = ["events.amazonaws.com", "sqs.amazonaws.com"] }
        Action    = "sqs:SendMessage"
        Resource  = local.queue_arn
      },
      {
        Sid       = "DenyHTTP"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sqs:*"
        Resource  = local.queue_arn
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  })
}

resource "aws_cloudwatch_event_rule" "interruption" {
  for_each = local.rules

  name        = "${var.cluster_name}-karpenter-${each.key}"
  description = "Karpenter interruption: ${each.value.detail_type}"
  event_pattern = jsonencode({
    source        = [each.value.source]
    "detail-type" = [each.value.detail_type]
  })
}

resource "aws_cloudwatch_event_target" "interruption" {
  for_each = local.rules

  rule      = aws_cloudwatch_event_rule.interruption[each.key].name
  target_id = "KarpenterInterruptionQueueTarget"
  # Built from the name like every ARN here; the queue policy must exist first.
  arn        = local.queue_arn
  depends_on = [aws_sqs_queue.interruption, aws_sqs_queue_policy.interruption]
}

# --- Controller identity --------------------------------------------------------

resource "aws_iam_role" "controller" {
  name                 = "${var.cluster_name}-karpenter-controller"
  description          = "Karpenter controller IRSA role for ${var.namespace}/${var.service_account} (SPEC-P6 D6)."
  assume_role_policy   = jsonencode(local.controller_trust)
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "controller" {
  name = "karpenter-controller"
  # name, not id: known in the plan, so plan_assert can check the attachment.
  role = aws_iam_role.controller.name
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.controller_statements
  })
}
