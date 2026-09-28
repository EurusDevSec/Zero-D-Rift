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
