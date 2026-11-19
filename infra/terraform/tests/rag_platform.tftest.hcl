# P4 shared RDS and IRSA contract tests (DRF-46). Mock providers only: no AWS
# call, no credentials. The IAM matrix below evaluates the planned policies with
# IAM glob rules (* and ? match any character, "/" included; actions ignore
# case). It is an offline approximation: scripts/rag_iam_check.sh runs the same
# matrix through AWS IAM simulation in the window.
mock_provider "aws" {
  source = "./tests/mocks"
}
mock_provider "tls" {
  source = "./tests/mocks"
}

variables {
  run_id                       = "P4-TEST-20261119-01"
  expires_at                   = "2026-11-20T12:00:00Z"
  endpoint_public_access_cidrs = ["203.0.113.10/32"] # TEST-NET-3, documentation range
  iam_cases                    = jsondecode(file("tests/rag_iam_matrix.json")).cases
  mock_master_arn              = "arn:aws:secretsmanager:us-east-1:000000000000:secret:rds!db-TEST-AbCdEf"
}

run "default_has_no_rag_platform" {
  command = apply

  assert {
    condition     = length(module.shared_rds) == 0 && length(module.rag_identity) == 0
    error_message = "No P4 resource may exist unless enable_rag_platform = true."
  }

  assert {
    condition     = output.rag_platform == null && output.rag_platform_config == null
    error_message = "P4 outputs must be null when disabled."
  }
}

run "rds_is_private_encrypted_and_destroyable" {
  command = apply

  variables {
    enable_rag_platform = true
  }

  assert {
    condition = (
      module.shared_rds[0].settings.engine == "postgres" &&
      module.shared_rds[0].settings.engine_version == "17.11" &&
      module.shared_rds[0].settings.instance_class == "db.t4g.micro" &&
      module.shared_rds[0].settings.allocated_storage == 20 &&
      module.shared_rds[0].settings.max_allocated_storage == 0 &&
      module.shared_rds[0].settings.storage_type == "gp3" &&
      !module.shared_rds[0].settings.multi_az
    )
    error_message = "Instance shape must match D2: postgres 17.11, db.t4g.micro, 20 GiB gp3, no autoscaling, Single-AZ."
  }

  assert {
    condition = (
      !module.shared_rds[0].settings.publicly_accessible &&
      module.shared_rds[0].settings.storage_encrypted &&
      module.shared_rds[0].settings.manage_master_password
    )
    error_message = "Instance must be private, encrypted, with an RDS-managed master password."
  }

  assert {
    condition = (
      module.shared_rds[0].settings.backup_retention_period == 0 &&
      module.shared_rds[0].settings.skip_final_snapshot &&
      !module.shared_rds[0].settings.deletion_protection &&
      !module.shared_rds[0].settings.auto_minor_version_upgrade
    )
    error_message = "Instance must be destroyable in the window (no backup, no final snapshot, no deletion protection) and keep its minor pin."
  }

  assert {
    condition     = module.shared_rds[0].settings.db_subnet_group_name == output.db_subnet_group_name
    error_message = "Instance must use the existing P2 DB subnet group."
  }

  assert {
    condition = (
      module.shared_rds[0].ingress.protocol == "tcp" &&
      module.shared_rds[0].ingress.from_port == 5432 &&
      module.shared_rds[0].ingress.to_port == 5432 &&
      module.shared_rds[0].ingress.cidr_ipv4 == null &&
      module.shared_rds[0].ingress.source_sg != null &&
      module.shared_rds[0].ingress.target_group == module.shared_rds[0].security_group_id &&
      module.shared_rds[0].settings.security_group_ids == toset([module.shared_rds[0].security_group_id])
    )
    error_message = "Exactly one way in: 5432/tcp from the node security group, no CIDR."
  }

  assert {
    condition = (
      output.rag_platform.db_identifier == "zero-drift-rag" &&
      output.rag_platform_config.master_secret_arn == var.mock_master_arn
    )
    error_message = "Outputs must name the instance and pass the RDS-managed secret on."
  }
}

run "five_roles_with_exact_trust" {
  command = apply

  variables {
    enable_rag_platform = true
  }

  assert {
    condition = output.rag_platform.roles == {
      db-admin      = "zero-drift-rag-db-admin"
      bootstrap     = "zero-drift-rag-bootstrap"
      crossplane-s3 = "zero-drift-rag-crossplane-s3"
      tenant-a      = "zero-drift-rag-tenant-a"
      tenant-b      = "zero-drift-rag-tenant-b"
    }
    error_message = "Exactly the five approved roles."
  }

  assert {
    condition = alltrue([
      for k, t in module.rag_identity[0].trust_policies :
      length(t.Statement) == 1 &&
      t.Statement[0].Action == "sts:AssumeRoleWithWebIdentity" &&
      t.Statement[0].Principal.Federated == "arn:aws:iam::000000000000:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/TEST" &&
      t.Statement[0].Condition.StringEquals["oidc.eks.us-east-1.amazonaws.com/id/TEST:aud"] == "sts.amazonaws.com"
    ])
    error_message = "Every role: one web identity statement from the cluster issuer, audience sts.amazonaws.com."
  }

  assert {
    condition = alltrue([
      for k, sub in {
        db-admin      = "system:serviceaccount:zdr-platform:rag-db-admin"
        bootstrap     = "system:serviceaccount:zdr-platform:rag-bootstrap"
        crossplane-s3 = "system:serviceaccount:crossplane-system:provider-aws-s3"
      } :
      module.rag_identity[0].trust_policies[k].Statement[0].Condition.StringEquals["oidc.eks.us-east-1.amazonaws.com/id/TEST:sub"] == sub &&
      !contains(keys(module.rag_identity[0].trust_policies[k].Statement[0].Condition), "StringLike")
    ])
    error_message = "Platform and Crossplane roles trust one exact ServiceAccount (StringEquals, no pattern)."
  }

  assert {
    condition = alltrue([
      for t in ["tenant-a", "tenant-b"] :
      module.rag_identity[0].trust_policies[t].Statement[0].Condition.StringLike["oidc.eks.us-east-1.amazonaws.com/id/TEST:sub"] == "system:serviceaccount:${t}:rag-*" &&
      !contains(keys(module.rag_identity[0].trust_policies[t].Statement[0].Condition.StringEquals), "oidc.eks.us-east-1.amazonaws.com/id/TEST:sub")
    ])
    error_message = "Tenant roles trust only rag-* ServiceAccounts in their own namespace (D6)."
  }
}

