---
id: SPEC-P7
title: Cost and utilization instrumentation, cost contract and reproducible manual baseline
status: APPROVED_20261128 (owner approved D1–D13 on 28/11)
phase: P7
start: 2026-11-28
deadline: 2026-11-29 (local part 28/11; L3 part in the joint P7+P8 window of 29/11)
schedule_baseline: ROADMAP "Rebaseline 28/11" (product and report by 09/12, defense 30/12)
estimated_effort: about 12 h local on 28/11 + about 4 h of the 29/11 window
mode: Pair (Claude implements; the owner runs the hand calculation, the two baselines and the teach-back)
canonical_scope: docs/de_cuong_tot_nghiep_ver3.md
linear: DRF-82 (T1), DRF-83 → DRF-85/86 (T2), DRF-87 (T3), DRF-88 (T4), DRF-84 → DRF-89/90 (T5); DRF-21/22 cancelled as superseded
authority: LOCAL_AND_KIND_ONLY; AWS window needs a separate owner approval
drafted_from: Fable draft 16/11 (`claude/specs-p5-p9-draft-ecc762`, `e0aca8f`), rebased on main `e59648e` after P6 closed
---

# 0. Status and what changed from the 16/11 draft

The 16/11 draft assumed a GPU node and two separate P7 windows. Since then:

- P6 ran on **CPU** nodes created by Karpenter (ADR-0009). Every batch result in P7 carries `CPU_SUBSTITUTE_FOR_GPU`; there is no GPU field, no GPU request and no DCGM.
- P6 is accepted and its learning gate is closed (DRF-81, 28/11).
- The school fixed the dates on 28/11: product and report by 09/12, defense 30/12. The owner keeps full scope and compresses the schedule (ROADMAP "Rebaseline 28/11").
- Therefore P7 has **one** L3 part, run inside the joint P7+P8 window of 29/11. Everything that does not need AWS is done on 28/11.

The draft's goal, negative boundaries and completion rule are kept. Nothing in ver3 is reduced.

# 1. Goal and boundaries

## Goal

Make cost and utilization measurable before any official trial, and make the comparison side of the experiments reproducible:

- a pinned Prometheus and OpenCost that show allocation per namespace and workload while the cluster runs, and whose raw data is exported before teardown;
- a **cost contract**: for one run, which instance seconds and which unit price give its variable compute cost, where each number comes from, and how it is later reconciled with AWS billing;
- a cost ledger that keeps variable compute, cluster fixed cost and the other categories of ver3 §8.4 apart;
- two manual baseline runbooks (RAG and batch) that the owner executes once each in the 29/11 window, with the same acceptance checks as the platform path and a written interaction count;
- one locked batch workload profile for the H5 matched pairs, fixed before any cost is seen.

This is the ver3 §12 exit criterion for P7: "Dashboard/raw metrics, cost contract và baseline tái lập được". Every P7 run is a dry run (`official=false`, `WARMUP_NOT_OFFICIAL`). H5 and the manual comparison are measured in P9.

## MUST deliverables

- This SPEC approved by the owner, with D1–D13 (§9.1) decided.
- Prometheus and OpenCost as pinned Argo CD applications, images by digest, with a kind smoke on Kubernetes 1.35 before the EKS window.
- `experiments/lib/export_metrics.sh`: raw Prometheus series and OpenCost allocation for a UTC window, to JSONL/JSON with `hashes.sha256`, taken before teardown.
- `experiments/lib/`: instance timeline collector, cost calculator and run manifest writer, with unit tests on synthetic inputs marked `SYNTHETIC`.
- `docs/finops/COST_MEASUREMENT.md`: the D4 cost contract, the known differences between the three cost sources, and the D5 reconciliation rule.
- `docs/finops/COST_LEDGER.md`: gross cost by phase and by ver3 §11 category, with source and billing status; P2–P6 backfilled from the owner's Billing readings already in evidence.
- Runbooks `docs/runbooks/BASELINE_RAG_MANUAL.md`, `docs/runbooks/BASELINE_BATCH_MANUAL.md` (EXPERIMENT_PLAN §5.2, §5.3), an interaction sheet template, and the P7 part of the joint window runbook.
- Workload profile `batch-cpu-small-v1` with every field of EXPERIMENT_PLAN §7.
- Evidence under `docs/evidence/p7/`: kind smoke, the window part, the hand calculation, exports, cost.

