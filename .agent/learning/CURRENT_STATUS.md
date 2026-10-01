---
as_of: 2026-10-01
active_phase: P2
active_task: P2-T1
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
| Terraform applied use | Foundation/basic | Prior AWS/DigitalOcean use, but no project-specific state/dependency lab yet |
| Crossplane and kro | Conceptual only | No hands-on controller or external-resource evidence |

## Current P2 learning gate

The next learning objective is Terraform configuration/state/provider/dependency
flow and predictable teardown. Before AWS implementation, the owner should:

1. Predict a small local `terraform_data` plan.
2. Observe init, plan, apply, unchanged re-plan and destroy without a cloud resource.
3. Explain what state records, why it is sensitive and what an empty plan proves.

Status remains below `PRACTICED` until that bounded lab has run with evidence.

## Coaching rule

Use Coach mode for P2 Task 1 decisions and the Task 2 micro-lab, then Pair mode
for the approved Terraform structure. Load older learning entries only to audit a
claim or update this status from new evidence.
