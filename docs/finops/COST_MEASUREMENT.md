---
document: COST_MEASUREMENT
version: 1.0.0
status: P7_CONTRACT (SPEC-P7 D4, D5; owner approved D1–D13 on 28/11/2026)
issue: DRF-87 (P7-T3)
applies_to: every dry run from P7 and every official H5 pair in P9
code: experiments/lib/cost_calc.py, collect_timeline.sh, timeline_normalize.py, export_metrics.sh
---

# Cost measurement contract

This document says **which number is the cost of a run**, where each input comes from, and how it is checked against the AWS bill. It is fixed before any H5 pair is run. If the rule changed after the cost had been seen, H5 would be invalid (EXPERIMENT_PLAN §7).

An analogy: the computed cost is the **meter reading**, AWS Billing is the **electricity bill**, and OpenCost is a **dashboard in the house** that splits the usage between rooms. The meter reading is ready a few minutes after a run, and the bill arrives a day later. The two must agree within the tolerance. The dashboard is never used as the bill.

## 1. Three sources, three roles

| Source | What it is | Ready | Role here |
|---|---|---|---|
| **Computed** (`cost_calc.py`) | EC2 instance seconds × unit price, plus volume GB-seconds × volume price | minutes after the run | **the cost of a run and of an arm** (H5) |
| **AWS Billing** (Bills, Cost Explorer console; owner reads) | what AWS charges, gross before credits | about a day | **reconciliation**, per window; the ledger |
| **OpenCost** (in cluster) | allocation per namespace/workload at public On-Demand prices | live | **visibility only**: which tenant reserved what |

Never present an OpenCost number as the bill (SPEC-P7 negative boundary 1).

## 2. Definitions

- **Run.** One workload execution, either on the platform path (optimized arm) or on the manual path (baseline arm), from the first capacity it causes to that capacity's termination.
- **Variable compute of a run.** Includes only the batch EC2 instances that the run causes, and their root volumes. EKS, system nodes, RDS, IPv4, logs and transfer are **fixed** costs, reported separately (EXPERIMENT_PLAN §7, ver3 §8.4).
- **Arm sum.** The sum of the variable compute of the runs in one arm, over complete pairs only.
- **Saving ratio (H5).** (baseline sum − optimized sum) / baseline sum, computed from **unrounded** sums. PASS needs ≥ 5 complete pairs and a ratio ≥ 0.40; fewer pairs give `INCONCLUSIVE`.

## 3. Formula

For each instance:

```text
billed_seconds = max(60, ceil(termination − launch))
compute_usd    = Σ over price segments  (segment_seconds / 3600) × usd_per_hour
volume_usd     = volume_GB × billed_seconds × usd_per_GB_month / seconds_in_launch_month
variable_usd   = compute_usd + volume_usd
```

- **Price segments.** An On-Demand instance has one segment. For Spot, the Spot price history for that type **and zone** is a step function. Every change inside the run is integrated, never averaged. History that does not cover the launch is refused.
- **Per-second billing and the 60 s minimum.** For Linux On-Demand this is documented (SPEC-P7 §12 S5). The Spot pricing page does not state it, so `spot_granularity_assumed=true` is written on every Spot instance until the EC2 User Guide is read.
- **Volume month.** The GB-month price is spread over the actual seconds of the month of launch (30 days in November = 2,592,000 s).
- **Money.** `Decimal` throughout. Outputs are rounded to 6 decimals (half up) only when written. Ratios use unrounded values.

Worked example (the T1 micro-lab, SYNTHETIC inputs), for one pair of m5.large with a 20 GB gp3 root:

| Arm | Capacity | Seconds | Compute | Volume | Variable |
|---|---|---:|---:|---:|---:|
| baseline | On-Demand 0.096 USD/h | 2,160 (300 s work + 1,800 s idle hold + 60 s) | 0.057600 | 0.001333 | **0.058933** |
| optimized | Spot 0.0397 USD/h | 420 (300 s work + boot + 60 s consolidation) | 0.004632 | 0.000259 | **0.004891** |

Saving ratio = (0.058933 − 0.004891) / 0.058933 ≈ **0.9170**. With one pair this is `INCONCLUSIVE`. The example shows why the result depends on the idle hold (ver3: 1,800 s) and on the run length: H5 measures *mechanism under a fixed profile*, not a general saving.

## 4. Where each input comes from