## Negative boundaries

1. Do not present an OpenCost number as the AWS bill, and do not present any cost as final while billing data is pending. Pending is `PENDING`, never zero (EXPERIMENT_PLAN §10 rule 9).
2. Do not say or imply that Pods at zero means cost at zero (ver3 §8.4). The ledger always shows the fixed categories.
3. Do not use a fixed Spot discount as a result. A Spot price is read for the zone and the time of the run (COST_PLAN §4 rule 5).
4. Do not add components beyond Prometheus and OpenCost: no Grafana, Alertmanager, Pushgateway, DCGM exporter, Loki, Athena, Kubecost, or a persistent volume driver, unless the owner changes D1, D2 or D6.
5. Do not give OpenCost or Prometheus an AWS identity (D3).
6. Do not call the Cost Explorer API from scripts (billed per request, COST_PLAN §7.4). The owner reads the console.
7. Do not change an account billing setting (cost allocation tags, data export, Budget) yourself. The owner makes the change in the console after approving that exact change (D5).
8. Do not let the manual baseline use anything the platform path does not get: same shared database, same pre-created roles, same image, same checks. Never the database master credential.
9. Do not hide automation inside "one step" of a baseline: a script counts as one interaction **and** its automated actions are recorded (EXPERIMENT_PLAN §5.1).
10. Do not change the idle window, timeouts or counting rule of EXPERIMENT_PLAN §5.4. Do not choose the workload profile after seeing a cost.
11. Do not hard-code a measured value in any script or report generator.
12. Do not count a P7 run as an official trial, and do not promote one later.
13. Do not run an AWS window without a separate execution approval, a fresh cost, identity and quota check, a stop time and a teardown owner.
14. No GPU field, GPU request, GPU NodePool or GPU conclusion (ADR-0009).

# 2. Assumptions from earlier phases (rechecked 28/11)

| # | Assumption | State on 28/11 | Recheck |
|---|---|---|---|
| A1 | P6 accepted: batch end to end on a Karpenter CPU node, node reclaimed | **Met.** Audit `P6_ACCEPTANCE_AUDIT_20261127.md`; gate closed 28/11 | — |
| A2 | Standard vCPU quota fits system (4) + batch (2) + manual baseline node (2) | On-Demand 8, Spot 8 (read 26/11) | T−30 of the window |
| A3 | P4 and P5 accepted; RAG path, credential tiers, tenant guardrails exist | **Met** | — |
| A4 | Two `m6i.large` system nodes have room for Prometheus (server, kube-state-metrics, node exporter) and OpenCost on top of P3–P6 | Unverified; tightest point so far | Pod count and memory at window start; fallback in §11 |
| A5 | No storage driver add-on, so Prometheus has no persistent volume | Module unchanged | module at the window revision |
| A6 | OpenCost works on Kubernetes 1.35 | **Met on kind 1.35.8** (P7-T2.1, 28/11): allocation rows per namespace; EKS pending | window |
| A7 | Project tags (`Project`, `RunId`, `ExpiresAt`, `ManagedBy`) on Terraform resources and on Karpenter instances and volumes | Seen on P6 instances (count by tag in T4.2 §6) | describe one batch instance in the window |
| A8 | EXPERIMENT_PLAN v0.1.0 unchanged: §5, §5.4, §7 | Unchanged except the ADR-0009 CPU wording | read again; D4 may need v0.2.0 |
| A9 | The owner can read Bills and Cost Explorer in the console | Done for P5 and P6 | — |
| A10 | A project Budget with alerts exists | Unknown | owner reads Budgets |
| A11 | Linux instances billed per second with a one-minute minimum, On-Demand and Spot | On-Demand `DOC_VERIFIED` (S5); Spot not stated on the Spot pricing page | EC2 User Guide before T3 `cost_calc` rounding |
| A12 | P4 `db-init`, `bootstrap`, `cleanup` entry points exist for the manual RAG baseline | Met (P4) | — |
| A13 | P6 training image is pinned by digest; default 300 steps ≈ 5 min, checkpoint every 25 steps (SPEC-P6 D10) | Met | VERSION_MATRIX "P6 pins" |

