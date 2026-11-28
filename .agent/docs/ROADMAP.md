---
project: Zero D-Rift
roadmap_version: 1.5
canonical_scope: docs/de_cuong_tot_nghiep_ver3.md
planning_method: rolling-wave
rebaseline_date: 2026-11-25 (owner, SPEC-P6 D13; previous 2026-10-29)
start_date: 2026-10-29
campaign_freeze_target: 2026-12-01
technical_execution_end_target: 2026-12-07
final_dataset_freeze_target: 2026-12-10
target_defense_assets: 2026-12-11
rehearsal_end_target: 2026-12-14
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
| P2 | 29/10–02/11 | COMPLETE (accepted 05/11) | Reproducible EKS bootstrap and teardown | Terraform state/modules, VPC, EKS, OIDC | EKS can be created and deleted from documented commands |
| P3 | 03–05/11 | COMPLETE (14/11) | First control-plane vertical slice | GitOps, CRDs, reconciliation, Crossplane before kro | One CR produces a stable S3 + Deployment resource graph |
| P4 | 06–08/11 | COMPLETE (24/11) | RAGSandbox end-to-end | IRSA, Secrets, RDS/pgvector, readiness | RAG application passes DB and AWS-access checks |
| P5 | 09–10/11 | TECHNICALLY COMPLETE 25/11; inventory and Bills 26/11 | Tenant and policy guardrails | RBAC, quotas, NetworkPolicy, Pod Security, Kyverno | Negative security suite passes |
| P6 | 11–14/11 → 25–26/11 | ACTIVE; SPEC approved 25/11 | BatchTrainingJob and node lifecycle (CPU, ADR-0009) | SQS, KEDA, Karpenter, Spot, checkpointing | Batch runs and the Karpenter node is reclaimed (CPU, ADR-0009) |
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

## Rebaseline 25/11 (owner, SPEC-P6 D13)

The 29/10 working targets above are history. Actual: P2 05/11, P3 14/11, P4
24/11, P5 technically 25/11 (delayed inventory and Bills on 26/11). On 25/11
the owner ordered P6 to start the same day and finish on 26/11. The rest follows
the ROADMAP allocations, with Claude implementing and the owner approving
(speed mode). Nothing in trials, acceptance, learning gate or teardown is cut
(ver3 §12.1); a step that does not fit moves to the next day.

| Phase | Working target | Allocation | Note |
|---|---|---:|---|
| P5 close | 26/11 | — | delayed inventory, Bills gross, Linear Done |
| P6 | 25–26/11, overflow 27/11 | 24–28 h | one L3 window (CPU, ADR-0009) |
| P7 | 27–28/11 | 16 h | Prometheus, OpenCost, manual baseline |
| P8 | 29/11–01/12 | 24 h | remediation, RDS recovery, pilot, **campaign freeze 01/12** |
| P9 | 02–07/12 | 48 h | official campaign; cycle time from the P8 pilot decides the fit |
| P9 cost append | 08–10/12 | — | delayed billing appended before the final dataset freeze |
| P10 | 08–11/12 | 32 h | acceptance audit, report, slides, video |
| P11 | 12–14/12 | 24 h | fixes in scope, retest, rehearsal |

The internal "defense-ready 02/12" target of 29/10 cannot hold without cutting a
phase; the owner chose not to cut. The school's submission and defense dates are
still `UNCONFIRMED`. If the school fixes a date before 14/12, the owner decides
again: the ADR-0009 cut order (P6 → P8 → P5) is the documented fallback, and P6
is already in progress, so P8 is the first candidate. Linear milestone target
dates follow this table.

## Rebaseline 28/11 (school dates fixed, owner keeps full scope)

On 28/11 the advisor fixed the dates: **product and report complete by 09/12/2026**,
**defense 30/12/2026** (owner's minutes, `docs/thesis/`, not committed). Claude
proposed cutting P8 (the fallback above). The owner refused ("tôi không bỏ cuộc")
and compressed the schedule instead. P6 closed on 28/11 (teach-back, owner gate
decision; DRF-81).

| Phase | Working target | Note |
|---|---|---|
| P7 | 28/11 | local work only: SPEC, metrics stack on kind, cost tools, baseline runbooks; its L3 part runs in the 29/11 window |
| P8 | 29/11 | one AWS window: P7 L3 (metrics, one batch smoke, two owner baselines) plus P8 remediation and recovery, pilot, **campaign freeze 29/11** |
| P9 | 30/11–02/12 | official campaign, same samples as ver3 (20/20/20/5); cycle time from the pilot decides the fit |
| P10 | 03–09/12 | acceptance audit and the full report; chapters 1–3 to the advisor early; **submit 09/12** |
| P11 | 10–29/12 | advisor revisions, slides, video, rehearsal, institute paper |

Rules kept: no cut in samples, acceptance, teardown or the learning gate (teach-backs
may run after 09/12 but before the defense; a phase without one stays "technically
accepted"). If the 29/11 window or the campaign slips, the owner decides again
before 02/12; P8 stays the first cut candidate, and anything cut goes to
"Hướng phát triển" in the report (advisor's rule: never present unfinished work as
a result). Linear milestone target dates follow this table (updated 28/11).

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

[P6 specification](../specs/SPEC-P6_BATCH_TRAINING_JOB.md) (owner-approved
25/11, from the Fable 5.2 draft, CPU per ADR-0009) governs current work. P5
([SPEC-P5](../specs/SPEC-P5_TENANT_GUARDRAILS.md)) is technically done
(audit `docs/evidence/p5/P5_ACCEPTANCE_AUDIT_20261125.md`). Fable drafts P7–P9
stay on branch `claude/specs-p5-p9-draft-ecc762` until their phase gate.

Closed contracts P1–P5 and accepted ADRs remain inputs, not instructions to
rerun or a claim of current AWS inventory. NCKH Evidence Graph remains a
separate parked research outcome.
