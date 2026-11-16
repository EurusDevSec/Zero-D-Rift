---
id: SPEC-P8
title: Security Group remediation, RDS data recovery, pilot and campaign freeze
status: DRAFT_FABLE_20261116
phase: P8
start: TBD (owner rebaseline)
deadline: TBD (owner rebaseline)
schedule_baseline: ver3 §12 window 17–19/11 and the freeze gate of 19/11 cannot hold; owner rebaseline open
estimated_effort: 34-40 hours (ROADMAP allocates 24 h)
mode: Coach for drift (independent Security Group test first) and recovery, then Pair; Executor only for the harness once the scenarios are understood
canonical_scope: docs/de_cuong_tot_nghiep_ver3.md
linear: DRF-23 (SG drift), DRF-24 (RDS recovery), DRF-25 (campaign freeze); outline issues, split into P8-T tasks at the phase gate
authority: DRAFT_ONLY_NO_INSTALL_NO_AWS_NO_CONTRACT_CHANGE_NO_LINEAR_CHANGE
drafted_from: main at df275e4 (2026-11-16); P4–P7 runtime on EKS is UNVERIFIED
---

# 0. Draft status

Early draft written on 16/11/2026 at the owner's request. It is **not** the
active contract (AGENTS §7, `.agent/docs/FEATURES.md`). Before P8 starts: recheck
§2, refresh every dated fact in §13, let the second agent review the candidate
revision and get the owner's decisions on §9.1. Nothing in ver3 is reduced.

One finding from writing this draft needs the owner's attention before P8 and is
explained in §10: with the Crossplane AWS provider pinned in P3, a Security Group
rule that is **added** outside Git will probably **not** be removed. That is the
exact mutation ver3 §9.3 and H4 describe. It is a source reading, not a runtime
result; a short spike decides it.

# 1. Goal and boundaries

## Goal

Three results, in this order:

1. **Configuration remediation.** A Security Group managed by Crossplane is
   changed outside Git; the controller notices and puts it back; detection and
   remediation are timestamped (ver3 §6.6, §9.3; H4).
2. **Data recovery.** A separate PoC PostgreSQL instance loses data in a
   controlled incident; a recovery workflow restores it from a verified manual
   snapshot to a new instance, updates the connection secret, the application
   reconnects, and a checksum proves the data (ver3 §6.6, §9.4; H6).
3. **Pilot and freeze.** The test harness runs each experiment a few times end
   to end, cycle times are measured, every campaign precondition is met and a
   freeze record is approved (EXPERIMENT_PLAN §2, §12.2).

The two scenarios run independently, never inside one trial (ver3 §6.6). This is
the ver3 §12 exit criterion for P8: "Hai kịch bản độc lập pass; đo cycle time và
đủ preconditions trước freeze". Every run in P8 is a dry run (`official=false`).

Outcome trace: remediation and recovery are the third value group of the PoC
(ver3 §13 item 3); the freeze is the cross-cutting condition for all of P9.

## MUST deliverables

- `SPEC-P8` approved by the owner with decisions D1–D16 (§9.1) resolved.
- ADR for the drift mechanism: provider package, the registered mutation(s), poll
  interval, ownership of the lab Security Group. It closes "Crossplane
  management/deletion policy" for the EC2 path (SYSTEM_DESIGN §8).
- ADR for recovery: owner of the recovery database, incident type, automation
  level, secret and endpoint switch. It closes "Recovery RDS owner" (VERSION_MATRIX §3).
- Drift lab: provider package pinned by digest, lab Security Group and rule as
  platform objects, provider role and injector role in Terraform, mutation and
  observation scripts.
- Recovery lab: Terraform module for the source instance and roles, the recovery
  workflow script with approval steps and a refusal guard, sentinel writer and
  verifier, application deployment with its own secret.
- Runbooks `docs/runbooks/P8_SG_DRIFT.md` and `docs/runbooks/P8_RDS_RECOVERY.md`
  (the recovery runbook of ver3 §13 item 6), each with stop conditions, undo and
  "Tự thử".
- Test harness under `experiments/`: one runner per experiment, evidence bundle
  per EXPERIMENT_PLAN §8.1, redaction and secret scan, analysis script that
  produces the outputs of §9.3 from raw data and rejects synthetic rows.
- Pilot evidence and a cycle-time table; the P9 window plan and priced estimate
  derived from it.
- EXPERIMENT_PLAN v0.2.0 if any definition is sharpened (D13), approved by the
  owner before the freeze.
