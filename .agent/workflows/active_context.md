---
project: Zero D-Rift
status: P4_T1_PINS_RECORDED
active_phase: P4
active_task: P4-T1 closing (DRF-40), then P4-T2.1 (DRF-45)
active_feature: RAGSandbox (SPEC-P4)
active_spec: .agent/specs/SPEC-P4_RAG_SANDBOX.md
current_learning: .agent/learning/CURRENT_STATUS.md
mode: Coach
authority: NO_INSTALL_NO_AWS_APPLY_UNTIL_TASK_GATES
last_reviewed: 2026-11-17
---

# Active Context

Current-state index, not scope, live AWS inventory or a transcript.
Follow [context governance](../references/context-governance.md).

## Current verified state

- P2 accepted 05/11/2026 (evidence `docs/evidence/p2/`).
- P3 done 14/11/2026 (PR #31, `114a7da`): L3 window P3-L3-20261105-01 passed
  on EKS, inventory CLEAN 05/11 and 06/11; audit
  `docs/evidence/p3/DRF38_P3_ACCEPTANCE_AUDIT_20261106.md` (Codex APPROVE,
  teach-back 6/6 with a provenance limit). PR #28 `recurse` fix verified on
  kind only, not on EKS.
- Learning: Terraform and Argo CD/kro/Crossplane `PRACTICED` + `EXPLAINED`
  (controllers with a provenance limit, audit §6.5).
- AWS holds only the retain allowlist: Terraform state bucket, role
  `zero-drift-bootstrap`, MFA device. No cluster, no P3 role.
- R1 least privilege deferred; it lacks the `zero-drift-p3-*` role and
  `PutRolePolicy`. Redo before DRF-27 (19/11) or at DRF-29.
- Tools: Terraform 1.16.4, kubectl v1.35.10 (`/r/_Dev_tools/kubectl`), kind
  v0.33.0 (`/r/_Dev_tools/kind`, default node v1.37.0, so always pass `--image`),
  Helm v4.2.2.
- SPEC-P4 `OWNER_APPROVED_20261114`: owner approved D1–D12 and the 5 USD P4
  cap ("Duyệt cả 12"), after Codex review APPROVE at `358da73` (three rounds,
  SPEC §9.4). Merged in PR #33 (`7dcaa44`). Nothing for P4 is built.
- ADR-0008 `ACCEPTED` 14/11 (Codex APPROVE at `8036e44`; owner "Chấp nhận
  ADR-0008"): Terraform owns shared RDS and every P4 role; direct SDK through
  IRSA; master/bootstrap only in `zdr-platform`. Runtime still `UNVERIFIED`.
  Merged in PR #34 (`df275e4`).
- kro spike on kind 14/11 (DRF-40 part B): externalRef across namespaces, Job
  in `zdr-platform`, `readyWhen` on a Job and rename pruning all PASS, including
  fail after success → not Ready. New: kro leaves deleted Jobs' Pods orphaned;
  SPEC §10/D9 cleanup deletes them by label. Evidence
  `docs/evidence/p4/P4-T1_KRO_SPIKE_20261114.md`, runbook `docs/runbooks/P4_L2_KIND_LAB.md`.
  Merged in PR #35 (main `1d68e54`).
- P4 pins 17/11 (DRF-40 B, owner's read-only CLI): RDS PostgreSQL 17.11,
  pgvector 0.8.2, `t4g.micro` gp3, `force_ssl=1`; prices unchanged. VERSION_MATRIX
  §8, evidence `docs/evidence/p4/P4-T1_PINS_PRICES_20261117.md`. Not merged.
- ADR-0009 `ACCEPTED` 17/11 (PR #36, `1277f7c`): AWS refused the G/VT quota
  twice, so P6 BatchTrainingJob runs on CPU nodes; limits recorded in the ADR
  and COST_PLAN §7.3.1. No AWS action authorised by it.
- [Linear routing](../docs/LINEAR_DELIVERY.md): P4 = 10 issues. DRF-40 (P4-T1,
  no sub-tasks); DRF-44 (P4-T2) → DRF-45, 46; DRF-49 (P4-T3) → DRF-50, 51;
  DRF-55 (P4-T4) → DRF-56, 57. Other DRF-41..63 and DRF-16/17 cancelled.

## Open decisions and blockers

1. Carried from P3 (not gates): re-ask teach-back Q3–Q5 orally at P11; endpoint
   check 7 only type-checks `aws:ResourceAccount` (fix with R1).
2. Schedule: P4 gate was 08/11, P6 14/11, P8 freeze 19/11. The 15/11 P4
   target was missed; owner's new P4 target is 17/11/2026 (set 17/11). Still
   open on 17/11: DRF-40 merge, DRF-44/45/46, DRF-49/50/51 and the L3 window plus
   acceptance (DRF-55/56/57). Ver3 §12.1 still forbids reducing trials,
   acceptance, learning gate or teardown to meet it. Full rebaseline of P5–P11
   is the owner's decision.
3. ADR-0005 still PROPOSED (owner review).
4. SPEC approval is not AWS approval: every P4 window still needs its own
   execution approval, cost check and stop time (SPEC negative boundary 10).

## Next safe action

Owner reviews and merges branch `hoang/drf-40-pins-prices` (DRF-40 parts A–C
all ticked; Done needs owner acceptance). Then DRF-45 (SQL entry points and
kind DB lab with the pinned pgvector image) and DRF-50 (reference app on the
pinned Python base), kind only, no AWS.

## Context expansion

Use SPEC-P4, ver3 §6.3–6.4 and §12, ADR-0003/0004/0006, THREAT_MODEL §6.5,
EXPERIMENT_PLAN §6, LEARNING_ROADMAP row P4. Live Git overrides this file.

## Checkpoint rule

Rewrite this index, update learning only from demonstration, run
check-context.sh and report actual Git/external state separately.
