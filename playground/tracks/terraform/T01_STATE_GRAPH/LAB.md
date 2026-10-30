---
id: TF-T01
status: READY
environment: D1_LOCAL
timebox: 2h
cost: 0 USD
delivery_link: DRF-4 / SPEC-P2 Task 2
---

# T01 — P2 Bootstrap Graph, Hands-on

## Why this lab

You build the real dependency shape of the P2 bootstrap — network -> EKS -> OIDC
-> system nodes — with `terraform_data` stand-ins, then change and break it the
way the real stack changes and breaks. Variable names, the module boundary and
the guardrails are the ones `infra/terraform/` will use (DRF-7), so this code is a
rehearsal of the project, not a toy.

Boundary: built-in `terraform_data` only. No provider download, no cloud call.
It proves Terraform graph/state/plan behavior and nothing about AWS or EKS.

## Rules

- Terraform exactly 1.16.4. Fresh run directory
  `playground/runs/TF-T01-<yyyymmdd>-<nn>/`; it is ignored by Git and holds the state.
- Before each `apply`/`destroy`, add one line to `notes.md`:
  `M<n> expect: <action symbols + addresses>`. After it: `M<n> actual: ...`.
  That is the whole prediction step.
- You write the HCL. Hints go concept -> missing boundary -> small fragment; a full
  solution only on request after an attempt.
- Owner-requested type-along version with full code and "why" notes:
  [WALKTHROUGH.md](WALKTHROUGH.md). Typing it still counts only with your own
  `expect` lines and explain-back.

## Build target

```text
TF-T01-<yyyymmdd>-<nn>/
├── versions.tf          # required_version = "= 1.16.4"
├── variables.tf         # project inputs + guardrails
├── main.tf              # module "network" -> module "cluster"
├── outputs.tf
├── modules/network/     # vpc, public_subnets, db_subnets, s3_gateway_endpoint
└── modules/cluster/     # eks, oidc_provider, system_nodes
```

Root variables:

| Variable | Default | Guardrail (`validation`) |
|---|---|---|
| `region` | `us-east-1` | must be `us-east-1` |
| `cluster_name` | `zero-drift` | lowercase letters, digits, `-` |
| `kubernetes_version` | `1.35` | none; you change it in M3 |
| `azs` | `["us-east-1a", "us-east-1b"]` | exactly 2 AZs |
| `vpc_cidr` | `10.0.0.0/16` | valid CIDR |
| `enable_nat_gateway` | `false` | must be `false` (ADR-0006) |
| `system_node_ami_type` | `AL2023_x86_64_STANDARD` | starts with `AL2023` |
| `system_node_desired_size` | `2` | 1–3 |

Stand-ins must copy real AWS update/replace behavior. Put a value in `input` when
AWS updates it in place, and in `triggers_replace` when AWS forces a new resource:

| Stand-in | `input` (update in place) | `triggers_replace` (destroy + create) |
|---|---|---|
| `vpc` | name tags | `vpc_cidr` |
| `public_subnets` (`for_each` AZ) | name tags | VPC id, AZ, subnet CIDR |
| `db_subnets` (`for_each` AZ) | name tags | VPC id, AZ, subnet CIDR |
| `s3_gateway_endpoint` | name tags | VPC id |
| `eks` | `kubernetes_version` | `cluster_name`, VPC id |
| `oidc_provider` | none | EKS id (new cluster = new issuer) |
| `system_nodes` | desired size, version from EKS | EKS id, `system_node_ami_type` |

Derive subnet CIDRs with `cidrsubnet()`. Pass ids between modules only through
module outputs and variables, as the real modules will.

## Missions

### M1 — Build, see the graph, first apply (35 m)

```bash
terraform init && terraform fmt -check -recursive && terraform validate
```

```bash
terraform graph | dot -Tsvg > graph-before.svg
```

Open the SVG and trace vpc -> subnets -> eks -> oidc/nodes. Then plan to a file,
apply that file, and inspect state:

```bash
terraform plan -out=tfplan && terraform apply tfplan
```

