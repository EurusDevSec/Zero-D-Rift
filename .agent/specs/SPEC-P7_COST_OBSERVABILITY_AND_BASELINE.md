---
id: SPEC-P7
title: Cost and utilization instrumentation, cost contract and reproducible manual baseline
status: DRAFT_FABLE_20261116
phase: P7
start: TBD (owner rebaseline)
deadline: TBD (owner rebaseline)
schedule_baseline: ver3 §12 window 15–16/11 already missed; owner rebaseline open
estimated_effort: 22-26 hours (ROADMAP allocates 16 h)
mode: Coach for the cost arithmetic (owner calculates one profile by hand first), then Pair
canonical_scope: docs/de_cuong_tot_nghiep_ver3.md
linear: DRF-21 (measurements), DRF-22 (manual baseline); outline issues, split into P7-T tasks at the phase gate
authority: DRAFT_ONLY_NO_INSTALL_NO_AWS_NO_BILLING_SETTING_NO_LINEAR_CHANGE
drafted_from: main at df275e4 (2026-11-16); P4, P5 and P6 runtime on EKS are UNVERIFIED
---

# 0. Draft status

Early draft written on 16/11/2026 at the owner's request. It is **not** the
active contract (AGENTS §7, `.agent/docs/FEATURES.md`). Before P7 starts: recheck
§2, refresh every dated fact in §12, let the second agent review the candidate
revision and get the owner's decisions on §9.1. Nothing in ver3 is reduced.

# 1. Goal and boundaries

## Goal

Make cost and utilization measurable before any official trial, and make the
comparison side of the experiments reproducible:

- a pinned Prometheus and OpenCost that show allocation per namespace and
  workload while the cluster runs, and whose raw data survives teardown;
- a **cost contract**: for one run, which instance seconds and which unit price
  give its variable compute cost, where each number comes from, and how it is
  later reconciled with AWS billing;
- a cost ledger that keeps variable compute, cluster fixed cost and the other
  categories of ver3 §8.4 apart;
- two manual baseline runbooks (RAG and batch) that the owner has executed once
  each, with the same acceptance checks as the platform path and a written
  interaction count;
- one locked batch workload profile for the matched cost pairs.

This is the ver3 §12 exit criterion for P7: "Dashboard/raw metrics, cost contract
và baseline tái lập được". Every run in P7 is a dry run (`official=false`,
`WARMUP_NOT_OFFICIAL`). H5 and the manual-interaction comparison are measured in
P9.

Outcome trace: cross-cutting condition for both Golden Paths ("cost-bounded",
AGENTS §0) and the measurement basis of H5.

## MUST deliverables

- `SPEC-P7` approved by the owner with decisions D1–D12 (§9.1) resolved.
- Prometheus and OpenCost as pinned Argo CD applications, images by digest, with
  a kind smoke result for Kubernetes 1.35 before any EKS install.
- Export script: raw Prometheus series and OpenCost allocation for a window as
  JSONL/CSV with hashes, taken before teardown.
- `experiments/lib/`: instance timeline collector, cost calculator and run
  manifest writer, with unit tests on synthetic inputs marked `SYNTHETIC`.
- `docs/finops/COST_MEASUREMENT.md`: the cost contract of D4, the known
  differences between the three cost sources, and the reconciliation rule.
- `docs/finops/COST_LEDGER.md`: gross cost by phase and by the ver3 §11
  category, with source and billing status; P2–P6 backfilled from what the owner
  reads in Billing.
- Runbooks `docs/runbooks/BASELINE_RAG_MANUAL.md` and
  `docs/runbooks/BASELINE_BATCH_MANUAL.md` (EXPERIMENT_PLAN §5.2, §5.3), an
  interaction sheet template, and `docs/runbooks/P7_COST_OBSERVABILITY.md`.
- Workload profile `batch-gpu-small-v1` recorded with every field of
  EXPERIMENT_PLAN §7.
- Evidence under `docs/evidence/p7/`: kind smoke, both windows, the hand
  calculation, exports, inventory and cost.

## Negative boundaries