# 3. Learning objectives

By the end of P7 the owner should be able to:

1. Compute the variable compute cost of one run by hand from instance start and end times and a unit price, and say which seconds are billed.
2. Separate variable compute cost, cluster fixed cost, other AWS cost and the invoice, and place any line of the bill in one of them.
3. Explain what OpenCost measures (allocation of node cost to workloads from requests and usage), what price it uses, and why it is not the bill.
4. Explain why billing data arrives late and what `PENDING` protects against.
5. Explain why the baseline is a reference procedure of the project and not a measurement of any company, and how one interaction is counted.
6. Explain why the profile is locked before any cost is seen, and how run length changes the H5 ratio (P6 teach-back Q7).

# 4. Acceptance scenarios

```gherkin
Scenario: The metrics stack is pinned and bounded
  Given approved chart versions and image digests
  When Prometheus and OpenCost are installed through Argo CD
  Then only the approved components run, none has an AWS identity and none has a persistent volume
  And the platform and both golden paths still pass their checks

Scenario: Allocation is visible while a workload runs
  Given one batch smoke run on a Karpenter CPU node
  Then OpenCost shows cost for the tenant namespace over that window
  And the view separates CPU and memory and shows idle cost
  And the raw series and the allocation export are saved with hashes before teardown

Scenario: The cost of a run is computed from raw inputs
  Given the instance timeline of the smoke run and the price sources of the contract
  When the cost calculator runs
  Then its result equals the owner's hand calculation within rounding
  And every input has a source, a timestamp and a hash
  And a missing price or a missing end time produces an error, not zero

Scenario: Three sources are compared honestly
  Given computed cost, OpenCost allocation and AWS billing for the same window
  Then each difference is either inside the registered tolerance or explained by a registered cause
  And billing that has not arrived is recorded as PENDING

Scenario: Fixed cost stays visible
  Given all workload Pods at zero and no batch node
  Then the ledger still shows control plane, system nodes, public IPv4, database, storage and log cost for the window

Scenario: The manual RAG baseline is reproducible
  Given the versioned runbook and a clean per-request inventory
  When the owner executes it once
  Then the same independent readiness and database checks as the platform path pass
  And interactions, commands, automated actions, waits and errors are recorded by the rule
  And per-request resources are removed and inventory is clean

Scenario: The manual batch baseline is reproducible
  Given the locked profile and one On-Demand CPU node created by the runbook
  When the owner executes the runbook once
  Then the TRAINING_STARTED marker, the checkpoint and the artifact exist
  And the node is held for the locked idle window and then removed
  And instance, volume and public address are gone

Scenario: Teardown keeps the evidence
  When the window ends
  Then exports are taken first, then controllers and the bootstrap are removed
  And inventory shows nothing outside the retain allowlist
```

# 5. Work breakdown

## 28/11, local (no AWS)

### P7-T1 — Contract (1.5 h)

- [ ] This SPEC; owner decides §9.1. Codex review is skipped for the SPEC (time; the guardrail code in T2 gets the review).
- [x] Pins: Prometheus chart and OpenCost chart versions; image digests resolved at T2.1; VERSION_MATRIX "P7 pins" (§11).
- [x] Read the OpenCost AWS pricing page for the pinned version (§12 S4) and the EC2 billing granularity (S5); Spot granularity still open.
- [ ] **Owner micro-lab (15 min):** from fixed inputs the owner computes both arms of one pair and the saving ratio on paper. The worked result becomes the first `SYNTHETIC` unit test.

