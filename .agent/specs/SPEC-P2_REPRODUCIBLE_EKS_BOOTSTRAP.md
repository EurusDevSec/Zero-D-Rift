---
id: SPEC-P2
title: Reproducible EKS bootstrap and teardown
status: DRAFT_FOR_OWNER_APPROVAL
phase: P2
start: TBD_AFTER_OWNER_APPROVAL
deadline: TBD_REBASELINE
estimated_effort: 27-31 hours
mode: Coach then Pair
canonical_scope: docs/de_cuong_tot_nghiep_ver3.md
iac_tool: Terraform
---

# 1. Goal and boundaries

## Goal

Build a reproducible Terraform bootstrap for the single-account, single-Region
Zero D-Rift PoC: VPC/network baseline, EKS 1.35, AL2023 system nodes, OIDC,
bootstrap IAM/access, bounded logging/budget controls and complete teardown.

This specification is a plan. It does not authorize `terraform apply`, paid AWS
resources, quota requests or account mutations. Each L3 action requires an
explicit task, current cost check, temporary/approved identity and teardown owner.

## MUST deliverables

- `infra/terraform/` root configuration and focused modules.
- Version-locked provider/module dependency files.
- Remote-state/security decision and bootstrap instructions.
- `docs/runbooks/P2_EKS_BOOTSTRAP_AND_TEARDOWN.md`.
- Redacted plan, smoke-test, inventory and teardown evidence under
  `docs/evidence/p2/`; sensitive-capable raw output stays outside Git.
- One observed create/verify/destroy cycle only after explicit L3 approval.

## Negative boundaries

1. Do not install Argo CD, Crossplane, kro, KEDA, Karpenter, Kyverno or OpenCost.
2. Do not create RDS, GPU, workload node pools or either golden path.
3. Do not create a NAT Gateway by default; follow accepted ADR-0006.
4. Do not give tenant workloads, controllers or daily users cluster-admin/AWS
   administrator permissions.
5. Do not put AWS credentials, account IDs, state files, sensitive plans or
   kubeconfig secrets in Git/evidence.
6. Do not use long-lived IAM-user credentials for workload identity. The
   bootstrap operator method must be reviewed before L3 apply.
7. Do not claim runtime success from `terraform validate` or plan-only evidence.
8. Do not continue after the approved cost/time window or with unknown orphaned
   inventory.

# 2. Approved P1 constraints carried forward

- Region: `us-east-1`; one AWS account, one EKS cluster, maximum two simulated tenants.
- EKS/Kubernetes 1.35 and AL2023; exact AMI/add-on versions resolve in P2 evidence.
- Terraform/OpenTofu owns VPC, EKS, OIDC, system node group, bootstrap IAM,
  baseline logging/budget and their teardown lifecycle (ADR-0003).
- Public worker subnets with restricted exposure, private DB subnets, no default
  NAT Gateway and an S3 gateway endpoint (ADR-0006).
- Gross project envelope remains 100 USD. P2 execution cap and active window are
  `TBD_OWNER_APPROVAL` and must fit the P1 category guardrails.
- GPU G/VT On-Demand and Spot quota remain zero; GPU is outside P2.
- kind remains proposed until an L2 micro-lab; local evidence does not prove EKS behavior.

# 3. Learning objectives

By the end of P2, the owner should be able to:

1. Explain configuration, state, provider and dependency graph roles.
2. Predict a plan change and distinguish create/update/replace/destroy.
3. Explain why EKS, OIDC and system nodes precede platform controllers.
4. Explain idempotency, remote-state sensitivity and state-locking risk.
5. Locate a bootstrap failure in Terraform, AWS API, EKS or worker-node join evidence.
6. Reproduce the documented plan/apply/verify/destroy flow and inventory check.

# 4. Acceptance scenarios