1. Do not present an OpenCost number as the AWS bill, and do not present any
   cost as final while billing data is pending. Pending is `PENDING`, never zero
   (EXPERIMENT_PLAN §10 rule 9).
2. Do not say or imply that Pods at zero means cost at zero (ver3 §8.4). The
   ledger always shows the fixed categories.
3. Do not use a fixed Spot discount as a result. A Spot price is read for the
   zone and the time of the run (COST_PLAN §4 rule 5).
4. Do not add components beyond Prometheus and OpenCost: no Grafana,
   Alertmanager, Pushgateway, DCGM exporter, Loki, Athena, Kubecost, or a
   persistent volume driver, unless the owner changes D1, D2 or D6.
5. Do not give OpenCost or Prometheus an AWS identity (D3).
6. Do not call the Cost Explorer API from scripts (it is billed per request,
   COST_PLAN §7.4). The owner reads the console.
7. Do not change an account billing setting (cost allocation tags, data export,
   Budget) without the owner's explicit approval of that exact change.
8. Do not let the manual baseline use anything the platform path does not get:
   same shared database, same pre-created roles, same image, same checks.
   Do not use the database master credential in a baseline.
9. Do not hide automation inside "one step" of a baseline: a script counts as one
   interaction **and** its automated actions are recorded (EXPERIMENT_PLAN §5.1).
10. Do not change the idle window, timeouts or counting rule of EXPERIMENT_PLAN
    §5.4. Do not choose the workload profile after seeing a cost.
11. Do not hard-code a measured value in any script or report generator.
12. Do not count a P7 run as an official trial, and do not promote one later.
13. Do not run an AWS window without a separate execution approval, a fresh cost,
    identity and quota check, a stop time and a teardown owner.

# 2. Giả định từ phase trước (kiểm lại khi vào phase)

| # | Assumption | Source today | Recheck |
|---|---|---|---|
| A1 | P6 is accepted: a `BatchTrainingJob` runs end to end on a real GPU node and the node is reclaimed | SPEC-P6 draft | P6 acceptance audit |
| A2 | Both G/VT quotas are approved. The batch baseline needs the **On-Demand** quota in particular | quota is 0 today (COST_PLAN §7.3) | `list-service-quotas` on the day |
| A3 | P4 and P5 are accepted; the RAG path, the three credential tiers and the tenant guardrails exist | SPEC-P4, SPEC-P5 draft | acceptance audits |
| A4 | Two `m6i.large` system nodes have room for Prometheus (server, kube-state-metrics, node exporter) and OpenCost on top of everything from P3–P6 | SPEC-P5 §10 estimate | pod count and memory in the P6 window; this is the tightest point so far |
| A5 | The cluster has no storage driver add-on, so Prometheus has no persistent volume | `modules/cluster/main.tf` at `df275e4`: add-ons are vpc-cni, kube-proxy, coredns | module as it is then |
| A6 | OpenCost works on Kubernetes 1.35 | not confirmed: its documentation names 1.28 as officially supported (§12 S2); VERSION_MATRIX keeps it `UNVERIFIED` | kind smoke in P7-T2.1 |
| A7 | Project tags (`Project`, `RunId`, `ExpiresAt`, `ManagedBy`) are on Terraform resources and on Karpenter-launched instances and volumes | COST_PLAN §10; SPEC-P6 D7 | describe one instance in the P6 window |
| A8 | EXPERIMENT_PLAN v0.1.0 is unchanged: baseline steps §5, limits §5.4, matched-pair contract §7 | approved 2026-09-29 | read it again; D4 may need v0.2.0 |
| A9 | The owner can read Bills and Cost Explorer in the console; IAM access to billing is on | COST_PLAN §3 | owner confirms |
| A10 | A project Budget with alerts exists | COST_PLAN §8.1 planned it for P2; state unknown | owner reads Budgets |
| A11 | Linux instances are billed per second with a one-minute minimum, On-Demand and Spot | author's recollection | AWS EC2 pricing pages (§12 S5) |
| A12 | The `db-init`, `bootstrap` and `cleanup` entry points of P4 exist, so the manual RAG baseline can perform the same SQL by hand | SPEC-P4 P4-T2.1 | P4 code |
| A13 | The training image and its `cpu-lab`/`gpu` profiles from P6 exist and are pinned | SPEC-P6 draft | VERSION_MATRIX "P6 pins" |

