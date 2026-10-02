---
project: Zero D-Rift
status: P2_TASK1_CLOSED_P2_T2_READY_NOT_STARTED
active_phase: P2
active_task: P2-T2
active_feature: Local Terraform state/dependency micro-lab authorization gate
active_spec: .agent/specs/SPEC-P2_REPRODUCIBLE_EKS_BOOTSTRAP.md
current_learning: .agent/learning/CURRENT_STATUS.md
mode: Coach
authority: NO_AWS_APPLY_OR_ACCOUNT_MUTATION
last_reviewed: 2026-10-02
---

# Active Context

This file is the current working-set index, not a transcript or source of truth
for live Git/AWS state. Follow `.agent/references/context-governance.md`.

## Current verified state

- P1 is complete only at documentation/design and `EXPLAINED` learning level.
  No local cluster, EKS cluster, platform controller, workload or project IAM
  policy has runtime evidence.
- P2 Task 1 decisions are owner-approved: scope/pins in SPEC-P2 and its review
  packet, identity/state in accepted ADR-0007, cap/window/owners in COST_PLAN §7.4.
  Task 1 is COMPLETE_WITH_L3_BLOCKERS, Phase1-approved 02/10; P2/learning incomplete.
- Aggressive P2-P11 rebaseline is owner-approved: ver3 section 12 is canonical,
  with `.agent/docs/ROADMAP.md` as its derived planning view. P2 gate is 06/10.
- The approved bootstrap boundary is Terraform -> VPC/EKS/OIDC/system
  nodes/bootstrap IAM. Platform controllers are later phases.
- Region remains `us-east-1`; the gross project envelope remains 100 USD. Cost,
  credit and quota observations must be rechecked before any account mutation.
- NCKH is parked and cannot expand P2 scope or spending. Its detailed state lives
  under `docs/research/nckh/`, not in this working set.

## Open decisions and blockers

1. HARD_BLOCKER before L3: current IAM user MFA count 0; approved MFA/temporary
   AssumeRole and tested independent recovery login are absent/unverified.
2. Installed CLI is 1.14.8; exact 1.16.4 installation/verification needs separate
   authority. Pins remain STATIC_SOURCE_COMPATIBLE, without runtime PASS.
3. EBS credit coverage is UNVERIFIED; price full gross exposure within P2 cap.
   Final gross service MTD/credit/quota scalars live in the preflight evidence.
4. Exact IAM/create permission, backend controls, Task 6 Budget control, priced
   plan, Tasks 2–6 and fresh account preflight remain before-L3 requirements.
5. Terraform denial observed only in Codex; owner warning not reproduced and
   directory accessible. Exact mechanism unproven; no global repair claimed.
6. P2-T2 is READY_NOT_STARTED; no lab or new learning evidence exists.

## Next safe action

Obtain separate owner authorization to install and verify exact Terraform 1.16.4
before generating P2-T2 lab evidence. Coach lab remains READY_NOT_STARTED.
This handoff authorizes no installation, Terraform command or lab execution, backend,
IAM/Budget/resource mutation, quota request, AWS apply, commit or push.

## Required evidence for the next transition

- Separate install/verification approval, official checksum and exact CLI version.
- Future Task 2 L1 evidence: owner prediction, observed state/plan/re-plan/destroy
  and explanation; no AWS/EKS runtime claim from that lab.
- Before L3: MFA/temporary/recovery, IAM/backend/Budget controls, exact priced plan,
  fresh account preflight and explicit execution approval remain required.

## Context expansion

- Current contract: read SPEC-P2 Goal/boundaries, Task 2, verification tiers and
  completion rule. Read the full spec for phase-wide approval.
- Ownership: `.agent/adr/ADR-0003_BOOTSTRAP_PLATFORM_BOUNDARY.md`.
- Network/cost: `.agent/adr/ADR-0006_POC_NETWORK_EGRESS_AND_COST_GUARDRAILS.md`
  and `docs/finops/COST_PLAN.md` when deciding the P2 cap or AWS plan.
- Durable facts: `.agent/memory/cold_memory.md` only when the task needs them.
- Learning history and workflow history are on-demand audit sources, not startup reads.

## Live-state rule

Run `git status --short` and `git rev-parse HEAD` at session start and checkpoint.
The working tree may contain owner-reviewed or untracked work; never infer current
state from an embedded hash and never discard changes to make a checkpoint match.

## Checkpoint rule

Rewrite this file around the next safe action. Promote durable decisions to ADRs,
results to evidence, learning to the learning files and completed milestones to
history. Remove expired detail, then run `.agent/scripts/check-context.ps1`.
