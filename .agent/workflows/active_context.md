---
project: Zero D-Rift
status: PHASE_1_COMPLETE_P2_SPEC_REVIEW
active_phase: P2
active_feature: P2 spec owner review and zero-cost preflight
active_spec: .agent/specs/SPEC-P2_REPRODUCIBLE_EKS_BOOTSTRAP.md
roadmap: .agent/docs/ROADMAP.md
architecture: .agent/docs/ARCHITECTURE.md
canonical_scope: docs/de_cuong_tot_nghiep_ver3.md
learning_plan: .agent/learning/LEARNING_ROADMAP.md
learning_log: .agent/learning/LEARNING_LOG.md
cold_memory: .agent/memory/cold_memory.md
git_head: d103508d1dc0b775e5e9afc86bf99133c446c4aa
git_state: DIRTY_EXPECTED_P1_CLOSEOUT_P2_DRAFT
last_verification: PASS_NCKH_FAILURE_LOCALIZATION_SCOPE_L0_2026-09-29
last_updated: 2026-09-29
---

# Active Context

## Current truth

- P1 is complete at documentation/design and `EXPLAINED` learning level.
  Application and infrastructure implementation have not started; no local
  cluster, platform controller, IAM policy or AWS resource was created in P1.
- `docs/de_cuong_tot_nghiep_ver3.md` is canonical, tracked and pushed.
- Teacher feedback was already incorporated into ver2; ver3 is the implementation
  optimization of ver2. No repeated full alignment review is required for P1.
- Root `AGENTS.md` and `.agent/` are the self-contained project workflow. The
  reusable framework source was removed in commit `2a5e6a4`.
- P1 Task 1 governance lineage is closed.
- P1 Task 2 functional and learning gates are complete: the system design exists,
  ADR-0003 and ADR-0004 are accepted, and the owner demonstrated the architecture
  boundaries and relevant failure diagnosis at `EXPLAINED` level.
- P1 Task 3 official-source research and documentation draft are complete. EKS
  1.35 + AL2023 is the baseline; controller compatibility and unresolved pairings
  are recorded in `docs/VERSION_MATRIX.md`.
- P1 Task 3 owner teach-back is complete at `EXPLAINED`: the owner distinguished
  release/documentation, kind compatibility and EKS/AWS runtime evidence.
- ADR-0005 proposes kind as the local-first environment. It remains `PROPOSED`
  until later L2 runtime evidence; owner understanding is no longer the open gate.
- P1 Task 4 functional and learning gates are complete at `EXPLAINED`: the threat
  model has 18 threat/control/test mappings, and the owner separated successful
  workload identity from over-broad cross-tenant S3 authorization. L2/L3 runtime
  evidence remains open for implementation phases.
- P1 Task 5 functional, account, owner-decision and learning gates are complete at
  `EXPLAINED`: the 100 USD envelope, dated prices/quotas, 61.60 USD known planning
  subtotal, Budget/TTL/GPU guardrails, inventory and teardown contract are explicit.
- ADR-0006 is accepted: the PoC has no default NAT Gateway, uses public worker
  subnets with bounded exposure, keeps RDS private and uses an S3 gateway endpoint.
- The 2026-09-28 redacted read-only probe confirmed IAM-user STS access,
  `us-east-1`, selected EKS/EC2/VPC/RDS quotas and one enabled Promotion credit
  with 100 USD remaining through 2027-06-13. Candidate EC2/RDS/GPU/network prices
  were read from AWS Price List API. G/VT On-Demand and Spot quotas are both zero.
- A separate 100 USD guide reward described by the owner is not yet earned or
  visible in `GetCredits`; it remains `UNVERIFIED_OWNER_PLANNED`. Even if later
  verified, the canonical gross project envelope remains 100 USD.