# 3. Learning objectives

By the end of P7 the owner should be able to:

1. Compute the variable compute cost of one run by hand from instance start and
   end times and a unit price, and say which seconds are billed.
2. Separate variable compute cost, cluster fixed cost, other AWS cost and the
   invoice, and place any line of the bill in one of them.
3. Explain what OpenCost measures (allocation of node cost to workloads from
   requests and usage), what price it uses, and why it is not the bill.
4. Explain why billing data arrives late and what `PENDING` protects against.
5. Explain why the baseline is a reference procedure of the project and not a
   measurement of any company, and how one interaction is counted.
6. Explain why the profile is locked before any cost is seen.

# 4. Acceptance scenarios

```gherkin
Scenario: The metrics stack is pinned and bounded
  Given approved chart versions and image digests
  When Prometheus and OpenCost are installed through Argo CD
  Then only the approved components run, none has an AWS identity and none has a persistent volume
  And the platform and both golden paths still pass their checks

Scenario: Allocation is visible while a workload runs
  Given a batch smoke run on a GPU node
  Then OpenCost shows cost for the tenant namespace over that window
  And the view separates CPU, memory and GPU and shows idle cost
  And the raw series and the allocation export are saved with hashes before teardown

Scenario: The cost of a run is computed from raw inputs
  Given the instance timeline of the smoke run and the price sources of the contract
  When the cost calculator runs
  Then its result equals the owner's hand calculation within rounding
  And every input has a source, a timestamp and a hash
  And a missing price or a missing end time produces an error, not zero

Scenario: Three sources are compared honestly
  Given computed cost, OpenCost allocation and AWS billing for the same window
  Then each difference is either inside the registered tolerance or explained
        by a registered cause
  And billing that has not arrived is recorded as PENDING

Scenario: Fixed cost stays visible
  Given all workload Pods at zero and no GPU node
  Then the ledger still shows control plane, system nodes, public IPv4, database,
       storage and log cost for the window

Scenario: The manual RAG baseline is reproducible
  Given the versioned runbook and a clean per-request inventory
  When the owner executes it once
  Then the same independent readiness and database checks as the platform path pass
  And interactions, commands, automated actions, waits and errors are recorded by the rule
  And per-request resources are removed and inventory is clean

Scenario: The manual batch baseline is reproducible
  Given the locked profile and an approved On-Demand GPU node
  When the owner executes the runbook once
  Then training starts with a CUDA device, the checkpoint and artifact exist
  And the node is held for the locked idle window and then removed
  And instance, volume and public address are gone

Scenario: Teardown keeps the evidence
  When the window ends
  Then exports are taken first, then controllers and the bootstrap are removed
  And inventory shows nothing outside the retain allowlist
```

# 5. Work breakdown

## P7-T1 — Contract: decisions, pins and the hand calculation (3.5 h)

**A. SPEC, review, approval (1.5 h)** — recheck §2; second-agent review; owner
decides D1–D12 and the P7 gross cap.

**B. Pins and sources (1 h)**

- [ ] Prometheus chart and OpenCost chart: versions, image digests, registry
      probe for their registry hosts (§12 S1, S3).
- [ ] How OpenCost prices nodes on AWS without credentials, and what it does for
      Spot nodes; read the documentation for the pinned version (§12 S4).
- [ ] Billing granularity for On-Demand and Spot (A11); Spot price history API
      fields; what Billing shows per tag and how late.
- [ ] VERSION_MATRIX gets a "P7 pins" section; the OpenCost and Prometheus rows
      leave `UNVERIFIED` only after the kind smoke.

**C. Micro-lab: one profile by hand (1 h)** — Coach mode.

- [ ] From fixed inputs (start, end, instance type, capacity type, unit price,
      volume size, idle window) the owner computes both arms of one pair and the
      saving ratio on paper, then predicts what OpenCost will show and why it
      will differ.
- [ ] The inputs and the worked result become the first unit test of the cost
      calculator, marked `SYNTHETIC`.