### P7-T2 — Metrics stack (4 h)

**T2.1 Manifests and kind smoke (3 h).**

- [x] Argo CD applications per D1 and D2: requests and limits, scrape interval and retention in Git, no PV, Alertmanager and Pushgateway off.
- [x] `gitops/check.sh`: chart versions exact, images by digest, no component outside D1/D2, no ServiceAccount annotation for IRSA on either.
- [x] kind (Kubernetes 1.35, ADR-0005): both install; OpenCost reaches Prometheus; an allocation query for a test namespace returns rows. Record what kind cannot show (no AWS prices, no real nodes).

Evidence: `docs/evidence/p7/P7-T2.1_L2_KIND_OPENCOST_20261128.md`.

**T2.2 Export (1 h).**

- [ ] `export_metrics.sh`: named queries over a UTC window to JSONL; OpenCost allocation by namespace, controller and Pod; `hashes.sha256`; no account or instance identifier in committed output.
- [ ] Named queries: node count by pool and capacity type over time; CPU and memory requested versus allocatable; Pod phase timeline of the training Job; CPU and memory use of the tenant namespaces.
- [ ] Dry run on kind; shape checked against EXPERIMENT_PLAN §9.2.

### P7-T3 — Cost contract and ledger (3.5 h)

- [ ] `COST_MEASUREMENT.md` per D4, D5: definitions, sources, formula, rounding, tolerance, registered causes of difference, `PENDING` rule.
- [ ] `collect_timeline.sh`: NodeClaim and Node events, EC2 launch and termination times, instance type, capacity type and zone, with aliases instead of instance IDs.
- [ ] `cost_calc`: variable compute per run and per arm; fixed categories per window from inventory hours and unit prices; refuses missing inputs.
- [ ] Unit tests: the owner's hand pair, a Spot price change inside a run, a run under one minute, a missing termination time, pending billing.
- [ ] `COST_LEDGER.md` with P2–P6 rows from the Billing readings already in evidence; each row has gross amount, category, source and status.

### P7-T4 — Baselines and the locked profile (3 h)

- [ ] RAG baseline runbook: steps 1–8 of EXPERIMENT_PLAN §5.2 as exact commands, D8 equal footing.
- [ ] Batch baseline runbook: steps 1–8 of §5.3; one On-Demand CPU node by D7; plain Job manifest without KEDA; marker and checkpoint checks identical to P6; 1,800 s idle hold with a visible timer; removal and inventory.
- [ ] Profile `batch-cpu-small-v1` (D9) and the interaction sheet; the same counting rule written for the platform path.

## 29/11, inside the joint P7+P8 window

### P7-T5 — L3 part and acceptance (about 4 h of the window)

- [ ] Platform, batch platform, RAG platform, Prometheus, OpenCost; wait until OpenCost has node prices.
- [ ] Idle observation with no workload: what is still running and what it costs per hour.
- [ ] One batch smoke; timeline collected; OpenCost view captured; exports; calculator run; compare with the owner's hand result.
- [ ] Owner executes the RAG baseline once, then the batch baseline once; Claude only keeps the sheet. Both measured for cycle time (preflight to clean inventory) for the P9 plan.
- [ ] Exports before teardown; the P8 part of the window follows; joint teardown and inventory.
- [ ] Acceptance audit `docs/evidence/p7/P7_ACCEPTANCE_AUDIT_<date>.md`; next-day billing read by the owner (ledger rows leave `PENDING` or keep it with the reading date); Codex review of the audit; teach-back §7.

Stop conditions: those of SPEC-P6, plus: a baseline step that needs a credential the platform path does not use; the idle hold exceeded by more than 5 minutes; any capacity created by hand still present at the stop time.

# 6. Verification tiers

