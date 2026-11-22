---
id: SPEC-P5
title: Tenant guardrails — RBAC, quota, NetworkPolicy, Pod Security, Kyverno
status: DRAFT_FABLE_20261116_RECHECKED_20261122
phase: P5
start: 2026-11-23 at the earliest (owner rebaseline, D11)
deadline: TBD (owner rebaseline)
schedule_baseline: ver3 §12 window 09–10/11 already missed; owner rebaseline open (D11)
estimated_effort: 20-24 hours (ROADMAP allocates 16 h)
mode: Coach ("write and break one policy at a time"), then Pair
canonical_scope: docs/de_cuong_tot_nghiep_ver3.md
linear: DRF-18 (outline issue; split into P5-T tasks at the phase gate)
authority: DRAFT_ONLY_NO_INSTALL_NO_AWS_NO_LINEAR_CHANGE
drafted_from: main at df275e4 (2026-11-16), Claude Fable 5.2
rechecked_at: main at df5d6f6 (2026-11-22), after P4 acceptance; §2 results recorded
---

# 0. Draft status

This file is an early draft written on 16/11/2026 at the owner's request, while
P4 is still being built. It is **not** the active contract. AGENTS §7 and
`.agent/docs/FEATURES.md` say to detail only the current phase; this draft exists
so that the P5 gate starts from a reviewed outline instead of a blank page.

Before P5 starts: recheck §2, refresh every dated fact in §11, let the second
agent review the candidate revision, and get the owner's decisions on §9.1. Only
then may the status move to `OWNER_APPROVED_<date>`. No date, trial count,
acceptance, learning gate or teardown in ver3 is reduced by this draft
(ver3 §12.1).

**Recheck 22/11/2026.** P4 closed its technical gate on 22/11 (audit
`docs/evidence/p4/P4_ACCEPTANCE_AUDIT_20261121.md`). Two procedural items are
still open: the delayed inventory of the 22/11 window and Bills gross. §2 now
records the result of every assumption.
- One assumption was false: A8, the location of the independent check. The
  ingress rule in D5 and P5-T3 changed with it.
- One is still unmeasured: A6, node headroom.
- New facts from P4 are rows A13–A17.

Decisions changed by the recheck: D3 (GPU line, ADR-0009), D5 (ingress source),
D10 (cost basis). New: D11 (schedule). Nothing in acceptance, trials or teardown
changed. The second-agent review and the owner decisions are still open.

# 1. Goal and boundaries

## Goal

Give the two simulated tenants the guardrails ver3 §4.2 item 3 and §9.5 promise,
and prove them with a versioned negative suite on EKS:

- a tenant's workload cannot read Kubernetes objects, secrets, database data or
  AWS resources of the other tenant;
- an unsafe or oversized workload is rejected before it runs;
- pod-to-pod traffic between tenants is denied while the paths a sandbox needs
  still work;
- both `RAGSandbox` instances from P4 keep passing their checks with every
  guardrail in `Enforce`.

This is the ver3 §12 exit criterion for P5: "Negative security/isolation suite
pass; không tuyên bố hard tenancy". The suite built here is the "Policy/isolation
suite" of EXPERIMENT_PLAN §6 (900 s stop) and runs again at every major policy or
configuration commit, including the P9 campaign commit.

Outcome trace: cross-cutting condition for both Golden Paths (AGENTS §0). Without
it the RAG and Batch paths cannot be offered to two tenants on one cluster.

## MUST deliverables

- `SPEC-P5` approved by the owner with decisions D1–D12 (§9.1) resolved.
- Tenant baseline under `gitops/platform/tenants/`: Pod Security labels, RBAC
  Role/RoleBinding per tenant, `default` ServiceAccount without token automount,
  ResourceQuota, LimitRange, NetworkPolicies.
- Argo CD `AppProject` for the request path: only the golden-path kinds, only the
  tenant namespaces.
- Kyverno installed through Argo CD, pinned by chart version and image digest,
  with the tenant policies of D6 in `Enforce` after an `Audit` stage.
- Terraform change: VPC CNI add-on configuration that enables NetworkPolicy
  enforcement, with a test and a plan assertion.
- `tests/isolation/`: one suite with positive and negative cases, each mapped to a
  THREAT_MODEL threat ID and to the layer expected to refuse it.
- Runbook `docs/runbooks/P5_TENANT_GUARDRAILS.md`: apply, verify, break-and-fix
  labs, undo, teardown order, and a "Tự thử" section.
- Evidence under `docs/evidence/p5/`: L2 kind labs, L3 window, suite result,
  inventory and cost. Raw logs stay outside Git.
- THREAT_MODEL §8 (T03–T16) and §11 rows updated from `PLANNED`/`UNVERIFIED` only
  where a run proves them.

## Negative boundaries

1. Do not call the result hard isolation, hostile-tenant isolation or
   production-grade (ver3 §5.3, THREAT_MODEL §7.2).
