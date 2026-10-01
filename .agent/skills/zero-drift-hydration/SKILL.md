---
name: zero-drift-hydration
description: Run or evaluate the Zero D-Rift account/session continuity test without mutating the repository or external systems; use for /hydration-test candidate or evaluator.
---

# Zero D-Rift Hydration Test

Choose exactly one role from the user's request.

## Candidate

1. Read [candidate instructions](../../tests/hydration/CANDIDATE_PROMPT.md) and
   [response template](../../tests/hydration/RESPONSE_TEMPLATE.md).
2. Hydrate only from live repository sources and read-only commands. Do not use
   old chat summaries as authority and do not inspect prior hydration reports.
3. Return the completed report in chat. Do not grade yourself, edit files or
   mutate Git, Terraform, Kubernetes, AWS or any external account.

## Evaluator

1. Read [evaluation guide](../../tests/hydration/EVALUATOR_GUIDE.md).
2. Re-query live Git and governing sources independently; never accept the
   candidate's citations or state claims without checking them.
3. Score the supplied report, identify every critical mismatch and return one
   outcome: `CONTINUITY_READY`, `CONDITIONAL` or `FAIL`.
4. Do not repair the candidate report during scoring. Recommend the smallest
   durable repository correction only when the failure exposes a harness gap.

The test measures whether the repository can reconstruct a safe working state.
It does not measure personality similarity, verbatim chat recall or technical
mastery beyond what the active task requires.