| Tier | P7 use | Evidence |
|---|---|---|
| L0 | Unit tests of the calculator and collectors, static checks, CI | commands, exit status |
| L1 | Synthetic manifest and events through the export and calculator pipeline | output files, hashes |
| L2 | kind: Prometheus and OpenCost on Kubernetes 1.35 | run ID, query output |
| L3 | EKS: allocation with a real Karpenter CPU node, timeline, computed cost, baselines, teardown | approval, exports, sheets, inventory |

# 7. Teach-back questions

1. A batch node ran from 02:00:10 to 02:14:40 UTC. Which seconds are billed, at which price, and where does each number come from?
2. OpenCost shows a lower or higher cost for the same run than your calculation. Give two reasons that are not bugs.
3. The bill for yesterday is not there yet. What do you write in the dataset, and what do you not write?
4. Pods are at zero for an hour. List what was still billed in that hour.
5. Why is running a script one interaction and not zero, and not twenty?
6. What would make the baseline unfair to the platform, and what would make it unfair to the manual side?
7. Why must the profile be fixed before the first cost pair?

The teach-back may run after 09/12 and before the defense (ROADMAP "Rebaseline 28/11"); until then P7 is "technically accepted".

# 8. P7 completion rule

P7 is complete only when every scenario in §4 has L3 evidence, the cost of one real run has been computed by the calculator and by the owner by hand with the same result, the three sources have been compared with billing either reconciled or explicitly `PENDING`, each baseline has been executed once by the owner with a complete sheet, the profile is recorded, teardown and delayed inventory are clean, an independent review has recorded findings and limits, and the owner reaches `PRACTICED` + `EXPLAINED` for the cost arithmetic, OpenCost allocation and the baseline method.

# 9. Decisions, traceability and tracking

## 9.1. Decisions (D1–D13): approved by the owner on 28/11/2026

| ID | Decision | Proposal | Why | Alternative |
|---|---|---|---|---|
| D1 | Prometheus distribution | Community `prometheus` chart `30.0.1` (app `v3.16.0`; candidate `31.0.0` rejected at T2.1: downloaded tgz ≠ index digest): server, kube-state-metrics, node exporter; Alertmanager and Pushgateway off; no PV; retention one window | Fewest Pods and CRDs; data exported before teardown | kube-prometheus-stack (operator, more Pods and CRDs) |
| D2 | Dashboard | OpenCost UI during the window, recorded; plus a static offline report from the exported data | ver3 §13 asks for an offline dashboard for the defense; no extra component | Grafana |
| D3 | OpenCost identity and prices | No AWS identity; public On-Demand prices; no Spot data feed; no billing integration. OpenCost is the allocation view only | No new IAM, bucket or query service; billing stays the reconciliation source | Spot data feed and billing integration |
| D4 | Cost contract for a run | Variable compute = billed instance seconds × unit price + volume GB-seconds × volume price. On-Demand price from the Price List, recorded in the run manifest; Spot price from Spot price history for that type and zone over the run; instance seconds from EC2 launch and termination | Available minutes after a run, reproducible, independent of OpenCost's Spot handling | Wait for the bill and use it as the only source |
| D5 | Reconciliation and tags | Owner reads Billing per window. Tolerance between computed and billed variable compute per window: 5 % or 0.02 USD, whichever is larger; otherwise a registered cause. **The owner activates cost allocation tags `Project` and `RunId` on 28/11** (not retroactive). No data export | A rule fixed before any pair; tags must be on before P9 | Console only, no tags (window-level reconciliation only) |
| D6 | Utilization | CPU and memory requested versus allocatable and used, from kube-state-metrics and node exporter. No GPU metric (ADR-0009) | H5 needs time and price | — |
| D7 | Capacity for the batch baseline | The owner creates one On-Demand CPU node by AWS CLI commands in the runbook (node role and subnets from Terraform outputs) and deletes it the same way | "Manual" means typed commands, as EXPERIMENT_PLAN §5 asks | A Terraform variable that adds one node (safer cleanup, hides many actions in one apply) |
| D8 | Equal footing for the RAG baseline | Same shared database, pre-created tenant role, image and checks; SQL by hand with the bootstrap tier from a platform Pod; bucket under the tenant prefix | The comparison is about steps and time, not rights | Baseline creates its own role and policy |
| D9 | Locked profile | `batch-cpu-small-v1`: P6 image by digest, 300 steps (≈ 5 min), checkpoint every 25 steps, CPU 500m / memory 384Mi request, **one instance type `m5.large` for both arms of every H5 pair**, gp3 root as Karpenter sets it, idle window 1,800 s, workload timeout 2,700 s | Same type in both arms (EXPERIMENT_PLAN §7); `m5.large` ran on Spot in P6. A 5-minute run favours the platform strongly (P6 teach-back Q7), so the report states the profile and does not generalise | Keep the 3-type allowlist and pair by observed type |
| D10 | Ledger | `docs/finops/COST_LEDGER.md`, gross, by phase and ver3 §11 category, with status | COST_PLAN §8.2 step 5 | Spreadsheet outside Git |
| D11 | Harness scope in P7 | Collectors, calculator and manifest writer only. Trial runners and the analysis script are P8 | Keeps P7 to measurement | Build the runners here |
| D12 | P7 gross cap | 2 USD for the P7 part of the joint window (metrics, one smoke, two baselines); the window total is set in the P8 window request | One window instead of two | — |
| D13 | Real PyTorch training and real RAG (agreed 27/11) | **Not** in the campaign. The locked profile keeps the P6 NumPy workload; real RAG and PyTorch go to "Hướng phát triển", or to a demo after 09/12 that is not an official trial | Changing the workload after the profile lock breaks H2/H5 comparability, and there is no time before the 29/11 freeze | Swap the image today and lock the profile on an untested workload |

