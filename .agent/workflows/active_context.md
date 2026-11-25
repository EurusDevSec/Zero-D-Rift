---
project: Zero D-Rift
status: P6_SPEC_CANDIDATE
active_phase: P6 (P5 technically done 25/11; inventory and Bills 26/11)
active_task: P6-T1 contract (DRF-73); P5-T4.3 close-out (DRF-72) on 26/11
active_feature: BatchTrainingJob on CPU (SPEC-P6, ADR-0009)
active_spec: .agent/specs/SPEC-P6_BATCH_TRAINING_JOB.md
current_learning: .agent/learning/CURRENT_STATUS.md
mode: Coach
authority: NO_INSTALL_NO_AWS_APPLY_UNTIL_TASK_GATES
last_reviewed: 2026-11-25
---

# Active Context

Current-state index, not scope, live AWS inventory or a transcript.
Follow [context governance](../references/context-governance.md).

## Current verified state

- P2 accepted 05/11 (`docs/evidence/p2/`). P3 done 14/11 (PR #31, audit
  `docs/evidence/p3/DRF38_P3_ACCEPTANCE_AUDIT_20261106.md`).
- AWS holds only the retain allowlist: Terraform state bucket, role
  `zero-drift-bootstrap`, MFA device. No cluster.
- R1 least privilege still deferred (no `zero-drift-p3-*` role, no `PutRolePolicy`).
- Tools: Terraform 1.16.4, kubectl v1.35.10, kind v0.33.0 (always pass `--image`), Helm v4.2.2.
- ADR-0008 `ACCEPTED` 14/11; ADR-0009 `ACCEPTED` 17/11 (P6 on CPU nodes).
- **P4 technically done** (audit `docs/evidence/p4/P4_ACCEPTANCE_AUDIT_20261121.md`):
  windows `P4-L3-20261121-01` and `P4-L3-20261122-01`, 65 destroyed, inventory
  CLEAN; Codex APPROVE at `70ad8d8` (audit 5.4); `fec7847` (Copilot follow-up)
  not Codex-checked. Teach-back: all SPEC-P4 §8 targets met, including transfer
  cases A and B (`P4-T4.2_TEACHBACK_20261121.md`, PR #60).
- **SPEC-P5** `OWNER_APPROVED_20261122` (PR #61, #62); Codex APPROVE at `26d3481`.
- [Linear routing](../docs/LINEAR_DELIVERY.md): P4 = 10 issues, DRF-40,
  DRF-44 → 45/46, DRF-49 → 50/51, DRF-55 → 56/57. P5 = 9 issues created 22/11:
  DRF-64 (T1), DRF-65 → 66/67, DRF-68 (T3), DRF-69 → 70/71/72, due 23/11;
  DRF-18 cancelled as superseded.

## Drafts and local records (read before writing anything new)

- **Fable 5.2 SPEC drafts P6–P9** (16/11, owner request) on branch
  `claude/specs-p5-p9-draft-ecc762`, not merged. At each phase gate start from
  that draft and recheck it against `main`; never write a new SPEC from
  scratch. SPEC-P6 predates ADR-0009 and must follow it. Index:
  `docs/README.md` §3.
- **Owner side-chat records** (21/11, committed in PR #63):
  `.agent/references/AI_INFRA_COST.md` (cost-motivation sources with a
  reliability column), `docs/learning/` (visual explorer), and the repo-map
  rewrite of `docs/README.md`. They record real owner discussions, not agent
  invention. Do not delete or overwrite them; cite a claim only at the
  reliability its own row states.

## Open decisions and blockers

1. Rebaseline done 25/11 (SPEC-P6 D13, ROADMAP); the internal 02/12 target
   moved to 14/12 and the school dates are still UNCONFIRMED; ver3 §12.1 forbids
   cutting trials, acceptance, learning gate or teardown. D12 (branch
   protection) deferred by the owner, so T01 stays an open limit.
2. P4 closed: billing (Bills gross 0.73 USD, audit §6.1), delayed inventory
   CLEAN 24/11 06:20Z (audit §6.2), Linear P4 issues Done 24/11. RDS 0.12 and
   Glue to inspect, not gating.
6. Kyverno findings F1–F6 (SPEC-P5 §10): a graceful scale-down removes the
   webhooks (admission open); only "unreachable" fails closed. Decided 25/11
   (owner delegated to Claude): §4 split into two scenarios, both met on EKS.
3. Carried from P3 (not gates): re-ask teach-back Q3–Q5 at P11; endpoint check 7
   only type-checks `aws:ResourceAccount` (fix with R1).
4. ADR-0005 still PROPOSED (owner review).
5. SPEC approval is not AWS approval: every window needs its own execution
   approval, cost check, stop time and teardown owner.

## Next safe action

P5: technical gate met 25/11 (audit `docs/evidence/p5/P5_ACCEPTANCE_AUDIT_20261125.md`,
Codex APPROVE, teach-back 8/8). Open for DRF-72: delayed inventory and Bills
gross on 26/11, then Linear DRF-69/71/72 Done.

P6 started 25/11 (owner: "mai là xong phase 6"). Owner rebaseline recorded as
SPEC-P6 D13 and ROADMAP "Rebaseline 25/11": P6 25–26/11 (overflow 27/11), P7
27–28/11, P8 29/11–01/12 (freeze), P9 02–07/12, P10 08–11/12, P11 12–14/12;
Linear milestone targets match. SPEC-P6 candidate from the Fable draft, CPU per
ADR-0009, one L3 window. Codex 25/11: review (9 findings) and re-review at
`1c24bda` (5 more), both REQUEST CHANGES, all applied (SPEC §9.3, R3); PR #90
awaits another Codex re-review and owner approval of D1–D14.
Linear: DRF-73 (T1), DRF-74 → 75/76 (T2), DRF-77 (T3), DRF-78 → 79/80/81 (T4);
DRF-19/20 cancelled. Runbooks `docs/runbooks/P6_L2_KIND_KEDA.md` and
`docs/runbooks/P6_L3_WINDOW.md` are plans until the code of T2/T3 exists.
Next: owner approves D1–D14, then P6-T2.1 (worker and image) and P6-T3
(Terraform) in parallel, then T2.2 (RGD, KEDA, kind lab).

## Context expansion

Use SPEC-P6, ADR-0009, THREAT_MODEL §6.4 and §11, ver3 §6.5, §9.2 and §12,
ADR-0003/0006/0008, P5 audit §3.1 and §4, LEARNING_ROADMAP row P6. Live Git overrides this file.

## Checkpoint rule

Rewrite this index, update learning only from demonstration, run
check-context.sh and report actual Git/external state separately.