- P1 Task 6 functional and learning gates are complete at `EXPLAINED`. Contract
  v0.1.0 is approved in `docs/experiments/EXPERIMENT_PLAN.md`: H1–H6, manual
  baselines, event/timeout rules, failure/exclusion semantics, schemas and dataset
  freeze are explicit. One JSON manifest parses successfully and is unambiguously
  `SYNTHETIC`. No official trial has started, and approval does not replace a
  campaign freeze.
- P1 Task 7 documentation/path and ver3 consistency review plus teach-back are
  complete. Stale status references were corrected. The owner independently
  diagnosed reconciliation/AWS boundaries, IRSA trust versus service permission
  and soft-isolation limits. Status is `EXPLAINED`, not hands-on mastery.
- P2 initial contract exists at
  `.agent/specs/SPEC-P2_REPRODUCIBLE_EKS_BOOTSTRAP.md` with status
  `DRAFT_FOR_OWNER_APPROVAL`. It begins with owner review, schedule/cost/identity
  preflight and a zero-cost Terraform state micro-lab before any L3 apply.
- A parallel proposed NCKH derivative is documented at
  `docs/research/nckh/NCKH_RESEARCH_CONTEXT.md`. It targets Category B and studies
  an Evidence-Graph-based Failure Localization method for RAGSandbox provisioning,
  but advisor acceptance, registration, non-duplication, funding and protocol
  approval remain `UNVERIFIED`. This record does not expand the active P2
  implementation spec.
- No AWS resource, local cluster, IAM policy or platform controller was created.
  The working tree is intentionally dirty for owner review before commit/push.

## Active objective

Review/approve or revise the P2 bootstrap contract, rebaseline the delayed roadmap
and begin only its zero-cost preflight/micro-lab. No AWS apply is authorized.

## Next actions

1. Owner reviews P2 scope, negative boundaries, task order and chooses Terraform
   or OpenTofu; no build or account mutation follows from draft creation.
2. Rebaseline P2-P11 dates and set a bounded P2 execution cap/window.
3. Decide temporary bootstrap identity, EKS access boundary and state backend.
4. Run the zero-cost `terraform_data` state/dependency micro-lab before AWS modules.
5. Keep ADR-0005 `PROPOSED` until its later L2 kind micro-lab. Commit/push only
   when explicitly requested and never use `git add .`.

## Known blockers and unknowns

- The possible second 100 USD guide reward is not earned/account-verified and is
  excluded from both current balance and spending assumptions.
- P2 spec is `DRAFT_FOR_OWNER_APPROVAL`; exact Terraform/OpenTofu and provider
  versions, dates, P2 gross cap/window and teardown owner are not approved yet.
- Current authenticated AWS CLI path uses a long-lived IAM-user key. It is valid
  only as recorded read-only account evidence, not an approved P2 bootstrap or
  workload identity; temporary-session/bootstrap access design remains open.
- Experiment contract v0.1.0 is approved, but no campaign freeze or runtime
  harness evidence exists; official trial collection remains forbidden.
- GPU G/VT On-Demand and Spot quotas in `us-east-1` are both zero; a future
  owner-approved increase or documented fallback is required before P6 GPU trials.
- Exact chart/image/OCI digests are not yet resolved.
- AWS Region is selected as `us-east-1` and ADR-0006 is accepted. Subnet CIDRs,
  endpoint policy, EKS API CIDR, runtime traffic, Spot price/capacity and final
  billing remain future plan/runtime evidence.
- Crossplane 2.4.0 + AWS provider 2.7.0, kro on Kubernetes 1.35 and OpenCost on
  Kubernetes 1.35 still require runtime evidence.
- kind is proposed but has no L2 evidence; ADR-0005 is not accepted.
- Crossplane and kro have not yet been practiced hands-on by the owner.
- Git branch protection, CI permissions, human AWS federation, EKS access entries,
  exact IRSA policies, IMDS restrictions, VPC CNI NetworkPolicy enforcement,
  secret integration, Kyverno behavior and RDS role grants are not runtime-verified.