- Freeze record for the campaign and the Git tag of D15.
- Evidence under `docs/evidence/p8/`.

## Negative boundaries

1. Do not mix the two experiments in one trial. The sequential "double incident"
   is a demonstration only, after both tests are stable, and is never part of
   the dataset (ver3 §6.6).
2. Do not mutate any Security Group except the lab group. The cluster, node and
   database security groups are never a drift target (EXPERIMENT_PLAN §6.1).
3. Do not inject a rule that opens anything to the Internet. The lab group is
   attached to nothing and the injected rule uses a private, non-routable source.
4. Do not run a recovery action against the shared RAG database. The workflow
   must refuse it by name and by tag, and IAM must deny it (THREAT_MODEL T17).
5. Do not start an incident before the snapshot is `available` and the sentinel
   checksum is recorded.
6. Do not call a restore a recovery. Success needs the checksum **and** the
   application reconnecting (ADR-0004 item 7).
7. Do not claim full automation. If a human approves a step, the report says so
   (ver3 §12.1).
8. Do not set a target for RTO or RPO, and do not revive the two-minute figure
   (ver3 H6, §14).
9. Do not change a metric, timeout, success rule or sample size because of a
   pilot result. A design change before the freeze is allowed only with an ADR
   or changelog entry that states the reason (ver3 §15.2).
10. Do not promote a pilot run to an official trial.
11. Do not install `provider-aws-rds`, `provider-aws-iam` or the whole AWS
    provider family; do not let Terraform and Crossplane manage the same
    resource (ADR-0003, ADR-0008).
12. Do not keep a recovery instance, a snapshot or a lab resource after its
    window except on the retain allowlist with an expiry (COST_PLAN §11.3).
13. Do not freeze with an unresolved precondition, an unresolved redaction
    finding or an unreviewed contract change.
14. Do not run an AWS window without a separate execution approval, a fresh cost,
    identity and quota check, a stop time and a teardown owner.

# 2. Giả định từ phase trước (kiểm lại khi vào phase)

| # | Assumption | Source today | Recheck |
|---|---|---|---|
| A1 | P4, P5, P6 and P7 are accepted on EKS | drafts and SPEC-P4; nothing built | the four acceptance audits |
| A2 | The AWS provider pin is still `v2.8.1` (family and S3) on Crossplane `2.4.3` | VERSION_MATRIX §7 | VERSION_MATRIX; a newer provider may change §10 |
| A3 | In that provider, `SecurityGroup` cannot declare inline rules; rules are separate managed resources | provider source at tag `v2.8.1`, read 2026-11-16 (§13 S1) | read the installed CRD; spike of P8-T1 C |
| A4 | The provider checks each resource for drift on a poll interval whose default is about 10 minutes and which can be set per provider | author's recollection; the flag source could not be fetched | provider `--help` or source; spike |
| A5 | The P4 application re-reads its secret and reconnects after a connection or authentication error | SPEC-P4 P4-T3.1 A (planned, "needed again in P8") | P4 code and its unit test |
| A6 | The P2 network has private DB subnets and a DB subnet group that can host one more small instance | ADR-0006; SPEC-P4 §2 | network module outputs |
| A7 | The shared-RDS shape and PostgreSQL minor pinned in P4-T1 B can be reused for the recovery instance | SPEC-P4 D2 (minor not pinned yet) | VERSION_MATRIX "P4 pins" |
| A8 | Collectors, cost calculator and manifest writer from P7 exist; the isolation suite from P5 exists; both baseline runbooks and the profile from P7 exist | drafts | repository at the P8 gate |
| A9 | Both G/VT quotas are approved (the pilot runs one cost pair) | 0 today | `list-service-quotas` |
| A10 | R1 least privilege is still open; the Terraform role is AdministratorAccess | active context 14/11: "redo before DRF-27 or at DRF-29" | D14 |
| A11 | EXPERIMENT_PLAN is still v0.1.0 | approved 2026-09-29 | read it |
| A12 | Billing visibility chosen in SPEC-P7 D5 (tags, export) is switched on before the pilot | proposal | owner |
| A13 | Argo CD polls Git about every 3 minutes by default and a refresh can be requested | author's recollection | Argo CD docs for the pinned version |
| A14 | A restore of a small `db.t4g.micro` instance takes roughly 10–20 minutes | author's estimate, not measured | P8-T3.2 measures it |
| A15 | CloudTrail event history shows the mutation and the corrective API calls with caller and time, at no extra charge | author's recollection | AWS documentation; check in the spike |
| A16 | Enough of the 100 USD envelope and the 15 USD GPU and RDS lines remain | COST_LEDGER from P7 | ledger on the day |

