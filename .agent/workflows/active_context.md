---
project: Zero D-Rift
status: P4_SPEC_DRAFT_REVIEW_PENDING
active_phase: P4
active_task: P4-T1 part A, SPEC-P4 Codex re-check and owner approval (DRF-40)
active_feature: RAGSandbox (SPEC-P4)
active_spec: .agent/specs/SPEC-P4_RAG_SANDBOX.md
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
- P3 done 14/11/2026 (owner merged PR #31, `114a7da`). Audit
  `docs/evidence/p3/DRF38_P3_ACCEPTANCE_AUDIT_20261106.md`: billing (month
  pre-tax 0.00 USD, us-east-1 0.29 USD), Codex review (1 MEDIUM guard finding,
  fixed with negative tests, re-check APPROVE), owner teach-back 6/6 with a
  provenance limit.
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
- SPEC-P4 drafted 14/11 (`DRAFT_OWNER_REVIEW_PENDING`), decisions D1–D12.
  Codex review 1 at `4431368`: REQUEST_CHANGES, 2 MAJOR (bootstrap fallback into
  tenant namespace; no retry for a `Failed` Job). Re-check at `4c23916`: both
  fixed, 1 new MAJOR (`readyWhen` fallback could fake Ready), fixed at
  `358da73`; Codex re-check APPROVE. Owner approval pending. Nothing for P4 is
  built.
- [Linear routing](../docs/LINEAR_DELIVERY.md): P4 = 10 issues. DRF-40 (P4-T1,
  no sub-tasks); DRF-44 (P4-T2) → DRF-45, 46; DRF-49 (P4-T3) → DRF-50, 51;
  DRF-55 (P4-T4) → DRF-56, 57. Other DRF-41..63 and DRF-16/17 cancelled.

## Open decisions and blockers

1. Carried from P3 (not gates): re-ask teach-back Q3–Q5 orally at P11; endpoint
   check 7 only type-checks `aws:ResourceAccount` (fix with R1).
2. Schedule: P4 gate was 08/11, P6 14/11, P8 freeze 19/11. Ver3 §12.1 requires a
   rebaseline from live state without reducing trials, acceptance, learning gate
   or teardown. Rebaseline is the owner's decision.
3. ADR-0005 still PROPOSED (owner review).
4. SPEC-P4 §9.1 D1–D12 need the owner's decision (Codex review done).
   P4 code, image, Terraform and any AWS window wait for that. D8 (public image
   on GHCR) and D10 (5 USD cap) are the two with outside effect.

## Next safe action

Owner decides D1–D12 and the P4 cap (DRF-40 part A), then merges PR #33. After that: DRF-40 part B (pins and prices, owner's read-only session)
and part C (ADR-0008).

## Context expansion

Use SPEC-P4, ver3 §6.3–6.4 and §12, ADR-0003/0004/0006, THREAT_MODEL §6.5,
EXPERIMENT_PLAN §6, LEARNING_ROADMAP row P4. Live Git overrides this file.

## Checkpoint rule

Rewrite this index, update learning only from demonstration, run
check-context.sh and report actual Git/external state separately.
