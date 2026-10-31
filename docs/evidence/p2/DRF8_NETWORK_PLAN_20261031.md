# DRF-8 — P2 network: VPC, S3 gateway endpoint, no NAT — 2026-10-31

Issue: DRF-8 (Linear). Source: SPEC-P2 Task 4, ADR-0006.
Procedure: `docs/runbooks/P2_NETWORK.md`.
Candidate: branch `hoang/drf-8-network` from `main` at `50d972f`.
Environment: owner's Windows machine, Terraform 1.16.4, AWS provider 6.67.0, VPC module 6.7.3.
Timezone: UTC in the table below; local time is UTC+7.
Redaction: account ID is written `<ACCOUNT>`.
Authority: speed mode, under which Claude implemented and ran plan only. **No apply**, and no AWS resource was created.

## Changes

| File | Change |
|---|---|
| `infra/terraform/modules/network/{main,variables,outputs}.tf` | New module. It wraps VPC 6.7.3 and vpc-endpoints 6.7.3 and builds the bounded S3 endpoint policy |
| `infra/terraform/main.tf`, `outputs.tf` | Call `module "network"`; add safe outputs (VPC ID, public subnet IDs, DB subnet group, NAT count) |
| `infra/terraform/tests/network.tftest.hcl` | New: 2 runs (contract, using apply on a mock provider; and the CIDR count guard) |
| `infra/terraform/scripts/plan_assert.sh` | New: 15 checks on a saved plan |
| `infra/terraform/scripts/check.sh` | Module pin check now skips `.terraform/`, because the downloaded module examples use `~>` pins |
| `infra/terraform/README.md` | Layout table updated |

## Static gate

| Time (UTC) | Command | Result |
|---|---|---|
| ~14:14 | `terraform validate` | Success |
| ~14:14 | `terraform test` | 9 passed, 0 failed (7 guardrails + 2 network) |
| ~14:14 | `./scripts/check.sh` | 8/8 PASS |

Fixed during development:
- The test mock returned random text for `aws_iam_policy_document`. The policy is now built with `jsonencode`.
- The module makes 2 DB route tables (one per AZ), not 1. The test now expects 2.
- `check.sh` had read pins from the downloaded module examples. It now skips `.terraform/`.

## Plan (read-only against AWS, S3 backend)

| Time (UTC) | Command | Result |
|---|---|---|
| 14:15 | `terraform plan -var-file=run.tfvars -out=tfplan` (`run_id = P2-PLAN-20261031-01`, profile `zdr-tf`) | `Plan: 19 to add, 0 to change, 0 to destroy.` exit 0 |
| 14:16 | `./scripts/plan_assert.sh tfplan` | 15/15 PASS |

The 19 planned resources:

| Type | Count |
|---|---|
| `aws_vpc` | 1 |
| `aws_subnet` | 4 |
| `aws_internet_gateway` | 1 |
| `aws_route_table` | 3 (1 public, 2 db) |
| `aws_route_table_association` | 4 |
| `aws_route` | 1 (`public_internet_gateway`) |
| `aws_vpc_endpoint` | 1 (`s3`) |
| `aws_db_subnet_group` | 1 |
| `aws_default_security_group` | 1 |
| `aws_default_network_acl` | 1 |
| `aws_default_route_table` | 1 |

The plan file was deleted after the check. The plan JSON was never written into the repository.

Negative test of `plan_assert.sh`. A copy of the plan JSON was made in the scratchpad, then deleted afterwards. Four faults were injected into it:
- an `aws_nat_gateway`;
- an ingress rule from `0.0.0.0/0` on port 22;
- a DB route `0.0.0.0/0`;
- an `aws_db_instance` with a delete action and no tags.

Result: `RESULT: FAIL`, exit 1. FAIL lines were reported for:
- actions;
- the NAT gateway;
- the DB instance;
- the resource counts;
- the routes;
- open ingress;
- the missing tags.

## AC results

**AC-01: PASS (static and plan).**
- 2 AZs are enforced by root validation.
- The CIDRs are `10.0.0.0/24` and `10.0.1.0/24` (public) and `10.0.10.0/24` and `10.0.11.0/24` (db).
- The module rejects a CIDR count that does not match the AZ count (test).
- The 6 mandatory tags are on every taggable resource.
- Subnets also carry `Tier`; public subnets carry `kubernetes.io/role/elb=1`.

**AC-02: PASS (plan).**
- No NAT, EIP, RDS, EC2 or interface endpoint.
- The default SG has 0 rules.
- There is no ingress from `0.0.0.0/0` and no port 22.
- NAT is also blocked by the `enable_nat_gateway` validation.

**AC-03: PASS (review of plan).**
- The S3 endpoint is a Gateway endpoint (`com.amazonaws.us-east-1.s3`) on the public route table.
- The endpoint policy (redacted) has two statements:
  - `OwnAccountBuckets`: `s3:*` where `aws:ResourceAccount = <ACCOUNT>`;
  - `AwsOwnedReadOnly`: `s3:GetObject` on `prod-us-east-1-starport-layer-bucket/*` and `al2023-repos-us-east-1-de612dc2/*`.
- The DB subnets have their own 2 route tables with no route out, and a DB subnet group, so the topology is ready for a later private RDS.

**AC-04: PASS (estimate), runtime Pending.**
- All 19 resources are 0 USD/hour.
- Data out through the IGW is billed per GB, with the first 100 GB/month free.
- Public IPv4 cost arrives with nodes in DRF-9 (0.005 USD/hour each).
- Prices are list prices from the AWS VPC pricing page and were not refetched today.
- Network runtime stays Pending until L3 (DRF-11).

## Deviations and limits

- One `terraform init` ran without `AWS_PROFILE` set. It used the `default` IAM-user key to read the backend; it read only and wrote nothing. The runbook now says to export the profile before init.
- Not verified until L3:
  - ECR layer pulls through the endpoint;
  - the AL2023 repo bucket name, which is taken from AWS docs;
  - whether denying other accounts' S3 through the endpoint blocks a later need.
- `apply` was not run (out of scope for DRF-8).

## Status

`CANDIDATE_FOR_OWNER_ACCEPTANCE`.
- The owner's explain-back is pending; the owner will re-run the runbook later.
- No independent reviewer yet.