| Input | Source | Tool | Recorded in |
|---|---|---|---|
| launch time | EC2 `LaunchTime` | `collect_timeline.sh` | `timeline/instances.json` |
| termination time | EC2 `StateTransitionReason` time | same | same; missing means **refused** |
| type, zone, capacity type | EC2 `InstanceType`, `Placement`, `InstanceLifecycle` | same | same |
| On-Demand price | AWS Price List `get-products` (Linux, shared, `Used`) | same | `cost/cost_input.json` |
| Spot price | `describe-spot-price-history`, that type and zone, from one day before the start to the end | same | same |
| root volume size | EC2NodeClass `batch` in Git (20 GiB) or the baseline runbook | flag | same |
| gp3 price | COST_PLAN §5.2 (0.08 USD/GB-month), rechecked before the window | flag | same |
| billed amount | owner reads Bills (gross, by service), the day after the window | ledger | `COST_LEDGER.md` |

No identifier is written: instance ids become aliases (`batch-1`, `baseline-1`), and node names become pseudonyms. Collection is read-only (`describe`, `get`). The Cost Explorer API is never called (it is billed per request; COST_PLAN §7.4).

## 5. Reconciliation (D5)

- Unit: **one window**. Billing cannot split the runs of one window reliably, because tags are not on every resource and billing is hourly in places.
- Compare the computed variable compute of all the runs in the window with the billed EC2 amount for the batch and baseline instances, read by the owner. Tags `Project` and `RunId` were activated on 28/11 and are not retroactive.
- **Tolerance:** |billed − computed| ≤ max(5 % of billed, 0.02 USD) → `WITHIN_TOLERANCE`. Otherwise → `NEEDS_REGISTERED_CAUSE`: the difference must match one of the causes in §6, or the window is reported as unexplained.
- **Pending:** while billing has not been read, the status is `PENDING`, with `billed_usd: null`. It is never 0 (EXPERIMENT_PLAN §10 rule 9). A `PENDING` cost cannot appear as a final number in the report.

## 6. Registered causes of difference

These are fixed now, before any pair. A difference may be explained only by one of these.

| # | Cause | Direction | Seen |
|---|---|---|---|
| C1 | **OpenCost resolution**: it samples Pods at 1 min resolution. A 75 s Pod did not appear at all, and a 5.5 min Pod showed 4.29 min | OpenCost low | kind 28/11 (P7-T2.2 §3) |
| C2 | **OpenCost Spot price**: with no Spot feed and no credentials (D3), a Spot node is likely priced at On-Demand | OpenCost high on Spot | docs 28/11 (P7-T2.1 §6); confirm in the window |
| C3 | **OpenCost charges max(request, use)**: idle reservations are allocated cost | OpenCost ≠ EC2 | kind 28/11 (P7-T2.1 §4) |
| C4 | **Spot billing granularity** not documented on the Spot page; computed assumes per second with 60 s minimum | computed low or high by < 60 s × price | open |
| C5 | **Billing delay and day boundary**: Bills can lag by a day, and a window that crosses 00:00 UTC is split across days | billed missing or split | P4–P6 readings |
| C6 | **Hourly or monthly items** inside the EC2 line: EBS snapshots, public IPv4, data transfer billed under EC2 | billed high | P6 Bills (EC2 includes system nodes) |
| C7 | **Account-wide reading**: Bills by service include every window of the month; a window's share is a difference of two readings | billed imprecise | P4–P6 method |
| C8 | **Termination time source**: `StateTransitionReason` is when termination started; billing may stop a few seconds later | computed low by seconds | open |

## 7. Refusal rules (the calculator exits 4)

The calculator refuses when:
- there is no termination time (the instance is still running, or it was not collected);
- there is no On-Demand price for the type;
- the Spot history does not cover the launch, or has no row for that zone;
- a run has no instances (no capacity is an input error, not a cost of 0);
- a run's arm is not `baseline|optimized`, or a pair has two runs in the same arm;
- a fixed line has no quantity, hours or unit price, or is tagged `variable_compute`.

## 8. Fixed costs per window

`cost_calc.py window` takes the window inventory as lines of `quantity × hours × unit price`, one category each:

| Category (ver3 §8.4) | Lines |
|---|---|
| `cluster_fixed` | EKS control plane (0.10 USD/h), system nodes (2 × m6i.large), their root volumes |
| `data_storage` | RDS instance and storage, snapshots, S3 |
| `network` | public IPv4 (0.005 USD/h each), NAT or endpoints if present, data transfer |
| `logging` | CloudWatch Logs ingestion and storage |
| `variable_compute` | only from the runs (§3), never typed by hand |

The ledger always shows the fixed categories next to the variable one, because Pods at zero is not cost at zero (SPEC-P7 negative boundary 2).

## 9. Change control

Changing a formula, a source, the tolerance or a cause requires a new version of this file, approved by the owner **before** the next pair. Version 1.0.0 is in force from the P8 pilot onward.
