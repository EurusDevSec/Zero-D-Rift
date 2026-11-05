# P3 provider IRSA contract tests (DRF-36). Mock providers only: no AWS call.
mock_provider "aws" {
  source = "./tests/mocks"
}
mock_provider "tls" {
  source = "./tests/mocks"
}

variables {
  run_id                       = "P3-TEST-20261105-01"
  expires_at                   = "2026-11-06T12:00:00Z"
  endpoint_public_access_cidrs = ["203.0.113.10/32"] # TEST-NET-3, documentation range
}

run "default_has_no_p3_role" {
  command = apply

  assert {
    condition     = output.p3_provider_role == null && length(module.p3_provider_irsa) == 0
    error_message = "The P3 role must not exist unless enable_p3_provider_role = true."
  }
}

run "window_role_trusts_one_service_account" {
  command = apply

  variables {
    enable_p3_provider_role = true
  }

  assert {
    condition     = output.p3_provider_role.name == "zero-drift-p3-crossplane-s3"
    error_message = "Unexpected role name."
  }

  assert {
    condition     = output.p3_provider_role.subject == "system:serviceaccount:crossplane-system:provider-aws-s3"
    error_message = "The role must trust only the provider-aws-s3 ServiceAccount."
  }

  assert {
    condition = (
      length(module.p3_provider_irsa[0].trust_policy.Statement) == 1 &&
      module.p3_provider_irsa[0].trust_policy.Statement[0].Action == "sts:AssumeRoleWithWebIdentity" &&
      module.p3_provider_irsa[0].trust_policy.Statement[0].Principal.Federated == "arn:aws:iam::000000000000:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/TEST" &&
      module.p3_provider_irsa[0].trust_policy.Statement[0].Condition.StringEquals["oidc.eks.us-east-1.amazonaws.com/id/TEST:sub"] == "system:serviceaccount:crossplane-system:provider-aws-s3" &&
      module.p3_provider_irsa[0].trust_policy.Statement[0].Condition.StringEquals["oidc.eks.us-east-1.amazonaws.com/id/TEST:aud"] == "sts.amazonaws.com"
    )
    error_message = "Trust policy must be web identity from the cluster issuer with exact sub and aud."
  }

  assert {
    condition = alltrue([
      for s in module.p3_provider_irsa[0].permissions_policy.Statement :
      s.Effect == "Allow" && s.Resource == ["arn:aws:s3:::zero-drift-p3-*"]
    ])
    error_message = "Permissions must apply only to arn:aws:s3:::zero-drift-p3-* (no *, no object ARN)."
  }

  assert {
    condition = alltrue([
      for s in module.p3_provider_irsa[0].permissions_policy.Statement :
      alltrue([for a in s.Action : startswith(a, "s3:") && (!strcontains(a, "*") || a == "s3:GetBucket*")])
    ])
    error_message = "Only S3 actions, never IAM; the only action wildcard is s3:GetBucket* (the resource also matches objects)."
  }
}

run "role_name_outside_prefix_is_rejected" {
  command = plan

  module {
    source = "./modules/p3-provider-irsa"
  }

  variables {
    role_name         = "crossplane-admin"
    oidc_provider_arn = "arn:aws:iam::000000000000:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/TEST"
    oidc_issuer_url   = "https://oidc.eks.us-east-1.amazonaws.com/id/TEST"
    bucket_prefix     = "zero-drift-p3-"
  }

  expect_failures = [var.role_name]
}

run "wildcard_bucket_prefix_is_rejected" {
  command = plan

  module {
    source = "./modules/p3-provider-irsa"
  }

  variables {
    role_name         = "zero-drift-p3-crossplane-s3"
    oidc_provider_arn = "arn:aws:iam::000000000000:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/TEST"
    oidc_issuer_url   = "https://oidc.eks.us-east-1.amazonaws.com/id/TEST"
    bucket_prefix     = "*"
  }

  expect_failures = [var.bucket_prefix]
}
