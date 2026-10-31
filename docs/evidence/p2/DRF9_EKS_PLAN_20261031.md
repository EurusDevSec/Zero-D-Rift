# DRF-9 — P2 EKS: 1.35, AL2023, OIDC, explicit access entries — 2026-10-31

Issue: DRF-9 (Linear). Source: SPEC-P2 Task 5, ADR-0003, ADR-0007.
Procedure: `docs/runbooks/P2_EKS.md`.
Candidate: branch `hoang/drf-9-eks` from `main` at `69c7dec`.
Environment:
- Terraform 1.16.4, AWS provider 6.67.0;
- EKS module 21.26.0, VPC module 6.7.3;
- profile `zdr-tf`.

Times below are UTC; local time is UTC+7.
Redaction:
- the account ID is written `<ACCOUNT>`;
- the workstation IP is written `<MY_IP>` and is kept only in the gitignored `run.tfvars`.

Authority: speed mode. Claude implemented the module and ran read-only AWS calls and `plan`. **No apply**, and no AWS resource was created.

## Version facts read from AWS (read-only, 31/10 ~14:22 UTC)

| Item | Command | Value |
|---|---|---|
| EKS 1.35 status | `aws eks describe-cluster-versions --cluster-versions 1.35` | `STANDARD_SUPPORT`, standard support ends 2027-03-27 |
| AL2023 AMI release | SSM `/aws/service/eks/optimized-ami/1.35/amazon-linux-2023/x86_64/standard/recommended/release_version` | `1.35.9-20261026` |
| vpc-cni | `describe-addon-versions --kubernetes-version 1.35`, default version | `v1.22.4-eksbuild.10` (latest: v1.23.2-eksbuild.8) |
| kube-proxy | same | `v1.35.3-eksbuild.62` (also the latest) |
| coredns | same | `v1.13.2-eksbuild.62` (latest: v1.14.7-eksbuild.22) |

We pin the default versions, not the latest. These are the versions AWS selects by default for 1.35.

## Changes

| File | Change |
|---|---|
| `infra/terraform/modules/cluster/{main,variables,outputs}.tf` | New: wraps EKS 21.26.0 |
| `infra/terraform/main.tf`, `outputs.tf` | Calls `module "cluster"`; safe outputs `access_entry_keys`, `bootstrap_admin_associations` |
| `infra/terraform/variables.tf` | New pinned variables, each with validation (listed below this table) |
| `infra/terraform/tests/cluster.tftest.hcl` | New: 7 runs |
| `infra/terraform/tests/mocks/{aws,tls}.tfmock.hcl` | New: shared mock values; fake account `000000000000` |
| `infra/terraform/tests/{guardrails,network}.tftest.hcl` | Use the shared mocks; add a test endpoint CIDR from the documentation range |
| `infra/terraform/scripts/check.sh` | The sensitive scan masks only `000000000000`; a real ID next to it still fails (tested) |
| `infra/terraform/scripts/plan_assert.sh` | Extended to 25 checks; counts managed resources only; adds `ADMIN_WINDOW=1` mode |
| `infra/terraform/README.md`, `docs/runbooks/P2_NETWORK.md` | Pointers updated |

The new variables in `variables.tf`:
- `system_node_ami_release_version`, which rejects `latest`;
- `system_node_instance_type` (only `m6i.large` or `t3.medium`);
- `system_node_desired_size` and `system_node_max_size` (1–2 each);
- `addon_versions` (exact `vX.Y.Z-eksbuild.N`);
- `endpoint_public_access_cidrs` (required, /24 or narrower);
- `bootstrap_role_name`;
- `bootstrap_cluster_admin` (default `false`).

Two defaults changed: the system node desired size went from 2 to 1, and its maximum from 3 to 2, to fit the 5 vCPU On-Demand quota and leave room for a P3 CPU node.

## Static gate

| Command | Result |
|---|---|
| `terraform validate` | Success |
| `terraform test` | **16 passed, 0 failed** |
| `./scripts/check.sh` | 8/8 PASS |

The 16 tests:
- guardrails: 7;
- network: 2;
- cluster: 7. These are: the default has the entry but no admin; window mode grants admin; and 5 rejection tests (`0.0.0.0/0` endpoint, `latest` AMI, 3 nodes, `g4dn.xlarge`, floating add-on).

## Plan

| Time (UTC) | Command | Result |
|---|---|---|
| ~14:40 | `terraform plan` | Hung, then was killed by a timeout. The CLI tried to refresh the MFA session less than 10 minutes before it expired. No lock was left: `aws s3 ls .../zero-d-rift/p2/` returned nothing after the owner renewed the session at 14:55 |
| ~14:57 | `terraform plan -var-file=run.tfvars -out=tfplan` | `Plan: 50 to add, 0 to change, 0 to destroy.` exit 0 |
| ~15:00 | `./scripts/plan_assert.sh tfplan` | 25/25 PASS |
| ~15:05 | `terraform plan ... -var bootstrap_cluster_admin=true -out=tfplan-window` | 51 to add (+ `aws_eks_access_policy_association.this["bootstrap_admin"]`) |
| ~15:05 | `ADMIN_WINDOW=1 ./scripts/plan_assert.sh tfplan-window` | PASS (51 managed). Run without `ADMIN_WINDOW` on the same plan: **FAIL**, as intended |

