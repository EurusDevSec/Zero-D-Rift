---
project: Zero D-Rift
roadmap_version: 1.4
canonical_scope: docs/de_cuong_tot_nghiep_ver3.md
planning_method: rolling-wave
rebaseline_date: 2026-10-29
start_date: 2026-10-29
campaign_freeze_target: 2026-11-19
technical_execution_end_target: 2026-11-25
final_dataset_freeze_target: 2026-11-28
target_defense_assets: 2026-11-29
rehearsal_end_target: 2026-12-02
school_defense_date: UNCONFIRMED
baseline: OWNER_REQUESTED_RECOVERY_2026-10-29
---

# Zero D-Rift Delivery Roadmap

## Planning policy

Canonical scope and baseline schedule: [ver3 section 12](../../docs/de_cuong_tot_nghiep_ver3.md).
Linear owns live issue/status/assignment/working dates; this file is a derived
phase view. [Linear routing](LINEAR_DELIVERY.md) identifies the project and issue
mapping. Linear milestones use the same phase IDs and names P2-P11;
there is no separate milestone counter.

Detail the current phase only, with at most a next-phase outline. Future outcome
issues remain Backlog until their phase contract, dependencies and authority are
ready. Every phase needs functional and learning evidence. MUST/SHOULD/COULD scope
and accepted ADR boundaries remain unchanged. No unapproved scope is rescued by
extra agent activity.

## Phase overview

| ID | Dates | Status | Technical outcome | Learning focus | Exit criteria |
|---|---|---|---|---|---|
| P0 | 23/08 | COMPLETE | Project-specific Eurus planning state | Evidence-based agent workflow | Root constitution, roadmap, active context, workflow, learning plan and P1 spec exist |
| P1 | 24–30/08 | COMPLETE (actual 29/09) | Architecture and experiment foundation | EKS architecture, IAM, reconciliation, experimental design | ADRs, baseline, threat model, cost plan, quota and version matrix reviewed |
| P2 | 29/10–02/11 | TASK 1 COMPLETE_WITH_L3_BLOCKERS; TASK 2 NOT STARTED | Reproducible EKS bootstrap and teardown | Terraform state/modules, VPC, EKS, OIDC | EKS can be created and deleted from documented commands |
| P3 | 03–05/11 | PLANNED; detailed phase SPEC pending | First control-plane vertical slice | GitOps, CRDs, reconciliation, Crossplane before kro | One CR produces a stable S3 + Deployment resource graph |
| P4 | 06–08/11 | PLANNED; detailed phase SPEC pending | RAGSandbox end-to-end | IRSA, Secrets, RDS/pgvector, readiness | RAG application passes DB and AWS-access checks |
| P5 | 09–10/11 | PLANNED; detailed phase SPEC pending | Tenant and policy guardrails | RBAC, quotas, NetworkPolicy, Pod Security, Kyverno | Negative security suite passes |
| P6 | 11–14/11 | PLANNED; detailed phase SPEC pending | BatchTrainingJob and GPU lifecycle | SQS, KEDA, Karpenter, Spot, checkpointing | Batch runs and GPU node is reclaimed |
| P7 | 15–16/11 | PLANNED; detailed phase SPEC pending | Cost and utilization instrumentation | Prometheus, OpenCost, AWS billing and FinOps math | Dashboard and raw cost/utilization evidence exist |
| P8 | 17–19/11 | PLANNED; detailed phase SPEC pending | Drift remediation and controlled data recovery | Reconciliation, RDS snapshot, RTO/RPO | Both independent scenarios pass; campaign preconditions and freeze record ready |
| P9 | 20–25/11; billing 26–28/11 | PLANNED; detailed phase SPEC pending | Official trials and frozen dataset | Test harness, p50/p95, reproducibility | Run manifests, raw dataset and analysis script are locked after sufficient samples and billing evidence |
| P10 | 26–29/11 | PLANNED; detailed phase SPEC pending | Release candidate and defense assets | Runbooks, limitations, evidence-based explanation | Code freeze, video, report and slides ready |
| P11 | 30/11–02/12 | PLANNED; detailed phase SPEC pending | Defect fixes and defense practice only | Teach-back and incident explanation | No new feature or technology |

