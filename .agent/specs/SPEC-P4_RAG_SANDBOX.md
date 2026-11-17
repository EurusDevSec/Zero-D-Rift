---
id: SPEC-P4
title: RAGSandbox — shared RDS PostgreSQL/pgvector, scoped identity, usable status
status: OWNER_APPROVED_20261114
phase: P4
start: 2026-11-14
deadline: 2026-11-18 (PROPOSED; ver3 §12 window 06–08/11 already missed)
schedule_baseline: OWNER_REQUESTED_RECOVERY_2026-10-29
estimated_effort: 28-33 hours (ROADMAP allocates 24 h to P4)
mode: Coach for IRSA/secrets/PostgreSQL, then Pair
canonical_scope: docs/de_cuong_tot_nghiep_ver3.md
linear: DRF-40 (P4-T1), DRF-44 (P4-T2), DRF-49 (P4-T3), DRF-55 (P4-T4); 10 issues in §9.3
authority: NO_INSTALL_NO_AWS_APPLY_UNTIL_TASK_GATES
---

# 1. Goal and boundaries

P3 was completed on 14/11/2026 (audit
`docs/evidence/p3/DRF38_P3_ACCEPTANCE_AUDIT_20261106.md`). This SPEC details only
P4; P5+ stay outlines in ver3 §12.

Schedule note: ver3 §12 gives P4 the window 06–08/11 and names 08/11 a gate. P4
starts on 14/11, so the gate is missed. Per ver3 §12.1 the owner rebaselines the
remaining plan from live state. This SPEC proposes 15–18/11 and does not reduce
scope, trial count, acceptance, learning gate or teardown. Until RAG runs end to
end, Batch Training stays a skeleton (ver3 §12.1).

## Goal

Deliver the first golden path on the real EKS bootstrap. One `RAGSandbox` request,
merged in Git and synced by Argo CD, gives a tenant a running RAG-shaped
application with:

- its own schema and login role on a **shared, pre-provisioned** RDS
  PostgreSQL/pgvector instance (ADR-0004);
- its own S3 bucket, reachable only through the tenant's IRSA role;
- a status that says Ready only when the app has really queried the database and
  reached its bucket, plus the access information a developer needs.

This is the ver3 §12 exit criterion for P4: "App, DB, S3 access và usable status
đạt end-to-end trên EKS". Runs in P4 are smoke runs; none is an official trial
(H1/H3 are measured in P9).

## MUST deliverables

- `SPEC-P4` approved by the owner, with decisions D1–D12 (§9.1) resolved, and
  ADR-0008 recording shared-RDS ownership, the secret-integration method and the
  workload IAM boundary (closes the `UNVERIFIED` rows in SYSTEM_DESIGN §8,
  THREAT_MODEL §11 and ADR-0004 item 8).
- Terraform: a shared-RDS module and a RAG identity module, both off by default
  and enabled only in an approved window, with tests and plan assertions.
- Reference workload under `workloads/rag-sandbox/`: one image with four entry
  points (`db-init`, `bootstrap`, `cleanup`, `serve`), pinned by digest.
- GitOps: `RAGSandbox` ResourceGraphDefinition, tenant and platform namespaces,
  two valid requests (one per tenant), disabled negative requests, static checks
  and a CI workflow that runs them on pull requests (ver3 §9.1 step 2).
- Independent verification scripts: readiness + DB query from outside the app
  Pod, and the negative suite of §4.
- Runbook `docs/runbooks/P4_RAG_SANDBOX.md`: prepare, verify, delete, retry,
  cleanup, teardown order, stop conditions, undo, and a "Tự thử" section.
- Evidence under `docs/evidence/p4/`: L2 kind labs, L3 window, positive and
  negative checks, inventory and cost. Raw logs stay outside Git.

## Negative boundaries

1. Do not create an RDS instance per request. The request path never calls an RDS
   API (ADR-0004, ver3 §6.4).
2. Do not install a new controller: no External Secrets Operator, no Secrets Store
   CSI driver, no `provider-aws-rds`, `provider-aws-iam` or any provider package
   beyond the P3 allowlist. KEDA, Karpenter, Kyverno, OpenCost and Prometheus stay
   out of P4.
3. Do not give the RDS master credential or the bootstrap credential to a tenant
   workload, a tenant namespace or a Kubernetes Secret. The `db-init` and
   `bootstrap` Jobs and their ServiceAccounts run only in `zdr-platform`, never in
   a tenant namespace, including as a fallback.
4. Do not put a database password, connection URI, AWS account ID, role ARN, RDS
   endpoint, kubeconfig or token into Git, Linear or evidence. Git holds secret
   **names** only.
5. Do not let Terraform and Crossplane manage the same resource (ADR-0003). RDS,
   its security group and every IAM role are Terraform's; sandbox buckets are
   Crossplane's.
6. Do not make the RDS instance public, and do not test it from the workstation.
   Every database check runs from a Pod inside the cluster.
7. Do not report Argo CD `Synced/Healthy`, a `Running` Pod or a successful secret
   read as usable. Usable means the checks in §4 pass.
8. Do not call a schema, a namespace or a shared instance hard isolation. P4
   tests the data-plane boundary (PostgreSQL grants, IAM); RBAC, quota,
   NetworkPolicy, Pod Security and Kyverno are P5.
