# Zero D-Rift Workflow History

This is a concise milestone ledger, not a chat transcript.

## 2026-08-23 — Project-specific Eurus initialization

- Created a root-level project constitution and `.agent` state so sessions that
  start at the Zero D-Rift root do not load sample state from the nested framework.
- Declared `docs/de_cuong_tot_nghiep_ver3.md` the canonical implementation scope.
- Created the delivery roadmap, architecture map, learning workflow, active P1
  spec, evidence-aware Definition of Done and safe checkpoint policy.
- Replaced automatic commit/push behavior with explicit owner approval.
- Replaced the universal five-second test rule with L0–L4 verification tiers.
- Verified all required project-state pointers and validated all six local skills
  with the bundled skill validator.
- No AWS resource, infrastructure code, workload code or experiment was created.
- Git commit/push intentionally not performed by initialization.

## 2026-08-23 — P0 persisted and reusable framework removed

- Committed and pushed the self-contained root `AGENTS.md`, `.agent/` and canonical
  documentation in `52c02ce`.
- Restored proposal records unchanged under `docs/governance/` and historical
  drafts under `docs/archive/`.
- Removed the reusable framework source in `2a5e6a4`; no active project workflow
  depends on it.
- Verified local `main` equals `origin/main` with a clean working tree before the
  final P1 handoff corrections.
- Activated `SPEC-P1`; its initial governance check was subsequently closed after
  the owner confirmed the approved document lineage.

## 2026-08-23 — P1 governance lineage confirmed

- Owner confirmed that teacher feedback was incorporated in ver2 and ver3 is the
  implementation-focused optimization of ver2.
- Closed P1 Task 1 without a redundant full document comparison.
- P1 next work is Task 2: system design and architectural ADRs.

## 2026-09-25 — P1 Task 2 architecture foundation completed

- Reviewed and corrected `docs/architecture/SYSTEM_DESIGN.md` within the active
  P1 scope.
- Accepted ADR-0003 for the Terraform/OpenTofu bootstrap boundary and ADR-0004
  for the shared RDS and isolated recovery-database boundary.
- Completed owner teach-back for bootstrap ordering, single resource ownership,
  shared-RDS trade-offs, and the distinction between IRSA/IAM authorization and
  PostgreSQL privileges; recorded the learning state as `EXPLAINED`.
- Passed documentation-level L0 checks for diff whitespace, unique ADR IDs,
  accepted statuses and referenced evidence paths.
- No AWS resource or platform controller was created; the next bounded work is
  P1 Task 3, the version and compatibility matrix.

## 2026-09-28 — P1 Task 4 learning gate closed and Task 5 cost plan drafted

- Closed Task 4 owner teach-back at `EXPLAINED`: the owner separated successful
  workload identity from over-broad S3 authorization and identified STS caller,
  CloudTrail data events and policy review as required evidence.
- Created `docs/finops/COST_PLAN.md` with the canonical 100 USD envelope, dated
  AWS pricing/quota sources, Budget/TTL/GPU guardrails, daily billing loop and
  pre/post-teardown inventory contract.
- Proposed ADR-0006: no default NAT Gateway, public worker subnets with restricted
  ingress, private RDS and a no-additional-charge S3 gateway endpoint for the PoC.
- A later redacted read-only probe confirmed `us-east-1` and captured EKS/EC2/VPC/
  RDS quotas. Both G/VT On-Demand and Spot quotas are zero; credit applicability,
  exact prices and ADR approval remain open.
- No AWS resource, Budget, quota request or infrastructure mutation was performed.

## 2026-09-29 — P1 Task 5 cost/account gate closed

- Verified one enabled 100 USD Promotion credit with 100 USD remaining through
  2027-06-13; the owner's possible second guide reward remains unverified and does
  not expand the canonical 100 USD gross project envelope.
- Captured candidate `us-east-1` On-Demand prices from AWS Price List API and
  produced a 61.60 USD known planning subtotal within category guardrails.
- Accepted ADR-0006 after owner review: no default NAT Gateway, public worker
  nodes with bounded exposure, private RDS and an S3 gateway endpoint.
- Closed the Task 5 learning gate at `EXPLAINED`; owner distinguished Pod
  scale-to-zero from teardown of persistent/fixed-cost AWS resources.
- No AWS resource, Budget or quota request was created; G/VT On-Demand and Spot
  quotas remain zero for the future GPU campaign.

## 2026-09-29 — P1 Task 6 experiment contract closed

- Approved experiment contract v0.1.0 with H1–H6 boundaries, reproducible manual
  baselines, event and timeout rules, retained failures, registered exclusions,
  data schemas and campaign-freeze requirements.
- Parsed one dry manifest marked `SYNTHETIC`, `official=false` and `EXCLUDED`; it
  is schema evidence only and cannot enter official metrics.
- Closed the learning gate at `EXPLAINED`: the owner distinguished real post-`t0`
  system outcomes from invalid measurements and explained why rules must be
  frozen before results to prevent biased exclusions.
- No observed trial or AWS resource was created. A later campaign freeze and
  runtime evidence remain required; active work moves to P1 Task 7.

## 2026-09-29 — P1 closed; P2 bootstrap spec drafted

- Completed the P1 cross-document review against ver3 and corrected stale status
  references for ADR-0005/0006, Region/cost evidence and the Task 6 evidence contract.
- Closed Task 7 teach-back at `EXPLAINED`, not mastered: the owner diagnosed
  reconciliation/AWS boundaries, IRSA trust versus permission and soft-isolation
  limits; hands-on gaps remain assigned to P2-P5 micro-labs.
- Created `.agent/specs/SPEC-P2_REPRODUCIBLE_EKS_BOOTSTRAP.md` as
  `DRAFT_FOR_OWNER_APPROVAL`, with a zero-cost Terraform state micro-lab before
  any explicitly approved EKS apply and a mandatory teardown/orphan audit.
- Recorded that the original schedule has slipped and must be rebaselined during
  P2 Task 1 without weakening acceptance criteria.
- No local cluster, platform controller, IAM policy or paid AWS resource was created.
