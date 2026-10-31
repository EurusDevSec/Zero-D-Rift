# Guardrail contract tests. mock_provider means no AWS call and no credentials.
# Run: terraform test
mock_provider "aws" {}

variables {
  run_id     = "P2-TEST-20261031-01"
  expires_at = "2026-11-02T12:00:00Z"
}

run "defaults_are_valid_and_tagged" {
  command = plan

  assert {
    condition     = output.common_tags.Project == "Zero-D-Rift" && output.common_tags.ManagedBy == "Terraform"
    error_message = "Mandatory tags are missing."
  }

  assert {
    condition     = output.subnet_plan["us-east-1a"].public == "10.0.0.0/24" && output.subnet_plan["us-east-1b"].db == "10.0.11.0/24"
    error_message = "Subnet CIDR layout changed."
  }
}

run "nat_gateway_is_rejected" {
  command = plan
  variables {
    enable_nat_gateway = true
  }
  expect_failures = [var.enable_nat_gateway]
}

run "other_region_is_rejected" {
  command = plan
  variables {
    region = "ap-southeast-1"
  }
  expect_failures = [var.region]
}

run "single_az_is_rejected" {
  command = plan
  variables {
    azs = ["us-east-1a"]
  }
  expect_failures = [var.azs]
}

run "unapproved_eks_version_is_rejected" {
  command = plan
  variables {
    kubernetes_version = "1.36"
  }
  expect_failures = [var.kubernetes_version]
}

run "non_al2023_nodes_are_rejected" {
  command = plan
  variables {
    system_node_ami_type = "AL2_x86_64"
  }
  expect_failures = [var.system_node_ami_type]
}

run "bad_expiry_is_rejected" {
  command = plan
  variables {
    expires_at = "2026-11-02 12:00"
  }
  expect_failures = [var.expires_at]
}
