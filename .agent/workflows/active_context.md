---
project: Zero D-Rift
status: PHASE_1_ACTIVE
active_phase: P1
active_feature: Foundation and compatibility decisions
active_spec: .agent/specs/SPEC-P1_FOUNDATION_AND_COMPATIBILITY.md
roadmap: .agent/docs/ROADMAP.md
architecture: .agent/docs/ARCHITECTURE.md
canonical_scope: docs/de_cuong_tot_nghiep_ver3.md
learning_plan: .agent/learning/LEARNING_ROADMAP.md
learning_log: .agent/learning/LEARNING_LOG.md
cold_memory: .agent/memory/cold_memory.md
git_head: 2a5e6a4dcca3be4e54ad874f30003d815fcde240
git_state: DIRTY_EXPECTED_P1_HANDOFF_FIXES
last_verification: PASS_P1_HANDOFF_AUDIT_2026-08-23
last_updated: 2026-08-23
---

# Active Context

## Current truth

- Project planning begins on 23/08/2026; application and infrastructure
  implementation have not started.
- `docs/de_cuong_tot_nghiep_ver3.md` is canonical, tracked and pushed.
- Teacher feedback was already incorporated into ver2; ver3 is the implementation
  optimization of ver2. No repeated full alignment review is required for P1.
- Root `AGENTS.md` and `.agent/` are the self-contained project workflow. The
  reusable framework source was removed in commit `2a5e6a4`.
- P0 creates documentation and agent workflow only. It does not provision AWS or
  mark any thesis feature as implemented.
- The final P1 handoff corrections have passed static validation but are not yet
  committed; review and persist them before opening the long-running P1 chat.

## Active objective

Complete P1 between 24–30/08/2026: review architecture boundaries, establish
official-version compatibility, define baseline/experiment schema, document the
threat model, and approve the cost/quota plan.

## Next actions

1. Review, commit and push the validated P1 handoff corrections when explicitly
   requested; do not use `git add .`.
2. Open the dedicated P1 chat and run `/resume`.
3. Start Task 2: system design and architectural ADRs.
4. Use Coach mode for EKS architecture, IAM and reconciliation learning.

## Known blockers and unknowns

- Exact AWS account credit applicability and service quota are not yet verified.
- Component versions and compatibility are not yet pinned.
- AWS Region and network egress design are not yet approved.
- Crossplane and kro have not yet been practiced by the owner.

## Evidence pointers

- Canonical requirements: `docs/de_cuong_tot_nghiep_ver3.md`
- Teacher feedback: `docs/governance/gop_y_de_cuong_tu_thay_Kiet.md`
- Initialized roadmap: `.agent/docs/ROADMAP.md`
- Detailed current work: `.agent/specs/SPEC-P1_FOUNDATION_AND_COMPATIBILITY.md`
- P0 project-agent commit: `52c02ce`.
- Framework removal and remote sync: `2a5e6a4`.
- Framework-removal decision: `.agent/adr/ADR-0002_SELF_CONTAINED_PROJECT_AGENT.md`.
- P1 handoff audit: clean Git state, required pointers present, governance/archive
  files content-identical to their original versions, six valid skills and no
  whitespace errors. The resulting documentation corrections are currently dirty.
- Governance lineage confirmation: feedback -> ver2 -> ver3; Task 1 is closed.

## Checkpoint rule

At session end, replace current status with observed results, exact verification
commands, evidence paths, current Git HEAD/dirty state, blockers, and the next
small action. Never paste a complete chat transcript into this file.