9. Do not call Bedrock or any model endpoint in P4 (D8).
10. Do not run an AWS window without a separate execution approval, a fresh cost
    and identity check, a stop time and a teardown owner (same rule as P2/P3).
11. Do not run the P8 recovery experiment against this instance, and do not keep
    the instance between windows.
12. Do not count a P4 run as an official H1/H3 trial.

# 2. Constraints carried forward

- EKS 1.35, AL2023, `us-east-1`, public worker subnets, no NAT, S3 gateway
  endpoint with a bounded policy, private DB subnets with no Internet route and a
  DB subnet group already created by the P2 network module (ADR-0006).
- Node metadata: IMDSv2 required, hop limit 1 (P2 cluster module). P4 tests that
  a tenant Pod cannot obtain node credentials.
- P3 platform as pinned in VERSION_MATRIX §7: Argo CD v3.5.7, Crossplane 2.4.3,
  provider-family-aws and provider-aws-s3 v2.8.1, kro v0.9.4. P3 teardown order and
  the `recurse` fix (PR #28, verified on kind only) apply unchanged.
- P3 lessons that bind P4:
  - an S3 resource `arn:aws:s3:::<prefix>*` also matches object ARNs, so every
    statement needs an exact action allowlist;
  - kro `readyWhen` may only reference its own resource, and dependents are
    created only after their dependency is ready;
  - registries that redirect layer downloads to S3 fail through the gateway
    endpoint unless their bucket is in the endpoint policy.
- Identity: `zdr-bootstrap` MFA AssumeRole, 1-hour sessions. The Terraform role is
  still AdministratorAccess; R1 least privilege is deferred to before DRF-27 or at
  DRF-29 and must then include the P4 roles and RDS actions.
- Carried from P3, not P4 gates: endpoint check 7 only type-checks
  `aws:ResourceAccount`; teach-back Q3–Q5 are re-asked orally at P11.
- Envelope: 100 USD gross, of which ver3 §11 reserves 15 USD for RDS, storage and
  snapshots. Billed so far: 0.29 USD in `us-east-1` (Billing console, 14/11).
- Learning state: Terraform and Argo CD/kro/Crossplane `PRACTICED` + `EXPLAINED`.
  IRSA for workloads, Secrets Manager and PostgreSQL privileges are new.

# 3. Learning objectives

By the end of P4 the owner should be able to:

1. Trace a tenant Pod to AWS: Pod → ServiceAccount → projected token → STS → IAM
   role → S3 / Secrets Manager, and say what each layer refuses.
2. Explain why IAM permission and PostgreSQL privilege are two separate layers,
   and show one request that passes the first and fails the second.
3. Explain the three credential tiers (master, bootstrap, sandbox) and what a
   leaked credential of each tier could reach.
4. Explain why the RDS instance is prepared before any request and what that
   does to the H1 measurement.
5. Read `RAGSandbox` status and locate a failure in Git/Argo, kro graph,
   bootstrap Job, IAM, secret, network or PostgreSQL.
6. State where every secret lives and prove that Git holds none.

# 4. Acceptance scenarios

```gherkin
Scenario: The shared service is prepared once and is private
  Given the approved Terraform plan for the window
  When the shared RDS instance and the RAG roles are created
  Then the instance is not publicly accessible and accepts 5432 only from the node security group
  And pgvector is installed once by the platform init Job
  And no RAGSandbox request creates, modifies or deletes an RDS instance

Scenario: One request gives a usable sandbox
  Given a merged RAGSandbox request in a tenant namespace
  When Argo CD syncs it
  Then kro creates the bucket, the bootstrap Job, the ServiceAccount, the Deployment and the Service
  And the bootstrap Job creates one schema and one login role for that sandbox
  And the instance reports Ready only after the app has queried its schema and reached its bucket
  And the status shows the endpoint, schema, bucket and secret name, and no secret value
  And an independent check outside the app Pod passes readiness and a vector query

Scenario: Readiness is not faked
  Given a request that is invalid, or whose namespace has no tenant role, or whose bootstrap Job fails
  When Argo CD syncs it or CI checks it
  Then the invalid request is rejected before merge
  And the others never report Ready while Argo CD can show Synced
  And the failing layer is visible in the instance, Job, Pod or managed-resource status

Scenario: Credentials are bounded
  Given the master, bootstrap and sandbox credentials
  Then the app Pod can read only its tenant's secrets and uses only its sandbox role
  And the sandbox role cannot create roles, read another schema or act as bootstrap
  And the bootstrap role is not a superuser and cannot read the master secret
  And a tenant Pod cannot obtain node credentials from the metadata service

Scenario: Tenants are separated on the data plane
  Given one sandbox in tenant-a and one in tenant-b
  Then tenant-a cannot read tenant-b's schema, secret or bucket, and the reverse
  And each allowed path still works

Scenario: Delete, retry and cleanup are predictable
  Given a request whose bootstrap Job has reached Failed
  When the cause is fixed in Git and the request's bootstrapAttempt is raised
  Then a new bootstrap Job runs, succeeds without rotating an existing password, and the request becomes Ready
  And nothing in the cluster was edited or deleted by hand
  When a request is removed from Git and the cleanup is run
  Then its Kubernetes objects, bucket, schema, role and secret are gone
  And the other sandbox keeps working

Scenario: Teardown is complete
  When sandboxes, then platform controllers, then the RDS instance and the EKS bootstrap are removed in order
  Then inventory shows no project resource outside the retain allowlist
  And no RDS instance, snapshot, P4 secret, P4 bucket or P4 role remains
```

# 5. Work breakdown

Numbering rule: `P4-T<task>` is a parent task; `P4-T<task>.<n>` is one of its
sub-tasks. The same code is the prefix of the Linear issue title, so a sub-task
is recognisable without looking at its `DRF-` number (§9.3).

P4 has 10 issues: four parents and six sub-tasks (P4-T1 has none). A sub-task is
one PR or one lab session of at most about one working day. Inside it, lettered
parts (A, B, …) group checklist items of 15–60 minutes. The owner asked for fewer
issues on 14/11; regrouping changed no work, acceptance or gate.

## P4-T1 — Contract: decisions, pins and ownership (4 h)

Outcome: nothing is built on an unapproved or unpriced design. One issue, no
sub-tasks.

**A. SPEC-P4, independent review, owner approval (1.5 h)**

- [x] SPEC-P4 drafted from ver3 §5.2, §6.3–6.4, §9.1, §10, ADR-0003/0004/0006,
      SYSTEM_DESIGN §5.1 and §6, THREAT_MODEL §6.5, EXPERIMENT_PLAN §5.2 and §6.
- [x] Codex reviews the candidate revision; findings, fixes and re-check
      recorded in §9.4.
- [x] Owner decides D1–D12 and the P4 gross cap (§9.1).

**B. Pins, prices and source checks (1.5 h)** — after A.

- [x] RDS: latest PostgreSQL 17 minor offered in `us-east-1`, its pgvector
      version, `db.t4g.micro` orderable for it, `rds.force_ssl` default
      (read-only AWS CLI; needs the owner's session). Done 17/11: 17.11
      (default is 17.9, so pin explicitly), pgvector 0.8.2 (doc), gp3
      orderable, `rds.force_ssl=1`.
- [x] Prices rechecked: RDS instance-hour, gp3 GB-month, Secrets Manager per
      secret and per call. COST_PLAN §5 updated if any differs. Done 17/11: no
      price changed; Secrets Manager row added to §5.2.
- [x] Image digests: Python base, pgvector image for kind, RDS CA bundle checksum
      (`docs/evidence/p4/P4-T1_PINS_PRICES_20261117.md`, VERSION_MATRIX §8).
- [x] kro v0.9.4 features the graph needs: `externalRef` to a ConfigMap in
      another namespace, a child in a namespace other than the instance's,
      `readyWhen` on a Job, and removal of a child whose name changes. Moved
      forward from a CRD read to a kind spike on 14/11: all four PASS on kind
      (`docs/evidence/p4/P4-T1_KRO_SPIKE_20261114.md`); new finding: Pods of
      Jobs kro deletes are left orphaned (§10). P4-T3.2 still re-proves them in
      the real graph.
- [x] VERSION_MATRIX gets a "P4 pins" section (§8).

**C. ADR-0008 and ownership records (1 h)** — after A.

- [x] ADR-0008: shared RDS owned by Terraform; secrets read by direct SDK through
      IRSA; workload IAM roles pre-created per tenant by Terraform; Crossplane
      receives no RDS or IAM permission; bootstrap credential confined to
      `zdr-platform`. Alternatives and revisit conditions listed. (`ACCEPTED`
      14/11/2026 after Codex APPROVE.)
- [x] SYSTEM_DESIGN §8/§9, THREAT_MODEL §6.5/§11, VERSION_MATRIX §3 and
      ADR-0004 item 8 updated to point at ADR-0008. No scope text in ver3 changes.

Gate: no code, image or Terraform change for P4 before part A is approved.

## P4-T2 — Shared service: RDS PostgreSQL/pgvector and credential boundary (8.5 h)

Outcome: a private shared database and three credential tiers, proven locally
and ready to plan.

### P4-T2.1 — Database entry points and kind database lab (4 h)

**A. SQL and platform entry points (2 h)**

- [ ] `db-init` (master credential, once per window): `CREATE EXTENSION vector`,
      database `rag`, role `rag_bootstrap` with `CREATEROLE` and `CREATE` on the
      database, no superuser; revoke `PUBLIC` defaults; write the bootstrap secret.
- [ ] `bootstrap` (bootstrap credential, per request): validate the sandbox name,
      create schema and login role, grant only that schema, write the sandbox
      secret. Idempotent: when the sandbox secret already exists, it reuses that
      password instead of rotating it, so a retried Job does not break a running
      app. Identifiers are quoted, never string-built.
- [ ] `cleanup` (bootstrap credential): drop schema and role, delete the secret.
- [ ] Unit tests for name validation, statement generation and the re-run path.

**B. L2 kind lab: database boundary, no AWS (2 h)** — owner predicts before each
step; Claude records prediction vs observed.

- [ ] In-cluster PostgreSQL with pgvector (pinned image) stands in for RDS.
- [ ] Run `db-init`, then `bootstrap` for two sandboxes; run `bootstrap` a second
      time for one of them and confirm nothing changes and the password is kept.
- [ ] Positive: each role creates a table with a `vector` column in its schema and
      runs a similarity query.
- [ ] Negative: role A on schema B, `CREATE ROLE` by a sandbox role, superuser
      attempt by bootstrap. (Secret access is an IAM test and belongs to
      P4-T4.1 part D.)
- [ ] Run `cleanup`; verify nothing of that sandbox remains.

Evidence: `docs/evidence/p4/P4-T2.1_L2_KIND_DB_<date>.md`. Limit to state: RDS
master is `rds_superuser`, not a PostgreSQL superuser; the lab cannot prove
RDS-specific behaviour.

### P4-T2.2 — Terraform modules `shared-rds` and `rag-identity` (4.5 h)

**A. Module `shared-rds` (2 h)**

- [ ] Instance per D2 in the existing DB subnet group; security group with one
      ingress rule, 5432 from the node security group; master password managed by
      RDS in Secrets Manager; project tags with `RunId` and `ExpiresAt`.
- [ ] Root flag `enable_rag_platform` (default false); outputs marked sensitive
      where they carry an endpoint or ARN.
- [ ] Mocked `terraform test`: private, encrypted, single ingress rule, no final
      snapshot, no deletion protection, class and storage as approved.

**B. Module `rag-identity` and guards (2.5 h)**

- [ ] Roles (all IRSA, exact subject and audience unless stated):
      `zero-drift-rag-db-admin` (read the master secret, write the bootstrap
      secret), `zero-drift-rag-bootstrap` (read the bootstrap secret, manage
      secrets under `zero-drift/rag/tenant-*/`), `zero-drift-rag-tenant-a` and
      `-tenant-b` (read own secrets, own buckets and their objects; subject
      pattern per D6), and the Crossplane S3 role for `zero-drift-rag-*` buckets.
      The two platform roles trust only ServiceAccounts in `zdr-platform`.
- [ ] `plan_assert.sh` checks behind `P4_WINDOW=1`, with synthetic-plan guard
      tests for each: no wildcard resource, exact action allowlists, no IAM
      action, tenant-a cannot name a tenant-b resource, platform roles not
      assumable from a tenant namespace, RDS not public.
- [ ] IAM simulation script: allowed and denied matrix for the five roles.
- [ ] `inventory.sh` learns RDS instances and snapshots, P4 secrets, P4 buckets
      and P4 roles. `check.sh` stays PASS.

## P4-T3 — RAGSandbox: one request gives a usable environment (10 h)

Outcome: the request path, including failure and retry, works on kind and is
ready for EKS.

### P4-T3.1 — Reference application and image (3.5 h)

**A. Application (2.5 h)**

- [ ] `serve`: `/healthz` (process only), `/readyz` (schema query with a `vector`
      column and a bucket check), `/query` (similarity search over seeded rows).
- [ ] Loads its connection from the secret named in `DB_SECRET_ID`; when the
      secret is missing, or on an authentication or connection error, it re-reads
      the secret and reconnects (needed again in P8).
- [ ] TLS to the database with the RDS CA bundle; dependencies pinned with hashes.
- [ ] Unit tests with a local PostgreSQL container or a fake.

**B. Image build and publication (1 h)**

- [ ] Dockerfile with a digest-pinned base, non-root user, read-only root
      filesystem compatible.
- [ ] Publication per D8; the resulting digest is recorded in VERSION_MATRIX and
      used everywhere by `@sha256`.

### P4-T3.2 — RGD, requests, CI and kind graph lab (6.5 h)

**A. RGD `RAGSandbox` and platform objects (2.5 h)**

- [ ] `gitops/platform/tenants/`: namespaces `tenant-a`, `tenant-b`,
      `zdr-platform`; ServiceAccounts `rag-db-admin` and `rag-bootstrap` in
      `zdr-platform` only. Role ARN annotations and the `platform-config`
      ConfigMap are applied in the window from Terraform outputs and ignored by
      Argo CD, as in P3.
- [ ] `gitops/platform/rgd/rag-sandbox.yaml`: nodes `platformConfig`
      (externalRef), `bucket`, `bootstrap` (Job in `zdr-platform`),
      `serviceAccount`, `app` (Deployment), `service`. Readiness: bucket Ready,
      Job succeeded, Deployment available with `/readyz` as its readiness probe.
- [ ] Bootstrap retry (D9): the request has `spec.bootstrapAttempt` (integer,
      default 0) and the Job name ends in it, so raising it in Git creates a new
      Job instead of patching an immutable one. The Job sets `backoffLimit` and
      `activeDeadlineSeconds` explicitly, so a failure ends in a terminal
      `Failed`. No `ttlSecondsAfterFinished`: kro would re-create a deleted Job
      and re-run bootstrap. If kro does not remove the Job with the old name,
      `cleanup` and the runbook delete lower attempts. The Job's Pod template
      carries the instance's labels, because kro deletes Jobs without their
      Pods (spike 14/11): `cleanup` and the runbook delete those Pods by label.
- [ ] Status: endpoint, schema, bucket, secret name, bootstrap attempt and Job
      state, available replicas.
- [ ] kro RBAC extended for the new kinds; nothing wider than needed.

**B. Requests, static checks and CI (1.5 h)**

- [ ] Two valid requests (`tenant-a`, `tenant-b`) and disabled negatives: a
      namespace without a tenant role, and a name the schema rejects.
- [ ] `gitops/check.sh`: request namespace is a known tenant, name pattern,
      `bootstrapAttempt` a non-negative integer, no secret value, image digests,
      provider allowlist unchanged, no platform ServiceAccount or Job in a tenant
      namespace.
- [ ] GitHub Actions workflow running `gitops/check.sh` and the Terraform static
      gate on pull requests; no cloud credential in CI.

**C. L2 kind lab: graph, readiness, failure and retry (2.5 h)** — owner predicts
before each step.

- [ ] Lab variant of the RGD (`labs/p4-kind/`): in-cluster PostgreSQL, secret from
      a lab-only source, no bucket node. Each kro feature listed in P4-T1 part B
      is proven, or its row in §10 is followed.
- [ ] One request: observe creation order and the moment the instance turns Ready.
- [ ] Failures, one at a time: the bootstrap Job reaches a terminal `Failed`
      (for example a wrong bootstrap secret); the app has a wrong credential; the
      database is unreachable. In each the instance must not be Ready.
- [ ] Retry: fix the cause and raise `bootstrapAttempt` in the request file only,
      re-applied as a sync would; no manual edit or delete in the cluster. A new
      Job succeeds, the instance becomes Ready, and what happened to the old Job
      is recorded.
- [ ] Delete the request and observe what kro removes.

Evidence: `docs/evidence/p4/P4-T3.2_L2_KIND_GRAPH_<date>.md`. kind proves nothing
about IRSA, Secrets Manager, RDS or S3.

## P4-T4 — L3 window on EKS and P4 acceptance (9.5 h)

Prerequisite: the kind labs of P4-T2.1 and P4-T3.2 have PASSED, and P4-T2.2,
P4-T3.1 and P4-T3.2 are merged.

### P4-T4.1 — L3 window: approval, build, end to end, negatives, teardown (6.5 h)

Parts A–E may span several MFA sessions; the stop conditions apply throughout.

**A. Window request and approval (1 h)**

- [ ] Request per the P2_L3_WINDOW template: run ID, plan and fingerprint,
      `plan_assert` with `P4_WINDOW=1`, priced estimate, cap, stop time, teardown
      owner, fresh identity/cost/quota check, pre-inventory.
- [ ] Owner's explicit execution approval recorded.

**B. Foundation and shared service (1.5 h)**

- [ ] Bootstrap as in P3, with `enable_rag_platform = true`; smoke as in P2.
- [ ] Platform via Argo CD; window-only annotations and `platform-config` applied.
- [ ] `db-init` Job; verify from a Pod: TLS on, pgvector present, bootstrap role
      attributes, instance not public (AWS describe) and unreachable from outside.
- [ ] Image pull of the reference image succeeds through the endpoint policy.

**C. End to end: two sandboxes (1.5 h)**

- [ ] Sync both requests; record the timestamps the H1 contract will use (Argo
      first observes the revision; later of readiness and independent query).
      These are smoke values, labelled as such.
- [ ] Independent check passes for both; status shows the access information.
- [ ] Owner-typed micro-lab: `aws sts get-caller-identity` and bucket access from
      inside a tenant Pod, to see the role and the allowed prefix.

**D. Negative suite (1.5 h)**

- [ ] Request in a namespace without a tenant role: never Ready, Argo Synced.
- [ ] Cross-tenant: tenant-a against tenant-b's schema, secret and bucket; and
      the reverse. Each denied at the expected layer.
- [ ] Sandbox role: no `CREATE ROLE`, no other schema, no bootstrap secret.
- [ ] Bootstrap identity: no master secret.
- [ ] Tenant Pod cannot reach node credentials through the metadata service.
- [ ] Observation limit 10 minutes per negative case.

**E. Delete, retry, cleanup, teardown (1 h)**

- [ ] Retry as in P4-T3.2 part C: a request whose bootstrap Job reached `Failed`
      is fixed in Git with `bootstrapAttempt` raised; it becomes Ready with no
      manual repair.
- [ ] Remove one request; run `cleanup`; verify objects, bucket, schema, role,
      secret and old Jobs are gone and the other sandbox still passes.
- [ ] Teardown order: requests and cleanup → P3 controller teardown →
      `terraform destroy` (RDS and roles go with it) → immediate inventory.

Stop conditions: any controller unhealthy after one fix attempt; RDS not
available 20 minutes after create; a resource outside the approved names; an
object stuck deleting for 15 minutes; under 40 minutes of session left before a
destroy; stop time reached. The cap counts every retry and cleanup.

### P4-T4.2 — Acceptance: evidence, review, teach-back (3 h)

**A. Evidence, delayed inventory and billing (1 h)**

- [ ] Acceptance audit `docs/evidence/p4/`: run ID, revision, versions and
      digests, scenario → evidence, limits.
- [ ] Delayed inventory the next day; billing read by the owner.

**B. Independent review (0.5 h plus waiting)**

- [ ] Codex reviews the candidate revision; verdict, findings, commands and
      limits recorded verbatim. Fixes get a re-check.

**C. Owner teach-back (1.5 h)** — may start once P4-T4.1 part E is done.

- [ ] Owner answers §7 in their own words; answers recorded verbatim.
- [ ] Learning status updated from demonstration only.

# 6. Verification tiers

| Tier | P4 use | Evidence |
|---|---|---|
| L0 | Unit tests, YAML/static checks, Terraform fmt/validate/test, plan assertions, CI | commands, exit status |
| L1 | Not used | — |
| L2 | kind: SQL privilege boundary, graph order, readiness, failure injection, retry | run ID, predictions, observed status |
| L3 | EKS: RDS, IRSA, Secrets Manager, S3, IMDS, end-to-end, negatives, teardown | approval, manifest, AWS/K8s output, inventory |

# 7. Teach-back questions

1. A tenant Pod calls S3. Walk from the Pod to the bucket: who checks what?
2. The app can read its secret but the query is refused. Which layer refused it,
   and why is that not an IAM problem?
3. What can a leaked sandbox credential reach? A leaked bootstrap credential? The master?
4. Why is the RDS instance created before any request, and what would change in
   H1 if each request created its own?
5. Argo CD shows Synced and the Pod is Running, but the instance is not Ready.
   Where do you look, in order?
6. Where is each secret stored, who may read it, and what does Git contain?
7. A request is deleted from Git. What disappears by itself, what needs the
   cleanup, and why?

# 8. P4 completion rule

P4 is complete only when every scenario in §4 has L3 evidence on EKS, teardown
and delayed inventory are clean, billing is read, an independent review has
recorded findings and limits, and the owner reaches `PRACTICED` + `EXPLAINED` for
workload IRSA, the secret flow and the PostgreSQL credential tiers. If the
end-to-end path is not stable, stop and fix it; do not start P6 beyond a skeleton
(ver3 §12.1).

# 9. Decisions, traceability and tracking

## 9.1. Decisions for the owner (D1–D12)

Owner approval, 14/11/2026, after Codex review 3 APPROVE at `358da73`, verbatim:
"Duyệt cả 12". All twelve proposals below are approved as written, including
D8 (public image on GHCR) and D10 (5 USD gross cap for all P4 windows and
retries). Approving the SPEC does not approve any AWS window; each window still
needs its own execution approval (negative boundary 10).

| ID | Decision | Proposal | Why | Alternative |
|---|---|---|---|---|
| D1 | Who owns the shared RDS | Terraform module, flag `enable_rag_platform`, created and destroyed with each window | Prepared before any request; one owner (ADR-0003); no new provider CRDs on a small node | `provider-aws-rds`: more CRDs, RDS/IAM rights for Crossplane |
| D2 | Instance shape | PostgreSQL 17 (minor pinned in P4-T1 part B), `db.t4g.micro`, Single-AZ, 20 GB gp3, encrypted, private, no automated backup, no final snapshot, no deletion protection | Priced in COST_PLAN (0.016 USD/h); must be destroyable in the window | Larger class if `t4g.micro` cannot be ordered |
| D3 | Tenancy inside the instance | One database `rag`; one schema and one login role per sandbox; pgvector installed once | Fast, no extension step per request | Database per sandbox from a template: stronger, slower, harder cleanup |
| D4 | Credential tiers | Master (RDS-managed secret, used once by `db-init`) → `rag_bootstrap` (`CREATEROLE`, no superuser) → sandbox role; master and bootstrap confined to `zdr-platform` | ADR-0004 items 4–5 | Bootstrap with master: rejected |
| D5 | Secret integration | Direct AWS SDK call through IRSA; no Kubernetes Secret holds a database password | THREAT_MODEL §6.5 forbids adding a controller silently | ESO or CSI driver: new technology |
| D6 | Workload IAM | Terraform pre-creates one role per tenant (two tenants); trust subject `system:serviceaccount:<tenant>:rag-*`. Crossplane gets no IAM right | PoC has at most two tenants; avoids IAM management in the request path | `provider-aws-iam` with a permissions boundary |
| D7 | S3 scope | One bucket per sandbox through Crossplane, `zero-drift-rag-<tenant>-<name>`; `forceDestroy` so deletion works, which adds object-delete rights on those buckets to the provider role | Keeps the proven Crossplane leg in the request path | Shared bucket with a prefix per sandbox; or empty the bucket in cleanup and keep the provider bucket-only |
| D8 | Workload and image | Small Python reference app; no Bedrock or model call; image built by GitHub Actions and published **public** on GHCR, pinned by digest | No registry cost, survives teardown, same pin discipline | ECR repository created by Terraform (private, rebuilt or retained each window) |
| D9 | Retry and cleanup of the bootstrap | Retry: fix the cause in Git and raise `spec.bootstrapAttempt`, which names a new Job; bootstrap is idempotent and keeps an existing password. Cleanup: operator-run `cleanup` Job, documented and tested, also removing old Jobs; not reconciled by a controller | A `Failed` Job never re-runs by itself; kro has no delete hook; a reaper is extra scope | Retry by deleting the Job by hand (breaks "no manual repair"); reaper CronJob comparing requests with schemas |
| D10 | P4 gross cap and window | 5 USD for all P4 windows and retries; one window planned, a second only on new approval; node count as approved in P3 | About 0.35 USD/h with RDS; inside the 100 USD envelope | — |
| D11 | Tenant identity of a request | The instance namespace is the tenant; requests outside `tenant-a`/`tenant-b` fail the static check and cannot get a role | Not spoofable from `spec` | A `spec.tenant` field |
| D12 | CI on pull requests | GitHub Actions runs the static gates only; no AWS or cluster credential | ver3 §9.1 step 2 | Keep checks local only |

Estimated effort is about 32 h (range 28–33 h) against a 24 h allocation. The
difference is the reference application, the identity module and the retry case
added after review; nothing in P4 is optional. Effort is not AWS run time: the
cap in D10 is priced per window, not per working hour.

## 9.2. Traceability from the outline issues

The outline issues DRF-16 and DRF-17 are superseded by the P4-T tasks. Their
acceptance criteria map as follows.

| Outline AC | Covered by |
|---|---|
| DRF-16 AC-01 approved design, priced AWS and secret boundary | P4-T1, P4-T4.1 A |
| DRF-16 AC-02 RDS not per request; DB/schema/role and bootstrap privilege tested both ways | P4-T2.1, P4-T4.1 B and D |
| DRF-16 AC-03 no admin credential in workloads; DB private; teardown/retain evidence | P4-T2.2, P4-T4.1 B and E |
| DRF-17 AC-01 valid request with observed EKS checks and status/access info | P4-T3.1, P4-T3.2, P4-T4.1 C |
| DRF-17 AC-02 invalid or unauthorised request never Ready; retry/cleanup; tenant boundary | P4-T3.2 B and C, P4-T4.1 D and E |
| DRF-17 AC-03 owner explains the flow; smoke not mixed with official trials | P4-T4.1 C (labelling), P4-T4.2 C |

## 9.3. Linear tracking

Titles carry the task code. `DRF-` numbers are Linear identities only; inside each
parent they still run upward. DRF-16 and DRF-17 were cancelled as superseded on
14/11/2026; their blocking relations moved to DRF-44 (blocks DRF-24) and DRF-55
(blocks DRF-18, DRF-19, DRF-22, DRF-25).

Later on 14/11 the owner asked for fewer issues, so P4 went from 24 issues to 10
with the same work and acceptance. Kept issues were re-titled and re-described.
DRF-41, DRF-42, DRF-43, DRF-47, DRF-48, DRF-52, DRF-53, DRF-54 and DRF-58 to
DRF-63 were cancelled as merged; each has a comment naming the issue that took
its work. No due dates are set: the rebaseline is the owner's decision.

| Code | Title | Issue | Blocked by |
|---|---|---|---|
| P4-T1 | Hợp đồng P4: SPEC, quyết định, pin và ADR-0008 | DRF-40 | — |
| P4-T2 | Shared service: RDS PostgreSQL/pgvector và ranh giới credential | DRF-44 | P4-T1 |
| P4-T2.1 | Entry point database và lab kind database | DRF-45 | P4-T1 |
| P4-T2.2 | Terraform module shared-rds và rag-identity | DRF-46 | P4-T1 |
| P4-T3 | RAGSandbox: một request tạo môi trường dùng được | DRF-49 | P4-T1 |
| P4-T3.1 | Ứng dụng tham chiếu và image | DRF-50 | P4-T2.1 |
| P4-T3.2 | RGD, request, CI và lab kind graph | DRF-51 | P4-T3.1 |
| P4-T4 | Window L3 trên EKS và nghiệm thu P4 | DRF-55 | P4-T2, P4-T3 |
| P4-T4.1 | Window L3: phê duyệt, dựng, end-to-end, test âm, teardown | DRF-56 | P4-T2.1, P4-T2.2, P4-T3.2 |
| P4-T4.2 | Nghiệm thu: evidence, review, teach-back | DRF-57 | P4-T4.1 |

## 9.4. Independent review

**Review 1 — Codex, 14/11/2026.** Revision
`44313683037d0404952d2d32f5916f93daeb5046` (PR #33), issue then DRF-41.
Verdict: `REQUEST_CHANGES` — 2 MAJOR, no BLOCKER. Read-only: repository, Linear
and official sources; no AWS or runtime run; no file or Linear status changed.
Commands: `check-context.sh` PASS, `git diff --check` PASS.

1. MAJOR — the §10 fallback moved the bootstrap Job into the tenant namespace
   with "a ServiceAccount no tenant RBAC can use". RBAC does not guarantee that:
   whoever may create workloads in a namespace may choose any ServiceAccount
   there, so a tenant could use the bootstrap identity. This contradicts
   negative boundary 3. Proposed: drop it, keep bootstrap credential and Job in
   `zdr-platform`, stop the L2 gate if kro cannot do it, and give each kro
   feature its own fallback (a namespace change does not fix `readyWhen`).
2. MAJOR — no mechanism to recover a `Failed` Job by a Git change. A Job that
   reached a terminal `Failed` does not re-run when its dependency is fixed, and
   the app re-reading its secret does not restart bootstrap. Proposed: choose a
   simple retry mechanism (for example an attempt field that names a new Job),
   add an L2 case `Failed` → fix in Git → bootstrap succeeds → Ready, keep
   bootstrap idempotent and clean old Jobs.

Other observations by the reviewer: D1–D5 fit ver3 and ADR-0004; D6 is
reasonable for a two-tenant PoC; D7 discloses the extra object-delete right; D8
needs the owner's approval as stated; D9–D12 fit scope apart from retry; nothing
reaches into P5+. Readiness does not rely on Argo status. Effort above 24 h does
not by itself require a higher cap. §9.2 maps all six AC; §9.3 matched Linear at
that time. No real sensitive data found.

Fixes (next revision on PR #33): negative boundary 3 and D4 confine master and
bootstrap to `zdr-platform`; §10 gives a fallback per kro feature and none that
moves the Job; D9, P4-T2.1 A, P4-T3.2 A–C, P4-T4.1 E and scenario 6 define and
test the `bootstrapAttempt` retry. The same revision regroups P4 into 10 issues
at the owner's request.

**Review 2 — Codex re-check, 14/11/2026.** Revision
`4c239163452f0c8f8bf8320fd13d859ace0354c6`. Verdict: `REQUEST_CHANGES` — 1
MAJOR. Document re-check only; no runtime proof. No file, commit, AWS call or
Linear change. Commands: `check-context.sh` PASS, `git diff --check` PASS.

- Review 1 MAJOR 1: fixed. Jobs, ServiceAccounts and master/bootstrap
  credentials stay in `zdr-platform`; no fallback moves a Job into a tenant.
- Review 1 MAJOR 2: fixed in the contract. `bootstrapAttempt` creates a new Job;
  terminal failure, retry through Git, kept password, L2/L3 checks and old-Job
  cleanup are defined.
- Regrouping: no step or AC lost; §9.2 keeps all six AC; the 10 kept Linear
  issues match §9.3 codes, parents and blocked-by; the 14 merged issues are
  Canceled and block nothing.
- New MAJOR: the §10 fallback for `readyWhen` on a Job (drop the Job condition)
  can report Ready falsely. If attempt 0 succeeded and attempt 1 fails, `/readyz`
  can still pass on the old credential, contradicting scenarios 3 and 6 and the
  negative case in P4-T3.2 C. Proposed: make it "no fallback", stop the L2 gate
  for the owner, keep the requirement that the current attempt's Job succeeded.

Fix (next revision on PR #33): §10 `readyWhen` row is now "no fallback; stop the
L2 gate", with the reason.

**Review 3 — Codex re-check, 14/11/2026.** Revision
`358da7326ec44f5d626086a70125333966b41f70`. Verdict: `APPROVE`; no finding in
the re-check scope. §10 now has no fallback for `readyWhen` on a Job, stops the
L2 gate and requires the current attempt's Job to succeed before Ready; no other
text allows dropping that condition (the old option in §9.4 is review history);
DRF-51 part C matches. `git diff --check 4c23916 358da73` PASS. Document and
Linear read only; no runtime proof; no file, commit or Linear change.

Independent review of the SPEC is complete. The owner approved D1–D12 and the
P4 cap on 14/11/2026 (§9.1).

# 10. Open risks

- kro v0.9.4 features: all four PASSED in a kind spike on 14/11/2026
  (`docs/evidence/p4/P4-T1_KRO_SPIKE_20261114.md`), including a later failed
  attempt turning a Ready instance back to not Ready. kro removed the old Job
  only once the new attempt and the whole graph were Ready. P4-T3.2 re-proves
  them in the real graph; the responses below stay in force if that lab
  disagrees. None moves a platform Job or credential into a tenant namespace
  (negative boundary 3):
  - `externalRef` to `platform-config` in `zdr-platform` fails: apply a copy of
    the non-secret `platform-config` into each tenant namespace in the window,
    from Terraform outputs and ignored by Argo CD, as with the P3 annotations.
  - a child Job in a namespace other than the instance's fails: no fallback.
    Stop the L2 gate and the owner re-decides the design before any EKS work. A
    Job in a tenant namespace would let anyone who may create workloads there use
    its ServiceAccount ([Kubernetes RBAC good practices](https://kubernetes.io/docs/concepts/security/rbac-good-practices/#workload-creation)).
  - `readyWhen` on a Job fails: no fallback. Stop the L2 gate and the owner
    re-decides the design. Dropping the Job condition is not allowed: after a
    successful attempt, a later attempt can fail while `/readyz` still passes on
    the existing schema and secret, so the instance would report Ready with the
    current bootstrap attempt failed (scenarios 3 and 6). The current attempt's
    Job must have succeeded before the instance is Ready.
  - a renamed child is not removed by kro: `cleanup` and the runbook delete old
    bootstrap Jobs (D9).
- When kro deletes a Job (old attempt or deleted instance), the Job's Pods stay
  in `zdr-platform` with no owner (spike 14/11). They hold no secret value,
  since secrets are read by SDK at run time, provided bootstrap never logs one.
  `cleanup` and the runbook delete them by the instance labels on the Pod
  template (D9).
- GHCR layer downloads may be redirected to a storage host the S3 gateway
  endpoint policy blocks, as quay.io and registry.k8s.io were in P3. P4-T4.1
  part B checks the pull first; the fix is an explicit, read-only endpoint entry.
- RDS creation and deletion each take several minutes and count against the
  1-hour session and the cap; a failed create still bills.
- Secrets created by Jobs are outside Terraform state. A missed cleanup leaves a
  billable secret; the inventory must list them.
- Bootstrap keeps an existing sandbox password on re-run. If the sandbox secret
  is missing, a new password is written and the app must recover by re-reading
  its secret.
- Schema-level tenancy shares catalog metadata and instance capacity. It is soft
  isolation and is reported as such.
- R1 least privilege is still deferred; the Terraform role is broader than the
  P4 plan needs.
- Schedule: P4 starts after its gate. P6 (14/11) and the P8 freeze (19/11) cannot
  hold as written; the owner's rebaseline is open.
