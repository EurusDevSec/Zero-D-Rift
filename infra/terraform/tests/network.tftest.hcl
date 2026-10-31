# Network contract tests (DRF-8). mock_provider: no AWS call, no credentials.
# command = apply runs against the mock only, so computed IDs are known and the
# counts below are checked on real values. Run: terraform test
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

run "network_matches_contract" {
  command = apply

  assert {
    condition     = output.nat_gateway_count == 0
    error_message = "A NAT Gateway was planned; ADR-0006 forbids it by default."
  }

  assert {
    condition     = length(output.public_subnet_ids) == 2 && length(module.network.db_subnet_ids) == 2
    error_message = "Expected exactly 2 public and 2 DB subnets (one each per AZ)."
  }

  assert {
    # The VPC module makes one DB route table per AZ when there is no NAT or IGW route.
    condition     = length(module.network.public_route_table_ids) == 1 && length(module.network.db_route_table_ids) == 2
    error_message = "Expected 1 public route table and 2 separate DB route tables."
  }

  assert {
    condition     = module.network.s3_endpoint_type == "Gateway"
    error_message = "The S3 endpoint must be a Gateway endpoint (no hourly charge)."
  }

  assert {
    condition     = output.db_subnet_group_name != null && output.db_subnet_group_name != ""
    error_message = "The DB subnet group for a later private RDS is missing."
  }
}

run "subnet_cidr_count_must_match_azs" {
  command = plan

  module {
    source = "./modules/network"
  }

  variables {
    name                = "test"
    region              = "us-east-1"
    vpc_cidr            = "10.0.0.0/16"
    azs                 = ["us-east-1a", "us-east-1b"]
    public_subnet_cidrs = ["10.0.0.0/24"]
    db_subnet_cidrs     = ["10.0.10.0/24", "10.0.11.0/24"]
  }

  expect_failures = [var.public_subnet_cidrs]
}
