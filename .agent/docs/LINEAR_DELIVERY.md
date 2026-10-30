# Linear delivery routing — Zero D-Rift

Setup date: 2026-10-29, Asia/Saigon. This is a routing/source index, not a live
status mirror or a second roadmap.

## Open the tracker

- Workspace: Zero Door / zero-door.
- Team: Zero D-Rift / DRF.
- Project: [Zero D-Rift — Triển khai và bảo vệ đồ án](https://linear.app/zero-door/project/zero-d-rift-trien-khai-va-bao-ve-djo-an-0c6bb6af5f0d).
- Team board: https://linear.app/zero-door/team/DRF/all
- Linear milestones use the repository's own phase IDs and names, P2-P11.
  There is no additional milestone numbering or mapping to remember.
- Owner/lead: the verified workspace profile Lê Văn Hoàng. Agents are not human
  assignees; they coordinate within the issue and the owner's authority.
- Project working start 29/10, target 02/12/2026. Exact school submission/defense
  dates UNCONFIRMED. Baseline 8 h/day; up to 10 is optional reserve. Live working
  issue dates/status are in Linear; canonical baseline and rebaseline rules are
  [ver3 section 12](../../docs/de_cuong_tot_nghiep_ver3.md).
- Uncommitted workflow/schedule changes are local until separately authorized
  publication. Existing GitHub branch links may show the preceding revision.

## Read sources in this order

1. [AGENTS](../../AGENTS.md), [main workflow](../workflows/main-workflow.md) and
   [active context](../workflows/active_context.md); Claude starts [CLAUDE](../../CLAUDE.md).
2. [Canonical ver3](../../docs/de_cuong_tot_nghiep_ver3.md): scope/architecture
   sections 5-6, measurement/AC 8-10, cost 11, schedule/gates 12, delivery 13-15.
3. [Derived roadmap](ROADMAP.md), then the active phase SPEC. Only
   [SPEC-P2](../specs/SPEC-P2_REPRODUCIBLE_EKS_BOOTSTRAP.md) is currently detailed.
4. [Experiment contract](../../docs/experiments/EXPERIMENT_PLAN.md) and
   [cost/teardown contract](../../docs/finops/COST_PLAN.md), plus task-required ADRs.
5. Live Linear issue body/AC/dependencies/authority and actual evidence, not a
   historical status in this index. Reconcile conflicts before implementation.

## Issue-source mapping

Issue numbers below are returned Linear identities, not a new repository counter.
Later phase issues are outcome outlines, to split/refine only at their phase gate.

| Linear issue | Phase | Governing source / outcome |
|---|---|---|
| [DRF-1](https://linear.app/zero-door/issue/DRF-1/delivery-tracking-linear-va-workflow-codex-claude-dung-chung) | P2 | Delivery tracking: Linear và workflow Codex–Claude dùng chung — shared workflow / ver3 §12 |
| [DRF-2](https://linear.app/zero-door/issue/DRF-2/bootstrap-decisions-ghi-nhan-closure-p2-t1-cung-l3-blockers) | P2 | Bootstrap decisions: ghi nhận closure P2-T1 cùng L3 blockers — SPEC-P2 Task 1 / historical Phase1 closure |
| [DRF-3](https://linear.app/zero-door/issue/DRF-3/terraform-cli-cai-va-xac-minh-exact-pin-1164) | P2 | Terraform CLI: cài và xác minh exact pin 1.16.4 — SPEC-P2 Tasks 1-2 / separate install authority |
| [DRF-4](https://linear.app/zero-door/issue/DRF-4/terraform-state-hoan-thanh-lab-local-va-giai-thich-dependency) | P2 | Terraform state: hoàn thành lab local và giải thích dependency — SPEC-P2 Task 2 |
| [DRF-5](https://linear.app/zero-door/issue/DRF-5/bootstrap-access-mfa-temporary-session-va-recovery-djuoc-kiem-chung) | P2 | Bootstrap access: MFA, temporary session và recovery được kiểm chứng — ADR-0007 / COST_PLAN §7.4 |
| [DRF-6](https://linear.app/zero-door/issue/DRF-6/terraform-backend-foundation-s3-bao-ve-state-va-locking) | P2 | Terraform backend: foundation S3 bảo vệ state và locking — ADR-0007 / COST_PLAN §7.4 |
| [DRF-7](https://linear.app/zero-door/issue/DRF-7/terraform-root-version-locks-variables-va-static-checks) | P2 | Terraform root: version locks, variables và static checks — SPEC-P2 Task 3 |
| [DRF-8](https://linear.app/zero-door/issue/DRF-8/bootstrap-network-vpc-va-s3-endpoint-khong-co-nat-mac-djinh) | P2 | Bootstrap network: VPC và S3 endpoint không có NAT mặc định — SPEC-P2 Task 4 |
| [DRF-9](https://linear.app/zero-door/issue/DRF-9/eks-bootstrap-al2023-oidc-va-explicit-access-entries) | P2 | EKS bootstrap: AL2023, OIDC và explicit access entries — SPEC-P2 Task 5 |
| [DRF-10](https://linear.app/zero-door/issue/DRF-10/bootstrap-gate-budget-runbook-va-exact-priced-plan-san-sang-duyet) | P2 | Bootstrap gate: Budget, runbook và exact priced plan sẵn sàng duyệt — SPEC-P2 Task 6 |
| [DRF-11](https://linear.app/zero-door/issue/DRF-11/eks-runtime-create-va-smoke-test-trong-approved-aws-window) | P2 | EKS runtime: create và smoke test trong approved AWS window — SPEC-P2 Task 7 |
| [DRF-12](https://linear.app/zero-door/issue/DRF-12/bootstrap-cleanup-idempotency-destroy-va-orphan-inventory) | P2 | Bootstrap cleanup: idempotency, destroy và orphan inventory — SPEC-P2 Task 8 |
| [DRF-13](https://linear.app/zero-door/issue/DRF-13/p2-acceptance-review-evidence-owner-giai-thich-va-mo-gate-p3) | P2 | P2 acceptance: review evidence, owner giải thích và mở gate P3 — SPEC-P2 Task 9 |
| [DRF-14](https://linear.app/zero-door/issue/DRF-14/platform-contract-pin-controllers-va-duyet-spec-p3) | P3 | Platform contract: pin controllers và duyệt SPEC-P3 — ver3/current experiment contract; future SPEC pending |
| [DRF-15](https://linear.app/zero-door/issue/DRF-15/resource-graph-mot-cr-tao-s3-va-deployment-on-djinh) | P3 | Resource graph: một CR tạo S3 và Deployment ổn định — ver3/current experiment contract; future SPEC pending |
| [DRF-16](https://linear.app/zero-door/issue/DRF-16/rag-shared-service-postgresqlpgvector-va-credential-boundary) | P4 | RAG shared service: PostgreSQL/pgvector và credential boundary — ver3/current experiment contract; future SPEC pending |
| [DRF-17](https://linear.app/zero-door/issue/DRF-17/ragsandbox-request-tao-moi-truong-dung-djuoc-end-to-end) | P4 | RAGSandbox: request tạo môi trường dùng được end-to-end — ver3/current experiment contract; future SPEC pending |
| [DRF-18](https://linear.app/zero-door/issue/DRF-18/tenant-guardrails-negative-suite-chung-minh-soft-isolation) | P5 | Tenant guardrails: negative suite chứng minh soft isolation — ver3/current experiment contract; future SPEC pending |
| [DRF-19](https://linear.app/zero-door/issue/DRF-19/batch-contract-queue-checkpoint-gpu-quota-va-lifecycle) | P6 | Batch contract: queue, checkpoint, GPU quota và lifecycle — ver3/current experiment contract; future SPEC pending |
| [DRF-20](https://linear.app/zero-door/issue/DRF-20/batchtrainingjob-outcome-checkpoint-va-node-reclamation) | P6 | BatchTrainingJob: outcome, checkpoint và node reclamation — ver3/current experiment contract; future SPEC pending |
| [DRF-21](https://linear.app/zero-door/issue/DRF-21/measurements-prometheusopencost-va-raw-cost-evidence) | P7 | Measurements: Prometheus/OpenCost và raw cost evidence — ver3/current experiment contract; future SPEC pending |
| [DRF-22](https://linear.app/zero-door/issue/DRF-22/manual-baseline-runbook-va-matched-workload-profile-tai-lap) | P7 | Manual baseline: runbook và matched workload profile tái lập — ver3/current experiment contract; future SPEC pending |
| [DRF-23](https://linear.app/zero-door/issue/DRF-23/sg-drift-reconciliation-co-timestamp-va-ownership-proof) | P8 | SG drift: reconciliation có timestamp và ownership proof — ver3/current experiment contract; future SPEC pending |
| [DRF-24](https://linear.app/zero-door/issue/DRF-24/rds-recovery-snapshot-du-lieu-va-app-reconnect-djuoc-kiem-chung) | P8 | RDS recovery: snapshot, dữ liệu và app reconnect được kiểm chứng — ver3/current experiment contract; future SPEC pending |
| [DRF-25](https://linear.app/zero-door/issue/DRF-25/campaign-freeze-pilot-cycle-time-va-toan-bo-preconditions-djuoc-khoa) | P8 | Campaign freeze: pilot cycle time và toàn bộ preconditions được khóa — ver3/current experiment contract; future SPEC pending |
| [DRF-26](https://linear.app/zero-door/issue/DRF-26/official-baseline-djo-dju-run-thu-cong-va-matched-cost-arms) | P9 | Official baseline: đo đủ run thủ công và matched cost arms — ver3/current experiment contract; future SPEC pending |
| [DRF-27](https://linear.app/zero-door/issue/DRF-27/official-campaign-dju-trial-rag-batch-drift-va-recovery) | P9 | Official campaign: đủ trial RAG, batch, drift và recovery — ver3/current experiment contract; future SPEC pending |
| [DRF-28](https://linear.app/zero-door/issue/DRF-28/dataset-analysis-metric-tai-lap-va-versioned-billing-append) | P9 | Dataset analysis: metric tái lập và versioned billing append — ver3/current experiment contract; future SPEC pending |
| [DRF-29](https://linear.app/zero-door/issue/DRF-29/final-acceptance-audit-scope-teardown-va-orphan-inventory) | P10 | Final acceptance: audit scope, teardown và orphan inventory — ver3/current experiment contract; future SPEC pending |
| [DRF-30](https://linear.app/zero-door/issue/DRF-30/bao-cao-va-slide-trinh-bay-ket-qua-phuong-phap-va-gioi-han) | P10 | Báo cáo và slide: trình bày kết quả, phương pháp và giới hạn — ver3/current experiment contract; future SPEC pending |
| [DRF-31](https://linear.app/zero-door/issue/DRF-31/defense-evidence-runbook-video-va-goi-tai-lap-offline) | P10 | Defense evidence: runbook, video và gói tái lập offline — ver3/current experiment contract; future SPEC pending |
| [DRF-32](https://linear.app/zero-door/issue/DRF-32/release-fixes-xu-ly-defect-trong-scope-va-retest-candidate) | P11 | Release fixes: xử lý defect trong scope và retest candidate — ver3/current experiment contract; future SPEC pending |
| [DRF-33](https://linear.app/zero-door/issue/DRF-33/defense-rehearsal-owner-giai-thich-va-demo-du-phong) | P11 | Defense rehearsal: owner giải thích và demo dự phòng — ver3/current experiment contract; future SPEC pending |

## Workflow and acceptance

Use existing team statuses: Backlog -> Todo -> In Progress -> In Review -> Done.
Do not change team-wide settings or create cycles/initiatives just for this setup.

- Backlog: prerequisites, decisions, authority or current-phase SPEC unresolved.
- Todo: bounded outcome/AC/file allowlist, dependencies and execution authority
  all ready. A source label READY_NOT_STARTED does not waive permission gates.
- In Progress: one active implementation issue; implementer records a work claim.
  The second agent reviews/researches or works on disjoint authorized outputs.
- In Review: candidate, verification results, evidence, gaps and reviewer handoff.
- Done: required AC/evidence and owner acceptance recorded. Do not auto-close from
  agent output or dates. Merge is not imposed for every documentation/local issue;
  official campaign freeze still requires immutable revision and separate Git
  publication authority. Historical closure keeps its actual provenance.
- Labels: reuse Feature/Improvement/Bug; team-local approval-required,
  contract-pending and blocked explain readiness, not a new status system.
- Blocking relations represent actual prerequisites. Report outline/runbooks/video
  may be prepared early; finalization requires final dataset/audit evidence.
- Native estimate scale/cycles were not configured. Planning hours in issue bodies
  are estimates/shared phase budgets, not observed durations or Linear points.

## Daily owner and agent loop

Choose one result and work in 15-60 minute subtasks. Include focused learning,
checks, evidence and cleanup within 8 h; use the optional extra 2 h for recovery.
End day: observed result, remaining estimate, blocker/unblock action and evidence
link on the live issue. Rebaseline at a missed gate, never reduce trials/AC.

Before editing, record issue, actor/session, revision/dirty paths, outcome and
file allowlist; one writer per overlapping file/resource. Handoff candidate,
diff/evidence, findings/learning gaps, authority and next step. See the main
workflow for Codex/Claude roles. If Claude lacks Linear, provide a dated issue
snapshot and mark remote state unverified; do not pretend a status was updated.

## Current execution boundary

Setup does not authorize Terraform installation or lab execution, IAM/MFA/backend
or Budget mutations, quota requests, AWS apply, commit/push or spending changes.
Next execution candidate is [DRF-3](https://linear.app/zero-door/issue/DRF-3/terraform-cli-cai-va-xac-minh-exact-pin-1164):
obtain separate exact CLI install/verification authority, then
[DRF-4](https://linear.app/zero-door/issue/DRF-4/terraform-state-hoan-thanh-lab-local-va-giai-thich-dependency) for separately
authorized local-only terraform_data lab. Task 1 closure remains historical
COMPLETE_WITH_L3_BLOCKERS; no AWS/bootstrap runtime or new owner learning evidence
was produced by tracker setup.

The 05/10 candidate AWS window is expired. Refresh identity/MFA/recovery, prices,
spend/credit/EBS exposure, quotas, physical backend/Budget and reviewed plan before
a newly approved window. GPU quota/capacity may delay P6; no request is authorized
by a target date. Backend 03/11 review/checkpoint is conditional on actual
existence/inventory, never automatic deletion. Independent tested recovery login
is required before L3; a second human remains optional SHOULD for single-owner PoC.
