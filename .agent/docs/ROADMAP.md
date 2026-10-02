---
project: Zero D-Rift
roadmap_version: 1.2
canonical_scope: docs/de_cuong_tot_nghiep_ver3.md
planning_method: rolling-wave
start_date: 2026-08-23
campaign_freeze_target: 2026-10-23
technical_execution_end: 2026-10-31
final_dataset_freeze_target: 2026-11-03
target_defense_assets: November 2026
baseline: OWNER_APPROVED_AGGRESSIVE_2026-10-02
---

# Zero D-Rift Delivery Roadmap

## Planning policy

- This roadmap mirrors ver3; it does not replace it.
- Detail the current phase into tasks and subtasks. Keep later phases at outcome
  level until the preceding dependency is stable.
- Every phase has a functional gate and a learning gate.
- Use `MUST`, `SHOULD`, and `COULD`. Cut `COULD` first when schedule slips.
- No unfinished phase may silently expand the next phase.

## Phase overview

| ID | Dates | Status | Technical outcome | Learning focus | Exit criteria |
|---|---|---|---|---|---|
| P0 | 23/08 | COMPLETE | Project-specific Eurus planning state | Evidence-based agent workflow | Root constitution, roadmap, active context, workflow, learning plan and P1 spec exist |
| P1 | 24–30/08 | COMPLETE (actual 29/09) | Architecture and experiment foundation | EKS architecture, IAM, reconciliation, experimental design | ADRs, baseline, threat model, cost plan, quota and version matrix reviewed |
| P2 | 02–06/10 | SCOPE APPROVED; TASK 1 OPEN | Reproducible EKS bootstrap and teardown | Terraform state/modules, VPC, EKS, OIDC | EKS can be created and deleted from documented commands |
| P3 | 07–09/10 | PLANNED | First control-plane vertical slice | GitOps, CRDs, reconciliation, Crossplane before kro | One CR produces a stable S3 + Deployment resource graph |
| P4 | 10–12/10 | PLANNED | RAGSandbox end-to-end | IRSA, Secrets, RDS/pgvector, readiness | RAG application passes DB and AWS-access checks |
| P5 | 13–14/10 | PLANNED | Tenant and policy guardrails | RBAC, quotas, NetworkPolicy, Pod Security, Kyverno | Negative security suite passes |
| P6 | 15–18/10 | PLANNED | BatchTrainingJob and GPU lifecycle | SQS, KEDA, Karpenter, Spot, checkpointing | Batch runs and GPU node is reclaimed |
| P7 | 19–20/10 | PLANNED | Cost and utilization instrumentation | Prometheus, OpenCost, AWS billing and FinOps math | Dashboard and raw cost/utilization evidence exist |
| P8 | 21–23/10 | PLANNED | Drift remediation and controlled data recovery | Reconciliation, RDS snapshot, RTO/RPO | Both independent scenarios pass; campaign preconditions and freeze record ready |
| P9 | 24–30/10; billing 01–03/11 | PLANNED | Official trials and frozen dataset | Test harness, p50/p95, reproducibility | Run manifests, raw dataset and analysis script are locked after sufficient samples and billing evidence |
| P10 | Technical audit 31/10; defense assets November | PLANNED | Release candidate and defense assets | Runbooks, limitations, evidence-based explanation | Code freeze, video, report and slides ready |
| P11 | November | PLANNED | Defect fixes and defense practice only | Teach-back and incident explanation | No new feature or technology |

The original weekly windows slipped; owner approved this aggressive rebaseline
on 2026-10-02. Dates and gates mirror canonical ver3 section 12; this roadmap is
a derived planning view. Technical implementation and official trials end in
October. Runbooks and video evidence are produced throughout P2-P9. October 31
is reserved for final acceptance audit, teardown, orphan inventory and packaging.
P9 reserves approximately 44-48 hours, adjusted using observed dry-run cycle time;
the previous 34-hour estimate is superseded. Delayed billing may be appended in
versioned files on November 1-3 before final dataset freeze, under the existing
experiment contract; trial results and observed event timestamps are preserved.
The November 3 freeze target depends on sufficient evidence; missing billing is
`PENDING`/`INCONCLUSIVE`, never zero. November covers final cost reconciliation,
report, slides, in-scope fixes and defense practice; defense is expected in early
December, with the exact school date unconfirmed. No scheduling decision grants
AWS apply/account-mutation authority.

## Scope gates

1. If Crossplane + kro cannot stably create the first S3 vertical slice by
   09/10, stop installing new components and fix or simplify that slice.
2. If RAGSandbox is not end-to-end by 12/10, keep BatchTrainingJob as a bounded
   skeleton until the primary path is stable.
3. If GPU Spot capacity is unavailable, use bounded On-Demand trials and report
   Spot as an observed limitation.
4. If RDS recovery cannot be safely automated, retain a documented human approval
   step and report the actual automation level.
5. After 18/10, do not add a portal, service mesh, multi-region design, model
   registry, or technology outside the MVP.

6. If the October 6 bootstrap gate, October 12 RAG gate, October 18 batch/GPU
   gate or October 23 campaign freeze slips, rebaseline from live state. Do not
   reduce trial count, acceptance criteria, learning gates or teardown to keep dates.

## Temporary October capacity model

For October 2-31 only, owner availability is a maximum of 8 hours/day: a theoretical
240-hour ceiling. This is temporary emergency capacity, not a sustainable daily
commitment. Estimated workload is 197-201 hours, leaving 39-43 hours of reserve.
Those estimates include learning, labs, implementation, verification, evidence,
documentation and teach-back. AWS runtime/cost windows require separate approval;
human availability does not authorize keeping paid resources active all month.

| Phase / activity | Estimated hours |
|---|---:|
| P2 | 31 (SPEC range: 27-31) |
| P3 / P4 / P5 | 20 / 22 / 14 |
| P6 / P7 / P8 | 26 / 12 / 20 |
| P9 campaign, cleanup, evidence and raw analysis | 44-48; revise from observed dry runs |
| October 31 final audit and teardown | 8 |
| Total workload / reserve | 197-201 / 39-43 |

Future-phase effort is a coarse estimate, not an approved detailed feature spec.
November capacity will be reviewed separately.

### Previous weekly capacity baseline (25–30 hours; superseded for October 2-31)

The original model is retained below for traceability. It is superseded only for
the temporary October window; it is not a second concurrent capacity allocation.

| Work type | Weekly target |
|---|---:|
| Official reading and focused learning | 5–6 h |
| Micro-labs and technical design | 3–4 h |
| Implementation | 12–14 h |
| Verification, troubleshooting and evidence | 4–5 h |
| Documentation, teach-back and checkpoint | 2 h |

The categories may overlap, but total weekly effort includes learning and
research; they were not additional to the previous 25–30-hour weekly baseline.

## Active detailed contract

P1 closed contract: `.agent/specs/SPEC-P1_FOUNDATION_AND_COMPATIBILITY.md`.

Bounded scope and Terraform CLI 1.16.4 approved; Task 1 decisions remain open:
`.agent/specs/SPEC-P2_REPRODUCIBLE_EKS_BOOTSTRAP.md`.

