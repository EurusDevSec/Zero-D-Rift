# P6 batch platform and Karpenter contract tests (DRF-77, SPEC-P6 P6-T3).
# Mock providers only: no AWS call, no credentials. The module statements must
# equal tests/p6_approved_policies.json, the same file plan_assert.sh check 19
# compares a real plan against and tests/batch_iam_offline.sh evaluates the
# allow/deny matrix on.
mock_provider "aws" {
  source = "./tests/mocks"
}
mock_provider "tls" {
  source = "./tests/mocks"
}

variables {
  run_id                       = "P6-TEST-20261125-01"
  expires_at                   = "2026-11-26T12:00:00Z"
  endpoint_public_access_cidrs = ["203.0.113.10/32"] # TEST-NET-3, documentation range
  iss                          = "oidc.eks.us-east-1.amazonaws.com/id/TEST"
}

run "default_has_no_batch_platform" {
  command = apply

  assert {
    condition     = length(module.batch_platform) == 0 && length(module.karpenter) == 0
    error_message = "No P6 resource may exist unless enable_batch_platform = true."
  }

  assert {
    condition     = output.batch_platform == null && output.batch_platform_config == null
    error_message = "P6 outputs must be null when disabled."
  }
}

run "batch_without_rag_platform_is_rejected" {
  command = plan

  variables {
    enable_batch_platform = true
    enable_rag_platform   = false
  }

  expect_failures = [var.enable_batch_platform]
}

run "queues_follow_d8_and_refuse_http" {
  command = apply

  variables {
    enable_rag_platform   = true
    enable_batch_platform = true
  }

  assert {
    condition = module.batch_platform[0].queue_settings == {
      visibility_timeout = 120
      retention          = 3600
      dlq_retention      = 3600
      sse                = true
      max_receive_count  = 3
    }
    error_message = "D8: visibility 120 s, retention 1 h on both queues, SSE-SQS, maxReceiveCount 3."
  }

  assert {
    condition     = output.batch_platform.queues == { main = "zero-drift-batch", dlq = "zero-drift-batch-dlq" }
    error_message = "Queue names: zero-drift-batch and zero-drift-batch-dlq."
  }

  assert {
    condition = alltrue(flatten([
      for k, p in module.batch_platform[0].queue_policies : [
        for s in p.Statement : s.Effect == "Deny" && s.Condition.Bool["aws:SecureTransport"] == "false"
      ]
    ]))
    error_message = "Queue policies only deny plain HTTP; no Allow to any principal (queue not public)."
  }
}

run "policies_equal_the_approved_file" {
  command = apply

  variables {
    enable_rag_platform   = true
    enable_batch_platform = true
  }

  assert {
    condition = jsonencode(merge(module.batch_platform[0].statements, module.karpenter[0].statements)) == jsonencode(
      jsondecode(replace(file("tests/p6_approved_policies.json"), "ACCT", "000000000000")).policies
    )
    error_message = "P6 inline policies differ from tests/p6_approved_policies.json (update both only with a reviewed reason)."
  }
}

run "roles_trust_one_exact_service_account" {
  command = apply

  variables {
    enable_rag_platform   = true
    enable_batch_platform = true
  }

  assert {
    condition = output.batch_platform.subjects == {
      keda     = "system:serviceaccount:keda:keda-operator"
      submit   = "system:serviceaccount:zdr-platform:batch-submit"
      tenant-a = "system:serviceaccount:tenant-a:batch-train"
      tenant-b = "system:serviceaccount:tenant-b:batch-train"
    }
    error_message = "Batch roles trust exactly the four approved ServiceAccounts."
  }

  assert {
    condition = alltrue([
      for k, t in merge(module.batch_platform[0].trust_policies, { karpenter = module.karpenter[0].controller_trust }) :
      length(t.Statement) == 1 &&
      t.Statement[0].Action == "sts:AssumeRoleWithWebIdentity" &&
      t.Statement[0].Principal.Federated == "arn:aws:iam::000000000000:oidc-provider/${var.iss}" &&
      t.Statement[0].Condition.StringEquals["${var.iss}:aud"] == "sts.amazonaws.com" &&
      keys(t.Statement[0].Condition) == ["StringEquals"]
    ])
    error_message = "Every P6 IRSA role: one web identity statement, audience sts.amazonaws.com, exact subject (StringEquals only)."
  }

  assert {
    condition     = module.karpenter[0].controller_trust.Statement[0].Condition.StringEquals["${var.iss}:sub"] == "system:serviceaccount:karpenter:karpenter"
    error_message = "The Karpenter controller role trusts only karpenter/karpenter."
  }
}