# 3. Learning objectives

By the end of P8 the owner should be able to:

1. Explain what a managed resource "owns" and why a controller only repairs what
   it owns; apply it to a rule that was added, removed or changed.
2. Explain what determines detection time (poll interval, events, API latency)
   and why a reported remediation time must name the poll interval.
3. Separate configuration remediation from data recovery: what each restores,
   what each cannot restore.
4. Define RTO and RPO for this experiment from its exact start and end events,
   and predict the RPO from the snapshot time.
5. Explain why a restore creates a new instance, what must be switched, and why a
   human approval stays in the workflow.
6. Explain every precondition of the freeze and why the rules are fixed before
   the first official trial.

# 4. Acceptance scenarios

```gherkin
Scenario: The drift target is isolated and owned
  Given the lab Security Group created by Crossplane from Git
  Then it is attached to no network interface
  And the provider identity can change only Security Groups tagged for the lab
  And the injector identity is a different principal with the same limit

Scenario: A registered mutation is detected and remediated
  Given the lab group equal to its desired state
  When the injector applies a registered mutation and AWS acknowledges it
  Then a controller event or log shows the divergence
  And AWS describes the group as equal to the desired state again within the stop limit
  And both times are recorded with their sources

Scenario: Remediation is clean
  Given a remediated trial
  Then every declared rule is still present and no other rule changed
  And no further corrective call happens during the observation period

Scenario: What the controller does not repair is reported
  Given a mutation the pinned provider does not own
  When it is applied
  Then the observed outcome is recorded as it is
  And it is neither counted as a pass nor hidden

Scenario: Recovery preconditions are proven
  Given the recovery source instance with sentinel data
  When a manual snapshot is taken
  Then the snapshot is available and the sentinel checksum is recorded before any incident
  And the shared RAG database is not part of the plan

Scenario: The workflow refuses the wrong target
  When the recovery workflow is pointed at the shared database or an untagged instance
  Then it stops before any change
  And IAM denies the call if the script check is bypassed

Scenario: A controlled incident is recovered
  Given an approved incident on the recovery instance
  When the workflow restores the snapshot to a new instance and switches the secret
  Then the application reconnects without a redeploy
  And the restored sentinel rows match the recorded checksum
  And RTO and RPO are computed from the registered events
  And the shared database is unchanged

Scenario: A failed recovery is a result
  Given a restore that does not finish, or a checksum that does not match
  Then the trial is recorded as failed with its error class
  And cleanup still runs

Scenario: Recovery leaves nothing behind
  When the trial ends
  Then the damaged instance, the trial snapshot and temporary secrets are removed
        or are on the retain allowlist with an expiry
  And inventory matches

Scenario: The harness produces a complete, reproducible bundle
  When a pilot run of each experiment finishes
  Then its bundle has manifest, events, inventories, acceptance, redacted logs, cost and hashes
  And the analysis script rebuilds every table from raw files
  And a synthetic row is rejected from every official figure

Scenario: The campaign can be frozen
  Given measured cycle times, a window plan, a priced estimate and every
        precondition of the experiment contract
  When the owner approves the freeze record
  Then it names the contract version, commit, definitions, run plan, pair mapping,
       digests, evidence paths and analysis version
  And the commit is tagged
```

# 5. Work breakdown

## P8-T1 — Contract, decisions and the drift spike (6 h)

**A. SPEC, review, approval (1.5 h)** — recheck §2; second-agent review; owner
decides D1–D16 and the P8 gross cap.

**B. Pins and sources (1.5 h)**

- [ ] `provider-aws-ec2` at the family's pinned version: digest, the kinds it
      installs for Security Groups, the fields of `SecurityGroup` and of each
      rule kind, read from the CRDs (not from examples).
- [ ] Provider poll and sync flags and their defaults; how to set them through a
      `DeploymentRuntimeConfig`.
- [ ] RDS: restore parameters, snapshot and instance pricing, engine minor,
      time to `available` as documented; Secrets Manager pricing.
- [ ] VERSION_MATRIX gets a "P8 pins" section.

**C. Drift spike on EKS (1.5 h, a short approved window or the tail of another)**

One lab group, one declared inbound rule. Apply each mutation once and record
what the provider does and when:

- [ ] M1 — add a foreign inbound rule (the ver3 §9.3 mutation).
- [ ] M2 — revoke the declared rule.
- [ ] M3 — change the declared rule in place.

