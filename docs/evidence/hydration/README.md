# Hydration continuity evidence

This directory stores sanitized, dated observations and evaluations of the
repository-defined hydration test. The harness and rubric remain canonical in
`.agent/tests/hydration/`; these records do not define current project state,
change approvals or authorize implementation.

## Recorded runs

| Run | Observed result | Scope and limitation |
| --- | --- | --- |
| [HYD-20261005-01](HYD-20261005-01.md) | Recorded evaluator result `CONTINUITY_READY`, 98/100 | Existing Phase1 chat after owner-reported account switch; same-chat evaluation; fresh-chat and independent account comparison not demonstrated |

## Using records

- Evaluators and historical audits may consult a record after a candidate has
  submitted its report. Candidates must not read prior reports or evaluations.
- Compare each report against its recorded repository revision and working tree,
  then independently check the governing sources. Current Git overrides old
  snapshots for current work; a changed checkout is not automatically a mismatch.
- A rubric score is a judgment about a report, not a measured success rate,
  probability of correct implementation or proof of runtime readiness.
- For a fresh-chat test, start a new chat without a fork, old transcript, previous
  report or answer hints. Record the evaluator's actual session separately; do
  not infer independent evaluation from merely switching roles in one chat.
- Retain failed and inconclusive results with their limits. Do not overwrite an
  earlier run when a later test succeeds; add a separately identified record.
- Store no credentials, private account identifiers, raw Terraform state/plans,
  kubeconfig, screenshots containing sensitive material or private machine paths.
  Account aliases are omitted from the shared evidence.

Optional private report copies still belong in the harness's ignored `reports/`
directory. This directory is the owner-requested, sanitized shared evidence.
