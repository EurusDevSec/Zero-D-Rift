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
| `tests/mocks/` | Shared mock values (fake account `000000000000`) so tests run without AWS |
| `scripts/check.sh` | Static gate: CLI pin, fmt, validate, tests, lockfile, module pins, Git leaks, secrets |
| `scripts/plan_assert.sh` | Plan gate on a saved plan (25 checks): network, EKS, nodes, add-ons, access entry, tags; `ADMIN_WINDOW=1` for a window plan |
| `scripts/plan_fingerprint.sh` | File hash and value-free shape hash of a saved plan; the L3 window must reproduce the approved shape hash |
| `scripts/inventory.sh` | Read-only AWS inventory (counts only) before create, after verify, after destroy; exit 0 only when just the retain allowlist is left |

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
