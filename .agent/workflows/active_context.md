---
project: Zero D-Rift
status: PHASE_1_COMPLETE_P2_SPEC_REVIEW
active_phase: P2
active_feature: P2 spec owner review and zero-cost preflight
active_spec: .agent/specs/SPEC-P2_REPRODUCIBLE_EKS_BOOTSTRAP.md
roadmap: .agent/docs/ROADMAP.md
architecture: .agent/docs/ARCHITECTURE.md
canonical_scope: docs/de_cuong_tot_nghiep_ver3.md
learning_plan: .agent/learning/LEARNING_ROADMAP.md
learning_log: .agent/learning/LEARNING_LOG.md
cold_memory: .agent/memory/cold_memory.md
history: .agent/workflows/history_archive.md
git_head: 92d5471a1d070d5df9ce36ae18eaaddb2e04ba7c
git_state: DIRTY_EXPECTED_HANDOFF_P2_NCKH_DRAFTS
last_verification: PASS_HANDOFF_CHECKPOINT_L0_2026-09-30
last_updated: 2026-09-30
---

# Active Context

## Current truth

- P1 is complete at documentation/design and `EXPLAINED` learning level. No local
  cluster, EKS cluster, platform controller, IAM policy or workload was created.
- The owner has explained the bootstrap/platform boundary, reconciliation and
  readiness flow, IRSA trust versus AWS permission, soft tenant isolation, cost
  guardrails and experiment exclusion rules. Hands-on evidence remains open.
- `docs/de_cuong_tot_nghiep_ver3.md` is the canonical implementation scope.
- Terraform/OpenTofu owns the initial VPC, EKS, OIDC, system node group,
  bootstrap IAM, logging and budget foundation. Argo CD, kro and Crossplane run
  only after the bootstrap cluster exists.
- Region is `us-east-1`. The canonical gross project envelope remains 100 USD.
  One enabled 100 USD promotional credit was observed on 2026-09-28; a possible
  second guide reward is not earned/account-verified and cannot expand the plan.
- ADR-0006 is accepted: no default NAT Gateway, bounded public worker subnets,
  private RDS subnets and an S3 gateway endpoint. GPU G/VT On-Demand and Spot
  quotas were both observed as zero.
- Experiment contract v0.1.0 is approved at documentation level. No official
  trial, campaign freeze or runtime result exists.
- P2 contract exists at
  `.agent/specs/SPEC-P2_REPRODUCIBLE_EKS_BOOTSTRAP.md` with status
  `DRAFT_FOR_OWNER_APPROVAL`. It is not implementation authorization.
- A separate NCKH derivative is recorded at
  `docs/research/nckh/NCKH_RESEARCH_CONTEXT.md`. The owner reports advisor
  agreement for a Category-B, 12-month plan and a TDMU journal article before
  acceptance. Administrative approval/evidence remains unverified.
- The NCKH proposal draft exists, but the 2026-09-30 bibliography/claim audit is
  `PARTIAL`: references [4] and [9] have incorrect author initials; the uses of
  [2] and [6] misstate the papers; the Kubernetes-configuration claim lacks a
  direct source; and the experimental-method citation set should be strengthened.
  Do not call the research proposal fully reference-verified until corrected.
- NCKH is parked while P2 is active. It does not expand P2 scope or authorize
  additional AWS spending.
- The working tree is intentionally dirty for owner review. Nothing has been
  staged, committed or pushed by the checkpoint.

## Active objective

Review and approve or revise the P2 bootstrap contract, rebaseline the delayed
roadmap and begin only its zero-cost preflight and local Terraform state lab.
No AWS apply is authorized.

## Next bounded actions

1. Owner reviews P2 scope, negative boundaries and task order, then chooses
   Terraform or OpenTofu. Recommended default: Terraform because it matches the
   owner's prior experience; this recommendation is not yet an owner decision.
2. Rebaseline P2-P11 dates and set a bounded P2 execution cap/window.
3. Decide temporary bootstrap identity, EKS access boundary, state backend,
   teardown owner and secret-output rules.
