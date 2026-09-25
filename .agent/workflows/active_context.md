---
project: Zero D-Rift
status: PHASE_1_ACTIVE
active_phase: P1
active_feature: Version and compatibility spike
active_spec: .agent/specs/SPEC-P1_FOUNDATION_AND_COMPATIBILITY.md
roadmap: .agent/docs/ROADMAP.md
architecture: .agent/docs/ARCHITECTURE.md
canonical_scope: docs/de_cuong_tot_nghiep_ver3.md
learning_plan: .agent/learning/LEARNING_ROADMAP.md
learning_log: .agent/learning/LEARNING_LOG.md
cold_memory: .agent/memory/cold_memory.md
git_head: 8e8d0e1974f1ef12147c293a08c5562fb1052a09
git_state: DIRTY_EXPECTED_P1_TASK2_CHECKPOINT
last_verification: PASS_TASK2_DOCUMENTATION_L0_2026-09-25
last_updated: 2026-09-25
---

# Active Context

## Current truth

- Application and infrastructure implementation have not started; no AWS resource
  or platform controller was created during P1 Task 2.
- `docs/de_cuong_tot_nghiep_ver3.md` is canonical, tracked and pushed.
- Teacher feedback was already incorporated into ver2; ver3 is the implementation
  optimization of ver2. No repeated full alignment review is required for P1.
- Root `AGENTS.md` and `.agent/` are the self-contained project workflow. The
  reusable framework source was removed in commit `2a5e6a4`.
- P1 Task 1 governance lineage is closed.
- P1 Task 2 functional and learning gates are complete: the system design exists,
  ADR-0003 and ADR-0004 are accepted, and the owner demonstrated the architecture
  boundaries and relevant failure diagnosis at `EXPLAINED` level.
- The Task 2 review/checkpoint changes are intentionally dirty and require owner
  review before any explicit commit or push.

## Active objective

Continue P1 with Task 3: establish official-version compatibility and keep every
unsupported selection marked `UNVERIFIED` before P2 bootstrap planning.

## Next actions

1. Review the current Task 2 checkpoint diff; commit/push only when explicitly
   requested and never use `git add .`.
2. Start Task 3 by creating the `docs/VERSION_MATRIX.md` skeleton with all
   selections initially marked `UNVERIFIED`.
3. Verify EKS/Kubernetes and AL2023 availability from current official AWS sources
   before pinning versions.
4. Continue the compatibility spike for Argo CD, Crossplane provider packages,
   kro, KEDA, Karpenter, Kyverno and OpenCost without installing them.

## Known blockers and unknowns

- Exact AWS account credit applicability and service quota are not yet verified.
- Component versions and compatibility are not yet pinned.
- AWS Region and network egress design are not yet approved.
- Local-first environment (`kind` or `k3d`) is not yet selected.
- Crossplane and kro have not yet been practiced hands-on by the owner.
- The original P1 calendar window has elapsed and must be rebaselined without
  weakening its acceptance criteria.

## Evidence pointers

- Canonical requirements: `docs/de_cuong_tot_nghiep_ver3.md`
- Teacher feedback: `docs/governance/gop_y_de_cuong_tu_thay_Kiet.md`
- Initialized roadmap: `.agent/docs/ROADMAP.md`
- Detailed current work: `.agent/specs/SPEC-P1_FOUNDATION_AND_COMPATIBILITY.md`
- Reviewed system design: `docs/architecture/SYSTEM_DESIGN.md`
- Accepted bootstrap/platform boundary: `.agent/adr/ADR-0003_BOOTSTRAP_PLATFORM_BOUNDARY.md`
- Accepted shared-RDS/recovery boundary: `.agent/adr/ADR-0004_SHARED_RDS_AND_RECOVERY_DATABASE.md`
- Task 2 learning evidence: `.agent/learning/LEARNING_LOG.md`
- P0 project-agent commit: `52c02ce`.
- Framework removal and remote sync: `2a5e6a4`.
- Framework-removal decision: `.agent/adr/ADR-0002_SELF_CONTAINED_PROJECT_AGENT.md`.
- Governance lineage confirmation: feedback -> ver2 -> ver3; Task 1 is closed.
- Task 2 L0 verification on 2026-09-25: `git diff --check`; ADR frontmatter/status
  and unique IDs checked; referenced evidence paths found; no trailing whitespace.
- Git at checkpoint: HEAD `8e8d0e1974f1ef12147c293a08c5562fb1052a09`,
  dirty only with the reviewed Task 2 documentation/checkpoint set.

## Checkpoint rule

At session end, replace current status with observed results, exact verification
commands, evidence paths, current Git HEAD/dirty state, blockers, and the next
small action. Never paste a complete chat transcript into this file.
