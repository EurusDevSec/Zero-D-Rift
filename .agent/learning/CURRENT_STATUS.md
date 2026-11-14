---
as_of: 2026-11-14
active_phase: P4
active_task: P4 SPEC (DRF-16, DRF-17)
task_status: P3_TEACHBACK_RECORDED
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
| Argo CD, kro, Crossplane | `PRACTICED` + `EXPLAINED` (14/11/2026), with a provenance limit | Kind lab parts 0–7 run by the owner. SPEC-P3 §7: Git → Argo (tracking-id) → kro renders the RGD into the MR → provider via IRSA; Argo green means only cluster = Git; selfHeal vs prune through Git and `managementPolicies: "*"`; DRC → SA → EKS webhook → STS and trust/permission layers; provider removed before MRs leaves finalizers and orphans; Terraform owns the role, Crossplane the bucket. Limit: Q3–Q6 were a pasted block close to Claude's wording; re-ask Q3–Q5 orally at P11 |

## Current P3 learning gate

As of 14/11/2026 the owner ran the P3 teach-back lab on kind, first answered Q1–Q2
with errors, then corrected them and answered Q3–Q6. Controllers are `PRACTICED` +
`EXPLAINED` with a provenance limit (audit §6.5).
Evidence: `docs/evidence/p3/DRF38_P3_ACCEPTANCE_AUDIT_20261106.md` §6 and the
2026-11-14 entry in `LEARNING_LOG.md`. P2 gate (DRF-13) evidence stays as recorded.

## Coaching rule

Use Coach mode for P2 Task 1 decisions and the Task 2 micro-lab, then Pair mode
for the approved Terraform structure. Load older learning entries only to audit a
claim or update this status from new evidence.