Record for each: corrected or not, time to correction, events and log lines that
can serve as "detection", CloudTrail entries, any repeat correction. Evidence:
`docs/evidence/p8/P8-T1_DRIFT_SPIKE_<date>.md`. The owner predicts all three
first.

**D. ADRs (1.5 h)** — drift mechanism (D1–D4) and recovery (D5–D9), written from
the spike result, accepted by the owner.

Gate: no drift or recovery implementation before part A; no H4 definition before
part C.

## P8-T2 — Security Group remediation (6 h)

**A. Terraform and manifests (2.5 h)**

- [ ] Module `drift-lab` behind `enable_drift_lab`: provider role (create,
      delete, authorize, revoke, modify and tag Security Groups limited by lab
      tag and VPC; describe actions as AWS requires) and injector role
      (authorize, revoke and modify on lab-tagged groups only).
- [ ] Provider package in the allowlist of `gitops/check.sh`; runtime config with
      the poll interval of D2; lab group and rule(s) as an Argo CD application.
- [ ] Plan assertions and IAM simulation: neither role can touch a group without
      the lab tag; guard tests.
- [ ] `inventory.sh` counts lab groups.

**B. Scripts (1.5 h)**

- [ ] `mutate.sh`: applies one registered mutation as the injector, logs request
      and response time in UTC, refuses any group without the lab tag.
- [ ] `observe.sh`: polls AWS at the contract interval until desired state or
      stop limit; collects controller events and the provider log window;
      watches for repeat corrections for the observation period.

**C. L3 lab (2 h)** — with the owner, in an approved window.

- [ ] Five dry trials of each registered mutation; times recorded as smoke.
- [ ] One trial of a mutation the provider does not own, if the ADR keeps one as
      a documented finding.
- [ ] Negative: injector against the node security group is denied.
- [ ] Delete the lab objects through Git; group gone on AWS; teardown.

## P8-T3 — RDS data recovery (9 h)

### P8-T3.1 — Module, workflow and kind rehearsal (5 h)

- [ ] Module `recovery-lab` behind `enable_recovery_lab`: source instance per
      D9, its security group (5432 from the node group only), recovery operator
      role limited to instances and snapshots with the recovery name prefix,
      application role for the one recovery secret.
- [ ] Sentinel writer: one row per second with sequence, UTC time and chained
      hash; a ledger of the same values kept outside the database.
- [ ] Verifier: restored rows are a prefix of the ledger and the chain is valid;
      reports the last restored time.
- [ ] `recover.sh`: preflight (target name and tag, snapshot `available`, ledger
      present) → approval prompt → incident per D6 → restore with every
      parameter explicit (subnet group, security group, class, storage type, not
      public, tags) → wait → approval prompt → switch the secret's host → wait
      for the application → verifier → write RTO, RPO and the event list.
- [ ] Refusal guard and its test: shared instance name, missing tag.
- [ ] Application: the P4 image as `recovery-app` in namespace `zdr-recovery`
      with the same guardrails as a tenant namespace.
- [ ] kind rehearsal with two in-cluster PostgreSQL instances standing in for
      "old" and "restored": secret switch, reconnect, verifier, RPO arithmetic.
      It proves nothing about RDS.

### P8-T3.2 — L3 lab (4 h)

- [ ] Window request; source instance created; application healthy; writer on.
- [ ] Owner predicts RPO from the snapshot time before the first run.
- [ ] Two dry recoveries end to end; restore duration, reconnect delay, RTO and
      RPO recorded as smoke; cycle time including cleanup recorded.
- [ ] Negative: workflow and IAM refuse the shared database name.
- [ ] One deliberately failed path (for example a wrong security group on
      restore) to see the failure class and the cleanup.
- [ ] Cleanup: instances, snapshots, secrets; teardown; inventory.

Stop conditions: those of SPEC-P4, plus: restore not `available` after
60 minutes; more than two recovery instances alive; any change observed on the
shared database; a snapshot or instance without the recovery prefix.

## P8-T4 — Harness, pilot and freeze (13 h)

### P8-T4.1 — Runners and analysis (6 h)

- [ ] Runners: `h1_rag`, `h2_batch` (also H3 and scale-down), `h4_drift`,
      `h5_pair` (baseline arm and optimized arm), `h6_recovery`,
      `baseline_manual` (sheet intake), `suite`. Each: preflight state check per
      EXPERIMENT_PLAN §4.2, clock check, inventory before, `t0`, end or timeout,
      acceptance map, cleanup, inventory after, bundle, hashes.
