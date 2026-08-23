---
id: SPEC-P1
title: Foundation and compatibility decisions
status: READY_FOR_OWNER_REVIEW
phase: P1
start: 2026-08-24
deadline: 2026-08-30
estimated_effort: 26-29 hours
mode: Coach then Pair
canonical_scope: docs/de_cuong_tot_nghiep_ver3.md
---

# 1. Goal and boundaries

## Goal

Produce the reviewed architecture, compatibility, security, cost and experiment
foundation required to start a reproducible EKS bootstrap in P2 without making
unsupported claims or installing the full platform prematurely.

## User story

As the project owner, I want all high-risk architecture and experiment assumptions
made explicit so that I can build the PoC in dependency order, control AWS cost,
and explain why each component exists.

## MUST deliverables

- `docs/VERSION_MATRIX.md`
- `docs/architecture/SYSTEM_DESIGN.md`
- `docs/security/THREAT_MODEL.md`
- `docs/finops/COST_PLAN.md`
- `docs/experiments/EXPERIMENT_PLAN.md`
- Material ADRs under `docs/adr/`
- Reviewed P2 scope and initial EKS-bootstrap spec

These files are planned outputs of P1; their names in this spec do not imply they
already exist.

## Negative boundaries

1. Do not create EKS, RDS, NAT Gateway, GPU or any paid AWS resource in P1.
2. Do not install Argo CD, Crossplane, kro, KEDA, Karpenter, Kyverno or OpenCost.
3. Do not add a portal, service mesh, multi-region, multi-account, model registry,
   full MLOps lifecycle or a third golden path.
4. Do not promote target versions or costs to verified facts before checking
   official sources/account state.
5. Do not rewrite the school-approved topic; record implementation refinements
   as alignment notes or ADRs.

# 2. Learning objectives

By the end of P1, the owner should be able to:

1. Explain EKS control plane, system nodes, workload nodes, OIDC and IRSA flow.
2. Explain Kubernetes reconciliation and why Crossplane and kro have different roles.
3. Explain the bootstrap plane vs platform control plane boundary.
4. Define baseline, trial, success, timeout, p50 and p95 without using future results.
5. Identify major cost leak paths and the teardown/inventory response.
6. Describe the PoC trust boundaries and why namespace tenancy is soft isolation.

# 3. Acceptance criteria

```gherkin
Scenario: Architecture is implementation-ready
  Given the ver3 scope and teacher feedback
  When the system design and ADRs are reviewed
  Then every MVP component has one responsibility and an explicit dependency
  And no out-of-scope component is required for P2

Scenario: Versions are evidence-based
  Given the target EKS and controller stack
  When official compatibility sources are checked
  Then each selected version has a source, check date and compatibility note
  And unresolved selections remain marked UNVERIFIED

Scenario: Cost is bounded before AWS work
  Given the 100 USD spending envelope
  When the account, Region, network and resource assumptions are reviewed
  Then cost categories, alerts, quotas, teardown and retained resources are documented

Scenario: Experiment definitions cannot be changed after seeing results
  Given the provisioning, reliability, drift, cost and recovery hypotheses
  When the experiment plan is approved
  Then start/end events, timeout, run fields and exclusion rules are specified
  Before official trial collection begins

Scenario: Learning is demonstrated
  Given the P1 learning objectives
  When the owner completes the teach-back review
  Then component boundaries, identity flow and baseline design can be explained
  And remaining gaps are recorded rather than hidden
```

# 4. Work checkpoint matrix

## Task 1 — Governance and canonical baseline review (2–3 h)

- [ ] Review `docs/de_cuong_tot_nghiep_ver3.md` against the historical teacher
      feedback from `git show 69be067:docs/gop_y_de_cuong_tu_thay_Kiet.md`;
      record only unresolved alignment issues.
- [ ] Confirm `docs/README.md` classification and decide later archive paths without
      changing the byte content of the approved proposal.
- [ ] Review the initialized root `AGENTS.md`, roadmap and active context.
- [ ] Review the complete Git file list before explicitly committing ver3 and
      project-agent state; do not use `git add .`.

Evidence: review note or ADR, changed-file list, Git status.

## Task 2 — System design and architectural ADRs (4–5 h)

