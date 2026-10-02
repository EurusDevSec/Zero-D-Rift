---
project: Zero D-Rift
status: P2_BOUNDED_SCOPE_APPROVED_TASK1_OPEN
active_phase: P2
active_task: P2-T1
active_feature: P2 bootstrap identity, EKS access and break-glass decision
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
- P2 bounded scope and Terraform CLI exact pin `1.16.4` are owner-approved;
  Task 1 remains open. Decisions and sources live in SPEC-P2 Task 1.
- Aggressive P2-P11 rebaseline is owner-approved: ver3 section 12 is canonical,
  with `.agent/docs/ROADMAP.md` as its derived planning view. P2 gate is 06/10.
- The approved bootstrap boundary is Terraform -> VPC/EKS/OIDC/system
  nodes/bootstrap IAM. Platform controllers are later phases.
- Region remains `us-east-1`; the gross project envelope remains 100 USD. Cost,
  credit and quota observations must be rechecked before any account mutation.
- NCKH is parked and cannot expand P2 scope or spending. Its detailed state lives
  under `docs/research/nckh/`, not in this working set.

## Open decisions and blockers

1. Temporary bootstrap identity/session, EKS access entries and break-glass owner.
2. State backend, encryption, locking, recovery and secret-output rules.
3. Fresh gross spend/credit/Region/quota preflight and approved P2 cost cap,
   active AWS window and teardown owner; the schedule does not approve these.
4. Source-checked exact provider/module pins and transitive compatibility;
   candidates remain unapproved (see SPEC-P2 Task 1).
5. CLI installation/upgrade permission is absent; the installed version was
   observed as 1.14.8 at Task 1 preflight, not as the approved 1.16.4 baseline.
6. Read-only diagnosis of the Terraform `%APPDATA%\terraform.d` warning.

## Next safe action

Coach the bootstrap identity/temporary-session decision, EKS access-entry boundary
and break-glass ownership. Produce a reviewed decision plus unresolved blockers.
Do not upgrade the CLI, create a backend, request quota, run `terraform apply`,
mutate AWS, commit or push. L3 approval remains separate from all document approvals.

## Required evidence for the next transition

- Reviewed bootstrap identity/session/access matrix and break-glass owner.
- Exact provider/module sources and compatibility evidence before approval.
- Approved cost cap, AWS window, teardown owner and state-management decisions.
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