- [ ] `t0` for H1/H2: the time Argo CD first reports the target revision, read
      from its API; a refresh request before it is harness automation and is
      counted as an automated action.
- [ ] Redaction and secret scan with a synthetic marker secret (THREAT_MODEL T12).
- [ ] Analysis script: ledger, summary, hypothesis decisions, charts, pair table,
      recovery table; nearest-rank p95; `x/20` success format; no literal result.
- [ ] Dry run of the whole analysis on a synthetic dataset; a test proves
      synthetic rows are excluded (EXPERIMENT_PLAN §13).

### P8-T4.2 — Pilot (4 h, one approved window)

- [ ] Pilot set per D12, all `official=false`, `WARMUP_NOT_OFFICIAL`.
- [ ] Isolation suite once at the pilot commit.
- [ ] Cycle-time table: per experiment, `t0` to end, cleanup, inventory, total;
      observed, not estimated.
- [ ] Harness defects fixed; each fix recorded. No target, timeout or rule
      changes.

### P8-T4.3 — Preconditions and freeze (3 h)

- [ ] R1 least privilege per D14, then the access negatives again.
- [ ] Every item of EXPERIMENT_PLAN §2: clean Git and immutable commit; pinned
      versions and digests; Region, zones, instance types, capacity types,
      profile; clock check; inventory, Budget, remaining envelope, teardown
      owner; positive smoke for each path; timeouts, success checks, exclusion
      codes, evidence paths; no open redaction finding.
- [ ] EXPERIMENT_PLAN v0.2.0 with the items of D13, reviewed and approved.
- [ ] Window plan and priced estimate for P9 from the cycle-time table; go or
      no-go against the remaining envelope.
- [ ] Freeze record; owner approval with timestamp; Git tag per D15.

## P8-T5 — Acceptance: evidence, review, teach-back (3 h)

- [ ] Acceptance audit in `docs/evidence/p8/`: scenario → evidence, the spike
      result and the ADRs, limits.
- [ ] Delayed inventory and billing for every window; ledger updated.
- [ ] Independent review by the second agent, including the freeze record.
- [ ] Owner teach-back on §7; learning status from demonstration only.

# 6. Verification tiers

| Tier | P8 use | Evidence |
|---|---|---|
| L0 | Unit tests of scripts and analysis, static checks, Terraform tests, plan assertions | commands, exit status |
| L1 | Synthetic dataset through the whole analysis | outputs, hashes |
| L2 | kind: provider package health and CRDs; recovery rehearsal with two local databases | run ID, observed |
| L3 | EKS: drift spike and lab, RDS recovery, pilot | approvals, bundles, inventory |
| L4 | Not used in P8; the freeze record is its entry condition | freeze record |

# 7. Teach-back questions

1. Someone adds a rule to the lab group by hand. Does Crossplane remove it? Why,
   in terms of what it owns?
2. Remediation took 48 seconds in one trial and 6 in the next. What explains the
   difference?
3. What does Argo CD do during a Security Group drift, and why?
4. The snapshot was taken at 10:00:00 and the incident happened at 10:02:30.
   What RPO do you expect, and what could make it larger?
5. After the restore the application still fails. Name three places to look, in
   order.
6. Why does the workflow ask a human twice, and what would have to be true to
   remove those prompts?
7. Why are the Security Group test and the database test never run together?
8. The pilot shows H1 at 7 minutes. What are you allowed to change before the
   freeze, and what are you not?

# 8. P8 completion rule

P8 is complete only when the drift scenario and the recovery scenario each have
L3 evidence from independent runs, the drift mechanism and its limits are
recorded in an accepted ADR, the recovery runbook has been executed by the owner,
the harness has produced a complete bundle for every experiment in the pilot,
cycle times are measured, every precondition of EXPERIMENT_PLAN §2 is met, the
freeze record is approved and tagged, teardown and delayed inventory are clean,
an independent review has recorded findings and limits, and the owner reaches
`PRACTICED` + `EXPLAINED` for reconciliation ownership, snapshot restore and
RTO/RPO. If a precondition is missing, the freeze moves; P9 does not start
(ver3 §12).

# 9. Decisions, traceability and tracking

## 9.1. Decisions for the owner (D1–D16) — proposals, not approved