2. Do not add a network or security product: no Cilium, Calico, service mesh,
   Falco, OPA Gatekeeper, image-signature verification or secret scanner
   service. Enforcement is the VPC CNI NetworkPolicy feature, Pod Security
   Admission and Kyverno only.
3. Do not give a tenant a kubeconfig, an EKS access entry, an AWS Console login
   or an IAM user. Tenants act through Git only (THREAT_MODEL §4).
4. Do not use Kyverno `mutate`, `generate` or cleanup rules in P5. Validate only,
   so that every rejection has one explainable cause (D6).
5. Do not move a policy to `Enforce` before its `Audit` result on the running RAG
   sandboxes is clean, and do not scope an enforcing policy or a fail-closed
   webhook to `kube-system`, `argocd`, `crossplane-system`, `kro-system` or any
   other platform namespace.
6. Do not claim that Kyverno, RBAC or NetworkPolicy controls changes made
   directly on AWS (ver3 §9.5).
7. Do not change the P4 credential design (ADR-0008): no new role, no wider
   trust subject, no Kubernetes Secret holding a database password.
8. Do not count NetworkPolicy YAML as isolation. Only an observed denied
   connection on EKS, with a control that shows the same connection succeeding
   without the policy, counts (THREAT_MODEL T10).
9. Do not run an AWS window without a separate execution approval, a fresh cost
   and identity check, a stop time and a teardown owner.
10. Do not record a suite run as an official H1–H6 trial.

# 2. Giả định từ phase trước (kiểm lại khi vào phase)

Every row was an assumption on 16/11/2026. On 22/11 each row was rechecked against
`main` at `df5d6f6` and the P4 evidence. A row that turned out false changes the
task list, not the acceptance.

