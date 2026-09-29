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

### 2026-09-25 — Version and compatibility baseline

- Phase/task: P1 / Task 3
- Learning objective: Distinguish a release pin, documented compatibility and
  project runtime evidence; explain why local Kubernetes evidence is not EKS evidence.
- Source(s) consulted: `docs/VERSION_MATRIX.md`, ADR-0005 and the official sources
  linked from the matrix.
- Prediction before lab: A release existing upstream might be mistaken for proof
  that an exact multi-component combination works in this project.
- Micro-lab/change performed: Agent completed the official-source compatibility
  spike and a read-only local tool probe. No cluster or controller was installed.
- Expected vs actual: The EKS 1.35 controller baseline was narrowed, while the
  Crossplane/provider/kro combination and OpenCost remain correctly `UNVERIFIED`.
  During teach-back the owner correctly separated release evidence, local kind
  compatibility evidence and EKS/AWS integration evidence.
- Evidence path: `docs/VERSION_MATRIX.md` and
  `.agent/adr/ADR-0005_KIND_LOCAL_FIRST_ENVIRONMENT.md`.
- Explain in my own words: Separate official releases do not prove that Crossplane
  core 2.4.0 and AWS provider 2.7.0 work together. A healthy provider on kind can
  prove Kubernetes/package compatibility, but real S3 creation still depends on
  EKS identity, IAM authorization, networking and AWS APIs. Kind was selected over
  k3d because it uses upstream Kubernetes 1.35, while K3s is a modified distribution.
- Failure I can now diagnose: Distinguish a package/controller compatibility
  failure from an IRSA/IAM/AWS external-resource failure, and avoid treating kind
  success as proof of EKS-specific behavior.
- Remaining gap: L2 kind and L3 EKS/AWS runtime evidence, exact artifact digests,
  ProviderRevision health and real external-resource tests do not yet exist.
- Status: EXPLAINED

### 2026-09-28 — Threat model and identity boundaries

- Phase/task: P1 / Task 4
- Learning objective: Explain the Git/CI, Kubernetes, IRSA/AWS, tenant and
  administrative trust boundaries and identify the evidence for a denied action.
- Source(s) consulted: `docs/security/THREAT_MODEL.md` and the official AWS EKS,
  Kubernetes, Kyverno and GitHub sources linked from it.
- Prediction before lab: Owner expected that a tenant-A Pod assuming tenant-A IAM
  role but reading tenant-B S3 data indicated an overly broad AWS authorization policy.
- Micro-lab/change performed: Reviewed IRSA flow, soft-tenancy boundary and T07/T08/T10,
  then diagnosed one cross-tenant S3 access scenario. No security control, cluster,
  IAM policy or AWS resource was created.
- Expected vs actual: Owner correctly separated a successful identity path from a
  failed authorization boundary and named STS caller identity, CloudTrail and policy
  review as evidence. Correction: the resource belongs to tenant B rather than a
  "Pod B", and the allow can originate from role identity/session policy or S3
  bucket/access-point policy rather than bucket policy alone.
- Evidence path: `docs/security/THREAT_MODEL.md`.
- Explain in my own words: If Pod A assumes Role A as intended, the identity flow
  works. If that role can read tenant-B S3 data, the authorization/isolation scope
  is too broad. Confirm the caller, inspect S3 data events and evaluate all relevant
  identity/resource policies to locate the allow path.
- Failure I can now diagnose: Distinguish wrong-role/trust failure from correct-role
  over-authorization and identify the evidence needed for cross-tenant S3 access.
- Remaining gap: Later L2/L3 positive and negative runtime tests, exact IAM policies,
  CloudTrail data-event configuration and VPC CNI/Kyverno enforcement.
- Status: EXPLAINED

### 2026-09-28 — Cost, quota and teardown guardrails

- Phase/task: P1 / Task 5
- Learning objective: Explain why scale-to-zero does not remove fixed AWS cost,
  compare public/NAT/endpoint egress options and identify the evidence required
  before paid AWS work.
- Source(s) consulted: `docs/de_cuong_tot_nghiep_ver3.md`,
  `docs/finops/COST_PLAN.md`, ADR-0006 and the dated AWS/Karpenter sources linked
  from the cost plan.
- Prediction before lab: Owner expected a second 100 USD guide reward to make
  200 USD credit available after completing the guide.
- Micro-lab/change performed: Agent completed the documentation-level cost plan
  and ran redacted read-only account, Billing and Price List probes. `us-east-1`,
  IAM-user STS access, EKS/EC2/VPC/RDS quota values, one enabled 100 USD credit
  and candidate On-Demand prices were observed; no resource or quota request was created.
- Expected vs actual: The 100 USD envelope, priced planning baseline,
  Budget/TTL/GPU guardrails and teardown contract are explicit. Region, one
  enabled 100 USD credit and selected applied quotas are account-verified; both
  G/VT On-Demand and Spot quotas are zero. The possible second credit remains
  correctly `UNVERIFIED_OWNER_PLANNED` until the guide is completed and re-queried.
- Evidence path: `docs/finops/COST_PLAN.md` and
  `.agent/adr/ADR-0006_POC_NETWORK_EGRESS_AND_COST_GUARDRAILS.md`.