```gherkin
Scenario: Plan respects the P1 ownership and cost boundary
  Given approved Region, network ADR and category envelopes
  When Terraform initialization, validation and plan complete
  Then the plan contains only approved bootstrap resources
  And it contains no NAT Gateway, RDS, GPU or platform controller
  And its priced estimate fits the owner-approved P2 cap

Scenario: Bootstrap becomes usable
  Given an explicitly approved L3 window and reviewed plan
  When Terraform applies the bootstrap configuration
  Then EKS 1.35 API, AL2023 system nodes and OIDC are observed healthy
  And access, endpoint, IMDS, tag, log and S3-endpoint checks have redacted evidence

Scenario: Re-running is predictable
  Given the same configuration and unmodified external state
  When Terraform plans again
  Then no unintended infrastructure change is proposed

Scenario: Teardown is complete
  Given captured evidence and an explicit retain allowlist
  When Terraform destroy and post-teardown inventory complete
  Then no paid project resource remains outside the allowlist
  And failed deletion/orphan state is retained as evidence rather than hidden
```

# 5. Work checkpoint matrix

## Task 1 — P2 approval, tool pin and zero-cost preflight (2–3 h)

- [x] Owner selects Terraform rather than OpenTofu for P2 (2026-10-01); exact
      CLI/provider/module versions remain source-checked pins.
- [ ] (30–45 m) Owner reviews and approves the bounded P2 scope.
- [ ] (30 m) Rebaseline P2–P11 dates without weakening acceptance criteria.
- [ ] (30–45 m) Decide bootstrap identity/temporary-session method, EKS access-entry
      boundary and break-glass owner; no account mutation yet.
- [ ] (30 m) Decide state backend, encryption, locking, recovery and secret-output rules.
- [ ] (30 m) Recheck current gross spend, credit, Region, EKS/VPC/EC2 quotas and
      set P2 execution cap/window/teardown owner.

Evidence: approved spec revision, tool/version sources, redacted preflight and
explicit list of unresolved blockers. No paid resource or backend is created.

## Task 2 — Local Terraform state/dependency micro-lab (2 h)

- [ ] (20 m) Predict the plan for a tiny local `terraform_data` graph.
- [ ] (30 m) Run init/validate/plan/apply with no cloud provider/resource.
- [ ] (30 m) Change one input and explain update versus replacement from the plan.
- [ ] (20 m) Re-plan unchanged configuration and observe idempotency.
- [ ] (20 m) Destroy and inspect state/working-directory cleanup evidence.

Evidence: L1 run ID, sanitized commands/output and owner explanation. This lab
does not prove AWS/EKS behavior.

## Task 3 — Terraform root, state contract and static checks (3 h)

- [ ] (30 m) Create the agreed `infra/terraform/` layout and `.gitignore` rules.
- [ ] (45 m) Pin Terraform/provider/module versions and required checksums/lockfile.
- [ ] (45 m) Define variables, validation, locals, common tags and safe outputs.
- [ ] (30 m) Implement backend initialization procedure without committing state.
- [ ] (30 m) Add formatting, validation and sensitive-pattern checks.

Evidence: L0/L1 output, version locks and no tracked state/credential material.

## Task 4 — VPC and cost-bounded network module (3–4 h)

- [ ] (45 m) Define VPC, public worker, private DB subnets and AZ/CIDR validation.
- [ ] (45 m) Define IGW/routes without a default NAT Gateway.
- [ ] (45 m) Define S3 gateway endpoint, route-table attachment and bounded policy.
- [ ] (30 m) Define security groups with no Internet ingress or SSH.
- [ ] (30–45 m) Test plan assertions for NAT absence, RDS-private-ready subnets,
      tags and approved resource counts.

Evidence: static plan assertions and priced network estimate; no runtime claim.

## Task 5 — EKS, OIDC, access and system nodes (4 h)

- [ ] (45 m) Define EKS 1.35 control plane, endpoint private access and bounded
      public CIDR only if the workstation path requires it.
