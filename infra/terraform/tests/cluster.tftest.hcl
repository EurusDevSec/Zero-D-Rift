# EKS contract tests (DRF-9). Mock providers only: no AWS call, no credentials.
mock_provider "aws" {
  source = "./tests/mocks"
}
mock_provider "tls" {
  source = "./tests/mocks"
}

variables {
  run_id                       = "P2-TEST-20261031-01"
  expires_at                   = "2026-11-02T12:00:00Z"
  endpoint_public_access_cidrs = ["203.0.113.10/32"] # TEST-NET-3, documentation range
}

run "default_has_entry_but_no_admin" {
  command = apply

  assert {
    condition     = output.access_entry_keys == ["bootstrap"]
    error_message = "Expected exactly one Terraform-managed access entry: bootstrap."
  }

  assert {
    condition     = output.bootstrap_admin_associations == 0
    error_message = "The default must not grant cluster admin (ADR-0007: admin only in a window)."
  }
}

run "window_grants_admin" {
  command = apply

  variables {
    bootstrap_cluster_admin = true
  }

  assert {
    condition     = output.bootstrap_admin_associations == 1
    error_message = "bootstrap_cluster_admin = true must add one admin association."
  }
}

run "open_endpoint_is_rejected" {
  command = plan
  variables {
    endpoint_public_access_cidrs = ["0.0.0.0/0"]
  }
  expect_failures = [var.endpoint_public_access_cidrs]
}

run "floating_ami_is_rejected" {
  command = plan
  variables {
    system_node_ami_release_version = "latest"
  }
  expect_failures = [var.system_node_ami_release_version]
}

run "too_many_nodes_are_rejected" {
  command = plan
  variables {
    system_node_desired_size = 3
  }
  expect_failures = [var.system_node_desired_size]
}

run "unpriced_instance_type_is_rejected" {
  command = plan
  variables {
    system_node_instance_type = "g4dn.xlarge"
  }
  expect_failures = [var.system_node_instance_type]
}

run "floating_addon_is_rejected" {
  command = plan
  variables {
    addon_versions = {
      vpc-cni    = "latest"
      kube-proxy = "v1.35.3-eksbuild.62"
      coredns    = "v1.13.2-eksbuild.62"
    }
  }
  expect_failures = [var.addon_versions]
}