run "policies_are_exact_allowlists" {
  command = apply

  variables {
    enable_rag_platform = true
  }

  assert {
    condition = module.rag_identity[0].policy_names == {
      rag-db-admin        = "db-admin"
      rag-db-admin-master = "db-admin"
      rag-bootstrap       = "bootstrap"
      rag-crossplane-s3   = "crossplane-s3"
      rag-tenant-a        = "tenant-a"
      rag-tenant-b        = "tenant-b"
    }
    error_message = "Exactly six inline policies on the five roles."
  }

  assert {
    condition = alltrue(flatten([
      for k, ss in module.rag_identity[0].statements : [
        for s in ss : s.Effect == "Allow" && alltrue([for r in s.Resource : r != "*"]) &&
        alltrue([for a in s.Action : a != "*" && !startswith(a, "iam:") && !startswith(a, "sts:") && !endswith(a, ":*")])
      ]
    ]))
    error_message = "No Deny-free wildcard: no resource *, no action *, no service:*, no IAM or STS action."
  }

  assert {
    condition = alltrue([
      for pair in [["tenant-a", "tenant-b"], ["tenant-b", "tenant-a"]] :
      alltrue([for s in module.rag_identity[0].statements[pair[0]] :
      alltrue([for r in s.Resource : strcontains(r, pair[0]) && !strcontains(r, pair[1])])])
    ])
    error_message = "A tenant role may only name its own tenant's resources."
  }

  assert {
    condition = alltrue(flatten([
      for k, ss in module.rag_identity[0].statements : [
        for s in ss : alltrue([for a in s.Action : contains([
          "secretsmanager:CreateSecret", "secretsmanager:DeleteSecret", "secretsmanager:GetSecretValue", "secretsmanager:TagResource",
          "s3:CreateBucket", "s3:DeleteBucket", "s3:GetAccelerateConfiguration", "s3:GetBucket*", "s3:GetEncryptionConfiguration",
          "s3:GetLifecycleConfiguration", "s3:GetReplicationConfiguration", "s3:ListBucket", "s3:ListBucketVersions",
          "s3:PutBucketTagging", "s3:DeleteObject", "s3:DeleteObjectVersion", "s3:GetObject",
        ], a)])
      ]
    ]))
    # Same union as plan_assert.sh check 16; per-statement sets are checked there.
    error_message = "An action outside the approved P4 list."
  }
}

run "iam_matrix" {
  command = apply

  variables {
    enable_rag_platform = true
  }

  assert {
    condition = length([
      for c in var.iam_cases : c
      if(anytrue([
        for s in module.rag_identity[0].statements[c.role] :
        s.Effect == "Allow" &&
        anytrue([for a in s.Action : can(regex("(?i)^${replace(replace(replace(a, ".", "\\."), "?", "."), "*", ".*")}$", c.action))]) &&
        anytrue([for r in s.Resource : can(regex("^${replace(replace(replace(r, ".", "\\."), "?", "."), "*", ".*")}$",
        replace(replace(c.resource, "ACCT", "000000000000"), "MASTER", var.mock_master_arn)))])
      ]) ? "allowed" : "implicitDeny") != c.expect
    ]) == 0
    error_message = "IAM matrix: a case got the wrong decision. Run: terraform test -filter=tests/rag_platform.tftest.hcl -verbose"
  }

  assert {
    condition     = length(var.iam_cases) >= 50 && length(distinct([for c in var.iam_cases : c.role])) == 5
    error_message = "The matrix must cover all five roles."
  }
}

run "tenant_name_that_prefixes_another_is_rejected" {
  command = plan

  module {
    source = "./modules/rag-identity"
  }

  variables {
    oidc_provider_arn = "arn:aws:iam::000000000000:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/TEST"
    oidc_issuer_url   = "https://oidc.eks.us-east-1.amazonaws.com/id/TEST"
    region            = "us-east-1"
    master_secret_arn = "arn:aws:secretsmanager:us-east-1:000000000000:secret:rds!db-TEST-AbCdEf"
    tenants           = ["tenant-a", "tenant-ab"]
  }

  expect_failures = [var.tenants]
}

run "larger_instance_class_is_rejected" {
  command = plan

  module {
    source = "./modules/shared-rds"
  }

  variables {
    vpc_id                 = "vpc-00000000000000000"
    db_subnet_group_name   = "zero-drift-db"
    node_security_group_id = "sg-00000000000000000"
    instance_class         = "db.t4g.small"
  }

  expect_failures = [var.instance_class]
}