## P7-T2 — Metrics stack (5 h)

### P7-T2.1 — Manifests and kind smoke (3 h)

- [ ] Argo CD applications per D1 and D2; resource requests and limits set;
      scrape interval and retention fixed in Git; node exporter only where the
      platform namespace allows host access.
- [ ] `gitops/check.sh`: chart versions exact, images by digest, no component
      outside D1/D2.
- [ ] kind (Kubernetes 1.35 image of ADR-0005): both install, OpenCost reaches
      Prometheus, an allocation query for a test namespace returns rows.
- [ ] Record what does not work on kind (no AWS prices, no real nodes).

Evidence: `docs/evidence/p7/P7-T2.1_L2_KIND_OPENCOST_<date>.md`.

### P7-T2.2 — Exports (2 h)

- [ ] `experiments/lib/export_metrics.sh`: named queries over a UTC window to
      JSONL; OpenCost allocation by namespace, controller and Pod to JSON;
      `hashes.sha256`; no account or instance identifier in committed output.
- [ ] Named queries: node count by pool and capacity type over time, GPU
      requested versus allocatable, Pod phase timeline of the training Job, CPU
      and memory use of tenant namespaces.
- [ ] Dry run on kind; schema checked against EXPERIMENT_PLAN §9.2.

## P7-T3 — Cost contract and ledger (4.5 h)

- [ ] `COST_MEASUREMENT.md` per D4 and D5: definitions, sources, formula,
      rounding, tolerance, registered causes of difference, `PENDING` rule.
- [ ] `collect_timeline.sh`: for a run, the NodeClaim and Node events and the EC2
      launch and termination times, instance type, capacity type and zone, as
      events with aliases instead of instance IDs.
- [ ] `cost_calc`: variable compute per run and per arm; fixed categories per
      window from inventory hours and unit prices; refuses missing inputs.
- [ ] Unit tests: the hand-calculated pair, a Spot price change inside a run, a
      run under one minute, a missing termination time, pending billing.
- [ ] `COST_LEDGER.md` with P2–P6 rows from the owner's Billing readings; each
      row has gross amount, category, source and status.
- [ ] If D4 changes or sharpens a definition in EXPERIMENT_PLAN §7, prepare
      contract v0.2.0 as a proposal for the P8 freeze. No silent edit.

## P7-T4 — Manual baselines and the locked profile (5 h)

**A. RAG baseline runbook (2 h)** — steps 1–8 of EXPERIMENT_PLAN §5.2 as exact
commands; database steps run from a Pod in `zdr-platform` with the bootstrap
tier; the bucket is created under the tenant's existing prefix so the
pre-created role covers it (D8); timer start and end as defined in §5.2.

**B. Batch baseline runbook (2 h)** — steps 1–8 of EXPERIMENT_PLAN §5.3; GPU
capacity per D7; plain Job manifest without KEDA; marker and checkpoint checks
identical to P6; 1,800 s idle hold with a visible timer; removal and inventory.

**C. Profile and sheet (1 h)**

- [ ] `batch-gpu-small-v1`: image digest, steps, checkpoint interval, expected
      duration, GPU request, instance type for the baseline arm, volume size,
      idle window, workload timeout, zone handling, logging configuration.
- [ ] Interaction sheet: one row per human action with time, command, wait,
      error and remedial action; totals for interactions, commands and
      automated actions.
- [ ] The same counting rule written for the platform path: opening the pull
      request, review, merge, any retry or repair.

## P7-T5 — L3 windows and acceptance (8 h)

Prerequisites: P6 accepted; P7-T2 to P7-T4 merged; kind smoke PASSED.

### P7-T5.1 — Window 1: metrics and one batch smoke (3 h)

- [ ] Window request and approval; RAG platform off.
- [ ] Platform, batch platform, Prometheus, OpenCost; wait until OpenCost has
      node prices.
- [ ] Idle observation with no workload: record what is still running and what
      it costs per hour.
- [ ] One `gpu` batch smoke; timeline collected; OpenCost view captured;
      exports; cost calculator run; compare with the hand method.
- [ ] Teardown; inventory.