- [ ] (45 m) Define AL2023 system node group, instance/count limits and labels/taints.
- [ ] (45 m) Define OIDC provider and minimum bootstrap/system IAM boundaries.
- [ ] (30 m) Define EKS access entries for bootstrap/daily/break-glass roles.
- [ ] (30 m) Pin required EKS add-ons/config needed by later VPC CNI policy work.
- [ ] (45 m) Add plan assertions for version, node limits, IMDS, logging and tags.

Evidence: reviewed plan and ownership/IAM matrix. No controller/workload IAM yet.

## Task 6 — Budget, runbook and final plan gate (3 h)

- [ ] (30–45 m) Define approved Budget alerts/actions without blocking teardown.
- [ ] (45 m) Write bootstrap/verify/teardown/recovery runbook and stop conditions.
- [ ] (30 m) Produce redacted final plan and pre-apply inventory.
- [ ] (30 m) Price the exact plan and compare with P2/project envelope.
- [ ] (30 m) Owner explains expected resources, risks and teardown before approval.

Gate: no L3 apply until exact plan, identity, cost cap, active window and teardown
owner are approved in the execution task.

## Task 7 — Explicitly approved L3 bootstrap and smoke test (3–5 h)

- [ ] Record approval, run ID, start time, estimate, stop time and pre-inventory.
- [ ] Apply the reviewed immutable plan; preserve errors and avoid blind retries.
- [ ] Verify EKS/Kubernetes version, endpoint, OIDC, add-ons and system Nodes.
- [ ] Verify node SG/IMDS/public-IP, DNS and S3 endpoint route behavior.
- [ ] Capture redacted Terraform/AWS/Kubernetes evidence and actual inventory.

Evidence: L3 run manifest and observed output. `apply` authorization is separate
from approval of this planning document.

## Task 8 — Idempotency, teardown and orphan audit (3–4 h)

- [ ] Re-plan unchanged infrastructure and investigate every unexpected diff.
- [ ] Capture pre-teardown evidence and explicit retain allowlist.
- [ ] Destroy in documented order; do not remove state to hide failed deletion.
- [ ] Run immediate and delayed post-teardown inventory across the cost-plan list.
- [ ] Reconcile delayed billing and record remaining resource/cost or clean result.

Evidence: plan result, destroy output, before/after inventory and billing follow-up.

## Task 9 — P2 review, teach-back and P3 readiness (2 h)

- [ ] Review functional and security evidence against this spec.
- [ ] Complete teach-back without reading generated prose verbatim.
- [ ] Record practical gaps and failed attempts in the learning log.
- [ ] Create P3 detailed spec only after P2 exit criteria are satisfied.
- [ ] Update roadmap, active context and history with observed state.

# 6. Verification tiers and evidence

| Tier | P2 use | Required evidence |
| --- | --- | --- |
| L0 | format, validate, static plan assertions, secret scan | commands, versions, exit status |
| L1 | local `terraform_data` state/dependency lab | run ID, prediction, observed plan/state/destroy |
| L2 | Optional only if a local Kubernetes behavior is required | parity limit and cleanup evidence |
| L3 | EKS create/verify/destroy | explicit approval, cost preflight, manifest, inventory, logs |

Build/validate passing is not safe-to-apply evidence. A successful apply is not
complete until smoke tests, teardown and orphan inventory pass.

# 7. Teach-back questions

1. What is Terraform state, and why is losing or leaking it dangerous?
2. How does the dependency graph order VPC, EKS, OIDC and system nodes?
3. What does an empty second plan prove, and what can it not prove?
4. Why does ADR-0006 remove NAT by default, and which controls compensate?
5. How would you distinguish Terraform failure, AWS authorization failure and a
   worker node that cannot join EKS?
6. Which inventory evidence is required before declaring teardown complete?

# 8. P2 completion rule

P2 is complete only when the approved bootstrap can be planned, created, verified
and destroyed with redacted evidence, no unapproved paid resource remains, and
the owner reaches at least `PRACTICED` plus `EXPLAINED` for the project-specific
Terraform/state/dependency and teardown flow. Planning artifacts alone are not P2.
