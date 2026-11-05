---
as_of: 2026-11-05
active_phase: P2
active_task: P2-T9
task_status: LEARNING_GATE_EVIDENCE_RECORDED
history: .agent/learning/LEARNING_LOG.md
---

# Current Learning Status

This is the concise coaching view for new sessions. Detailed dated evidence stays
in `LEARNING_LOG.md`; this file must not invent mastery from generated artifacts.

## Demonstrated level

| Area | Current evidence level | What the owner can presently explain |
|---|---|---|
| System architecture and reconciliation boundaries | `EXPLAINED` | Terraform bootstrap, Argo sync, kro composition, Kubernetes/Crossplane reconciliation and `Synced != Ready` |
| IAM/IRSA and tenant boundaries | `EXPLAINED` | STS trust versus service permission and why namespace tenancy remains soft isolation |
| Cost, quota and experiment guardrails | `EXPLAINED` | Fixed AWS cost, no-default-NAT PoC trade-off, teardown inventory and retained failed trials |
| Terraform applied use | `PRACTICED` + `EXPLAINED` (05/11/2026) | Local `terraform_data` lab with predictions (dependency order, NOOP/exit code, update vs replace); one L3 EKS create/verify/destroy window; own-words answers to SPEC-P2 §7 (state sensitivity, no-NAT trade-off, failure localization, NOOP limits, teardown inventory). Gaps: losing state and plaintext secrets in state; ECR API still needs Internet without interface endpoints |
| Crossplane and kro | Conceptual only | No hands-on controller or external-resource evidence |

## Current P2 learning gate

As of 05/11/2026 the P2 learning evidence is recorded (DRF-13 AC-02): local lab with
predictions, the L3 window P2-L3-20261104-01 and own-words SPEC §7 answers. See the
2026-11-05 entry in `LEARNING_LOG.md` and
`docs/evidence/p2/DRF13_P2_ACCEPTANCE_AUDIT_20261104.md`.

P2 is not closed yet: DRF-13 still needs an independent review (AC-03), DRF-12
billing reconciliation, and owner acceptance. Next learning focus after the gate:
P3 controllers (Argo CD, Crossplane), starting at `Conceptual only`.

## Coaching rule

Use Coach mode for P2 Task 1 decisions and the Task 2 micro-lab, then Pair mode
for the approved Terraform structure. Load older learning entries only to audit a
claim or update this status from new evidence.