## 9.2. Traceability

| Source requirement | Covered by |
|---|---|
| ver3 §8.1 reproducible manual baseline | P7-T4, scenarios 6 and 7 |
| ver3 §8.2 manual interactions, variable compute cost | P7-T3, P7-T4 |
| ver3 §8.3 raw data, no hard-coded numbers | P7-T2.2, P7-T3, negative boundary 11 |
| ver3 §8.4 four cost groups reported separately | D10, scenario 5 |
| ver3 §8.4 OpenCost for allocation, AWS data for reconciliation | D3, D4, D5, scenario 4 |
| ver3 §11 daily billing check, tags | D5, P7-T5 |
| EXPERIMENT_PLAN §5 baseline, counting rule and limits | P7-T4 |
| EXPERIMENT_PLAN §7 matched-pair contract | D4, D9 |
| VERSION_MATRIX OpenCost and Prometheus rows `UNVERIFIED` | P7-T1, P7-T2.1 |
| DRF-21 | P7-T2, P7-T3, P7-T5 |
| DRF-22 | P7-T4, P7-T5 |

## 9.3. Independent review

Not done for this candidate. Claude proposes to skip a Codex review of the SPEC because of the 28/11 time limit (the owner decides with §9.1). Codex reviews the guardrail changes of T2 and the acceptance audit of T5.

# 10. Cost of P7

Unit prices from COST_PLAN §5.2 (28/09), rechecked before the window.

| Item | Estimate |
|---|---:|
| P7 share of cluster time, about 4 h × 0.309 | 1.24 |
| Batch smoke on Spot `m5.large`, under 0.5 h | < 0.05 |
| Batch baseline arm, On-Demand `m5.large` about 0.75 h (run + 30 min idle) × 0.096 | 0.07 |
| RDS for the RAG baseline, shared with P8 | in the P8 share |
| **Total P7 share** | **≈ 1.4** |

Proposed cap (D12): 2 USD for the P7 share. Prometheus and OpenCost add no AWS charge; they add load on the system nodes.

# 11. Open risks

