# DRF-4 — P2-T2 local Terraform state/dependency lab (TF-T01) — 2026-10-31

Issue: DRF-4 (Linear). Sources: SPEC-P2 Task 2,
`playground/tracks/terraform/T01_STATE_GRAPH/LAB.md` and `WALKTHROUGH.md`.
Candidate: HEAD `e8f6d69` plus uncommitted workflow/docs/playground diff.
Run ID: `TF-T01-20261030-01`. Tier: L1 local, built-in `terraform_data` only,
Terraform 1.16.4 windows_amd64. Timezone: Asia/Saigon. Cost: 0 USD.

## Who did what

| Actor | Work |
|---|---|
| Owner | Typed all 11 configuration files from the walkthrough; ran `init`, `fmt -check`, `validate` and rendered `graph-before.svg` (31/10 08:40) |
| Claude | At the owner's explicit request to finish the run: added the missing `default = 2` for `system_node_desired_size` (the owner's `plan` was waiting for that input), fixed an `ADDR-0006` message typo, added `noop-check.sh`, ran M1–M7 (08:51), restored the version default to 1.35 |

The owner wrote no `expect` lines; prediction versus observation was therefore
not demonstrated by the owner. The missions below are a **Claude-run**, not an
owner demonstration.

## Observed results (Claude-run, 08:51:11–08:51:19)

| Mission | Command scenario | Result |
|---|---|---|
| M1 | `plan -out`, `apply tfplan` | `Plan: 9 to add`; vpc first, S3 endpoint and 4 subnets parallel, then eks, then oidc_provider and system_nodes; 6 graph edges, eks depends on public_subnets |
| M2 | `noop-check.sh` | `NOOP`, exit 0 |
| M3 | version default 1.35 -> 1.36 | `0 to add, 2 to change, 0 to destroy` (eks, system_nodes); re-plan `NOOP` |
| M4 | `-var cluster_name=zero-drift-v2` | `3 to add, 6 to change, 3 to destroy`; eks, oidc_provider, system_nodes `must be replaced`; destroy before create; revert apply then `NOOP` |
| M5 | NAT on, `ap-southeast-1`, one AZ | each exit 1 with its validation message; `NOOP` afterwards |
| M6 | fake `vpc_id` and `subnet_ids`, plan only | edge `eks -> public_subnets` removed; `3 to add, 0 to change, 3 to destroy`; restored, `NOOP` |
| M7 | `plan -destroy`, apply | `9 destroyed`; `terraform state list` 0 lines; tfstate `resources` length 0 |

Raw log, graphs and state stay in the gitignored run directory
(`claude-run.log`, `graph-*.svg`, `graph-edges-*.txt`); none is committed here.

## Acceptance criteria

| AC | Result | Reason |
|---|---|---|
| AC-01 owner authority and exact CLI pin before run | PASS | owner requested the run; CLI 1.16.4 verified in DRF-3 |
| AC-02 prediction vs observed plans; owner explains update/replace | PARTIAL | explanation part MET: owner explain-back v2 (31/10, given in chat, Claude typed it verbatim) correctly covers state as the code-to-real-id map and the orphan risk, update `~` vs replace `-/+` / `must be replaced` with `cluster_name` in `triggers_replace`, and NOOP versus the L3 `kubectl` smoke test. Prediction part NOT MET: no `expect` lines before apply |
| AC-03 destroy and cleanup with commands/exit/run ID | PASS (Claude-run) | M7 counts above, run ID recorded |
| AC-04 learning only from owner demonstration; no EKS PASS | PASS | learning level unchanged; local result proves nothing about AWS/EKS |

## Status and next action

`CANDIDATE_FOR_OWNER_ACCEPTANCE` with a recorded gap. Explain-back v2 is
accepted by the Claude review (run directory `notes.md`). On 31/10 the owner
chose not to do the prediction re-run, to move on to the next issue. An M1
apply the owner had started at 11:40 was destroyed by Claude (9 destroyed,
state 0). Gap carried forward: the prediction step (`expect` before apply) was
never shown, so learning status stays below `PRACTICED`. Practise it in the
first real network plan after DRF-5.