Both plan files were deleted after the checks.

Fields read from the default plan (redacted):

| Resource | Observed |
|---|---|
| `aws_eks_cluster` | version `1.35`; `upgrade_policy.support_type = STANDARD`; `authentication_mode = API`; `bootstrap_cluster_creator_admin_permissions = false`; private endpoint `true`; public endpoint `true` with 1 CIDR, a `/32`; log types `audit, authenticator`; `encryption_config = []` |
| `aws_cloudwatch_log_group` | `retention_in_days = 3` |
| `aws_eks_node_group` | `AL2023_x86_64_STANDARD`, release `1.35.9-20261026`, `m6i.large`, `ON_DEMAND`, min 1 / desired 1 / max 2 |
| `aws_launch_template` | `http_tokens = required`, `http_put_response_hop_limit = 1`; `block_device_mappings = []` (AMI default disk) |
| `aws_eks_addon` | vpc-cni `v1.22.4-eksbuild.10` (before compute), coredns `v1.13.2-eksbuild.62`, kube-proxy `v1.35.3-eksbuild.62` |
| `aws_eks_access_entry` | `STANDARD`, `arn:aws:iam::<ACCOUNT>:role/zero-drift-bootstrap` (role ARN, not a session) |
| `aws_eks_access_policy_association` | none (default `bootstrap_cluster_admin = false`) |
| IAM attachments | cluster: `AmazonEKSClusterPolicy`; node: `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly` |
| `aws_security_group_rule` (12) | Ingress only from the cluster/node security groups or `self` (ports 443, 4443, 6443, 8443, 9443, 10250, 10251, 53, 1025–65535). Egress `0.0.0.0/0`. No ingress from `0.0.0.0/0`, no port 22 |
| `aws_iam_openid_connect_provider` | 1 |

Negative test of the EKS checks, on a scratch copy of the plan JSON that was deleted afterwards. The injected faults:
- support `EXTENDED`;
- creator admin `true`;
- public endpoint `0.0.0.0/0`;
- `http_tokens = optional`;
- no version on coredns;
- AMI `latest`;
- one admin association.

Result: `RESULT: FAIL`, exit 1. Each fault was reported on its own FAIL line, and the resource count check failed too.

## AC results

- **AC-01: PASS (plan).**
  - EKS 1.35.
  - AL2023 with release `1.35.9-20261026` pinned and `use_latest_ami_release_version = false`.
  - System nodes: `m6i.large`, 1–2 nodes, On-Demand.
  - Add-ons pinned with `most_recent = false`. The source of each version is recorded above, and no floating `latest` is used.
- **AC-02: PASS (plan and test).**
  - `authentication_mode = API`, with one explicit STANDARD entry for the bootstrap role and creator admin off.
  - The admin association is controlled by a variable and is off by default.
  - Removing elevation is part of the design: the next apply with the default removes the association, and the window plan is checked separately.
  - The negative runtime check (`Forbidden` after removal) is planned in DRF-5 AC-04 and the runbook, and is Pending until L3.
- **AC-03: PASS (plan).**
  - Endpoint: private on, public only `/32`.
  - Security groups: no Internet ingress, no SSH.
  - IMDSv2 only, hop limit 1.
  - OIDC provider present.
  - IAM: only the 4 AWS managed policies listed above.
  - Logging: audit and authenticator, 3 days.
- **AC-04: PARTIAL.**
  - Done: the ownership and IAM matrix, and the reason bootstrap must come before controllers, are written in the runbook.
  - Pending: the owner's explanation in their own words. The owner will re-run the runbook later, and Claude does not write it for them.
  - No runtime PASS is claimed from validate or plan.

## Cost (exact plan, one 8-hour window)

- About 1.73 USD with 1 node, about 2.56 USD with 2 nodes, both under the 5 USD P2 cap. The breakdown is in the runbook.
- Prices come from COST_PLAN §5.2 and must be rechecked before L3.

## Limits

- The root disk size is left to the AMI default and has not been checked.
- Not verified until L3:
  - node readiness, add-on health and kubectl access;
  - the `Forbidden` check after the admin association is removed;
  - log volume.
- Same as DRF-8: the bootstrap role is still `AdministratorAccess`. Least privilege must be done before L3.

## Status

`CANDIDATE_FOR_OWNER_ACCEPTANCE`. AC-04 is waiting for the owner's explanation, and there is no independent reviewer yet.