run "karpenter_has_no_iam_write" {
  command = apply

  variables {
    enable_rag_platform   = true
    enable_batch_platform = true
  }

  assert {
    condition = toset(flatten([
      for s in module.karpenter[0].statements.karpenter-controller : [for a in s.Action : a if startswith(a, "iam:")]
    ])) == toset(["iam:GetInstanceProfile", "iam:ListInstanceProfiles", "iam:PassRole"])
    error_message = "D6: the only IAM actions are PassRole, GetInstanceProfile and ListInstanceProfiles."
  }

  assert {
    condition = alltrue([
      for s in module.karpenter[0].statements.karpenter-controller :
      alltrue([for r in s.Resource : r != "*"]) if anytrue([for a in s.Action : startswith(a, "iam:")])
    ])
    error_message = "No IAM action on resource *."
  }

  assert {
    condition = one([
      for s in module.karpenter[0].statements.karpenter-controller : s.Resource if contains(s.Action, "iam:PassRole")
    ]) == ["arn:aws:iam::000000000000:role/zero-drift-karpenter-node"]
    error_message = "iam:PassRole only for the one node role."
  }

  assert {
    condition = (
      module.karpenter[0].node_policies == ["AmazonEC2ContainerRegistryPullOnly", "AmazonEKSWorkerNodePolicy", "AmazonEKS_CNI_Policy"] &&
      module.karpenter[0].access_entry_type == "EC2_LINUX" &&
      output.batch_platform.karpenter.instance_profile == "zero-drift-karpenter-node"
    )
    error_message = "Node role: three EKS worker policies (no SSM), EC2_LINUX access entry, pre-created instance profile."
  }

  assert {
    condition = toset([for k, r in module.karpenter[0].rules : r.detail_type]) == toset([
      "AWS Health Event", "EC2 Spot Instance Interruption Warning",
      "EC2 Instance Rebalance Recommendation", "EC2 Instance State-change Notification",
    ])
    error_message = "Four interruption rules."
  }
}

run "tenant_and_submit_boundaries" {
  command = apply

  variables {
    enable_rag_platform   = true
    enable_batch_platform = true
  }

  assert {
    condition = alltrue([
      for pair in [["tenant-a", "tenant-b"], ["tenant-b", "tenant-a"]] :
      alltrue([for s in module.batch_platform[0].statements["batch-${pair[0]}"] :
      alltrue([for r in s.Resource : !strcontains(r, pair[1])])])
    ])
    error_message = "A tenant role names no resource of the other tenant."
  }

  assert {
    condition = (
      !contains(flatten([for s in module.batch_platform[0].statements.batch-submit : s.Action]), "s3:GetObject") &&
      alltrue([for s in module.batch_platform[0].statements.batch-submit :
      lookup(s, "Condition", null) != null if contains(s.Action, "s3:ListBucket")])
    )
    error_message = "Submit role: no s3:GetObject; s3:ListBucket only with the s3:prefix condition."
  }

  assert {
    condition = alltrue(flatten([
      for k, ss in module.batch_platform[0].statements : [
        for s in ss : alltrue([for a in s.Action : !strcontains(a, "*") && !startswith(a, "iam:") && !startswith(a, "sts:")])
      ]
    ]))
    error_message = "Batch roles: exact actions, no IAM or STS action."
  }

  assert {
    condition = contains(flatten([
      for s in module.rag_identity[0].statements["crossplane-s3"] : s.Resource
    ]), "arn:aws:s3:::zero-drift-batch-*")
    error_message = "The Crossplane S3 role must manage zero-drift-batch- buckets in a batch window (A7)."
  }
}

run "crossplane_prefix_only_in_batch_window" {
  command = apply

  variables {
    enable_rag_platform = true
  }

  assert {
    condition = !anytrue([
      for r in flatten([for s in module.rag_identity[0].statements["crossplane-s3"] : s.Resource]) : strcontains(r, "zero-drift-batch-")
    ])
    error_message = "Without the batch platform the Crossplane role keeps the P4 scope."
  }
}
