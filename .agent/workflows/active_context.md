---
project: Zero D-Rift
status: P2_ACCEPTED_P3_SPEC_DRAFT
active_phase: P3
active_task: P3-T1
active_feature: SPEC-P3 owner review and decisions D1-D8
active_spec: .agent/specs/SPEC-P3_FIRST_RESOURCE_GRAPH.md
current_learning: .agent/learning/CURRENT_STATUS.md
mode: Coach
authority: NO_INSTALL_NO_AWS_APPLY_UNTIL_TASK_GATES
last_reviewed: 2026-11-05
---

# Active Context

Current-state index, not scope, live AWS inventory or a transcript.
Follow [context governance](../references/context-governance.md).

## Current verified state

- P2 accepted 05/11/2026: L3 window P2-L3-20261104-01 (apply 51, smoke 33/33,
  admin removal Forbidden, destroy 50, state 0), delayed inventory CLEAN,
  billing ≈ 0.07 USD in us-east-1 month to date. Evidence in `docs/evidence/p2/`
  (DRF11_L3_RUN, DRF12_CLEANUP, DRF13 audit). Codex reviewed DRF-13: APPROVE.
- Learning: Terraform `PRACTICED` + `EXPLAINED`; Argo CD, Crossplane, kro
  `Conceptual only`.
- AWS now holds only the retain allowlist: Terraform state bucket (review 12/11),
  role `zero-drift-bootstrap`, MFA device. No cluster.
- R1 least privilege deferred by the owner (04/11); Terraform role is still
  AdministratorAccess. Redo before DRF-27 (19/11) or at DRF-29.
- Tools: Terraform 1.16.4, kubectl v1.35.10 (`/r/_Dev_tools/kubectl`, per-terminal
  PATH), Helm v4.2.2, k3d v5.8.3, Docker client. kind not installed.
- [Linear routing](../docs/LINEAR_DELIVERY.md): P3 = DRF-14 (contract) and DRF-15
  (resource graph). Linear owns live status; repository owns scope and evidence.

## Open decisions and blockers

1. SPEC-P3 §9 decisions D1–D8 and the P3 gross cap need owner approval.
2. Schedule: ver3 §12 P3 window 03–05/11 is missed; SPEC-P3 proposes 05–08/11.
   Rebaseline of P4+ is the owner's decision (ver3 §12.1).
3. kind install (Task 2) and every AWS window need separate approval.
4. Crossplane 2.4.0 + provider 2.7.0 pairing and kro 0.9.4 on 1.35 are UNVERIFIED.

## Next safe action

Owner reviews SPEC-P3 and decides D1–D8. Then Task 1 (release recheck, digests,
CRD reading, sizing), then the Task 2 kind lab after install approval.

## Context expansion

Use SPEC-P3 §1, §5 and §9; ADR-0003 (ownership), ADR-0005 (kind), ADR-0006
(network), ADR-0007 (identity/state); VERSION_MATRIX §2–3; P2 runbooks for the
EKS window. Live Git overrides this file; preserve dirty work.

## Checkpoint rule

Rewrite this index, update learning only from demonstration, run
check-context.sh and report actual Git/external state separately.
