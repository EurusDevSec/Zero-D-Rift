# P6 — one Codex review before the L3 window (2026-11-25)

> Requested by Claude for the owner (SPEC-P6 §9.3; L3 runbook §3 P4). One review
> for every P6 part where a mistake would give a **false PASS, a cost leak or too
> much IAM**. The owner pastes the prompt below into Codex and copies its verdict,
> verbatim, into §Result.

## In scope (and why)

| Part | PR / files | Why it needs a second agent |
|---|---|---|
| T3 Terraform IAM + Karpenter | PR #93 — `infra/terraform/modules/batch-platform/`, `modules/karpenter/`, `scripts/plan_assert.sh` (P6 checks), `scripts/batch_iam_check.sh`, `tests/batch_iam_matrix.json` | IAM breadth (`iam:PassRole`, EC2 create, SQS/S3 per tenant); node SG reach; cost (instances outside Terraform) |
| T2.2 RGD + static rules | PR #94 (merged 26/11, review on `main` `c7d779e`) — `gitops/platform/rgd/batch-training-job.yaml`, `gitops/platform/batch/`, `gitops/platform/apps/5{0,5,7}-*.yaml`, `gitops/check.sh` rules 19-23 | D5 (one Job), kro/KEDA label interaction (found on kind), NodePool limits/expiry, quota D9 |
| T4.1 suite + window helper | PR #96 — `gitops/tests/batch-suite.sh`, `infra/p6-window/window.sh` | Every B-case verdict: can any case PASS without the behaviour? Can a failed read become 0? Does any output leak an ID? |

**Out of scope:** T2.1 worker (PR #92, merged; 65 unit tests, smoke on S3Mock),
docs and the kind lab files. Codex may still flag them if it sees a blocker.

## Prompt for Codex

```
Review, read-only, the P6 batch-training candidate of Zero-D-Rift. Do not run AWS,
kind or terraform apply. Read AGENTS.md and .agent/specs/SPEC-P6_BATCH_TRAINING_JOB.md
(§4 scenarios, §5 P6-T2.2/T3/T4, §9.5 teardown, D1-D14) first.

Scope: PR #93 (Terraform batch-platform + karpenter, plan_assert P6, batch_iam_check),
PR #94 (merged; read it on main c7d779e: RGD batch-training-job, KEDA/Karpenter apps, NodePools, gitops/check.sh 19-23),
and PR #96 (gitops/tests/batch-suite.sh, infra/p6-window/window.sh).

Answer for each, with file:line:
1. False PASS: can any of B01-B14 or any check.sh / plan_assert rule pass while the
   behaviour it claims is absent? (e.g. a READ_FAILED or empty read counted as 0,
   a missing object treated as "none", a stale marker from another attempt.)
2. IAM: is any role broader than SPEC D2/D6 (KEDA read-only on the queue, submit send +
   prefix list, tenant own bucket prefix + own queue ops, Karpenter no IAM write and
   PassRole only on the node role)?
3. Cost: can a Karpenter node or a Spot request outlive teardown §9.5, or start outside
   NodePool limits (2 vCPU per pool, expireAfter 2h, WhenEmpty 60s)?
4. Leaks: can any output, log line, ConfigMap in Git, or evidence field print an account
   ID, ARN, queue URL, IP, node or instance name?
5. Window helper: does annotate/batch-config/purge/cleanup refuse on a failed read and
   never run cleanup while the request still exists (D3)?

Verdict: APPROVE or REQUEST CHANGES; findings as HIGH/MEDIUM/LOW with a concrete fix.
```

## Result

_(owner pastes Codex's verdict here; Claude applies the findings and records them in SPEC-P6 §9.3)_
