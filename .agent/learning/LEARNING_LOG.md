# Zero D-Rift Learning Log

This file records demonstrated understanding and open gaps. It does not award
completion merely because an agent generated working files.

## Initial self-assessment — 2026-08-23

| Area | Starting evidence | Current level for project | Immediate action |
|---|---|---|---|
| AWS | CLF-C02, labs and small projects | Foundation/application | Deepen EKS, IAM/OIDC, cost and operational troubleshooting in P1–P2 |
| Kubernetes | Many labs and small projects | Foundation/application | Focus on reconciliation, CRDs, policy and failure diagnosis |
| Terraform | Used on AWS and DigitalOcean | Basic applied use | Strengthen state, module design, lifecycle and reproducible teardown |
| Crossplane | No hands-on use reported | New | Start with one managed S3 resource in P3 |
| kro | No hands-on use reported | New | Learn only after the Crossplane and CRD concepts are separated |
| KEDA/Karpenter | Not yet assessed | Unknown | Assess just before P6; do not front-load now |
| Experimental analysis | Not yet assessed | Unknown | Establish baseline and run-manifest schema in P1 |

## Entry template

```markdown
### YYYY-MM-DD — Topic
- Phase/task:
- Learning objective:
- Source(s) consulted:
- Prediction before lab:
- Micro-lab/change performed:
- Expected vs actual:
- Evidence path:
- Explain in my own words:
- Failure I can now diagnose:
- Remaining gap:
- Status: STARTED | PRACTICED | EXPLAINED | REPRODUCIBLE
```

Status meanings:

- `STARTED`: read or watched; no practical evidence.
- `PRACTICED`: completed a bounded exercise with evidence.
- `EXPLAINED`: can explain responsibility, flow and one failure mode.
- `REPRODUCIBLE`: can repeat the project-specific outcome from documentation.

### 2026-09-25 — System design and architectural boundaries

- Phase/task: P1 / Task 2
- Learning objective: Explain the bootstrap/platform boundary, controller
  responsibilities, shared-RDS decision and recovery isolation boundary.
- Source(s) consulted: `docs/de_cuong_tot_nghiep_ver3.md`,
  `docs/architecture/SYSTEM_DESIGN.md`, ADR-0003 and ADR-0004.
- Prediction before lab: Initially treated a resource object as the actor for a
  transition and did not distinguish Argo CD `Synced` from end-to-end `Ready`.
- Micro-lab/change performed: Traced the bounded `A -> B -> C -> D` request path
  on paper and reviewed failure scenarios for missing managed/external resources,
  dual ownership and database authorization. No controller or AWS resource was created.
- Expected vs actual: After guided correction, correctly located failures by the
  first missing object and the controller owning the preceding transition; also
  separated IRSA/IAM authorization from PostgreSQL privileges.
- Evidence path: `docs/architecture/SYSTEM_DESIGN.md`,
  `.agent/adr/ADR-0003_BOOTSTRAP_PLATFORM_BOUNDARY.md`, and
  `.agent/adr/ADR-0004_SHARED_RDS_AND_RECOVERY_DATABASE.md`.
- Explain in my own words: Terraform creates the EKS bootstrap foundation; Argo CD
  syncs Git state, kro expands a golden-path request, Kubernetes/Crossplane
  reconcile child resources, and readiness is distinct from sync. Shared RDS stays
  outside each sandbox request, while destructive recovery uses a separate PoC DB
  or clone.
- Failure I can now diagnose: Argo CD can be synced while a Crossplane resource is
  not ready; dual-managing one AWS resource can create a reconciliation loop; and
  successful secret retrieval does not grant PostgreSQL `CREATE SCHEMA` privilege.
- Remaining gap: Crossplane and kro have not been practiced hands-on. Exact
  versions, provider packages, Region, IAM scope, secret integration and
  management/deletion policies remain `UNVERIFIED` for later P1 tasks.
- Status: EXPLAINED