- **Node headroom** (A4). If two `m6i.large` are not enough: drop node exporter, lower limits, or a larger system node (changes the vCPU budget; owner decides).
- **OpenCost on Kubernetes 1.35** (A6). If the kind smoke fails: newest chart; if that fails, keep Prometheus and the computed contract and record OpenCost as not available. ver3 names OpenCost, so dropping it needs the owner and an ADR.
- **OpenCost and Spot.** Without a Spot feed its batch-node figure can differ from the computed one; registered cause, not an error.
- **Late or coarse billing.** Billing shows a window the next day or later, by service and tag. Reconciliation is per window.
- **Tags not retroactive.** If the owner does not activate them on 28/11, P9 runs cannot be separated by `RunId` in Billing.
- **Hand-made capacity** (D7). A node created by CLI is outside Terraform state; the runbook, the stop condition and the inventory cover it.
- **One long window on 29/11.** P7 and P8 share the window; a P7 failure must not block the P8 part. P7-T5 runs first and stops at its stop time.
- **Schedule.** About 12 h of local work on 28/11. If T2.1 (kind smoke) fails late, the window carries Prometheus only and OpenCost is recorded as `NOT_AVAILABLE` until fixed.

# 12. Sources and dated facts

| # | Fact | Source | Checked | Status |
|---|---|---|---|---|
| S1 | OpenCost chart `2.5.35` (app `1.121.5`, 25/11/2026); `2.5.34` (app `1.121.4`) | `opencost.github.io/opencost-helm-chart/index.yaml` | 2026-11-28 | **Pinned** `2.5.35`, tgz = index digest (P7-T2.1) |
| S2 | OpenCost installation page names Kubernetes 1.28 as officially supported | OpenCost installation docs | 2026-11-16 | `DOC_VERIFIED`; 1.35 `UNVERIFIED` |
| S3 | Prometheus chart `31.0.0` (app `v3.16.0`, 26/11/2026), `30.0.1` (25/11/2026); `kubeVersion >=1.19.0-0` | `prometheus-community.github.io/helm-charts/index.yaml` | 2026-11-28 | **Pinned** `30.0.1`; `31.0.0` tgz ≠ index digest, rejected (P7-T2.1 §1) |
| S4 | On-Demand price from the public price list `pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonEC2/current/<region>/index.json`, no credentials. Spot without the data feed: tries `DescribeSpotPriceHistory` (needs credentials, which D3 withholds), then falls back to On-Demand, so a Spot node is likely priced as On-Demand. Spot label `eks.amazonaws.com/capacityType`; Karpenter key not seen | OpenCost AWS configuration docs; `pkg/cloud/aws/provider.go` (`develop`, partly read) | 2026-11-28 | `DOC_VERIFIED` (On-Demand); Spot fallback and Karpenter label `UNVERIFIED`, observe in the window |
| S5 | Linux On-Demand billed per second, minimum 60 s; the Spot pricing page states no granularity | `aws.amazon.com/ec2/pricing/on-demand/`, `aws.amazon.com/ec2/spot/pricing/` | 2026-11-28 | On-Demand `DOC_VERIFIED`; Spot `UNVERIFIED` (EC2 User Guide) |
| S6 | Cost Explorer API billed per request | COST_PLAN §7.4 | 2026-10-02 | `DOC_VERIFIED` |
| S7 | Unit prices: EKS 0.10, `m6i.large` 0.096, `m5.large` 0.096, `db.t4g.micro` 0.016 USD/h; gp3 0.08 USD/GB-month; public IPv4 0.005 USD/h | COST_PLAN §5.2 | 2026-09-28 | recheck before the window |
| S8 | Cost allocation tags apply only to usage after activation | AWS Billing documentation | not read yet | `UNVERIFIED`; read before the owner activates |
| S9 | Standard On-Demand and Spot vCPU quotas 8 each | P6-T4.2 evidence §preflight | 2026-11-26 | `ACCOUNT_VERIFIED` then; reread at T−30 |
