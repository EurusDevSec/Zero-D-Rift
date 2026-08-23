---
project: Zero D-Rift
roadmap_version: 1.0
canonical_scope: docs/de_cuong_tot_nghiep_ver3.md
planning_method: rolling-wave
start_date: 2026-08-23
feature_freeze: 2026-10-26
target_release_candidate: 2026-11-01
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
| P1 | 24–30/08 | ACTIVE | Architecture and experiment foundation | EKS architecture, IAM, reconciliation, experimental design | ADRs, baseline, threat model, cost plan, quota and version matrix reviewed |
| P2 | 31/08–06/09 | PLANNED | Reproducible EKS bootstrap and teardown | Terraform state/modules, VPC, EKS, OIDC | EKS can be created and deleted from documented commands |
| P3 | 07–13/09 | PLANNED | First control-plane vertical slice | GitOps, CRDs, reconciliation, Crossplane before kro | One CR produces a stable S3 + Deployment resource graph |
| P4 | 14–20/09 | PLANNED | RAGSandbox end-to-end | IRSA, Secrets, RDS/pgvector, readiness | RAG application passes DB and AWS-access checks |
| P5 | 21–27/09 | PLANNED | Tenant and policy guardrails | RBAC, quotas, NetworkPolicy, Pod Security, Kyverno | Negative security suite passes |
| P6 | 28/09–04/10 | PLANNED | BatchTrainingJob and GPU lifecycle | SQS, KEDA, Karpenter, Spot, checkpointing | Batch runs and GPU node is reclaimed |
| P7 | 05–11/10 | PLANNED | Cost and utilization instrumentation | Prometheus, OpenCost, AWS billing and FinOps math | Dashboard and raw cost/utilization evidence exist |
| P8 | 12–18/10 | PLANNED | Drift remediation and controlled data recovery | Reconciliation, RDS snapshot, RTO/RPO | Both independent scenarios pass their bounded checks |
| P9 | 19–25/10 | PLANNED | Official trials and frozen dataset | Test harness, p50/p95, reproducibility | Run manifests, raw dataset and analysis script are locked |
| P10 | 26/10–01/11 | PLANNED | Release candidate and defense assets | Runbooks, limitations, evidence-based explanation | Code freeze, video, report and slides ready |
| P11 | November | PLANNED | Defect fixes and defense practice only | Teach-back and incident explanation | No new feature or technology |

## Scope gates

1. If Crossplane + kro cannot stably create the first S3 vertical slice by
   13/09, stop installing new components and fix or simplify that slice.
2. If RAGSandbox is not end-to-end by 20/09, keep BatchTrainingJob as a bounded
   skeleton until the primary path is stable.
3. If GPU Spot capacity is unavailable, use bounded On-Demand trials and report
   Spot as an observed limitation.
4. If RDS recovery cannot be safely automated, retain a documented human approval
   step and report the actual automation level.
5. After 18/10, do not add a portal, service mesh, multi-region design, model
   registry, or technology outside the MVP.

## Weekly capacity model (25–30 hours)

| Work type | Weekly target |
|---|---:|
| Official reading and focused learning | 5–6 h |
| Micro-labs and technical design | 3–4 h |
| Implementation | 12–14 h |
| Verification, troubleshooting and evidence | 4–5 h |
| Documentation, teach-back and checkpoint | 2 h |

The categories may overlap, but total weekly effort includes learning and
research; they are not additional to the 25–30 hours.

## Active detailed contract

See `.agent/specs/SPEC-P1_FOUNDATION_AND_COMPATIBILITY.md`.