### P7-T5.2 — Window 2: manual baselines (3.5 h)

- [ ] Window request priced with the GPU node at the On-Demand rate for the full
      baseline arm; RAG platform on.
- [ ] Owner executes the RAG baseline once; a second person or agent only keeps
      the sheet and does not type.
- [ ] Owner executes the batch baseline once.
- [ ] Both dry runs measured for cycle time (preflight to clean inventory); the
      values go to P8 for the campaign plan.
- [ ] Teardown; inventory including node groups, launch templates and volumes.

Stop conditions: those of SPEC-P6, plus: a baseline step that needs a credential
the platform path does not use; the idle hold exceeded by more than 5 minutes;
any GPU capacity created by hand still present at the stop time.

### P7-T5.3 — Acceptance (1.5 h)

- [ ] Acceptance audit in `docs/evidence/p7/`: scenario → evidence, the three
      cost figures of window 1 with their status, the two interaction sheets,
      limits.
- [ ] Next-day billing read by the owner; ledger rows move from `PENDING` or stay
      there with the date of the reading.
- [ ] Independent review by the second agent.
- [ ] Owner teach-back on §7; learning status from demonstration only.

# 6. Verification tiers

| Tier | P7 use | Evidence |
|---|---|---|
| L0 | Unit tests of the calculator and collectors, static checks, CI | commands, exit status |
| L1 | Synthetic manifest and events through the export and calculator pipeline | output files, hashes |
| L2 | kind: Prometheus and OpenCost on Kubernetes 1.35 | run ID, query output |
| L3 | EKS: allocation with a real GPU node, timeline, computed cost, baselines, teardown | approval, exports, sheets, inventory |

# 7. Teach-back questions

1. A GPU node ran from 02:00:10 to 02:14:40 UTC. Which seconds are billed, at
   which price, and where does each number come from?
2. OpenCost shows a lower or higher cost for the same run than your calculation.
   Give two reasons that are not bugs.
3. The bill for yesterday is not there yet. What do you write in the dataset, and
   what do you not write?
4. Pods are at zero for an hour. List what was still billed in that hour.
5. Why is running a script one interaction and not zero, and not twenty?
6. What would make the baseline unfair to the platform, and what would make it
   unfair to the manual side?
7. Why must the profile be fixed before the first cost pair?

# 8. P7 completion rule

P7 is complete only when every scenario in §4 has L3 evidence, the cost of one
real run has been computed by the calculator and by the owner by hand with the
same result, the three sources have been compared with billing either reconciled
or explicitly `PENDING`, each baseline has been executed once by the owner with a
complete sheet, the profile is recorded, teardown and delayed inventory are
clean, an independent review has recorded findings and limits, and the owner
reaches `PRACTICED` + `EXPLAINED` for the cost arithmetic, OpenCost allocation and
the baseline method.

# 9. Decisions, traceability and tracking

## 9.1. Decisions for the owner (D1–D12) — proposals, not approved

