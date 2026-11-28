---
as_of: 2026-11-28
active_phase: P7
active_task: P7 cost observability and baseline (DRF-21, DRF-22)
task_status: P7_STARTED (P6 gate closed by owner decision 28/11, with recorded gaps)
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
| P4 RAGSandbox: IRSA workload, secret flow, PostgreSQL credential tiers | `PRACTICED` + `EXPLAINED` (22/11/2026) | kind graph lab and two EKS micro-labs; the owner kept the `sts` line. Typed answers, no hints: the bucket waits for bootstrap through a graph reference; retry is `bootstrapAttempt` in Git; `db-init` is idempotent. Two transfer cases (a leaked sandbox password, a Secret committed to GitOps) were derived correctly. Gaps: RDS ingress is the node SG only; Secrets Manager force delete; `ALTER ROLE` keeps open sessions; no branch protection; `propagationPolicy` unverified |
| P5 tenant guardrails: RBAC, Pod Security, NetworkPolicy, quota/LimitRange, AppProject, Kyverno | `PRACTICED` + `EXPLAINED` (25/11/2026) | Kind labs 24/11 and EKS micro-lab 25/11 typed by the owner, no predictions. SPEC-P5 §7 teach-back 7/7 plus a quota question, typed answers with a hint line per question: Pod Security owns `hostNetwork` and Kyverno has no rule for it; NetworkPolicy not programmed (PolicyEndpoint) versus written wrong; 443 stays open because NetworkPolicy knows only IP and port, IAM decides what a reached API allows; impersonation tests authorization, not login (D1); Kyverno scale-to-zero fails open, unreachable fails closed, platform namespaces outside the selector, orphan webhooks (G2); any Pod in a namespace can use any SA there, so platform SAs stay in `zdr-platform`; shared RDS, nodes and platform keep isolation soft; LimitRange per container versus quota per namespace. Gaps: a→b also needs tenant-a egress checked; the 443 rule also excludes the VPC range; when `zdr-require-resources` matters not yet in own words |
| P6 batch: SQS semantics, KEDA ScaledJob, Karpenter NodePool, Spot, checkpointing | Karpenter `PRACTICED` + `EXPLAINED`; SQS, KEDA, checkpointing `EXPLAINED` only (28/11/2026) | EKS micro-lab M1, M2, M4 typed by the owner (no predictions; M3, M5 not done). SPEC-P6 §7 teach-back 8/8 with hints: chain message → KEDA (needs IAM) → Job → Pending → NodeClaim → node Ready; delete the message last, DLQ after 3 receives; taint/toleration/nodeSelector and why batch nodes are separate; SIGTERM writes the checkpoint and leaves the message; stacked guards, AWS quota is the only AWS-enforced one; fixed cost when Pods are at zero (failed first, met on re-ask); short runs save a larger share; return nodes before removing Karpenter. Corrected in the session: checkpoint is in S3 not in the message; system nodes are On-Demand; order q → s → p → r. Gaps: no owner lab for SQS, KEDA or checkpointing; several answers paraphrased Claude's explanation, re-ask 2a, 3b, 4, 7, 8 |

## P6 learning gate (closed by owner decision, 28/11/2026)

SPEC-P6 §8 asks `PRACTICED` + `EXPLAINED` for SQS semantics, KEDA, Karpenter and
checkpointing. Met in full for Karpenter only. SQS, KEDA and checkpointing reached
`EXPLAINED` through the teach-back; there is no owner-typed lab for them, so they are
not `PRACTICED`. On 28/11 the owner closed the gate with this gap recorded ("Đóng P6,
sang P7") because the 09/12 deadline leaves no time for a P6 lab. Evidence:
`docs/evidence/p6/P6-T4.3_TEACHBACK_20261128.md` and the 2026-11-28 entry in `LEARNING_LOG.md`.

## P5 learning gate (closed)

As of 25/11/2026, SPEC-P5 §8 learning is met: RBAC, Pod Security, NetworkPolicy, quota and Kyverno
are `PRACTICED` + `EXPLAINED`. Evidence: `docs/evidence/p5/P5-T4.3_TEACHBACK_20261125.md` and the
2026-11-25 entry in `LEARNING_LOG.md`. Limit: no predictions before the labs (owner's choice).

## P4 learning gate (closed)

As of 22/11/2026, SPEC-P4 §8 learning is met: IRSA, the secret flow and the PostgreSQL
credential tiers are `PRACTICED` + `EXPLAINED`. The last two now rest on transfer cases, not on recall.
Evidence: `docs/evidence/p4/P4-T4.2_TEACHBACK_20261121.md` and the 2026-11-22 entry in `LEARNING_LOG.md`.

## P3 learning gate (closed)

As of 14/11/2026 the owner ran the P3 teach-back lab on kind, first answered Q1–Q2
with errors, then corrected them and answered Q3–Q6. Controllers are `PRACTICED` +
`EXPLAINED` with a provenance limit (audit §6.5).
Evidence: `docs/evidence/p3/DRF38_P3_ACCEPTANCE_AUDIT_20261106.md` §6 and the
2026-11-14 entry in `LEARNING_LOG.md`. P2 gate (DRF-13) evidence stays as recorded.

## Coaching rule

Use Coach mode for P2 Task 1 decisions and the Task 2 micro-lab, then Pair mode
for the approved Terraform structure. Load older learning entries only to audit a
claim or update this status from new evidence.
