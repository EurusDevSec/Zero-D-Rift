# infra/terraform — P2 EKS bootstrap root

Root configuration for SPEC-P2 (`.agent/specs/SPEC-P2_REPRODUCIBLE_EKS_BOOTSTRAP.md`).
DRF-7 built the skeleton only: pins, variables, tags, safe outputs, backend contract
and static checks. DRF-8 added the network module and DRF-9 the EKS module (50 resources, plan only; not applied).

## Layout

| File | Purpose |
|---|---|
| `versions.tf` | Exact CLI/provider pins; module pin list |
| `.terraform.lock.hcl` | Provider builds and checksums (tracked) |
| `backend.tf` | Partial S3 backend; values come from untracked `backend.hcl` |
| `backend.hcl.example` | Backend contract from ADR-0007 with private values blank |
| `providers.tf` | AWS provider: Region and `default_tags`, no credentials |
| `variables.tf` | Inputs and guardrails (Region, 2 AZs, no NAT, AL2023, EKS 1.35) |
| `locals.tf` | Mandatory tags (COST_PLAN §10), subnet CIDR layout |
| `outputs.tf` | Safe outputs only |
| `run.tfvars.example` | Per-run `run_id` and `expires_at` |
| `main.tf` | Calls `modules/network` (DRF-8) and `modules/cluster` (DRF-9) |
| `modules/network/` | VPC 6.7.3: 2 public + 2 DB subnets, IGW, no NAT, S3 gateway endpoint with bounded policy, default SG with no rules |
| `tests/guardrails.tftest.hcl` | Guardrail and tag tests with a mocked AWS provider |
| `tests/network.tftest.hcl` | Network contract tests (no NAT, subnet/route-table counts, Gateway endpoint) |
| `modules/cluster/` | EKS 21.26.0: 1.35 standard support, API auth, bootstrap access entry, pinned add-ons and AL2023 AMI, IMDSv2 |
| `tests/cluster.tftest.hcl` | EKS contract tests (admin only in window, bounded endpoint, pins, node limits) |
| `modules/p3-provider-irsa/` | DRF-36: Crossplane provider-aws-s3 IRSA role, trust = one ServiceAccount, S3 bucket actions on `zero-drift-p3-*` only; created only when `enable_p3_provider_role = true` |
| `tests/p3_irsa.tftest.hcl` | P3 IRSA contract tests (off by default, exact sub/aud, prefix-only resource, name/prefix validation) |
| `modules/shared-rds/` | DRF-46: P4 shared RDS PostgreSQL 17.11, `db.t4g.micro`, 20 GiB gp3, private in the P2 DB subnet group, encrypted, RDS-managed master secret, no backup/final snapshot/deletion protection; one ingress rule 5432/tcp from the node SG; created only when `enable_rag_platform = true` |
| `modules/rag-identity/` | DRF-46: five P4 IRSA roles (db-admin, bootstrap, tenant-a, tenant-b, crossplane-s3) with exact trust subjects and exact action allowlists; created only when `enable_rag_platform = true` |
| `tests/rag_platform.tftest.hcl` | P4 contract tests (off by default, RDS shape, single ingress, five roles and trust, exact allowlists, tenant separation) and the offline IAM matrix |
| `tests/rag_iam_matrix.json` | Allow/deny matrix for the five P4 roles, shared by the tftest (offline) and `rag_iam_check.sh` (AWS simulation) |
| `tests/plan_assert_guards.sh`, `tests/p4_good_plan.jq` | Negative tests for plan_assert guards on synthetic plans (P3 policy, endpoint, P4 checks 14-17) |
| `tests/mocks/` | Shared mock values (fake account `000000000000`) so tests run without AWS |
| `scripts/check.sh` | Static gate: CLI pin, fmt, validate, tests, lockfile, module pins, Git leaks, secrets |
| `scripts/plan_assert.sh` | Plan gate on a saved plan: network, EKS, nodes, add-ons, access entry, IAM scope, tags, P3 role (check 13), P4 RDS, ingress, policies and trust (checks 14-17); `ADMIN_WINDOW=1` for a window plan, `P3_WINDOW=1` when the P3 role is enabled, `P4_WINDOW=1` when `enable_rag_platform = true` |
| `scripts/p3_iam_check.sh` | Read-only P3 role check: Access Analyzer + IAM simulation (P3 buckets allowed, everything else denied), from a saved plan or the live role |
| `scripts/rag_iam_check.sh` | Read-only P4 role check: Access Analyzer + IAM simulation of `tests/rag_iam_matrix.json` for the five roles, from a saved P4 plan or the live roles (with live trust) |
| `scripts/plan_fingerprint.sh` | File hash and value-free shape hash of a saved plan; the L3 window must reproduce the approved shape hash |
| `scripts/iam_check.sh` | Read-only R1 check: Access Analyzer + IAM simulation of `infra/iam/zero-drift-terraform-policy.json` (or the live role with `--principal`) |
| `scripts/smoke.sh` | L3 runtime smoke test (DRF-11 AC-03): control plane, OIDC, add-ons, nodes, IMDS, SGs, S3 endpoint route, DNS; read-only on AWS, two short-lived probe Pods |
| `scripts/inventory.sh` | Read-only AWS inventory (counts only) before create, after verify, after destroy; exit 0 only when just the retain allowlist is left; P4 adds RDS automated snapshots/backups, P4 and RDS-managed secrets (including pending deletion), P4 buckets and roles |

## Pins

| Component | Version |
|---|---|
| Terraform CLI | 1.16.4 |
| hashicorp/aws | 6.67.0 |
| hashicorp/tls, time, cloudinit, null | 4.4.1, 0.14.2, 2.4.1, 3.3.2 (EKS transitive) |
| terraform-aws-modules/vpc/aws (+ `vpc-endpoints`) | 6.7.3 |
| terraform-aws-modules/eks/aws | 21.26.0 |
| terraform-aws-modules/kms/aws | 4.0.0 (EKS transitive) |

Source: `docs/evidence/p2/P2_T1_DECISION_REVIEW.md`. Never widen a pin or use
`init -upgrade` to fix a failed init.

## Init: local versus backend

Local, no AWS, no backend (downloads providers from the public registry). With
the tracked lockfile in place, `-lockfile=readonly` fails instead of changing it:

```bash
terraform init -backend=false -lockfile=readonly
```

```bash
./scripts/check.sh
```

Backend, only under DRF-6 authority with a reviewed temporary session:

```bash
terraform init -backend-config=backend.hcl
```

Lockfile refresh, only after an approved pin change:

```bash
terraform providers lock -platform=windows_amd64 -platform=linux_amd64
```

## Never in Git

State, plans, `.terraform/`, `backend.hcl`, `*.tfvars`, kubeconfig, credentials,
account IDs. The root `.gitignore` covers the files; `scripts/check.sh` checks it.
A passing check is static evidence only and proves nothing about AWS.
