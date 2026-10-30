# Linear and Codex/Claude setup — 2026-10-29

Status: IMPLEMENTED_SELF_VERIFIED_AWAITING_OWNER_OR_CLAUDE_REVIEW.
Verification snapshot: 2026-10-29, approximately 13:54 UTC / 20:54 Asia/Saigon.
This is static/tracker evidence, not a lab, AWS runtime or owner learning result.

## Authorization and baseline

Owner requested shared Claude/Codex workflow and creation of the agreed DRF
project/milestones/issues in Zero Door, with a recovery schedule starting today.
Existing restrictions on installation, lab, cloud/account/quota changes and Git
publication remain. No new scope/technology/metric/sample/cost allowance granted.

Live Git baseline: e8f6d69c03d7743bffa77c1e5256e52b08d790c1,
branch codex/context-terraform-dojo. Pre-existing dirty
.agent/tests/hydration/README.md and docs/evidence/hydration/ were preserved.
Setup documentation is a recorded dirty candidate, not an immutable official
experiment revision or remotely published Git artifact.

## Created and read back

- Workspace zero-door; new team Zero D-Rift / DRF. Team created through the
  observed Linear UI because the connector exposes no team-create operation.
- [Project](https://linear.app/zero-door/project/zero-d-rift-trien-khai-va-bao-ve-djo-an-0c6bb6af5f0d): start 29/10,
  target 02/12/2026, lead/assignee the verified Lê Văn Hoàng profile.
- 10 ordered milestones M1-M10, mapped to P2-P11; dates are working targets.
- 33 issues DRF-1–DRF-33; 13 current-bootstrap/tracking/prerequisite contracts
  and 20 future outcome outlines. All issue IDs are returned by Linear.
- Three team labels: approval-required, contract-pending, blocked; existing
  Feature/Improvement/Bug reused. No native points/cycles or existing team
  workflow changed; ZERO DOOR and S-cool objects were not modified.
- [Project entrypoint document](https://linear.app/zero-door/document/bat-djau-o-djay-workflow-nguon-yeu-cau-va-phoi-hop-codex-claude-a040364affe9).
- 45 blocking edges, all reverse relations checked; dependency graph acyclic.
  Report/runbook preparation has no artificial upstream start blocker; explicit
  finalization requirements are related links/AC.
- DRF-2 alone is Done from actual 02/10 P2-T1 accepted closure with L3 blockers;
  issue created on 29/10, no backdating/new runtime claim.
- DRF-1 handed off In Review; independent Claude review and owner acceptance
  pending. Remaining 31 issues Backlog, no fabricated started implementation.
- [Local routing/source index](../../../.agent/docs/LINEAR_DELIVERY.md).

| Milestone | Target | Returned issue IDs |
|---|---|---|
| M1 | 2026-11-02 | DRF-1, DRF-2, DRF-3, DRF-4, DRF-5, DRF-6, DRF-7, DRF-8, DRF-9, DRF-10, DRF-11, DRF-12, DRF-13 |
| M2 | 2026-11-05 | DRF-14, DRF-15 |
| M3 | 2026-11-08 | DRF-16, DRF-17 |
| M4 | 2026-11-10 | DRF-18 |
| M5 | 2026-11-14 | DRF-19, DRF-20 |
| M6 | 2026-11-16 | DRF-21, DRF-22 |
| M7 | 2026-11-19 | DRF-23, DRF-24, DRF-25 |
| M8 | 2026-11-25 | DRF-26, DRF-27, DRF-28 |
| M9 | 2026-11-29 | DRF-29, DRF-30, DRF-31 |
| M10 | 2026-12-02 | DRF-32, DRF-33 |

## Local changes

- AGENTS.md: shared agent/routing pointers and current roadmap horizon.
- CLAUDE.md: small entrypoint into the existing constitution/workflow.
- .agent/workflows/main-workflow.md: implementer/reviewer, one-writer claim,
  disjoint parallel work, environment serialization, handoff, daily learning and
  owner authority; no new independent roadmap.
- .agent/docs/LINEAR_DELIVERY.md: tracker/source/issue map and completion policy.
- Canonical ver3 section 12 only: 29/10 recovery schedule, capacity and gates;
  scope/hypotheses/metrics/acceptance and sections outside 12 unchanged.
- .agent/docs/ROADMAP.md: derived schedule and actual Task 1 closed/Task 2 pending.
- SPEC-P2: schedule metadata and explicit historical-window note only; P1
  constraints, learning objectives, acceptance and Tasks 1-9 unchanged.
- COST_PLAN section 7.4: historical 05/10 AWS window expired, new execution
  approval required; cap/retention/security/cleanup observations unchanged.
- Active context: fresh routing/schedule/freshness limits; learning files unchanged.

## Observed verification

1. Connector get_project: correct DRF team, lead, dates, 10 milestone names/dates.
2. list_issues: exactly 33, no next page. Full get_issue read-back for all 33:
   correct team/project/owner/milestone/due date; Outcome/Scope/AC/Dependencies/
   Security/Verification/Evidence/Next-action sections present.
3. Full relation read-back for all 33: 45 expected prerequisite edges, reverse
   blocks sides and finalization related links; no cycle or missing relation.
4. Local PowerShell checks exit 0: nine source/routing documents' relative links,
   sensitive patterns in additions, changed-line whitespace via git diff --check,
   new-file whitespace, ver3-only-section-12 boundary, unchanged SPEC acceptance/
   tasks/learning and no learning/infra/staged changes.
5. .agent/scripts/check-context.ps1 exit 0: CONTEXT_LINES=75, CONTEXT_CHECK=PASS.
6. Browser independently displays DRF team/project, source resources, M1-M10
   dates and 33 issues. Screenshot saved outside Git in the task visualization
   directory: linear-zero-drift-20261029.jpg.

Initial checker corrections are retained honestly: context required three exact
section headings, corrected then PASS; list_issues description previews were
truncated, so full get_issue bodies were used; a whole-file whitespace scan
flagged existing ver3 Markdown hard-break spaces, which were preserved while
changed lines/new files were checked. No acceptance was relaxed.

## Remaining limits and next action

Working schedule is not observed velocity or a confirmed school submission/
defense date. P9 48 h fit requires measured pilot cycle time; GPU quota/capacity,
component compatibility, pricing/budget and recovery remain risks.

Tracking/Markdown changes are local until separately authorized publication.
No CLI download/install, Terraform/lab command, AWS/account/backend/IAM/Budget/
quota operation, commit or push occurred. No lab/learning/runtime status advanced.

Next: owner/Claude review [DRF-1](https://linear.app/zero-door/issue/DRF-1/delivery-tracking-linear-va-workflow-codex-claude-dung-chung); then separately
authorize exact CLI install/verification [DRF-3](https://linear.app/zero-door/issue/DRF-3/terraform-cli-cai-va-xac-minh-exact-pin-1164) and
local-only lab [DRF-4](https://linear.app/zero-door/issue/DRF-4/terraform-state-hoan-thanh-lab-local-va-giai-thich-dependency). A reviewer must read actual diff
and current Git/Linear state, not accept this self-verification as independence.


## Phase naming alignment — owner-approved 2026-10-29

The owner reversed the extra M1-M10 naming convention: use repository phases
P2-P11 directly on Linear, while retaining the 29/10 recovery schedule. The M
names in the earlier sections above are a historical setup snapshot, not current
routing. No new milestone/issue objects were created for this change.

- Renamed the same 10 milestone IDs to P2-P11, keeping order and target dates.
- Restored ROADMAP's original phase-table columns: ID, Dates, Status, Technical
  outcome, Learning focus, Exit criteria; P0-P11 appear once each. Current
  dates/status remain truthful; the missed early-October calendar was not restored.
- Aligned canonical ver3 section 12, SPEC-P2 schedule note, active context,
  shared workflow, Claude entrypoint and Linear routing/source index.
- Aligned project/document descriptions and 10 issue bodies by narrow text
  patches. Existing user/reviewer AC checkmarks and other concurrent content
  were preserved; no issue status was changed.
- Fresh read-back: 33 same issue IDs/UUIDs, owners, statuses, dates and milestone
  membership; all 45 blocking relations and related links unchanged. Project
  start/target remains 29/10-02/12. No old M code in active repo/tracker text.
- Verification: git diff --check exit 0; phase table 12 unique rows P0-P11;
  check-context.ps1 PASS at 75 lines; learning/infra unchanged. One transient
  connector send error on project update was reconciled by read-back (not
  applied), then the narrow patch completed successfully.
- Earlier evidence and screenshot remain historical; no AWS, Terraform,
  installation, commit or push occurred. Execution/learning boundaries unchanged.
