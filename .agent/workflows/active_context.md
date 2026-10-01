---
project: Zero D-Rift
status: PHASE_1_COMPLETE_P2_SPEC_REVIEW
active_phase: P2
active_task: P2-T1
active_feature: P2 approval, tool pin and zero-cost preflight
active_spec: .agent/specs/SPEC-P2_REPRODUCIBLE_EKS_BOOTSTRAP.md
current_learning: .agent/learning/CURRENT_STATUS.md
mode: Coach
authority: NO_AWS_APPLY_OR_ACCOUNT_MUTATION
last_reviewed: 2026-10-01
---

# Active Context

This file is the current working-set index, not a transcript or source of truth
for live Git/AWS state. Follow `.agent/references/context-governance.md`.

## Current verified state

- P1 is complete only at documentation/design and `EXPLAINED` learning level.
  No local cluster, EKS cluster, platform controller, workload or project IAM
  policy has runtime evidence.
- P2 is active, but its spec remains `DRAFT_FOR_OWNER_APPROVAL`; this does not
  authorize implementation or paid AWS work.
- The approved bootstrap boundary is Terraform -> VPC/EKS/OIDC/system
  nodes/bootstrap IAM. Platform controllers are later phases.
- Region remains `us-east-1`; the gross project envelope remains 100 USD. Cost,
  credit and quota observations must be rechecked before any account mutation.
- NCKH is parked and cannot expand P2 scope or spending. Its detailed state lives
  under `docs/research/nckh/`, not in this working set.

## Open decisions and blockers

1. Owner approval of bounded P2 scope. Terraform is selected; approval of this
   tool choice does not approve implementation or AWS mutation.
2. Source-checked Terraform CLI/provider/module pins.
3. Rebaselined P2-P11 dates and bounded P2 cap/window/teardown owner.
4. Temporary bootstrap identity, EKS access entries and break-glass boundary.
5. State backend, encryption, locking, recovery and secret-output rules.
6. Read-only diagnosis of the Terraform `%APPDATA%\terraform.d` warning.

## Next safe action

Review P2 Task 1 one decision at a time, beginning with bounded scope approval
and the exact Terraform CLI pin.
Produce an approved decision record plus unresolved-blocker list. Do not create a
backend, request quota, run `terraform apply`, create AWS resources, commit or push.

## Required evidence for the next transition

- Owner-approved P2 scope/tool decision.
- Official source links for selected version pins.
- Rebaselined schedule and explicit cost/teardown ownership.
- Reviewed identity/access and state-management decisions.
- Fresh redacted account preflight immediately before any later L3 request.

## Context expansion

- Current contract: read SPEC-P2 Goal/boundaries, Task 1, verification tiers and
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