- Explain in my own words: NAT Gateway retains its hourly charge and adds per-GB
  processing cost while it exists, so the short-lived PoC accepts public worker
  nodes instead. That trade-off requires no Internet ingress or SSH, restrictive
  security groups, IMDS controls, bounded EKS public API CIDR and private RDS.
  Additional credit does not expand the canonical 100 USD gross envelope.
  `Pod=0` removes workload Pods, not the EKS control plane, system nodes, RDS,
  public IPv4, EBS/snapshots, S3 objects, CloudWatch logs, load balancers or any
  accidentally retained NAT Gateway.
- Failure I can now diagnose: Distinguish workload scale-to-zero from infrastructure
  teardown, detect a fixed-cost resource that survived the run and identify a GPU
  launch blocked by zero G/VT vCPU quota.
- Remaining gap: Runtime billing lag, Spot price/capacity and the separately
  approved GPU quota-increase decision remain future campaign evidence.
- Status: EXPLAINED

### 2026-09-29 — Baseline and experiment contract

- Phase/task: P1 / Task 6
- Learning objective: Explain why event boundaries, timeout, failure, exclusion
  and dataset-freeze rules must be registered before official trials.
- Source(s) consulted: `docs/de_cuong_tot_nghiep_ver3.md`,
  `docs/experiments/EXPERIMENT_PLAN.md`, the threat-model evidence rules and the
  project Definition of Done.
- Prediction before lab: Owner needed to distinguish a real system failure after
  `t0` from an invalid measurement that may be excluded.
- Micro-lab/change performed: Created the documentation-level experiment contract
  and parsed one manifest marked `SYNTHETIC`, `official=false` and `EXCLUDED`.
  No cluster, AWS resource or observed trial was created.
- Expected vs actual: H1–H6 targets/sample counts, manual baselines, event/timeout
  rules, retained failures, pre-registered exclusions, JSONL/CSV shapes and
  dataset freeze are explicit. Synthetic exclusion guards and JSON parsing pass.
- Evidence path: `docs/experiments/EXPERIMENT_PLAN.md` and
  `docs/experiments/examples/SYNTHETIC_RUN_MANIFEST.json`.
- Explain in my own words: After `t0`, a timeout or system failure is a real trial
  outcome, so it remains in the denominator and counts as failure. Exclusion is
  only for an invalid measurement, such as missing collector evidence or use of
  the wrong frozen artifact. Freezing timeout, success and exclusion rules before
  results prevents cherry-picking bad outcomes and keeps the thesis conclusion
  comparable and defensible.
- Failure I can now diagnose: A post-`t0` capacity or timeout outcome is a retained
  failed trial, whereas a registered measurement-pipeline failure can be excluded
  with its reason code and evidence.
- Remaining gap: Later harness implementation, campaign freeze and real L3/L4
  trial evidence; these are not prerequisites for the P1 learning gate.
- Status: EXPLAINED

### 2026-09-29 — P1 retention and P2-readiness audit

- Phase/task: P1 / Task 7
- Learning objective: Reconstruct the P1 system boundary and diagnose a small
  number of cross-layer scenarios without reading generated prose verbatim.
- Source(s) consulted: P1 spec, ver3, system design, version matrix, threat model,
  cost plan, experiment contract and ADR-0003 through ADR-0006.
- Prediction before lab: Prior guided answers might show point-in-time recognition
  without durable independent recall or hands-on understanding.
- Micro-lab/change performed: Documentation/path consistency audit plus bounded
  paper scenarios for Argo/Crossplane readiness, AWS authorization, bootstrap
  dependency, IRSA and soft tenant isolation. No local cluster, controller, IAM
  policy or AWS resource was created.
- Expected vs actual: Required P1 artifacts are aligned after correcting stale
  status references. The owner initially self-assessed only high-level recognition,
  then independently located controller/AWS failure boundaries, traced IRSA and
  bounded soft-tenancy claims. This supports current `EXPLAINED`, not hands-on or
  durable `PRACTICED`/`REPRODUCIBLE` mastery.
- Evidence path: `.agent/specs/SPEC-P1_FOUNDATION_AND_COMPATIBILITY.md` and the
  canonical P1 documents listed there.
- Explain in my own words: Argo can be synced while a Crossplane managed resource
  and AWS resource are not ready. Provider health proves the controller runtime,
  not IAM authorization. Terraform creates the first EKS because Crossplane needs
  an existing Kubernetes runtime. IRSA exchanges a ServiceAccount token through
  OIDC/trust and STS before service permission is evaluated. Namespace controls
  reduce tenant access but shared EKS/VPC and privileged components keep isolation soft.
- Failure I can now diagnose: Distinguish Argo sync from end-to-end readiness;
  controller health from AWS authorization; STS trust failure from S3 permission
  failure; and a passed RBAC negative test from a hard-isolation claim.
- Remaining gap: No hands-on Terraform state cycle, controller runtime, real IRSA,
  NetworkPolicy/RBAC suite or AWS reconciliation evidence exists. These gaps move
  to the bounded P2-P5 micro-labs and must not be described as mastered.
- Status: EXPLAINED