| ID | Decision | Proposal | Why | Alternative |
|---|---|---|---|---|
| D1 | Prometheus distribution | The community `prometheus` chart: server, kube-state-metrics, node exporter; Alertmanager and Pushgateway off; no persistent volume; retention equal to a window | Fewest Pods and CRDs; data is exported before teardown anyway | kube-prometheus-stack (operator, more Pods and CRDs) |
| D2 | Dashboard | The OpenCost UI during a window, recorded; plus a static offline report generated from the exported data by the analysis script | ver3 §13 asks for an offline dashboard for the defense; no extra component | Grafana |
| D3 | OpenCost identity and price sources | No AWS identity; public On-Demand prices; no Spot data feed; no billing-data integration. OpenCost is the allocation view only | No new IAM, bucket or query service; EXPERIMENT_PLAN §7 already makes AWS billing the reconciliation source | Spot data feed and billing integration (new bucket, role and query service) |
| D4 | Cost contract for a run | Variable compute cost = billed instance seconds × unit price + volume GB-seconds × volume price. On-Demand price from the Price List, recorded in the run manifest. Spot price from Spot price history for that type and zone over the run interval. Instance seconds from EC2 launch and termination times | Available minutes after a run, reproducible from raw inputs, independent of OpenCost's Spot handling | Wait for the bill and use it as the only source |
| D5 | Reconciliation | Owner reads Billing in the console per window. Registered tolerance between computed and billed variable compute for a window: 5 % or 0.02 USD, whichever is larger; otherwise a registered cause must explain it. Activate cost allocation tags `Project` and `RunId`; a data export with resource IDs to S3 is proposed so instances can be matched one by one | A rule fixed before any pair is measured; tags and exports only cover usage after they are switched on, so they must be on before P8 | Console only, no tags and no export (window-level reconciliation only) |
| D6 | GPU utilization | Not collected. Use GPU requested, node lifetime and the training markers | H5 needs time and price, not utilization | DCGM exporter (new DaemonSet) |
| D7 | GPU capacity for the batch baseline | The owner creates one On-Demand GPU node by AWS CLI commands in the runbook, using the node role and subnets from Terraform outputs, and deletes it the same way | "Manual" should mean typed commands; EXPERIMENT_PLAN §5 asks for a CLI runbook | A Terraform variable that adds one GPU node (safer cleanup, hides many actions in one apply) |
| D8 | Equal footing for the RAG baseline | Same shared database, pre-created tenant role, image and checks; SQL by hand with the bootstrap tier from a platform Pod; bucket under the tenant prefix | The comparison is about steps and time, not about who has more rights | Baseline creates its own role and policy (adds IAM work the platform path does not have at request time) |
| D9 | Locked profile | `batch-gpu-small-v1` with the P6 workload at about 5 minutes on `g4dn.xlarge`, 50 GB gp3, idle window 1,800 s | SPEC-P6 §10.3 shows the result depends on run length; lock it now | A longer run (closer to real training, smaller relative saving) |
| D10 | Ledger | `docs/finops/COST_LEDGER.md`, gross, by phase and ver3 §11 category, with status | COST_PLAN §8.2 step 5 | Spreadsheet outside Git |
| D11 | Harness scope in P7 | Collectors, calculator and manifest writer only. Trial runners and the analysis script are P8 | Keeps P7 to measurement; runners need the P8 scenarios | Build the runners here |
| D12 | P7 gross cap and windows | 5 USD for all P7 windows and retries, of which at most 1 USD GPU; two windows planned | §10 | — |

## 9.2. Traceability

| Source requirement | Covered by |
|---|---|
| ver3 §8.1 reproducible manual baseline | P7-T4, scenarios 6 and 7 |
| ver3 §8.2 manual interactions, variable compute cost | P7-T3, P7-T4 C |
| ver3 §8.3 raw data, no hard-coded numbers | P7-T2.2, P7-T3, negative boundary 11 |
| ver3 §8.4 four cost groups reported separately | D10, scenario 5 |
| ver3 §8.4 OpenCost for allocation, AWS data for reconciliation | D3, D4, D5, scenario 4 |
| ver3 §11 daily billing check, tags | D5, P7-T5.3 |
| EXPERIMENT_PLAN §5 baseline, counting rule and limits | P7-T4 |
| EXPERIMENT_PLAN §7 matched-pair contract | D4, D9 |
| VERSION_MATRIX OpenCost and Prometheus rows `UNVERIFIED` | P7-T1 B, P7-T2.1 |
| DRF-21 (Prometheus/OpenCost and raw cost evidence) | P7-T2, P7-T3, P7-T5.1 |
| DRF-22 (manual baseline and matched profile) | P7-T4, P7-T5.2 |

## 9.3. Independent review

Not done. This draft has had no second-agent review and no owner approval.

# 10. Cost of P7

Unit prices as in SPEC-P6 §10.2 (COST_PLAN §5.2, 2026-09-28); all rechecked
before the window.

| Window | Cluster | Other | Estimate |
|---|---:|---:|---:|
| 1 — metrics and one batch smoke, 4 h | 4 × 0.309 = 1.24 | GPU ≤ 0.5 h at 0.537 → 0.27 | 1.5 |
| 2 — manual baselines, 5 h | 5 × 0.309 = 1.55 | RDS 5 h ≈ 0.10; GPU baseline arm 0.75 h → 0.40 | 2.1 |
| **Total** | | | **3.6** |