| # | Assumption (16/11) | Source then | Recheck | Result 22/11 |
|---|---|---|---|---|
| A1 | P4 is complete on EKS: two `RAGSandbox` instances Ready, P4 negative suite passed, teardown clean | SPEC-P4 §8; nothing built yet | P4 acceptance audit in `docs/evidence/p4/` | **True, with limits.** P4 audit: 7/7 scenarios with L3 evidence (scenario 6 partial, C7). Both sandboxes ACTIVE in windows `P4-L3-20261121-01` and `-20261122-01`. `probe sandbox` (allowed paths) and `probe cross` (denied paths, IMDS included) passed. Teardown `65 destroyed`, inventory CLEAN. Open: delayed inventory of 22/11 and Bills gross |
| A2 | Namespaces `tenant-a`, `tenant-b`, `zdr-platform` and the P4 ServiceAccounts exist under `gitops/platform/tenants/` | SPEC-P4 P4-T3.2 A (planned) | `git ls-files gitops/platform/tenants` | **True.** `namespaces.yaml`, `serviceaccounts.yaml`. Labels today: Pod Security `enforce: restricted` only (no `audit`/`warn`). Tenant namespaces carry `rag.zero-drift.io/tenant: "true"`. Only the bootstrap Job and its Pod carry `rag.zero-drift.io/tenant: <tenant>` (RGD); the app Pod template and the window probe Pods carry no tenant label, and probe Pods declare no resources. Both must change before the D6 rules are enforced (P5-T2.2, P5-T4.1). The draft's `zdr.io/tenant` label does not exist; P5 reuses the `rag.zero-drift.io/` prefix (P5-T2.1 A). Sandbox ServiceAccounts `rag-<name>` are created by the RGD, not listed in Git |
| A3 | The reference image runs as non-root and tolerates a read-only root filesystem | SPEC-P4 P4-T3.1 B (planned) | image config and a `restricted` dry-run on kind | **True.** RGD containers: `runAsNonRoot`, `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`. Pods ran under `restricted` on EKS |
| A4 | kro v0.9.4 behaviour seen in the spike holds on EKS: child Job in `zdr-platform`, `readyWhen` on a Job, orphaned Job pods | spike on `origin/hoang/drf-40-kro-spike` (kind only, PR #35 not merged) | P4-T3.2 and P4-T4.1 evidence | **True on EKS.** Job in `zdr-platform`, `readyWhen` on `Complete`, orphaned `boot-0` Pod seen in window 21/11 part H. PR #35 is merged. `propagationPolicy` as the cause is still unverified |
| A5 | The VPC CNI add-on has no configuration values, so NetworkPolicy is **not** enabled today | `infra/terraform/modules/cluster/main.tf` at `df275e4`; add-on `v1.22.4-eksbuild.10` | read the module again; `aws eks describe-addon` in the window | **True.** `modules/cluster/main.tf` has no `configuration_values`; pin still `v1.22.4-eksbuild.10` |
| A6 | One or two `m6i.large` system nodes carry Argo CD, Crossplane, two providers, kro, the RAG workloads **and** Kyverno | root variables: desired 1, max 2 | pod count and allocatable memory in the P4 window (§10) | **Unmeasured.** P4 ran with `system_node_desired_size = 1` (default) and recorded no Pod count or allocatable memory. Measure first thing in the P5 window, or plan two nodes (D7, §10) |
| A7 | `gitops/check.sh` and the pull-request CI workflow from P4-T3.2 B exist and can be extended | SPEC-P4 (planned) | `git ls-files .github gitops/check.sh` | **True.** `gitops/check.sh` (rules 0–12, 35 guards) and `.github/workflows/static-gates.yml` |
| A8 | The independent RAG check runs from a Pod in `zdr-platform` | SPEC-P4 §4 says "outside the app Pod", location not fixed | P4 verify script; it decides the ingress rule in D5 | **False.** The window probes run in the **tenant** namespace with the sandbox ServiceAccount (`window.sh run_probe`), and call `http://rag-<name>.<tenant>.svc:8080`. Only `probe platform` runs in `zdr-platform`. D5 and P5-T3 B now allow app ingress from the same namespace, not from `zdr-platform` |
| A9 | Tenant app Pods do not need the Kubernetes API | THREAT_MODEL §6.4 | P4 app code | **True.** App and Job Pods run with `automountServiceAccountToken: false`; IRSA works through its own projected token |
| A10 | The P4 trust subject is `system:serviceaccount:<tenant>:rag-*` (a pattern, not one exact name) | ADR-0008 §4, SPEC-P4 D6 | Terraform `rag-identity` module as merged | **True.** `rag-identity`: tenant trust `system:serviceaccount:<tenant>:rag-*` with `StringLike`; platform and Crossplane trust exact names |
| A11 | R1 least privilege is still deferred; the Terraform role is broader than P5 needs | active context 14/11 | owner decision before DRF-27 | **True.** Still deferred (active context) |
| A12 | Argo CD applications use the `default` AppProject | P3 manifests in `gitops/platform/apps/` | read the Application files | **True.** All nine Applications use `project: default` |
| A13 | (new) Worker nodes are in public subnets with a public IPv4 and an IGW route, no NAT and no interface endpoints; only S3 has a gateway endpoint | `modules/network/main.tf` (ADR-0006) | — | **Fact.** STS and Secrets Manager are reached on public addresses, so the "443 outside the VPC" egress rule of P5-T3 B is required, not a shortcut. Removing that limit needs private subnets and interface endpoints: out of scope |
| A14 | (new) `main` has no branch protection | GitHub settings; P4 teach-back case B (22/11) | — | **Fact.** A red CI does not block a merge. T01 stays open unless the owner enables a ruleset (D12) |
| A15 | (new) The P4 window stack and tools are reusable | `infra/p4-window/`, `inventory.sh`, `plan_assert` (65 resources, shape hash) | — | **Fact.** P5 window = the P4 stack + VPC CNI configuration + Kyverno. Estimate rate 0.35 USD/h (P4 D10 basis), so the 1 h 04 min confirm window is estimated at 0.37 USD; gross not yet read |
| A16 | (new) P4 process lessons | P4 evidence and PRs #55–#59 | — | **Fact.** Each lesson is now a rule in P5: <br>• Code changed after the window forced a second window, so the candidate is reviewed **before** the window and nothing changes in it. <br>• MFA lasts 1 h. Refresh with a plain `sts` call; never clear the CLI cache while Claude has commands running. <br>• The tag index lags teardown, so the delayed inventory runs next day. <br>• Merge only after checking `headRefOid` |
| A17 | (new) Remaining calendar | ver3 §12, today 22/11 | — | **Fact.** P5–P11 cannot fit before 02/12 at 8 h/day; P9 alone is 44–48 h (D11) |

# 3. Learning objectives

By the end of P5 the owner should be able to:

1. Name, for any forbidden request, the first layer that refuses it (Git/CI,
   AppProject, RBAC, Pod Security, Kyverno, quota, NetworkPolicy, IAM,
   PostgreSQL) and where its evidence appears.
2. Explain why a NetworkPolicy object does nothing unless the CNI enforces it,
   and what the start-up gap in standard mode means.
3. Explain what "whoever can create a Pod in a namespace can use every
   ServiceAccount and Secret there" implies for this design.
4. Explain what happens to tenant workloads when the Kyverno webhook is down, and
   why the policies are scoped to tenant namespaces only.
5. Explain why the sum of these controls is still soft isolation.

# 4. Acceptance scenarios

```gherkin
Scenario: The request path accepts only golden-path resources
  Given the AppProject for requests and the static check in CI
  When a request file contains a kind other than RAGSandbox or BatchTrainingJob,
       or targets a namespace that is not a tenant
  Then CI rejects it before merge
  And if it is applied anyway Argo CD refuses to sync it and nothing is created

Scenario: A tenant cannot read the other tenant in Kubernetes
  Given the tenant developer group and the workload ServiceAccounts of tenant-a
  When each tries to get or list Secrets, Pods, ServiceAccounts and RAGSandbox
       objects in tenant-b, or any cluster-scoped object
  Then every attempt is Forbidden
  And the same subject can still read its own namespace as designed

Scenario: Unsafe workloads are rejected
  Given Pod Security "restricted" and the Kyverno policies in Enforce
  When a privileged, hostNetwork, hostPath or root Pod is created in a tenant namespace
  Then Pod Security rejects it
  When a Pod has no requests or limits, an image without digest, an image from a
       registry outside the allowlist, or a tenant label that differs from its namespace
  Then Kyverno rejects it and the rejection names the policy

Scenario: Resource use is bounded
  Given the ResourceQuota and LimitRange of a tenant namespace
  When a workload inside the quota is created
  Then it is admitted
  When a Pod, an object count or a GPU request exceeds the quota
  Then it is rejected with a quota error

Scenario: Network paths are default-deny
  Given NetworkPolicy enforcement enabled on the VPC CNI
  And a control run without policies in which tenant-a reaches a listener in tenant-b
  When the default-deny and allow policies are applied
  Then tenant-a cannot reach tenant-b and the reverse
  And DNS, the shared database and the AWS API paths a sandbox needs still work
  And a tenant Pod cannot reach the node metadata endpoint

Scenario: AWS-side isolation still holds
  When the P4 identity negatives are run again after all guardrails are applied
  Then tenant-a cannot read tenant-b's secret, bucket or schema
  And a ServiceAccount outside the trusted subject cannot assume a tenant role

Scenario: Guardrails do not break the golden path
  Given every guardrail in Enforce
  When both RAGSandbox requests are deleted and created again
  Then both become Ready and the independent check passes

Scenario: Admission failure is understood
  Given the Kyverno admission controller scaled to zero
  When a compliant Pod is created in a tenant namespace
  Then the observed behaviour matches the configured failurePolicy
  And platform namespaces are not affected
  And the cluster can still be torn down

Scenario: Teardown is complete
  When requests, guardrails, controllers and the bootstrap are removed in order
  Then no webhook configuration, policy or finalizer blocks deletion
  And inventory shows nothing outside the retain allowlist
```

# 5. Work breakdown

Numbering follows the P4 rule: `P5-T<task>` is a parent, `P5-T<task>.<n>` a
sub-task, lettered parts are 15–60 minute checklist groups.

## P5-T1 — Contract: decisions, pins and source checks (3 h)

**A. SPEC, review, approval (1.5 h)**

- [ ] Recheck §2; rewrite any task whose assumption is false.
- [ ] Second agent reviews the candidate revision; findings recorded in §9.3.
- [ ] Owner decides D1–D12 and the P5 gross cap.

**B. Pins and sources (1.5 h)**

- [ ] Kyverno: choose the release (§11 row S1), confirm Kubernetes 1.35 in its
      support table, record chart version and every image digest.
- [ ] Policy API: decide between `ClusterPolicy` (`kyverno.io`) and the CEL
      policy kinds (`policies.kyverno.io`) for the pinned release; read the CRD,
      do not copy an older example.
- [ ] VPC CNI: confirm the pinned add-on version meets the NetworkPolicy minimum
      and read the configuration schema with
      `aws eks describe-addon-configuration` (read-only, owner's session).
- [ ] VERSION_MATRIX gets a "P5 pins" section. THREAT_MODEL §11 rows "VPC CNI
      version, NetworkPolicy enablement and strict mode" and "Kyverno failure
      policy and exception process" point at the decisions here.

Gate: no manifest, policy or Terraform change before part A is approved.

## P5-T2 — Namespace baseline and admission (8 h)

### P5-T2.1 — Baseline objects, AppProject and kind lab (4 h)

**A. Manifests (2 h)**

- [ ] Namespace labels: keep `rag.zero-drift.io/tenant` (decide whether the
      namespace value becomes the tenant name instead of `"true"`, since Pods and
      Jobs already carry the name); add Pod Security `audit` and `warn` =
      `restricted` next to the existing `enforce`, version pinned to the cluster minor.
- [ ] RBAC per D1: Role `tenant-viewer` and RoleBinding to group
      `zdr:<tenant>:developers`; no ClusterRoleBinding for tenants; no `secrets`
      verb; no wildcard.
- [ ] `default` ServiceAccount and every tenant workload Pod:
      `automountServiceAccountToken: false` (D2). The IRSA token is a separate
      projected volume and must still be present.
- [ ] ResourceQuota and LimitRange per D3.
- [ ] AppProject `zdr-requests` per D4; the requests Application moves into it.
- [ ] `gitops/check.sh`: request kinds allowlist, tenant namespaces, no RBAC or
      cluster-scoped object under `gitops/requests/`.

**B. L2 kind lab: break one control at a time (2 h)** — owner predicts the layer
and the message before each step; Claude records prediction vs observed.

- [ ] RBAC: `kubectl auth can-i` matrix with `--as` / `--as-group`; one real API
      call from a Pod using a ServiceAccount token.
- [ ] Pod Security: privileged, hostNetwork, hostPath, root user, missing
      seccomp. Then the reference image, which must pass.
- [ ] Quota: one Pod over the limit, one object count over the limit, one Pod
      with no requests (LimitRange default applies).
- [ ] AppProject on kind with Argo CD: a foreign kind and a foreign namespace.

Evidence: `docs/evidence/p5/P5-T2.1_L2_KIND_BASELINE_<date>.md`.

### P5-T2.2 — Kyverno: install, policies, kind lab (4 h)

**A. Install and policies (2 h)**

- [ ] Argo CD Application for the pinned chart; images by digest; server-side
      apply for the CRDs; components per D7; replica counts stated.
- [ ] Policies per D6, each with `match` limited to namespaces labelled
      `rag.zero-drift.io/tenant`, each starting in `Audit`.
- [ ] RGD app Pod template gains `rag.zero-drift.io/tenant: <tenant>` (A2), labels
      only, before the tenant-label rule leaves `Audit`.
- [ ] `kyverno test` cases (L1) for every rule: one resource that passes, one that
      fails.
- [ ] Webhook scope and `failurePolicy` per D8; verified in the rendered
      `ValidatingWebhookConfiguration`, not only in values.

**B. L2 kind lab (2 h)**

- [ ] Audit stage: deploy the lab variant of the RAG graph; policy reports must
      be clean before the switch.
- [ ] Enforce stage: each forbidden Pod of §4 scenario 3 is rejected; record the
      message.
- [ ] Outage: scale the admission controller to zero; create one compliant Pod in
      a tenant namespace and one in `kube-system`; record both results; restore.
- [ ] Uninstall order: policies, then Kyverno; confirm no webhook configuration
      remains.

Evidence: `docs/evidence/p5/P5-T2.2_L2_KIND_KYVERNO_<date>.md`. kind proves
nothing about VPC CNI enforcement or IRSA.

## P5-T3 — Network isolation (3.5 h)

**A. Terraform (1.5 h)**

- [ ] Cluster module: `configuration_values` for `vpc-cni` with
      `enableNetworkPolicy = "true"`; enforcing mode per D5.
- [ ] `terraform test` asserts the value; `plan_assert.sh` fails when it is
      missing in a P5+ window; guard test with a synthetic plan.
- [ ] Runbook note: enabling the feature restarts `aws-node`; do it at cluster
      creation, not on a cluster that carries trials.

**B. Policies (2 h)**

- [ ] Per tenant namespace: `default-deny` for ingress and egress; allow DNS to
      CoreDNS; allow 5432 to the DB subnets; allow 443 to addresses outside the
      VPC (AWS APIs and the S3 gateway endpoint), excluding the VPC range and the
      link-local metadata address; allow ingress to the app port 8080 only from
      the same tenant namespace, where the window probes run (A8, false on 22/11);
      allow egress to the app port 8080 inside the same tenant namespace, so the
      probe reaches the app Service (`/readyz`, `/query`) under default-deny egress.
- [ ] `zdr-platform`: policies for the bootstrap and cleanup Jobs if D5 says so.
- [ ] Static check: every tenant namespace has a default-deny policy; no policy
      allows `0.0.0.0/0` on all ports.
- [ ] Written limit: Kubernetes NetworkPolicy matches addresses and ports, not
      AWS service names, so "443 to anywhere outside the VPC" is the tightest
      egress rule available here. Which AWS API a Pod may call is decided by IAM.

## P5-T4 — Isolation suite, L3 window and acceptance (9 h)

### P5-T4.1 — Suite (3 h)

- [ ] `tests/isolation/run.sh`: runs every case, writes `acceptance.json` with
      case ID, threat ID, expected layer, expected result, observed result,
      UTC time and evidence reference; exit 0 only when all match.
- [ ] Cases cover T03, T04, T05, T06, T07, T08, T10, T11, T13, T14, T15 and the
      positive path of each. The P4 negatives (schema, secret, bucket, bootstrap
      identity, metadata) move into this suite unchanged.
- [ ] Probe Pods use the reference image and their manifest carries the tenant
      label `rag.zero-drift.io/tenant: <tenant>` and the requests and memory limit
      chosen for D6, so they pass the same policies (A2). The same image alone is
      not enough.
- [ ] A dry run on kind for the cases that do not need AWS; AWS and network
      cases are marked `SKIPPED_NEEDS_EKS`, never `PASS`.

### P5-T4.2 — L3 window on EKS (4 h)

Parts may span several MFA sessions; the P4 stop conditions apply.

**A. Request and approval (0.5 h)** — run ID, plan and fingerprint, priced
estimate, cap, stop time, teardown owner, fresh identity, cost and quota check,
pre-inventory, the owner's explicit approval.

**B. Build (1 h)** — bootstrap with the RAG platform and NetworkPolicy enabled;
platform through Argo CD; both sandboxes Ready **before** any guardrail.

**C. Control, then guardrails (1 h)**

- [ ] Control run: tenant-a reaches a listener in tenant-b (expected to succeed).
- [ ] Apply baseline and NetworkPolicies; Kyverno in `Audit`; reports clean;
      switch to `Enforce`.
- [ ] Delete and re-create both sandboxes; both Ready; independent check passes.

**D. Suite and failure case (1 h)**

- [ ] Full suite; observation limit 10 minutes per negative case, 900 s total.
- [ ] Kyverno outage case of §4 on EKS.
- [ ] Owner-typed micro-lab: one forbidden request per layer, typed by hand.

**E. Teardown (0.5 h)** — requests and cleanup → policies → Kyverno → P4/P3
teardown order → `terraform destroy` → immediate inventory.

Stop conditions: those of SPEC-P4 P4-T4.1, plus: a guardrail blocks a platform
controller or the teardown; a webhook configuration survives its controller.

### P5-T4.3 — Acceptance (2 h)

- [ ] Acceptance audit in `docs/evidence/p5/`: run ID, revision, versions and
      digests, scenario → evidence, limits, soft-isolation statement.
- [ ] Delayed inventory the next day; billing read by the owner.
- [ ] Independent review by the second agent, verbatim verdict and limits.
- [ ] Owner teach-back on §7 in their own words; learning status updated from
      demonstration only.

# 6. Verification tiers

| Tier | P5 use | Evidence |
|---|---|---|
| L0 | YAML and static checks, Terraform fmt/validate/test, plan assertion, CI | commands, exit status |
| L1 | `kyverno test` for every rule | test output |
| L2 | kind: RBAC, Pod Security, quota, AppProject, Kyverno audit/enforce/outage | run ID, predictions, observed messages |
| L3 | EKS: NetworkPolicy enforcement, IRSA negatives, RAG regression, suite, teardown | approval, manifest, suite output, inventory |

# 7. Teach-back questions

1. A Pod with `hostNetwork: true` is submitted to tenant-a. Which layer rejects
   it, and which layers would have rejected it next if that one were absent?
2. NetworkPolicies are applied but tenant-a still reaches tenant-b. Name two
   causes and how you would tell them apart.
3. Why does egress 443 stay open to addresses outside the VPC, and what stops a
   tenant Pod from calling an AWS API it should not?
4. Tenants have no kubeconfig. What do the RBAC tests prove, and what do they not
   prove?
5. Kyverno is down. What happens to a new tenant Pod, to a new Pod in
   `kube-system`, and to `terraform destroy`?
6. A tenant can create a Pod in its namespace. What can that Pod reach inside the
   namespace, and why does the design keep platform ServiceAccounts out of it?
7. List three ways tenant-a could still affect tenant-b after P5.

# 8. P5 completion rule

P5 is complete only when every scenario in §4 has L3 evidence on EKS, both RAG
sandboxes pass with all guardrails in `Enforce`, the suite passes from a clean
checkout at a recorded revision, teardown and delayed inventory are clean, billing
is read, an independent review has recorded findings and limits, and the owner
reaches `PRACTICED` + `EXPLAINED` for RBAC, Pod Security, NetworkPolicy, quota and
Kyverno. The acceptance text states soft isolation and its limits.

# 9. Decisions, traceability and tracking

## 9.1. Decisions for the owner (D1–D12) — proposals, not approved

| ID | Decision | Proposal | Why | Alternative |
|---|---|---|---|---|
| D1 | Tenant identity for RBAC | A read-only Role per tenant bound to a group name; tested by impersonation from the admin session; no EKS access entry and no IAM role for a tenant persona | Tenants act through Git only; an access entry adds IAM for a path nobody uses | One IAM role and access entry per tenant, tested by a real login |
| D2 | Kubernetes API token in tenant Pods | `automountServiceAccountToken: false` on the `default` ServiceAccount and on workload Pods; IRSA keeps its own projected token | Apps do not call the Kubernetes API (A9) | Leave automount on and rely on RBAC giving the ServiceAccount nothing |
| D3 | Quota values | Per tenant: a small CPU/memory budget sized for two sandboxes, a Pod count, `count/` limits for Jobs and Services, `requests.nvidia.com/gpu: 0`; LimitRange with defaults and maxima. Exact numbers from the P4 window's observed usage | T11. ADR-0009 moved P6 to CPU nodes, so `requests.nvidia.com/gpu: 0` stays for the whole project as a guard. Exact numbers come from P4 requests (app `50m`/`96Mi`, memory limit `192Mi`, no CPU limit) plus probe Pods | No GPU line |
| D4 | Request path scope | AppProject `zdr-requests`: sources this repository, destinations `tenant-a` and `tenant-b`, namespaced kinds `RAGSandbox` (and `BatchTrainingJob` from P6), no cluster-scoped kind | The only tenant write path is a pull request; this is its runtime backstop (T03) | CI check only |
| D5 | NetworkPolicy mode and scope | Standard mode; policies for tenant namespaces; ingress to the app port (8080) only from Pods in the same tenant namespace, where the window probes run (A8). Record the start-up gap as a limit | Strict mode needs a policy for every endpoint, CoreDNS included, which is a large change for a PoC | Strict mode; or also policies for platform namespaces |
| D6 | Who blocks what | Pod Security owns privilege, host namespaces, hostPath, root and capabilities. Kyverno owns: requests and memory limit required, image by `@sha256` from the registry allowlist, tenant label equals the namespace's tenant. Validate only | One cause per rejection; the tenant-label rule protects the selectors NetworkPolicy relies on | Duplicate the Pod Security rules in Kyverno, as THREAT_MODEL §7.1 words it |
| D7 | Kyverno footprint | Admission, background and reports controllers, one replica each; cleanup controller off | Reports are the audit evidence; the node is small (A6) | Admission controller only, using admission events as evidence |
| D8 | Webhook failure behaviour | Fail closed for tenant namespaces only; platform namespaces excluded by namespace selector | A silent bypass is worse than a blocked tenant Pod (T15); excluding the platform keeps teardown possible | Fail open with an alert |
| D9 | Exceptions | No PolicyException in P5. A workload that cannot comply is changed, or the rule is changed by pull request | Two tenants, two workload types | A reviewed exception process |
| D10 | P5 gross cap and windows | 4 USD for all P5 windows and retries; one window planned, a second only on new approval | P4 estimate rate: 0.35 USD/h for the 65-resource stack (A15). The P4 total for both windows is estimated at about 0.92 USD, Credits included; gross not yet read. On that estimate 4–5 h of P5 fits | — |
| D11 | Schedule | P5 from 23/11; the owner rebaselines P6–P11 before the P5 window (ADR-0009 cut order P6 → P8 → P5) | A17; ver3 §12.1 forbids cutting trials, acceptance, learning gate or teardown to keep a date | Keep 02/12 and cut a phase per ADR-0009 |
| D12 | Branch protection (T01) | Owner enables a ruleset on `main` requiring the `static-gates` check and a pull request; evidence is a redacted export | A14; the missing layer in teach-back case B. A GitHub setting, so the owner changes it | Record T01 as an accepted limit |

D6 changes the wording of THREAT_MODEL §7.1, which lists the privilege rules
under Kyverno. If the owner accepts D6, THREAT_MODEL is updated in P5-T1; if not,
the Kyverno policy set grows and the learning objective 1 gets harder to test.

## 9.2. Traceability

| Source requirement | Covered by |
|---|---|
| ver3 §9.5 tenant A cannot read tenant B's secret, ServiceAccount or object | scenario 2; P5-T2.1; suite T04 |
| ver3 §9.5 IAM role of tenant A cannot reach tenant B's S3 | scenario 6; suite T07, T08 (from P4) |
| ver3 §9.5 default-deny ingress/egress on the VPC CNI | scenario 5; P5-T3; suite T10 |
| ver3 §9.5 Kyverno blocks missing requests/limits, image/tag, metadata | scenario 3; P5-T2.2; suite T05, T14 |
| ver3 §9.5 Kyverno is not a control for AWS changes | negative boundary 6; acceptance text |
| ver3 §8.2 isolation/policy pass rate at each major commit | P5-T4.1; reused in P8 and P9 |
| THREAT_MODEL §12 "before tenant/golden-path acceptance" | P5-T4.2, P5-T4.3 |
| DRF-18 outline | whole SPEC; split into P5-T issues at the gate |

## 9.3. Independent review

The 22/11 recheck was done by Claude (Opus 5.5); it is not a second-agent review.

**Codex review 1 (22/11), head `c248e20`: REQUEST CHANGES.** Handling:

| Finding | Level | Handling |
|---|---|---|
| P5-T3 default-deny egress blocks the probe's call to the app on 8080 | MEDIUM | Fixed: P5-T3 B allows egress to 8080 inside the same tenant namespace |
| App Pod and window probe Pods carry no tenant label; probe Pods declare no resources | MEDIUM | Fixed: A2 corrected; P5-T2.2 A adds the label to the RGD app template; P5-T4.1 requires label and resources in the probe manifest |
| §10 headroom contradicts A6 and names the P4 window | LOW | Fixed: §10 follows A6, measures in the P5 window, uses the 8 vCPU quota seen 22/11 |
| 0.35 USD/h, 0.37 and 0.92 USD called measured or upper bounds | LOW | Fixed: A15 and D10 call them estimates; gross unverified |
| A1 lists `probe sandbox` as a negative test | LOW | Fixed: allowed paths vs denied paths |

Not yet re-reviewed. No owner approval.

## 9.4. Linear tracking (proposal)

Created after the owner approves the SPEC, parents just before their sub-tasks
(LINEAR_DELIVERY). DRF-18 is cancelled as superseded, like DRF-16/17 in P4.

| Code | Title | Est. |
|---|---|---|
| P5-T1 | Hợp đồng P5: quyết định D1–D12, pin Kyverno và VPC CNI | 3 h |
| P5-T2 | Baseline namespace và admission | parent |
| P5-T2.1 | Baseline, RBAC, quota, AppProject và lab kind | 4 h |
| P5-T2.2 | Kyverno: cài đặt, policy và lab kind | 4 h |
| P5-T3 | Network isolation: VPC CNI và NetworkPolicy | 3.5 h |
| P5-T4 | Isolation suite, window L3 và nghiệm thu | parent |
| P5-T4.1 | Isolation suite | 3 h |
| P5-T4.2 | Window L3 trên EKS | 4 h |
| P5-T4.3 | Nghiệm thu P5 | 2 h |

# 10. Open risks

- **Pod and memory headroom.** An `m6i.large` holds at most 29 Pods with the
  default VPC CNI settings (ENI limit; AWS `eni-max-pods` list, recheck) and
  8 GiB. Argo CD, Crossplane with two providers, kro, CoreDNS and the RAG
  workloads run on one node, but P4 recorded no Pod count or allocatable memory
  (A6). Kyverno adds three Pods, the suite adds probe Pods. P5 may need the
  second system node (4 of the 8 Standard On-Demand vCPUs in the quota seen
  22/11; recheck before the window). Measure first thing in the P5 window, before
  sizing D3 and D7.
- **Standard mode start-up gap.** A new Pod is default-allow until its policies
  are programmed (AWS documentation, §11 row S3). Short-lived probe Pods may
  finish inside that gap; the suite must wait before it tests a deny.
- **Kubelet probes under default-deny.** Whether the node's own address is
  allowed by the VPC CNI agent is `UNVERIFIED`; if readiness probes fail, an
  explicit rule for the node range is needed.
- **Fail-closed webhook and teardown.** If Kyverno is removed while its webhook
  configuration remains, tenant namespaces cannot be cleaned. The runbook removes
  requests first and checks for leftover webhook configurations.
- **Kyverno CRD size and Argo CD.** Client-side apply can fail on large CRDs;
  use server-side apply. The pinned release may also deprecate `ClusterPolicy`
  in favour of CEL policy kinds; P5-T1 B decides.
- **`restricted` and the P4 pod template.** Resolved 22/11 (A3). The RGD is
  hardened and ran under `restricted` on EKS. The RGD may still change for the
  Kyverno tenant label (D6), labels only, with no image rebuild.
- **Impersonation is not a login.** D1 proves the authorizer's answer, not an
  end-to-end tenant session.
- **Trust subject pattern.** `rag-*` (A10) lets any ServiceAccount with that
  prefix in the tenant namespace assume the tenant role. Tenants cannot create
  ServiceAccounts through the request path, and the suite tests a non-matching
  name; a tighter subject would be an ADR-0008 change.
- **Schedule.** P5 starts after its ver3 window; the rebaseline is the owner's (D11, A17).

# 11. Sources and dated facts (recheck at P5-T1)

| # | Fact | Source | Checked | Status |
|---|---|---|---|---|
| S1 | Kyverno latest release `v1.20.0`, chart `3.10.0`; default install has four controllers | [Kyverno releases](https://github.com/kyverno/kyverno/releases), [installation](https://kyverno.io/docs/installation/) | 2026-11-16 | `SOURCE_VERIFIED`; Kubernetes 1.35 support for 1.20 **not** confirmed — recheck |
| S2 | Kyverno `v1.19.1` supports Kubernetes 1.33–1.35 | VERSION_MATRIX §2 | 2026-09-25 | `DOC_VERIFIED`; recheck, a newer patch may exist |
| S3 | VPC CNI NetworkPolicy: add-on value `enableNetworkPolicy: "true"`; minimum version 1.21 for standard and admin policies; `NETWORK_POLICY_ENFORCING_MODE=strict` gives default-deny at Pod start, standard mode starts default-allow | [EKS: restrict Pod traffic with network policies](https://docs.aws.amazon.com/eks/latest/userguide/cni-network-policy-configure.html) | 2026-11-16 | `DOC_VERIFIED`; runtime `UNVERIFIED` |
| S4 | Cluster add-on pin `vpc-cni v1.22.4-eksbuild.10`, no configuration values | `infra/terraform/variables.tf`, `modules/cluster/main.tf` | 2026-11-22 (Git) | repository fact, unchanged since 16/11; recheck the default for 1.35 before the window |
| S5 | Standard On-Demand vCPU quota 5; `m6i.large` 0.096 USD/h; EKS 0.10 USD/h; public IPv4 0.005 USD/h; `db.t4g.micro` 0.016 USD/h | COST_PLAN §5.2, §7.3 | 2026-09-28 | `PRICE_API_VERIFIED` / `ACCOUNT_VERIFIED`; recheck before the window |
| S6 | Pod Security Standards "restricted" profile | [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) | THREAT_MODEL §13, 2026-09-28 | recheck against Kubernetes 1.35 |
| S7 | `m6i.large` 29 Pods per node | author's recollection of the AWS `eni-max-pods` list | not looked up | `UNVERIFIED`; read the list or `kubectl describe node` |