| ID | Decision | Proposal | Why | Alternative |
|---|---|---|---|---|
| D1 | The H4 mutation | Decide after the spike. If the spike confirms §10: register M2 or M3 (a change to a declared rule) as the H4 mutation through an ADR and EXPERIMENT_PLAN v0.2.0, and report M1 (added rule not removed) as a limitation with its own evidence | Keeps the pinned, already proven provider; the limit is a real finding about the tool | Keep M1 and add a mechanism that enforces an exclusive rule set: a newer provider resource if one exists, or the older community AWS provider whose Security Group has inline rules (a second, much larger provider package; compatibility unverified) |
| D2 | Poll interval | Set the EC2 provider's poll interval explicitly (proposal 60 s), fixed before the pilot, written in the run manifest and in the report next to every H4 number | Detection is poll-driven; with a 10-minute default H4 cannot be met and many trials would hit the 600 s stop | Provider default (H4 fails by design, reported as such) |
| D3 | Lab ownership | Crossplane `provider-aws-ec2` owns one lab Security Group and its rule(s), delivered by Argo CD as platform objects (no kro, not a golden-path request). Terraform owns the provider role and the injector role | VERSION_MATRIX §3 selected this package for exactly this experiment; one owner per resource | A kro graph around the group |
| D4 | Injector | A separate IAM role assumed from the owner's session, limited to lab-tagged groups | The actor is visible in CloudTrail as different from the controller; least privilege | The bootstrap role |
| D5 | Recovery database owner | Terraform owns the source instance, its security group and the roles. The recovery workflow owns each trial's snapshot and restored instance and removes them. No Crossplane | A restore creates a new instance each trial; putting that in Terraform state means an apply per trial | Terraform per trial with a snapshot variable; or `provider-aws-rds` |
| D6 | Incident | Logical destruction: drop the sentinel and application tables on the current recovery instance, acknowledged by SQL; the damaged instance is deleted after the trial | Exact `t0`; no waiting for an instance deletion; the common real-world case | Delete the instance without a final snapshot |
| D7 | Automation level | One script, two human approvals (before the incident, before the endpoint switch). Reported as "operator-approved runbook automation" | ver3 §5.3 and §12.1 keep a human approval | Remove the prompts after five clean dry runs (owner decides, with an ADR) |
| D8 | Application and switch | The P4 application in its own namespace with its own role and one secret; the workflow changes only the host in that secret; the application reconnects by itself | ADR-0008 secret flow; no DNS component | A Route 53 record or ExternalDNS (new component) |
| D9 | Recovery instance shape | Same as the shared instance of SPEC-P4 D2: PostgreSQL 17 pinned minor, `db.t4g.micro`, Single-AZ, 20 GB gp3, encrypted, private, no automated backup, no deletion protection; restore uses the same storage type | Priced; no post-restore backup delay; a storage change slows a restore | — |
| D10 | Sentinel and RPO | Writer adds a row every second; snapshot; writes continue for a fixed interval before the incident; RPO = incident time − last restored row time | Makes RPO non-zero and measurable from data, as EXPERIMENT_PLAN §6.1 defines it | Stop writes before the snapshot (RPO ≈ 0, less informative) |
| D11 | Harness shape | Bash runners and a small Python analysis script in `experiments/`, no framework, no service | Matches the existing scripts; reproducible offline | pytest harness (ver3 §7 allows either) |
| D12 | Pilot set | H1 × 2, H2 × 2, H4 × 3, one H5 pair, H6 × 1, suite × 1 | Every runner exercised; small enough for one window | A larger pilot |
| D13 | Contract v0.2.0 items | (a) H4 mutation and its end event; (b) poll interval as a recorded factor; (c) the per-run cost definition of SPEC-P7 D4; (d) H5: a pair counts toward the five only if its optimized arm ran on Spot, other pairs are reported separately; (e) scale-down "Pod absent" means no training Pod in a running phase and the Node gone; (f) which trials serve several metrics (five optimized cost arms inside the 20 batch trials; manual batch baseline runs as baseline arms); (g) trial order and tenant alternation; (h) the Argo CD `t0` source | Each is a gap or ambiguity in v0.1.0 that would otherwise be decided after seeing data | Leave v0.1.0 and decide case by case (not acceptable under ver3 §15.2) |
| D14 | R1 least privilege | Do it in P8 before the pilot, then rerun the access negatives | An IAM change after the freeze would invalidate the precondition "access tests rerun after IAM changes" | At DRF-29, with the campaign on the broad role and that limit stated |
| D15 | Freeze tag | Annotated tag `campaign-v1` on the frozen commit, pushed by the owner's instruction | ver3 §15.2 | Commit SHA only |
| D16 | P8 gross cap and windows | 8 USD for all P8 windows and retries, of which at most 1 USD GPU; four windows planned (spike, drift, recovery, pilot) | §11 | — |