Proposed cap (D12): 5 USD, GPU part at most 1 USD. Prometheus and OpenCost add no
AWS charge of their own; they add load on the system nodes. A data export to S3
(D5) costs storage and requests in cents; the owner approves it separately.

# 11. Open risks

- **Node headroom** (A4). If two `m6i.large` are not enough, the options are a
  smaller footprint (no node exporter, lower limits) or a larger system node.
  A larger node changes the Standard vCPU budget (quota 5) and the system-node
  cost line; it is the owner's decision.
- **OpenCost on Kubernetes 1.35** (A6). If the kind smoke fails, try the newest
  chart; if that fails, P7 keeps Prometheus and the computed cost contract and
  records OpenCost as not available. ver3 names OpenCost, so dropping it needs
  the owner and an ADR.
- **OpenCost and Spot.** Without a Spot data feed it cannot know the real Spot
  price. Its GPU-node figure can be far from the computed one; this is a
  registered cause, not an error.
- **Late or coarse billing.** The console may show a window only the next day or
  later, and by service and tag rather than by instance. Without the export of
  D5 reconciliation is per window, not per run.
- **Cost allocation tags are not retroactive.** Usage before activation is not
  tagged in Billing. Activate before P8.
- **Hand-made GPU capacity** (D7). A node group created by CLI is outside
  Terraform state; if it is not deleted first, `terraform destroy` can fail or
  leave a running GPU instance. The runbook, the stop condition and the
  inventory cover it.
- **Baseline skill effect.** The owner gets faster with every repetition. The
  dry run here and the five official runs in P9 are different runs; the report
  states the learning effect instead of hiding it.
- **Prometheus data is ephemeral.** A crash of the Pod or node loses the window's
  series; the timeline collector reads the Kubernetes and EC2 APIs directly and
  does not depend on Prometheus.
- **Schedule.** P7 starts after its ver3 window; the rebaseline is the owner's.

# 12. Sources and dated facts (recheck at P7-T1)

| # | Fact | Source | Checked | Status |
|---|---|---|---|---|
| S1 | OpenCost Helm chart latest `2.5.34`, application `v1.121.4`; matrix candidate was chart `2.5.20` / app `1.120.2` | [opencost-helm-chart releases](https://github.com/opencost/opencost-helm-chart/releases); VERSION_MATRIX §2 | 2026-11-16; 2026-09-25 | `SOURCE_VERIFIED`; pin at P7-T1 |
| S2 | OpenCost needs Kubernetes 1.21+ and Prometheus; its installation page names Kubernetes 1.28 as officially supported | [OpenCost installation](https://opencost.io/docs/installation/install/) | 2026-11-16 | `DOC_VERIFIED`; 1.35 is `UNVERIFIED` |
| S3 | Prometheus chart version and images | — | not looked up | `UNVERIFIED`; pin at P7-T1 |
| S4 | How OpenCost prices AWS nodes without credentials and how it treats Spot | [OpenCost AWS configuration](https://opencost.io/docs/configuration/aws/) (ver3 reference 10) | not read for this draft | `UNVERIFIED` |
| S5 | Per-second billing with a one-minute minimum for Linux On-Demand and Spot | author's recollection | not looked up | `UNVERIFIED`; read the EC2 On-Demand and Spot pricing pages |
| S6 | Cost Explorer API is billed per request | COST_PLAN §7.4 (AWS Cost Explorer pricing) | 2026-10-02 | `DOC_VERIFIED`; recheck |
| S7 | Unit prices: EKS 0.10, `m6i.large` 0.096, `g4dn.xlarge` 0.526, `db.t4g.micro` 0.016 USD/h; gp3 0.08 USD/GB-month; public IPv4 0.005 USD/h | COST_PLAN §5.2 | 2026-09-28 | `PRICE_API_VERIFIED`; recheck |
| S8 | User-defined cost allocation tags must be activated and apply only to later usage; data exports can include resource IDs | author's recollection of AWS Billing documentation | not looked up | `UNVERIFIED`; read before deciding D5 |
