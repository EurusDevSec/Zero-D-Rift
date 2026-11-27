# P6 — Codex review after the L3 window (2026-11-27)

> Requested by Claude for the owner (SPEC-P6 §5 P6-T4.3 "second-agent review").
> Scope: only what changed in or after window `P6-L3-20261126-01` where a mistake
> would give a **false PASS, too much IAM, or a broken next window**. The owner pastes
> the prompt below into Codex and copies its verdict, verbatim, into §Result.
> The pre-window review (rounds 1–4, APPROVE at `58c9982`) is in
> `P6_CODEX_REVIEW_REQUEST_20261125.md` and is not repeated.

## In scope (and why)

| Part | PR / files | Why it needs a second agent |
|---|---|---|
| IAM check fix | PR #105 (merged in the window, `407b751`) — `infra/terraform/scripts/batch_iam_check.sh`, `tests/batch_iam_matrix.json` | Merged under window time pressure. The matrix row `karpenter iam:ListInstanceProfiles` now simulates on `*`: could that hide a real over-grant? Can the `jq -r` path print or pass a wrong policy? |
| Karpenter access entry ordering | PR #108 — `infra/terraform/main.tf`, `modules/karpenter/main.tf`, `modules/karpenter/variables.tf` | Window error 3. The fix must make the access entry wait for the cluster without changing names, IAM or the plan shape |
| Runbook gate changes | PR #107 — `docs/runbooks/P6_L3_WINDOW.md` §4 (profile row), B1, C2, K3, F4, §6 H8 | H8 relaxes the gate for an S2 retry plan: is the replacement rule strong enough? Does any new command print an ID? |
| Window evidence | PR #107 — `docs/evidence/p6/P6-T4.2_L3_WINDOW_20261126.md` | Does any claim go beyond the recorded output (suite JSON, logs)? Is anything counted as PASS that was not? |

**Out of scope:** PR #99–#104 (window request PRs, one-line changes checked with
`git merge-tree`), PR #106 (P1g, two request files byte-identical to `8692146`).

## Prompt for Codex

```
Review, read-only, the post-window P6 changes of Zero-D-Rift. Do not run AWS, kind or
terraform apply. Read AGENTS.md, .agent/specs/SPEC-P6_BATCH_TRAINING_JOB.md (§5 P6-T4,
§9.5, D6) and docs/evidence/p6/P6-T4.2_L3_WINDOW_20261126.md §9 (errors) first.

Scope: PR #105 (merged; read on main 407b751), PR #108, PR #107.

Answer for each, with file:line:
1. False PASS: can batch_iam_check.sh pass while a role is broader than D2/D6? Is the
   ListInstanceProfiles row on "*" a real check or a hole? Can H8 (S2 retry plan) let a
   plan through that adds or changes something outside the approved full plan?
2. Terraform: does access_entry_cluster_name = module.cluster.cluster_name make
   aws_eks_access_entry.node wait for the cluster? Does it change any name, any IAM
   document, the plan shape hash, or make a value unknown at plan time? Is a cycle possible?
3. Runbook: does every new command fail loudly (READ_FAILED, not 0 or None counted as a
   pass)? K3 with length(Contents[]) prints None on an empty prefix: is that handled?
4. Evidence: is any statement in the T4.2 evidence not backed by the suite JSON or the
   logs it cites? Is any account ID, ARN, IP, queue URL, node or instance name present?
5. Anything else that would make the next window fail or cost more.

Verdict: APPROVE, or CHANGES with a numbered list (severity HIGH/MEDIUM/LOW, file:line, fix).
```

## Result

_Pending. Owner pastes Codex's verdict here verbatim._
