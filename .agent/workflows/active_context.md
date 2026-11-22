---
project: Zero D-Rift
status: P4_T4_2_REREVIEW_FIXES
active_phase: P4
active_task: P4-T4.2 (DRF-57) Codex re-review 22/11 fixes (R1 R2); Codex check, Bills, close P4
active_feature: RAGSandbox (SPEC-P4)
active_spec: .agent/specs/SPEC-P4_RAG_SANDBOX.md
current_learning: .agent/learning/CURRENT_STATUS.md
mode: Coach
authority: NO_INSTALL_NO_AWS_APPLY_UNTIL_TASK_GATES
last_reviewed: 2026-11-21
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
- Tools: Terraform 1.16.4, kubectl v1.35.10, kind v0.33.0 (always pass `--image`), Helm v4.2.2.
- SPEC-P4 `OWNER_APPROVED_20261114`: owner approved D1–D12 and the 5 USD P4
  cap ("Duyệt cả 12"), after Codex review APPROVE at `358da73` (three rounds,
  SPEC §9.4). Merged in PR #33 (`7dcaa44`).
- ADR-0008 `ACCEPTED` 14/11 (Codex APPROVE at `8036e44`; owner "Chấp nhận
  ADR-0008"): Terraform owns shared RDS and every P4 role; direct SDK through
  IRSA; master/bootstrap only in `zdr-platform`. Runtime `UNVERIFIED` (PR #34).
- DRF-40 done: kro spike 4/4 PASS on kind, kro
  orphans deleted Jobs' Pods so D9 cleanup deletes them by label (PR #35);
  pins RDS 17.11, pgvector 0.8.2, prices unchanged, VERSION_MATRIX §8 (PR #37,
  `ef04ca3`). Evidence `docs/evidence/p4/P4-T1_*`.
- DRF-45 done (PR #38, `39856e9`): db-init/bootstrap/cleanup; owner lab D1–D7
  PASS. Learning gaps in `P4-T2.1_L2_KIND_DB_20261119.md` (D2, D4, D5/D6).
- DRF-50 (PR #39, #40; time-bound fix PR #43): image
  `rag-sandbox@sha256:850c77c2…` from `e0c8319` (22/11; window 21/11 ran `512e982a…`).
  DRF-46 (PR #41, `27058f9`): `shared-rds`, `rag-identity`; static only.
- DRF-51 done (PR #42, `2db156a`, CI `static-gates` PASS): RGD `rag-sandbox`
  (bucket/SA/app/service wait for the bootstrap Job), tenants app, kro RBAC,
  requests + 2 negatives, check.sh rules 8-12 + 29 guards. Kind graph: Claude
  dry run PASS; owner run 21/11 G3-G11 with predictions (G11 missed what kro
  leaves behind). Owner skipped the explanation questions (open gap, re-ask
  before DRF-57). DRF-44/46/50/51 Done in Linear; DRF-49 open until DRF-56 bucket.
- DRF-56 window `P4-L3-20261121-01` (21/11, 08:15-09:40Z): 65 added, B-E PASS (C: sts output open) on
  EKS (probe platform/sandbox/cross, G2 both layers, G3, retry: cause via kubectl, attempt via Git; cleanup),
  one fix PR #46 (`AWS_DEFAULT_REGION`); destroy 65, inventory CLEAN; est. 0.50 USD.
  Evidence `docs/evidence/p4/P4-T4.1_L3_WINDOW_20261121.md` (PR #53).
- ADR-0009 `ACCEPTED` 17/11 (PR #36): G/VT quota refused, P6 runs on CPU nodes.
- [Linear routing](../docs/LINEAR_DELIVERY.md): P4 = 10 issues. DRF-40 (P4-T1,
  no sub-tasks); DRF-44 (P4-T2) → DRF-45, 46; DRF-49 (P4-T3) → DRF-50, 51;
  DRF-55 (P4-T4) → DRF-56, 57. Other DRF-41..63 and DRF-16/17 cancelled.

## Open decisions and blockers

1. Carried from P3 (not gates): re-ask teach-back Q3–Q5 orally at P11; endpoint
   check 7 only type-checks `aws:ResourceAccount` (fix with R1).
2. Schedule: P4 gate was 08/11; owner's P4 target 17/11 was missed. Open on
   21/11: the L3 window and acceptance (DRF-55/56/57). Ver3 §12.1 forbids
   reducing trials, acceptance, learning gate or teardown to meet a date. Full
   rebaseline of P5–P11 is the owner's decision.
3. ADR-0005 still PROPOSED (owner review).
4. SPEC approval is not AWS approval: every P4 window still needs its own
   execution approval, cost check and stop time (SPEC negative boundary 10).

## Next safe action

DRF-57: audit `docs/evidence/p4/P4_ACCEPTANCE_AUDIT_20261121.md`. Codex REQUEST
CHANGES (10 findings) fixed with negative tests, PR #55 merged. New image pinned.
Confirm window P4-L3-20261122-01 (02:56-04:00Z): V1-V6 PASS, sts line kept,
65 destroyed, inventory CLEAN, est. 0.37 USD (`P4-T4.2_L3_CONFIRM_20261122.md`).
Codex re-review 22/11: REQUEST CHANGES, 2 MEDIUM 2 LOW (audit 5.2). R1 cleanup
read after Job, R2 CI rejects jsonnet/List, R4 R5 wording fixed with tests;
R3 GetBucketLocation kept as accepted limit (audit 5.3). Next: Codex checks
R1 R2; owner reads Bills gross both windows; inventory next day; learning. Re-ask 4 explanation questions + orphan Pod.

## Context expansion

Use SPEC-P4, ver3 §6.3–6.4 and §12, ADR-0003/0004/0006, THREAT_MODEL §6.5,
EXPERIMENT_PLAN §6, LEARNING_ROADMAP row P4. Live Git overrides this file.

## Checkpoint rule

Rewrite this index, update learning only from demonstration, run
check-context.sh and report actual Git/external state separately.