- The original P1-P9 calendar windows have slipped. P2 Task 1 must rebaseline the
  remaining roadmap without weakening acceptance or hiding target-release risk.

## Evidence pointers

- Canonical requirements: `docs/de_cuong_tot_nghiep_ver3.md`
- Teacher feedback: `docs/governance/gop_y_de_cuong_tu_thay_Kiet.md`
- Initialized roadmap: `.agent/docs/ROADMAP.md`
- Closed P1 contract: `.agent/specs/SPEC-P1_FOUNDATION_AND_COMPATIBILITY.md`
- Detailed current work: `.agent/specs/SPEC-P2_REPRODUCIBLE_EKS_BOOTSTRAP.md`
- Proposed NCKH handoff context: `docs/research/nckh/NCKH_RESEARCH_CONTEXT.md`
- Reviewed system design: `docs/architecture/SYSTEM_DESIGN.md`
- Accepted bootstrap/platform boundary: `.agent/adr/ADR-0003_BOOTSTRAP_PLATFORM_BOUNDARY.md`
- Accepted shared-RDS/recovery boundary: `.agent/adr/ADR-0004_SHARED_RDS_AND_RECOVERY_DATABASE.md`
- Task 2 learning evidence: `.agent/learning/LEARNING_LOG.md`
- Task 3 compatibility baseline: `docs/VERSION_MATRIX.md`
- Proposed local-first decision: `.agent/adr/ADR-0005_KIND_LOCAL_FIRST_ENVIRONMENT.md`
- Task 4 security design: `docs/security/THREAT_MODEL.md`
- Task 5 cost/quota/teardown plan: `docs/finops/COST_PLAN.md`
- Task 5 redacted credit/price evidence:
  `docs/finops/evidence/2026-09-28_ACCOUNT_COST_PREFLIGHT.md`
- Task 6 experiment contract: `docs/experiments/EXPERIMENT_PLAN.md`
- Task 6 synthetic schema sample:
  `docs/experiments/examples/SYNTHETIC_RUN_MANIFEST.json`
- Task 7 document/ver3 consistency evidence:
  `.agent/specs/SPEC-P1_FOUNDATION_AND_COMPATIBILITY.md`
- Task 7 teach-back and carry-over gaps: `.agent/learning/LEARNING_LOG.md`
- Accepted PoC network egress decision:
  `.agent/adr/ADR-0006_POC_NETWORK_EGRESS_AND_COST_GUARDRAILS.md`
- P0 project-agent commit: `52c02ce`.
- Framework removal and remote sync: `2a5e6a4`.
- Framework-removal decision: `.agent/adr/ADR-0002_SELF_CONTAINED_PROJECT_AGENT.md`.
- Governance lineage confirmation: feedback -> ver2 -> ver3; Task 1 is closed.
- Task 3 L0 verification on 2026-09-25: `git diff --check`; required evidence
  paths found; ADR IDs unique; Task 3 functional checklist closed; no trailing
  whitespace in the reviewed files.
- Local read-only probe on 2026-09-25: `kubectl v1.33.5` present; Docker, kind,
  k3d and Helm not found on `PATH`.
- Task 4 L0 verification on 2026-09-28: `git diff --check`; required threat-model
  sections found; 18 unique threat IDs; Mermaid/code fences balanced; no 12-digit
  account-ID or AWS access-key pattern; Task 4 functional checklist closed.
- Task 4 teach-back on 2026-09-28: owner correctly localized a cross-tenant S3
  allow to AWS authorization after confirming the intended caller identity; learning
  status is `EXPLAINED`.
- Task 5 redacted account probe on 2026-09-28: `us-east-1`, STS IAM-user identity,
  EKS clusters 100, managed node groups 30, VPCs 5, ENIs 5000, RDS instances 40,
  manual DB snapshots 100, Standard On-Demand/Spot vCPU 5/5 and G/VT
  On-Demand/Spot vCPU 0/0. No resource or quota request was created.
