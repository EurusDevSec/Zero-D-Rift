---
project: Zero D-Rift
status: P3_L3_DONE_CLOSEOUT_PENDING
active_phase: P3
active_task: P3-T6
active_feature: DRF-38 evidence, independent review, owner teach-back
active_spec: .agent/specs/SPEC-P3_FIRST_RESOURCE_GRAPH.md
current_learning: .agent/learning/CURRENT_STATUS.md
mode: Coach
authority: NO_INSTALL_NO_AWS_APPLY_UNTIL_TASK_GATES
last_reviewed: 2026-11-06
---

# Active Context

Current-state index, not scope, live AWS inventory or a transcript.
Follow [context governance](../references/context-governance.md).

## Current verified state

- P2 accepted 05/11/2026 (evidence `docs/evidence/p2/`).
- P3 Tasks 1–5 done (DRF-34, DRF-39, DRF-35, DRF-36, DRF-37). L3 window
  P3-L3-20261105-01 ran 15:41–16:45Z on 05/11: graph, negative IAM test and
  delete-through-Git passed on EKS; one stop fixed once (S3 endpoint blocked
  quay.io/registry.k8s.io layers, PR #27); destroy 52, inventory CLEAN.
  Evidence `docs/evidence/p3/DRF37_L3_WINDOW_20261105.md`.
- Closeout audit: `docs/evidence/p3/DRF38_P3_ACCEPTANCE_AUDIT_20261106.md`
  (self-check by Claude, not independent review).
- Learning: Terraform `PRACTICED` + `EXPLAINED`; Argo CD, Crossplane, kro still
  `Conceptual only` until the owner's teach-back.
- AWS holds only the retain allowlist: Terraform state bucket, role
  `zero-drift-bootstrap`, MFA device. No cluster, no P3 role.
- R1 least privilege deferred; it lacks the `zero-drift-p3-*` role and
  `PutRolePolicy`. Redo before DRF-27 (19/11) or at DRF-29.
- Tools: Terraform 1.16.4, kubectl v1.35.10 (`/r/_Dev_tools/kubectl`), kind
  v0.33.0 (`/r/_Dev_tools/kind`), Helm v4.2.2.
- [Linear routing](../docs/LINEAR_DELIVERY.md): P3 = DRF-14, DRF-15 and sub-issues.

## Open decisions and blockers

1. Delayed inventory CLEAN 06/11 04:01Z. Billing check still open (owner,
   Billing console).
2. Independent review by Codex: request in DRF-38 audit §4.
3. Owner teach-back: `docs/runbooks/P3_TEACHBACK_LAB.md`, then 6 answers (SPEC §7).
4. ADR-0005 still PROPOSED (owner review).
5. Schedule: P3 slipped past 05/11; P4+ rebaseline is the owner's decision.

## Next safe action

Owner runs the teach-back lab on kind and answers SPEC-P3 §7; Codex reviews the
candidate `c98b4a1`. Claude records both verbatim, then updates learning status.

## Context expansion

Use SPEC-P3 §4, §7, §8; DRF37/DRF38 evidence; runbooks `P3_RESOURCE_GRAPH.md`
(window, lessons C5) and `P3_TEACHBACK_LAB.md`. Live Git overrides this file.

## Checkpoint rule

Rewrite this index, update learning only from demonstration, run
check-context.sh and report actual Git/external state separately.
