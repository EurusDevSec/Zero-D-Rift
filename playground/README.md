# Zero D-Rift Dojo

Zero D-Rift Dojo is the disposable DevOps and cloud practice lane. It exists so
the owner can repeat tools, break systems and build troubleshooting fluency
without turning every exercise into a project deliverable.

## Two-lane contract

| Delivery lane | Dojo lane |
|---|---|
| Driven by the active SPEC and phase deadline | Driven by a skill gap or practice goal |
| Produces canonical project evidence | Produces local practice evidence |
| Uses approved code, versions and ownership | Uses disposable exercises and controlled failures |
| Can block phase completion | Never blocks the active phase by itself |
| L3/L4 follows project authorization | Real AWS still requires the same L3 authorization |

Micro-labs remain inside the delivery workflow when a focused mechanism must be
understood before the current task. Dojo labs are independent repetition and
deeper practice. A single exercise may be promoted later, but never automatically.

## Practice cycle

```text
Understand -> Predict -> Build -> Break -> Observe -> Diagnose
-> Repair -> Repeat -> Teardown -> Explain
```

The owner performs the meaningful steps. The agent coaches, gives progressive
hints and reviews the evidence instead of completing the drill immediately.

## Environment levels

| Level | Environment | Meaning |
|---|---|---|
| D0 | Paper or static reasoning | Predict flows, plans, policies and failure boundaries |
| D1 | Local CLI, mock or disposable process | Zero-cloud-cost mechanism practice |
| D2 | kind or another disposable local cluster | Controller and Kubernetes integration practice |
| D3 | KodeKloud or similar training sandbox | Vendor sandbox practice; not project AWS evidence |
| D4 | Project AWS account/EKS | Requires explicit L3 task, cost guard and teardown owner |

The level describes the practice environment, not the project verification tier.

## Evidence and promotion

- Raw outputs belong under `playground/runs/<run-id>/` and are ignored by Git.
- Durable reflection may be summarized in `PROGRESS.md`; never record credentials,
  account IDs, kubeconfigs, tokens, state or unredacted plans.
- Dojo results use `NOT_STARTED`, `PRACTICED`, `REPEATED` or `NEEDS_REVIEW`.
- To promote a result, compare it with the active SPEC, exact pinned versions,
  required environment, acceptance criterion and evidence schema. If any differ,
  rerun the project verification rather than relabeling the Dojo result.

## Scope control

- Keep one active lab.
- Timebox ordinary drills to 20–90 minutes.
- Detail only the next lab; keep later tracks at catalog level.
- Do not copy playground code into canonical `infra/`, manifests or controllers
  without an approved Pair task.
- Failed practice is retained as learning, not hidden or converted into PASS.

## Commands

```text
/dojo status
/dojo suggest one lab for the current skill gap
/dojo terraform T01
/dojo save
```

Start with [CATALOG.md](CATALOG.md) and load only the selected track/lab.