All dates are working targets under the owner's 29/10 restart instruction, not
observed completion or a confirmed school defense date. The prior 02/10 baseline
and its October-only execution requirement are superseded for scheduling; the
existing scope, samples, acceptance, learning, cost and cleanup gates survive.
Historical approval/preflight records keep their actual dates.

## Capacity and daily execution

- Baseline 8 focused hours/day; up to 10 is optional recovery capacity. Do not
  schedule all work on the assumption of 10 productive hours every day.
- The 29/10-02/12 calendar has a theoretical 280 h at 8 h/day; startup day is
  partial. No observed velocity exists yet. P2-P9 remaining work is a coarse
  186-191 h after Task 1; foundation/tracker setup, final audit, report/slides and
  rehearsal consume the remaining allocation. Reserve must be measured anew.
- Allocations by calendar window: P2 40 h, P3 24 h, P4 24 h, P5 16 h, P6 32 h,
  P7 16 h, P8 24 h, P9 48 h, P10 32 h, P11 24 h. These include learning, evidence
  and cleanup; they are not additional hours on top of the baseline.
- P9 retains the previous 44-48 h estimate and allocates 48 h for 20-25/11.
  Pilot cycle time, capacity, cleanup and cost decide whether that fits.
- One active implementation issue; one writer per overlapping file/environment.
  Codex/Claude may split bounded disjoint outputs or implement/review. Use
  [main workflow](../workflows/main-workflow.md) and root CLAUDE.md.
- Build runbooks, video evidence and report outline incrementally from P2.
  Review gates and remaining estimates each day; do not plan a final-day evidence rush.

## Scope and schedule gates

1. Rebaseline remaining targets after any missed gate, especially P2 02/11,
   P4 08/11, P6 14/11 or campaign freeze P8 19/11. Never lower samples,
   acceptance, learning or teardown to preserve a date.
2. If the first Crossplane/kro S3 + Deployment slice is unstable at P3 05/11,
   stop widening the platform and fix that slice.
3. Batch implementation beyond skeleton waits for usable RAGSandbox evidence.
4. GPU quotas/capacity are unverified historical blockers; any quota request,
   paid window or On-Demand fallback needs separate authority and current cost.
   Do not relabel fallback observations as Spot evidence for H5.
5. Recovery uses an isolated PoC/clone and verified snapshot, not the shared RAG
   database. Keep manual approval when automation cannot be shown safe.
6. No portal, service mesh, multi-region, model registry or new MVP technology.
7. Billing append target 26-28/11 is versioned and cannot change trial outcomes
   or observed timestamps. Freeze only with sufficient evidence; otherwise keep
   PENDING/INCONCLUSIVE and rebaseline.
8. Human work windows never authorize continuously running AWS resources.
   The old candidate 05/10 AWS window is expired; review and approve a new exact
   window before L3. Total gross cap 100 USD and P2 5 USD remain unchanged.

## Active detailed contract

[P2 specification](../specs/SPEC-P2_REPRODUCIBLE_EKS_BOOTSTRAP.md) governs current
implementation. Task 1 COMPLETE_WITH_L3_BLOCKERS; Task 2 READY_NOT_STARTED and
still requires separate exact CLI install/verification and local-lab authority.
Source pins are STATIC_SOURCE_COMPATIBLE, not fresh runtime compatibility.

[P1 closed contract](../specs/SPEC-P1_FOUNDATION_AND_COMPATIBILITY.md) and accepted
ADRs remain inputs, not instructions to rerun or a claim of current AWS inventory.
NCKH Evidence Graph remains a separate parked research outcome.