4. Recheck current cost/credit/quota evidence before any account mutation.
5. Run the zero-cost `terraform_data` state/dependency micro-lab before creating
   AWS modules or requesting L3 authorization.

## P2 negative boundaries

- Do not install Argo CD, Crossplane, kro, KEDA, Karpenter, Kyverno or OpenCost.
- Do not create RDS, GPU resources, workload node pools or either golden path.
- Do not create a NAT Gateway by default.
- Do not use the current long-lived IAM-user key as workload identity or assume
  it is an approved bootstrap identity.
- Do not run `terraform apply`, create paid AWS resources, request quotas, commit
  or push without the separate authority required by the project constitution.
- Do not mark P2 complete from plan/static evidence. P2 requires one explicitly
  approved create/verify/destroy cycle, orphan audit and owner learning evidence.

## Open decisions and blockers

- P2 spec status, Terraform/OpenTofu choice, exact tool/provider/module pins,
  schedule, gross P2 cap, execution window and teardown owner are not approved.
- Temporary bootstrap identity, EKS access entries and state backend are open.
- Subnet CIDRs, endpoint policy, EKS API CIDR and exact runtime traffic are open.
- The active AWS CLI path uses a long-lived IAM-user key; it is read-only account
  evidence, not approved P2 bootstrap or workload identity.
- Crossplane 2.4.0 with AWS provider 2.7.0, kro on Kubernetes 1.35 and OpenCost on
  Kubernetes 1.35 still lack runtime evidence.
- ADR-0005 remains `PROPOSED` until the later L2 kind micro-lab.
- Crossplane and kro remain without owner hands-on evidence; they are not P2 work.
- The original roadmap dates slipped and must be rebaselined without weakening
  acceptance criteria or hiding the November 2026 release risk.

## Evidence pointers

- Active P2 contract: `.agent/specs/SPEC-P2_REPRODUCIBLE_EKS_BOOTSTRAP.md`
- Canonical implementation scope: `docs/de_cuong_tot_nghiep_ver3.md`
- Roadmap: `.agent/docs/ROADMAP.md`
- P1 learning evidence: `.agent/learning/LEARNING_LOG.md`
- Durable project facts: `.agent/memory/cold_memory.md`
- Milestone history: `.agent/workflows/history_archive.md`
- Bootstrap/platform ownership: `.agent/adr/ADR-0003_BOOTSTRAP_PLATFORM_BOUNDARY.md`
- Local-first proposal: `.agent/adr/ADR-0005_KIND_LOCAL_FIRST_ENVIRONMENT.md`
- Network/cost decision: `.agent/adr/ADR-0006_POC_NETWORK_EGRESS_AND_COST_GUARDRAILS.md`
- Version baseline: `docs/VERSION_MATRIX.md`
- Threat model: `docs/security/THREAT_MODEL.md`
- Cost plan and account evidence: `docs/finops/COST_PLAN.md` and
  `docs/finops/evidence/2026-09-28_ACCOUNT_COST_PREFLIGHT.md`
- Experiment contract: `docs/experiments/EXPERIMENT_PLAN.md`
- NCKH handoff: `docs/research/nckh/NCKH_RESEARCH_CONTEXT.md`
- NCKH proposal draft: `docs/research/nckh/ThuyetMinhDeCuong.md`

## Latest checkpoint evidence

- Current Git HEAD: `92d5471a1d070d5df9ce36ae18eaaddb2e04ba7c`.
- Dirty state before this checkpoint: modified `active_context.md`; untracked P2
  spec and `docs/research/` drafts.
- NCKH content comparison found Sections 8-13 aligned after formatting
  normalization, with administrative differences recorded separately.
- NCKH reference audit verified that all eleven cited works exist, but returned
  `PARTIAL` because of the open corrections listed in Current truth.
- No AWS resource, cluster, controller, IAM policy, Budget or quota request was
  created during P1, the NCKH work or this checkpoint.

## Checkpoint rule

At session end, keep this file as a short current-state index. Move completed
milestones to `history_archive.md`, durable lessons to `cold_memory.md`, and raw
experiment evidence to its evidence directory. Never paste a chat transcript or
long verification chronology here.