```bash
terraform state list && terraform state show 'module.cluster.terraform_data.eks'
```

Done when the created count matches your `expect` line and the graph has no edge
you did not intend.

### M2 — Idempotency gate in bash (15 m)

Write `noop-check.sh`: run `terraform plan -detailed-exitcode -input=false "$@"`,
print `NOOP` (exit 0), `DRIFT` (exit 2) or `ERROR` (exit 1), and exit 0 only on
`NOOP`. Handle exit code 2 under `set -euo pipefail` without the script dying
early; `"$@"` lets later missions pass `-var` flags through. This becomes the P2 Task 8 idempotency check and later a CI drift check.

Done when it prints `NOOP` and exits 0.

### M3 — EKS version upgrade is in place (15 m)

Change the `kubernetes_version` default to `"1.36"` in `variables.tf` (real
upgrades go through a reviewed code change, not a typed `-var`). Write your
`expect` line, then:

```bash
terraform plan -out=tfplan
```

List the planned actions per address (reuse this in M4):

```bash
terraform show -json tfplan | jq -r '.resource_changes[] | select(.change.actions != ["no-op"]) | "\(.change.actions | join(",")) \(.address)"'
```

Apply it, then run `./noop-check.sh`. Note which downstream resources updated only because
they read an upstream value that was unknown until apply.

Done when the plan had zero replacements and the re-plan is `NOOP`.

### M4 — Rename the cluster: blast radius (15 m)

`expect` first, then plan `-var cluster_name=zero-drift-v2` and list actions with
the same `jq` filter. Count every `delete,create`. Apply it and watch the order of
destroy and create in the output. Revert to the default name and apply again.

Done when `notes.md` lists each replaced address and which value forced it.

### M5 — Guardrails stop bad input at plan time (10 m)

Each must fail at `plan` with your validation message and exit 1:

```bash
terraform plan -var enable_nat_gateway=true
```

```bash
terraform plan -var region=ap-southeast-1
```

```bash
terraform plan -var 'azs=["us-east-1a"]'
```

Done when all three fail and `noop-check.sh` still prints `NOOP`.

### M6 — Break the graph on purpose (10 m)

In root `main.tf`, replace both `module.network` references passed to
`module.cluster` (`vpc_id`, `subnet_ids`) with hard-coded fake values. Render
`graph-broken.svg`, compare it with `graph-before.svg` and plan once without
applying. Restore the references.

Done when the missing edge is visible and the restored config is `NOOP`.

### M7 — Destroy and prove cleanup (15 m)

`expect` the destroy order first, then:

```bash
terraform plan -destroy -out=destroy.tfplan && terraform apply destroy.tfplan
```

```bash
terraform state list | wc -l && jq '.resources | length' terraform.tfstate
```

Done when both counts are 0 and the observed destroy order is in `notes.md`.
Keep the run directory until the review is accepted, then delete only that directory.

### Explain-back (5 m)

One or two sentences each in `notes.md`, from what you saw:

1. What did state hold that the `.tf` files did not?
2. Which change in M3/M4 would cost a real EKS cluster, and how did the plan warn you?
3. What does `NOOP` prove, and what does it not prove about AWS?

## Evidence to hand to the reviewer

`terraform version`, `notes.md`, `graph-before.svg`, `graph-broken.svg`,
`noop-check.sh`, the M3/M4 action lists, M5 error lines and the M7 counts.
Never hand over `terraform.tfstate`, `tfplan` files or `.terraform/`.

Result labels: `PRACTICED`, `NEEDS_REVIEW` or `NOT_RUN`; never project `PASS`.

## After this lab

Keep the module boundary and swap the `network` stand-ins for real
`aws_vpc`, subnets, internet gateway, route tables, security groups and the S3
gateway endpoint on the approved AWS provider 6.67.0. None of those has an hourly
charge without NAT, Elastic IPs or instances, so it is the first real AWS apply
of P2 (SPEC-P2 Task 4). It stays gated by DRF-5 (MFA and reviewed temporary
identity), a fresh cost check and explicit owner approval.
