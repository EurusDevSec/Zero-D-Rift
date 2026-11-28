---
document: COST_LEDGER
status: LIVE (append only; SPEC-P7 D10)
issue: DRF-87 (P7-T3)
basis: gross before credits, account-wide, us-east-1, read by the owner on the Billing console
cap: 100 USD gross for the project (COST_PLAN §4); phase caps in each SPEC
last_reading: 2026-11-27 (November gross 2.39 USD)
---

# Cost ledger

Rules:
- **gross before credits.** The invoice is 0 because credits cover it, and that is not the cost (COST_PLAN §4 rule 1).
- **One row per reading.** A new reading appends rows; it never edits an old one.
- **A phase's share is a difference** between two account-wide readings, taken before and after its window (cause C7 in [COST_MEASUREMENT](COST_MEASUREMENT.md) §6).
- **A missing reading is `PENDING`**, never 0.
- **Estimates are labelled.** They come from the evidence and never replace a reading.

## 1. Readings (account-wide, cumulative for the month)

| Read on | Period | Gross USD | Source | Evidence |
|---|---|---:|---|---|
| 2026-10-31 | October | 0.00 | Bills, October (status Pending) | `docs/evidence/p2/DRF6_STATE_BACKEND_20261031.md` |
| 2026-11-05 | November to date | ≈ 0.07 (region total; no service table) | Billing home | `docs/evidence/p2/DRF12_CLEANUP_20261105.md` |
| 2026-11-24 | November to date | **0.73** | Bills, Savings → Credits | `docs/evidence/p4/P4_ACCEPTANCE_AUDIT_20261121.md` §6.1 |
| 2026-11-26 | November to date | **1.62** | Bills, Savings → Credits | `docs/evidence/p5/P5_ACCEPTANCE_AUDIT_20261125.md` §6 |
| 2026-11-27 | November to date | **2.39** | Bills, Savings → Credits | `docs/evidence/p6/P6_ACCEPTANCE_AUDIT_20261127.md` §6 |

## 2. By phase and category (gross USD)

There are no Bills by phase. AWS Billing shows services, which map to the ver3 §8.4 categories as follows:
- EKS → `cluster_fixed`;
- EC2 → mixed (system nodes are `cluster_fixed`; batch instances are `variable_compute`; volumes);
- VPC (public IPv4) and Data Transfer → `network`;
- RDS, S3 and Secrets Manager → `data_storage`.

| Phase | Window(s) | EKS | EC2 (mixed) | RDS | VPC | Data Transfer | Secrets, S3 | **Total** | Status | Cap |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|---:|
| P1 | none | — | — | — | — | — | — | 0.00 | `READ` (no resource) | — |
| P2 + P3 + P4 | 04/11, 05/11, 21/11, 22/11 | 0.31 | 0.28 | 0.12 | 0.02 | 0.00 | 0.00 | **0.73** | `READ` 24/11 (combined; the split below is an estimate) | 5 + 3 + 5 |
| P5 | 25/11 | 0.28 | 0.52 | 0.04 | 0.03 | 0.01 | 0.01 | **0.89** | `READ` by difference 1.62 − 0.73 | 4 |
| P6 | 26/11 | 0.23 | 0.46 | 0.05 | 0.02 | 0.01 | 0.00 | **0.77** | `READ` by difference 2.39 − 1.62 | 4 |
| P7 + P8 | 29/11 (joint) | | | | | | | `PENDING` | read 30/11 | P7 2 (D12); window total in the P8 request |
| **Project to date** | | **0.82** | **1.26** | **0.21** | **0.07** | **0.02** | **0.01** | **2.39** | `READ` 27/11 | **100** |

The P5 service split is the difference of the 26/11 and 24/11 service tables. The P6 split is the difference of the 27/11 and 26/11 tables. The "Project to date" row is the 27/11 table, so the rows add up to it.

Estimates inside the combined row, from the evidence, **not readings**:
- P2: about 0.07–0.12 (DRF-12);
- P3: about 0.22 (window 1.05 h × 0.21 USD/h, DRF-37);
- P4: the rest, at most 0.73.

## 3. What the readings show (for the report)

- **Fixed cost dominates.** In every window, EKS plus the two system nodes (in EC2) make up most of the gross, while the batch node lives for minutes. This is the ver3 §8.4 point: Pods at zero is not cost at zero.
- **A window costs about 0.3 USD per hour of stack life.** For P6, about 0.77 USD over about 2.5 h. This rate is what bounds the P9 campaign, together with the cap.
- **Variable compute is not yet separated** from EC2 in any reading. From P7 on, it is computed per run ([COST_MEASUREMENT](COST_MEASUREMENT.md) §3) and reconciled per window (§5).

## 4. Next rows

| When | Row | Who |
|---|---|---|
| 30/11 | P7 + P8 window (29/11): gross by service, the share by difference, and computed variable compute versus billed EC2 batch | owner reads; Claude records |
| 03/12 onward | P9 campaign windows, one row each, plus the delayed-billing append (ROADMAP gate 7) | same |
