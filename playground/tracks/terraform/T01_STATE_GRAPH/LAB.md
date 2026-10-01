---
id: TF-T01
status: WAITING_FOR_CLI_PIN
environment: D0_THEN_D1_LOCAL
timebox: 45-60m
cost: 0 USD
---

# T01 — State and Dependency Graph

## Capability and boundary

Practice predicting how Terraform configuration, dependency graph and state
interact through create, in-place update, replacement, unchanged re-plan and
destroy.

This lab uses only built-in `terraform_data` resources after the exact Terraform
CLI version is approved. It does not use a cloud provider and proves nothing
about AWS, EKS or provider compatibility.

## Prerequisite gate

- P2 records an exact Terraform CLI pin from an official source.
- `terraform version` matches that pin.
- A new local run directory is used; no copied project state is present.

Until those conditions hold, perform only the D0 prediction section. Do not create
an unpinned starter configuration merely to make the lab appear runnable.

## D0 — Predict before writing HCL

Sketch three objects representing `foundation`, `cluster` and `system_nodes`.
The latter two must reference upstream outputs so Terraform can infer the graph.

Before running anything, write predictions for:

1. Create order and possible parallelism.
2. Reverse destroy order.
3. What state must remember after apply.
4. What an unchanged second plan proves and does not prove.
5. Which kind of input change should update in place and which should force
   replacement through `triggers_replace`.

## D1 — Challenge after the CLI pin

The owner writes the smallest configuration that:

- Declares the approved `required_version`.
- Creates the three `terraform_data` objects with inferred dependencies.
- Exposes only non-sensitive outputs needed to observe the graph.
- Contains one ordinary `input` and one `triggers_replace` value for comparison.

Run the normal local lifecycle: initialize, format-check, validate, plan, apply,
inspect state, unchanged re-plan and destroy. Predict each plan before accepting
it. Store raw output only under `playground/runs/<run-id>/`.

## Controlled failures

Choose one at a time:

1. Remove an upstream reference and predict how the dependency graph changes.
2. Change the ordinary input, then compare it with a `triggers_replace` change.
3. Interrupt before a planned action is accepted and explain what did or did not
   reach state.

Do not corrupt or delete state in T01; state recovery belongs to T05.

## Evidence and teardown

Record expected versus actual action symbols, `terraform state list`, the final
unchanged plan and destroy result. After destroy, verify state contains no managed
object and remove only the disposable run directory according to the lab runbook.

Result labels are `PRACTICED`, `NEEDS_REVIEW` or `NOT_RUN`; never project `PASS`.

## Explain-back

1. Why does file order not determine creation order?
2. What relationship is stored in configuration and what is stored in state?
3. Why can an empty plan not prove AWS or EKS works?
4. Why does `triggers_replace` differ from an ordinary input change?
5. What evidence is needed before saying the local lab was cleaned up?

## Hint policy

- Hint 1 names the relevant Terraform concept.
- Hint 2 points to the missing graph/state boundary.
- Hint 3 gives a small HCL fragment, not the full file.
- A complete reference solution is shown only after an attempt or explicit request.