## 9.2. Traceability

| Source requirement | Covered by |
|---|---|
| ver3 §6.6 independent experiments | negative boundary 1; separate runners |
| ver3 §6.6 `managementPolicies` from the pinned version only | P8-T1 B; ADR |
| ver3 §9.3 scripted, timestamped mutation; rule removed, valid rules kept, no loop | scenarios 2–4; §10; D1 |
| ver3 §9.4 steps 1–5 | scenarios 5–9; P8-T3 |
| ver3 §10.1 drift detected and corrected automatically | scenario 2; §8 |
| ver3 §10.1 recovery runbook, checksum, reconnect | scenario 7; runbook |
| ver3 §12.1 keep approval if automation is not safe | D7 |
| EXPERIMENT_PLAN §2 preconditions | P8-T4.3 |
| EXPERIMENT_PLAN §6 H4 and H6 events | D1, D10; runners |
| EXPERIMENT_PLAN §12.2 freeze record | P8-T4.3 |
| THREAT_MODEL T17, T18 | scenarios 6, 10 |
| DRF-23 | P8-T1 C, P8-T2 |
| DRF-24 | P8-T3 |
| DRF-25 | P8-T4 |

## 9.3. Independent review

Not done. This draft has had no second-agent review and no owner approval.

# 10. Why the H4 mutation may need to change

What ver3 and the contract say. ver3 §9.3: add an inbound rule outside the
desired state, then verify the rule is removed. EXPERIMENT_PLAN §6: the end event
is "injected rule absent and valid desired rules retained".

What the pinned provider does, from its source at tag `v2.8.1`
(`config/namespaced/ec2/config.go`, read 2026-11-16): for `aws_security_group`
it calls `config.MoveToStatus(r.TerraformResource, "ingress", "egress")` with the
comment "Mutually exclusive with aws_security_group_rule". So `SecurityGroup`
has no inline rules in its spec; rules are their own managed resources
(`SecurityGroupRule`, `SecurityGroupIngressRule`, `SecurityGroupEgressRule`).

What follows, as reasoning (not observed): a managed resource reconciles only the
external object it owns. A rule added by hand is owned by no managed resource,
and the group's own rule list is status only. The provider therefore has no
desired value to compare the extra rule against, and is expected to leave it in
place. A rule that **is** declared and is removed or changed by hand has an
owner and is expected to be put back. An "exclusive rule set" resource was not
found in the part of the provider's resource list that could be read (the file
was read to about 92 %).

What this draft does not know: the runtime behaviour on AWS; whether a newer
provider release adds an exclusive-rules resource; the provider's default poll
interval. The spike of P8-T1 C answers the first directly.

Consequences for the owner's decision D1:

| Option | H4 as written in ver3 | Cost |
|---|---|---|
| Register a change to a declared rule (M2 or M3) | The hypothesis text "returns to the declared state" still holds; the scenario text of §9.3 and the end event change, through an ADR and contract v0.2.0 before any official trial | The security story is weaker: an attacker's added rule is not reverted. This must be said in the report |
| Keep M1 and add an exclusive mechanism | Unchanged | A new provider or resource to pin, test and explain; possibly hundreds of extra CRDs on a small node (ver3 §6.2 warns against this) |
| Keep M1 with the pinned provider | Unchanged | H4 is expected to fail 0/20; a valid, honest result, but it uses 20 trials to show what the spike shows in one |

This draft recommends the first option together with one documented M1 trial as
a negative finding, and it is the owner's call. Whatever is chosen is fixed
before the pilot; it is a design decision made before data collection, not a
change made after seeing results (ver3 §15.2).

Timing under the first option, as an expectation to test: with a poll interval
`P` and little else in the path, time to correction is roughly uniform between
0 and `P` plus a few seconds of API time, so p95 ≈ 0.95 × `P`. `P` = 60 s would
put p95 near one minute against the 120 s target; the provider default, if it is
10 minutes, would not meet the target and would exceed the 600 s stop in some
trials. The H4 result is therefore largely a statement about the configured
interval, and the report must present it that way.

# 11. Cost of P8

