# Dojo Catalog

This catalog is intentionally outcome-level. Only an about-to-run lab receives a
detailed `LAB.md` so the Dojo does not become a second speculative roadmap.

| Track | Core capability | Typical environment | First progression | Status |
|---|---|---|---|---|
| Terraform engineering | Predict state, graph, lifecycle, tests, drift and teardown | D0-D1, later D4 | State graph -> plan tests -> modules -> drift/recovery | T01 drafted |
| AWS foundations | Trace VPC/EKS/resource lifecycle, quota, cost and inventory | D0, D3, D4 | Network flow -> inventory -> teardown incident | Outline |
| IAM and workload identity | Separate identity, trust, STS and service authorization | D0, D3, D4 | Policy evaluation -> AssumeRole -> IRSA failures | Outline |
| Kubernetes reconciliation | Diagnose desired/observed state and controller boundaries | D1-D2 | Deployment chain -> CRD/status -> admission failure | Outline |
| Argo CD GitOps | Separate sync, health and end-to-end readiness | D2 | Sync drift -> missing dependency -> prune/rollback | Outline |
| Crossplane | Reconcile managed resources and external state | D2, later D4 | Provider health -> managed condition -> AWS failure | Outline |
| kro | Build and diagnose resource dependency graphs | D2 | RGD expansion -> dependency failure -> readiness summary | Outline |
| IRSA | Trace ServiceAccount token to STS and AWS authorization | D0-D2, D4 proof | Trust failure -> credential success -> S3 deny | Outline |
| Karpenter and KEDA | Connect event demand, pending Pods and node capacity | D0-D2, D4 proof | Scheduling reasoning -> scaler -> real capacity | Outline |
| IDP and golden paths | Design safe self-service contracts and status | D0-D2 | API contract -> guardrails -> failure UX | Outline |
| Troubleshooting and incidents | Locate first failing boundary and recover safely | Any | Evidence trace -> orphan cleanup -> cost incident | Outline |

Track detail currently exists only for [Terraform](tracks/terraform/TRACK.md).
