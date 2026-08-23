---
method: just-in-time
weekly_budget: 5-6 focused learning hours plus learning embedded in implementation
owner_goal: explain, troubleshoot, and defend each implemented mechanism
---

# Zero D-Rift Learning Roadmap

## Meaning of “understand” for this project

Understanding does not mean memorizing every option in a technology. For each
component used in the PoC, the owner should be able to:

1. Explain the problem and responsibility boundary.
2. Draw or narrate its control/data flow.
3. Configure the subset used by the project.
4. Diagnose at least one realistic failure from logs/events/state.
5. Explain an alternative and the chosen trade-off.
6. Reproduce the relevant demo from the runbook.

## Phase learning track

| Phase | Learn now | Micro-lab before integration | Proof of understanding |
|---|---|---|---|
| P1 | EKS architecture, Kubernetes reconciliation, IAM/OIDC, experimental design | Trace a Kubernetes reconciliation example and map AWS identity flow on paper/local cluster | Explain bootstrap plane vs control plane and define a measurable baseline |
| P2 | Terraform state/module boundaries, VPC/EKS/OIDC | Plan a minimal module and inspect plan/destroy behavior without long-lived credentials | Explain state, dependency graph, idempotency and teardown risk |
| P3 | Argo CD sync, CRD/controller loop, Crossplane managed resource, kro graph | Crossplane creates one S3 resource; kro separately composes Deployment + Service | Explain that kro composes while Crossplane calls AWS APIs |
| P4 | IRSA, Secrets, PostgreSQL/pgvector, readiness | Pod reads only an allowed S3 prefix using scoped identity | Trace Pod -> ServiceAccount -> IAM -> AWS and app -> RDS connectivity |
| P5 | RBAC, quota, NetworkPolicy, Pod Security, Kyverno | Write and break one policy at a time | Predict which layer blocks each negative request and where evidence appears |
| P6 | SQS semantics, KEDA ScaledJob, Karpenter NodePool, Spot/checkpoint | KEDA local/CPU behavior, then Karpenter CPU node before GPU | Explain pod scaling vs node provisioning and why checkpointing belongs to the app |
| P7 | Prometheus metrics, OpenCost allocation, AWS billing delay, cost formula | Calculate one workload profile manually from fixed inputs | Distinguish variable compute cost, cluster fixed cost and invoice truth |
| P8 | Desired-state remediation, RDS snapshot/restore, RTO/RPO | Independent SG drift test before DB recovery | Explain configuration recovery vs data recovery and human approval boundary |
| P9 | Trial design, timestamps, p50/p95, failure retention | Dry-run a small synthetic dataset through analysis | Explain every included/excluded run and avoid changing metrics after results |
| P10/P11 | Runbooks, architecture defense, limitations | Timed offline demo and failure walkthrough | Answer panel questions without reading implementation notes verbatim |

## Learning sequence for unfamiliar control-plane tools

```text
Kubernetes reconciliation concept
  -> Crossplane managed resource lifecycle
  -> one AWS S3 vertical slice
  -> kro ResourceGraphDefinition with native resources
  -> kro composition that includes the proven Crossplane resource
```

Do not study or integrate Crossplane and kro as one opaque block.

## Weekly learning rhythm

- Before implementation: 45–90 minutes of official reading and prediction.
- During implementation: one bounded micro-lab and active troubleshooting.
- After verification: 20–30 minutes of teach-back and learning-log update.
- At week end: review unresolved gaps and carry forward only those required by
  the next phase.

Avoid unrelated certifications, full-course completion and broad technology
survey during the MVP window unless a concrete blocker requires them.