- [ ] Create `[NEW] docs/architecture/SYSTEM_DESIGN.md` with bootstrap, control,
      workload, identity, secret, data, observability and teardown flows.
- [ ] Draw the end-to-end request sequence from Git PR to workload readiness/status.
- [ ] Record responsibility boundaries for Terraform, Argo CD, Crossplane and kro.
- [ ] Record the shared-RDS and separate-recovery-database decision.
- [ ] List unresolved decisions without letting an agent choose them silently.

Micro-assertion: every technology in the system diagram has exactly one primary
responsibility and a linked reason for inclusion.

## Task 3 — Version and compatibility spike (5–6 h)

- [ ] Create `[NEW] docs/VERSION_MATRIX.md` with component, version/digest, source,
      checked date, compatibility and verification status.
- [ ] Verify the available EKS/Kubernetes versions and AL2023 constraints from
      current official AWS documentation.
- [ ] Check Argo CD, Crossplane AWS provider packages and kro compatibility.
- [ ] Check KEDA, Karpenter, Kyverno and OpenCost requirements without installing them.
- [ ] Decide `kind` or `k3d` for local-first work and document parity gaps.
- [ ] Create ADRs only for choices supported by the compatibility evidence.

Evidence: direct official links and `UNVERIFIED` labels for remaining unknowns.

## Task 4 — Threat model and identity design (4 h)

- [ ] Create `[NEW] docs/security/THREAT_MODEL.md` with assets, actors, trust
      boundaries, abuse cases and mitigations.
- [ ] Draw the Git/CI, Kubernetes, AWS API, tenant and administrative identity flows.
- [ ] Define least-privilege IRSA boundaries and negative-access test intentions.
- [ ] Document why namespace/RBAC/NetworkPolicy is soft multi-tenancy.
- [ ] Define secret redaction rules for Git, logs, screenshots and experiment data.

Evidence: threat-to-control-to-test mapping; no secret values.

## Task 5 — Cost, quota and teardown plan (4 h)

- [ ] Create `[NEW] docs/finops/COST_PLAN.md` using the 100 USD envelope from ver3.
- [ ] Verify credit applicability and relevant account quotas without creating resources.
- [ ] Compare NAT Gateway, public subnet and/or VPC endpoint assumptions for this PoC.
- [ ] Define Budget thresholds, TTL tags, daily billing check and GPU limits.
- [ ] Define resource inventory and retain/delete allowlists for P2 onward.

Evidence: assumptions marked `VERIFIED` or `UNVERIFIED`, dated price/source links,
and a teardown checklist.

## Task 6 — Baseline and experiment contract (4 h)

- [ ] Create `[NEW] docs/experiments/EXPERIMENT_PLAN.md`.
- [ ] Define manual baseline actions without inventing enterprise duration/error data.
- [ ] Define run-manifest fields, timestamps, timeout, success and failure rules.
- [ ] Define trial retention/exclusion and dataset-freeze rules before collection.
- [ ] Sketch the CSV/JSONL schema and analysis outputs for p50/p95 and success/total.

Evidence: one dry example manifest clearly marked `SYNTHETIC`, not an observed run.

## Task 7 — P1 review, teach-back and P2 readiness (3 h)

- [ ] Run documentation link/consistency checks appropriate to the repository.
- [ ] Review architecture, cost, threat and experiment documents against ver3.
- [ ] Answer the P1 teach-back questions without reading generated prose verbatim.
- [ ] Record gaps in `.agent/learning/LEARNING_LOG.md`.
- [ ] Create the P2 spec with tasks/subtasks only after P1 decisions are approved.
- [ ] Update roadmap, active context and history with observed completion state.

# 5. Teach-back questions

1. Why must Terraform create EKS before Crossplane can provision selected AWS resources?
2. What is the difference between Argo CD reconciliation, kro composition and
   Crossplane external-resource reconciliation?
3. How does an EKS Pod obtain temporary AWS credentials through IRSA?
4. Why is a namespace-based tenant not equivalent to a separate AWS account?
5. Which costs can remain after pods and Karpenter nodes scale to zero?
6. Why must baseline and exclusion rules be written before official trials?

# 6. P1 completion rule

P1 is complete only when all MUST tasks satisfy both the functional and learning
Definition of Done. Merely generating the six documents is not sufficient; their
assumptions must be reviewed and their unresolved items must remain visible.