Unit prices from COST_PLAN §5.2 (2026-09-28): cluster with two `m6i.large`
0.309 USD/h; `db.t4g.micro` 0.016 USD/h; RDS gp3 0.115 USD/GB-month; snapshot
storage 0.095 USD/GB-month; GPU node 0.537 USD/h On-Demand. All rechecked before
each window.

| Window | Cluster | Other | Estimate |
|---|---:|---:|---:|
| Spike, 1.5 h | 0.46 | — | 0.5 |
| Drift lab, 3 h | 0.93 | — | 0.9 |
| Recovery lab, 4 h | 1.24 | up to 2 instances × 4 h ≈ 0.15; snapshots and secrets in cents | 1.4 |
| Pilot, 7 h | 2.16 | shared RDS 0.13; recovery 0.10; GPU: two runs and one pair ≈ 0.80 | 3.2 |
| **Total** | | | **6.0** |

Proposed cap (D16): 8 USD, GPU part at most 1 USD. One recovery trial costs about
0.05 USD outside the cluster time: two small instances for about an hour.

# 12. Open risks

- **H4 as written may not be achievable with the pinned provider** (§10).
- **Poll interval dominates H4.** Choosing it is legitimate before the freeze and
  must be visible in the result.
- **Restore time is unknown** (A14) and sets the recovery cycle time and the P9
  plan. Lazy loading after restore can slow the first full read; the sentinel
  table is small.
- **Restore defaults.** Without explicit parameters a restored instance gets the
  default security group and parameter group (§13 S3). The workflow passes them
  and the failed-path test shows what a wrong one looks like.
- **Leftover recovery resources.** Each trial creates an instance and a snapshot
  outside Terraform state. Name prefix, tags, inventory and the stop condition
  are the controls.
- **Reconnect behaviour** (A5). If the P4 application caches a connection
  without retry, RTO grows or the trial fails; that would be a P4 defect to fix
  before the freeze, not a metric change.
- **Harness measuring itself.** Polling every 5 s adds up to 5 s of uncertainty
  (EXPERIMENT_PLAN §6); CloudTrail times are a cross-check, with their own
  delivery delay.
- **Pilot temptation.** A bad pilot number invites tuning. Only design changes
  with a recorded reason are allowed; targets, timeouts and rules are not.
- **R1 timing** (D14). Doing it late risks a failed apply close to the campaign;
  doing it never leaves the campaign on a broad role.
- **Effort.** 34–40 h against 24 h allocated: the harness and the freeze are
  larger than the ROADMAP line suggests. Nothing here is optional.
- **Schedule.** The 19/11 freeze cannot hold; the rebaseline is the owner's.

# 13. Sources and dated facts (recheck at P8-T1)

| # | Fact | Source | Checked | Status |
|---|---|---|---|---|
| S1 | In `provider-upjet-aws` `v2.8.1`, `aws_security_group` has `ingress` and `egress` moved to status; separate rule resources exist | [provider source, tag v2.8.1](https://github.com/crossplane-contrib/provider-upjet-aws/blob/v2.8.1/config/namespaced/ec2/config.go) and `config/externalname.go` | 2026-11-16 | `SOURCE_VERIFIED` for the configuration; behaviour on AWS `UNVERIFIED` |
| S2 | Latest provider release `v2.9.0`; P3 pin `v2.8.1` | [provider releases](https://github.com/crossplane-contrib/provider-upjet-aws/releases); VERSION_MATRIX §7 | 2026-11-16; 2026-11-05 | `SOURCE_VERIFIED` |
| S3 | A snapshot restore always creates a new DB instance; the default security group and parameter group apply unless specified; data loads lazily after `available`; changing storage type slows the restore | [RDS: restoring to a DB instance](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_RestoreFromSnapshot.html) | 2026-11-16 | `DOC_VERIFIED` |
| S4 | Provider poll interval default and flag name | — | could not be fetched | `UNVERIFIED` |
| S5 | `db.t4g.micro` 0.016 USD/h; RDS gp3 0.115 USD/GB-month; extra backup storage 0.095 USD/GB-month | COST_PLAN §5.2 | 2026-09-28 | `PRICE_API_VERIFIED`; recheck |
| S6 | Secrets Manager price per secret and per call | — | not looked up (also open in SPEC-P4 P4-T1 B) | `UNVERIFIED` |
| S7 | RDS restore duration for this shape | — | not measured | `ASSUMPTION` |
| S8 | CloudTrail event history content, delay and price | — | not looked up | `UNVERIFIED` |
| S9 | Argo CD default Git polling interval for the pinned version | — | not looked up | `UNVERIFIED` |
