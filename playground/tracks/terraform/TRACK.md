# Terraform Engineering Track

## Outcome

Build the ability to predict Terraform behavior, explain state and dependency
decisions, test configuration without accidental cloud mutation, diagnose drift
and complete teardown from evidence.

This track supports P2 but does not replace its micro-lab, acceptance criteria or
observed create/verify/destroy cycle.

## Progression

| Lab | Capability | Environment | Cost | Status |
|---|---|---|---|---|
| T01 | P2 bootstrap graph: state, update vs replace, guardrails, teardown | D1 local | 0 USD | Ready (DRF-4) |
| T02 | Variables, validation and plan assertions | D1 mock | 0 USD | Outline |
| T03 | Module boundary and stable resource identity | D1 mock | 0 USD | Outline |
| T04 | Update versus replacement and lifecycle risk | D1 mock | 0 USD | Outline |
| T05 | Drift detection, import and state recovery | D1 disposable | 0 USD | Outline |
| T06 | Cost-bounded AWS plan and teardown reasoning | D0/D1 then D4 | D4 requires approval | Outline |

## Advancement rule

- `PRACTICED`: completed once with prediction, evidence, teardown and explain-back.
- `REPEATED`: completed again with a changed input/failure without following the
  first solution step by step.
- Project `PRACTICED` or `PASS` remains governed by the active SPEC and learning log.

Start with [T01](T01_STATE_GRAPH/LAB.md).
