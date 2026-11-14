---
project: Zero D-Rift
status: P3_GATES_EVIDENCED_OWNER_CLOSE_PENDING
active_phase: P4
active_task: P4-T0 SPEC draft (DRF-16, DRF-17)
active_feature: P3 close (DRF-38, PR #31), then SPEC-P4 RAGSandbox
active_spec: .agent/specs/SPEC-P3_FIRST_RESOURCE_GRAPH.md
current_learning: .agent/learning/CURRENT_STATUS.md
mode: Coach
authority: NO_INSTALL_NO_AWS_APPLY_UNTIL_TASK_GATES
last_reviewed: 2026-11-14
---

# Active Context

Current-state index, not scope, live AWS inventory or a transcript.
Follow [context governance](../references/context-governance.md).

## Current verified state

- P2 accepted 05/11/2026 (evidence `docs/evidence/p2/`).
- P3 Tasks 1–5 done (DRF-34, DRF-39, DRF-35, DRF-36, DRF-37). L3 window
  P3-L3-20261105-01 passed on EKS; destroy 52; inventory CLEAN 05/11 and delayed
  inventory CLEAN 06/11. Evidence `docs/evidence/p3/`.
- P3 §8 gates evidenced 14/11 (audit
  `docs/evidence/p3/DRF38_P3_ACCEPTANCE_AUDIT_20261106.md`): billing (month
  pre-tax 0.00 USD, us-east-1 0.29 USD), Codex review (REQUEST CHANGES, 1 MEDIUM
  guard finding fixed in PR #31 with negative tests), owner teach-back 6/6.
  Closes when the owner merges PR #31 and accepts the limits.
- PR #28 `recurse` fix verified on kind (root Synced at `ee34db4`), not on EKS.
- Learning: Terraform and Argo CD/kro/Crossplane `PRACTICED` + `EXPLAINED`
  (controllers with a provenance limit, audit §6.5).
- AWS holds only the retain allowlist: Terraform state bucket, role
  `zero-drift-bootstrap`, MFA device. No cluster, no P3 role.
- R1 least privilege deferred; it lacks the `zero-drift-p3-*` role and
  `PutRolePolicy`. Redo before DRF-27 (19/11) or at DRF-29.
- Tools: Terraform 1.16.4, kubectl v1.35.10 (`/r/_Dev_tools/kubectl`), kind
  v0.33.0 (`/r/_Dev_tools/kind`, default node v1.37.0, so always pass `--image`),
  Helm v4.2.2.
- [Linear routing](../docs/LINEAR_DELIVERY.md): P3 = DRF-14, DRF-15; P4 = DRF-16,
  DRF-17 (no SPEC yet).

## Open decisions and blockers

1. P3 close: owner merges PR #31 and accepts the limits (billing month total only,
   Codex has not re-checked the fix, teach-back provenance).
2. Schedule: P4 gate was 08/11, P6 14/11, P8 freeze 19/11. Ver3 §12.1 requires a
   rebaseline from live state without reducing trials, acceptance, learning gate
   or teardown. Rebaseline is the owner's decision.
3. ADR-0005 still PROPOSED (owner review).
4. SPEC-P4 does not exist; P4 implementation and any AWS window wait for it.

## Next safe action

Draft SPEC-P4 (RAGSandbox: shared RDS PostgreSQL/pgvector, IRSA S3 prefix,
usable status) from ver3 §P4 and roadmap row P4; request Codex review before
implementation. Carried P3 gates can close in parallel.

## Context expansion

Use ver3 §12 (schedule, scope gates), LEARNING_ROADMAP row P4, SPEC-P3 as the
template, DRF38 audit for carried gates. Live Git overrides this file.

## Checkpoint rule

Rewrite this index, update learning only from demonstration, run
check-context.sh and report actual Git/external state separately.
