---
project: Zero D-Rift
status: PHASE_1_ACTIVE
active_phase: P1
active_feature: Task 5 cost plan review and account preflight
active_spec: .agent/specs/SPEC-P1_FOUNDATION_AND_COMPATIBILITY.md
roadmap: .agent/docs/ROADMAP.md
architecture: .agent/docs/ARCHITECTURE.md
canonical_scope: docs/de_cuong_tot_nghiep_ver3.md
learning_plan: .agent/learning/LEARNING_ROADMAP.md
learning_log: .agent/learning/LEARNING_LOG.md
cold_memory: .agent/memory/cold_memory.md
git_head: bb9ce630de63334039da1ab9729c82a81394506d
git_state: DIRTY_EXPECTED_P1_TASK5_REVIEW
last_verification: PASS_TASK5_DOCUMENTATION_L0_2026-09-28
last_updated: 2026-09-28
---

# Active Context

## Current truth

- Application and infrastructure implementation have not started; no AWS resource
  or platform controller was created during P1 Task 2.
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
- P1 Task 5 documentation/design is complete in `docs/finops/COST_PLAN.md`: the
  100 USD envelope, dated pricing/quota facts, Budget/TTL/GPU guardrails, network
  comparison, inventory and teardown contract are explicit.
- ADR-0006 proposes a cost-bounded PoC egress baseline with no default NAT Gateway,
  public worker subnets, private RDS and an S3 gateway endpoint. It is not accepted.
- The 2026-09-28 redacted read-only probe confirmed IAM-user STS access and
  `us-east-1`; EKS/EC2/VPC/RDS quotas were captured. G/VT On-Demand and Spot
  quotas are both zero. Credit and exact prices remain `UNVERIFIED`; no AWS
  resource, quota request or account setting was changed.
- No AWS resource, local cluster, IAM policy or platform controller was created.
  The working tree is intentionally dirty for owner review before commit/push.

## Active objective

Review ADR-0006 and obtain credit/exact-price evidence so Task 5 can close without
weakening the 100 USD envelope; treat zero G/VT quotas as a later P6 blocker.

## Next actions

1. Owner reviews `docs/finops/COST_PLAN.md` and accepts, rejects or adjusts the
   cost/security trade-off proposed in ADR-0006.
2. Verify credit amount, applicable products and expiry through Billing console/API;
   installed AWS CLI `2.0.30` does not support `billing get-credits`.
3. Resolve exact EC2/RDS/GPU/network prices for `us-east-1` and verify the plan
   remains within each category envelope before P2.
4. Keep ADR-0005 `PROPOSED` until its later L2 kind micro-lab; Task 5 does not
   change the local-runtime gate.
5. Start Task 6 only after Task 5 account/owner gate is closed. Commit/push only
   when explicitly requested and never use `git add .`.

## Known blockers and unknowns

- Exact AWS credit applicability is not verified. Installed CLI cannot call
  `GetCredits`; Billing console or a newer approved client is required.
- GPU G/VT On-Demand and Spot quotas in `us-east-1` are both zero; a future
  owner-approved increase or documented fallback is required before P6 GPU trials.
- Exact chart/image/OCI digests are not yet resolved.
- AWS Region is selected as `us-east-1`. Network egress is proposed in ADR-0006
  but not approved; exact Region pricing is still open.
- Crossplane 2.4.0 + AWS provider 2.7.0, kro on Kubernetes 1.35 and OpenCost on
  Kubernetes 1.35 still require runtime evidence.
- kind is proposed but has no L2 evidence; ADR-0005 is not accepted.
- Crossplane and kro have not yet been practiced hands-on by the owner.
- Git branch protection, CI permissions, human AWS federation, EKS access entries,
  exact IRSA policies, IMDS restrictions, VPC CNI NetworkPolicy enforcement,
  secret integration, Kyverno behavior and RDS role grants are not runtime-verified.
- The original P1 calendar window has elapsed and must be rebaselined without
  weakening its acceptance criteria.

## Evidence pointers

- Canonical requirements: `docs/de_cuong_tot_nghiep_ver3.md`
- Teacher feedback: `docs/governance/gop_y_de_cuong_tu_thay_Kiet.md`
- Initialized roadmap: `.agent/docs/ROADMAP.md`
- Detailed current work: `.agent/specs/SPEC-P1_FOUNDATION_AND_COMPATIBILITY.md`
- Reviewed system design: `docs/architecture/SYSTEM_DESIGN.md`
- Accepted bootstrap/platform boundary: `.agent/adr/ADR-0003_BOOTSTRAP_PLATFORM_BOUNDARY.md`
- Accepted shared-RDS/recovery boundary: `.agent/adr/ADR-0004_SHARED_RDS_AND_RECOVERY_DATABASE.md`
- Task 2 learning evidence: `.agent/learning/LEARNING_LOG.md`
- Task 3 compatibility baseline: `docs/VERSION_MATRIX.md`
- Proposed local-first decision: `.agent/adr/ADR-0005_KIND_LOCAL_FIRST_ENVIRONMENT.md`
- Task 4 security design: `docs/security/THREAT_MODEL.md`
- Task 5 cost/quota/teardown plan: `docs/finops/COST_PLAN.md`
- Proposed PoC network egress decision:
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
- Task 5 L0 verification on 2026-09-28: `git diff --check`; required cost/ADR/
  threat-model paths found; six ADR IDs unique; Markdown fences balanced; required
  cost-plan sections found; envelope sum equals 100; no 12-digit account-ID or
  AWS access-key pattern found. Result: `TASK5_L0=PASS`.
- Git at checkpoint: HEAD `bb9ce630de63334039da1ab9729c82a81394506d`,
  dirty with the Task 4 review set listed by `git status --short`.

## Checkpoint rule

At session end, replace current status with observed results, exact verification
commands, evidence paths, current Git HEAD/dirty state, blockers, and the next
small action. Never paste a complete chat transcript into this file.