- Task 5 Billing/price probe on 2026-09-28: AWS CLI 2.37.4, one enabled 100 USD
  Promotion credit with 100 USD remaining through 2027-06-13, relevant product
  coverage, and candidate On-Demand unit prices for the planning baseline. The
  second guide reward is not verified. No AWS resource was created.
- Task 5 owner review on 2026-09-29: ADR-0006 accepted and owner teach-back passed
  at `EXPLAINED`; owner identified NAT fixed/processing cost, public-node controls,
  persistent cost after `Pod=0` and the invariant 100 USD gross envelope.
- Task 5 completion L0 on 2026-09-29: `git diff --check` passed; ADR-0006 is
  `ACCEPTED`, Task 5 is marked complete, learning is `EXPLAINED`, active work is
  Task 6, stale-open-state scan passed and no access-key/account-ID pattern was found.
- Task 6 contract L0 on 2026-09-29: synthetic JSON parsed; all exclusion guards
  matched; 16 Markdown fences were balanced; H1–H6/sample/timeout/freeze markers
  were present; seven functional checks were closed, three owner gates remained;
  `git diff --check` and secret/account-ID scans passed.
- Task 6 completion L0 on 2026-09-29: contract status is `APPROVED_CONTRACT`, all
  ten review gates are closed, synthetic guards and JSON parsing pass, stale review
  markers are absent, and `git diff --check` passes.
- Task 7 documentation consistency L0 on 2026-09-29: required P1 artifacts exist;
  24 scope/status markers, synthetic guards and six unique ADR IDs pass; 39 inline
  path occurrences contain no unexpected missing active path. Three immutable-ver3
  historical references are mapped in `docs/README.md`; three occurrences refer
  to future experiment outputs. Sixty-eight dated external URLs were not live-reprobed.
- P1 closeout/P2 draft L0 on 2026-09-29: all six Task 7 checks are closed;
  Task 7 learning is `EXPLAINED` with explicit hands-on carry-over; P2 draft has
  nine bounded tasks, negative/cost/apply gates and teardown requirements;
  Markdown fences, secret/account-ID scan and `git diff --check` pass.
- NCKH handoff L0 on 2026-09-29: the context file and its index links exist;
  required status, title, separation, research-question, experiment, unknown,
  handoff and source sections are present; linked project paths resolve;
  Markdown fences are balanced; no AWS access-key or 12-digit account-ID pattern
  was found; `git diff --check` passed.
- NCKH Failure Localization scope pivot L0 on 2026-09-29: the chosen Vietnamese
  and English titles, four revised RQs, three comparison methods, primary metrics,
  scope boundaries and expected contributions are present; the superseded title
  is absent; Markdown fences, sensitive-identifier scan and `git diff --check`
  pass. Advisor approval and literature-gap validation remain `UNVERIFIED`.
- Task 5 L0 verification on 2026-09-28: `git diff --check`; required cost/ADR/
  threat-model paths found; six ADR IDs unique; Markdown fences balanced; required
  cost-plan sections found; envelope sum equals 100; no 12-digit account-ID or
  AWS access-key pattern found. Result: `TASK5_L0=PASS`.
- Task 5 account/price L0 verification on 2026-09-28: `git diff --check` passed;
  credit/price evidence path exists; Markdown fences are balanced; envelope sum
  is 100, known planning subtotal is 61.60, and changed files contain no access-key
  or 12-digit account-ID pattern. Result: `TASK5_ACCOUNT_PRICE_L0=PASS`.
- Git HEAD remains `d103508d1dc0b775e5e9afc86bf99133c446c4aa`; reviewed P1
  documentation changes are intentionally unstaged for owner review.

## Checkpoint rule

At session end, replace current status with observed results, exact verification
commands, evidence paths, current Git HEAD/dirty state, blockers, and the next
small action. Never paste a complete chat transcript into this file.
