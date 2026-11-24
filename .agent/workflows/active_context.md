---
project: Zero D-Rift
status: P5_SPEC_OWNER_APPROVED
active_phase: P5 (P4 closed 24/11)
active_task: owner L2 labs done 24/11 except Kyverno step 2b (DRF-67); then Codex review and L3 window request (P5-T4.2)
active_feature: Tenant guardrails (SPEC-P5)
active_spec: .agent/specs/SPEC-P5_TENANT_GUARDRAILS.md
current_learning: .agent/learning/CURRENT_STATUS.md
mode: Coach
authority: NO_INSTALL_NO_AWS_APPLY_UNTIL_TASK_GATES
last_reviewed: 2026-11-24
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
- **SPEC-P5** merged (PR #61, #62, `183a553`): Fable 5.2 draft of 16/11 kept as
  first commit, rechecked 22/11 against P4 (A8 false → same-namespace ingress
  and egress on 8080; A6 unmeasured). Codex review 1 REQUEST CHANGES fixed;
  review 2 APPROVE at `26d3481` (SPEC §9.3). Owner 22/11: D1–D10 as proposed,
  D11 rebaseline (P5 on 23/11, overflow moves a day, never cut), D12 deferred.
  Status `OWNER_APPROVED_20261122`.
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

1. Owner rebaselines P6–P11 before the P6 gate (D11); ver3 §12.1 forbids
   cutting trials, acceptance, learning gate or teardown. D12 (branch
   protection) deferred by the owner, so T01 stays an open limit.
2. P4 closed: billing (Bills gross 0.73 USD, audit §6.1), delayed inventory
   CLEAN 24/11 06:20Z (audit §6.2), Linear P4 issues Done 24/11. RDS 0.12 and
   Glue to inspect, not gating.
6. Kyverno findings F1–F6 (SPEC-P5 §10): a graceful scale-down removes the
   webhooks (admission open); only "unreachable" fails closed. The owner
   decides the proposed split of §4 "Admission failure is understood".
3. Carried from P3 (not gates): re-ask teach-back Q3–Q5 at P11; endpoint check 7
   only type-checks `aws:ResourceAccount` (fix with R1).
4. ADR-0005 still PROPOSED (owner review).
5. SPEC approval is not AWS approval: every window needs its own execution
   approval, cost check, stop time and teardown owner.

## Next safe action

P5-T2.1 A merged (PR #66). Kyverno, tenant NetworkPolicies, vpc-cni
NetworkPolicy in Terraform and the isolation suite merged as PR #70
(`05afd58`). On 24/11 the owner ran both L2 labs on kind end to end, without
predictions; every step matched (`docs/evidence/p5/P5-T2.1_L2_KIND_BASELINE_20261124.md`,
`docs/evidence/p5/P5-T2.2_L2_KIND_KYVERNO_20261124.md`; T2.1 B API call and
reference image via step 0b, `labs/p5-kind/api-call.sh`). Codex light review
of PR #71: Enforce stays open until the owner runs step 2b of the Kyverno
runbook (tag only, outside registry, no requests without LimitRange). Next:
step 2b, Codex review of the P5 candidate, then the P5 L3 window (P5-T4.2) on
its own approval.
Overflow moves to 25/11 (D11).

## Context expansion

Use SPEC-P5, THREAT_MODEL §6–7 and §12, ver3 §9.5 and §12, ADR-0006/0008/0009,
P4 audit, LEARNING_ROADMAP row P5. Live Git overrides this file.

## Checkpoint rule

Rewrite this index, update learning only from demonstration, run
check-context.sh and report actual Git/external state separately.
