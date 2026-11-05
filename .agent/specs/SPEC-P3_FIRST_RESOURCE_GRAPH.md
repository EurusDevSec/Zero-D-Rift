---
id: SPEC-P3
title: First resource graph — Argo CD, Crossplane and kro vertical slice
status: DRAFT_FOR_OWNER_REVIEW
phase: P3
start: 2026-11-05
deadline: 2026-11-08 (PROPOSED; ver3 §12 window 03–05/11 already missed)
schedule_baseline: OWNER_REQUESTED_RECOVERY_2026-10-29
estimated_effort: 18-22 hours
mode: Coach for new controllers, then Pair
canonical_scope: docs/de_cuong_tot_nghiep_ver3.md
linear: DRF-14 (contract), DRF-15 (resource graph)
authority: NO_INSTALL_NO_AWS_APPLY_UNTIL_TASK_GATES
---

# 1. Goal and boundaries

P2 was accepted on 05/11/2026 (DRF-13: evidence audit, owner PRACTICED + EXPLAINED,
Codex review APPROVE). This SPEC details only P3; P4+ stay outlines in ver3 §12.

Schedule note: ver3 §12 gives P3 the window 03–05/11. P3 starts on 05/11, so the
P3 gate is missed as planned. Per ver3 §12.1 the remaining plan must be rebaselined
from live state by the owner; this SPEC proposes 05–08/11 and does not reduce
scope, trial count, acceptance, learning gate or teardown.

## Goal

Prove the platform control plane on the real EKS bootstrap with one thin vertical
slice: a single high-level custom resource, merged in Git and synced by Argo CD,
makes kro build a small graph that contains one in-cluster `Deployment` and one
Crossplane-managed S3 bucket. The slice must show readiness that is real (not
`Synced`), a tested deletion/ownership path, and complete cleanup.

This is the ver3 exit criterion for P3: "Một CR tạo resource graph ổn định,
ownership/readiness/cleanup rõ". It is a spike for P4 `RAGSandbox`, not a golden path.

## MUST deliverables

- `SPEC-P3` approved by the owner, with decisions D1–D8 (§9) resolved.
- Pinned install manifests/values for Argo CD, Crossplane core, the AWS provider
  family plus `provider-aws-s3` only, and kro; chart versions and image digests
  recorded in `docs/VERSION_MATRIX.md` and the run manifest.
- A Git layout Argo CD syncs from (proposed `gitops/platform/` and
  `gitops/requests/`), with static checks added to `infra/terraform/scripts/check.sh`
  or a sibling script.
- Terraform change for the Crossplane provider IRSA role (bootstrap IAM per ADR-0003),
  scoped to the P3 bucket name prefix, with plan assertions.
- One `ResourceGraphDefinition` and one instance (proposed kind `StorageAppSpike`).
- Runbook `docs/runbooks/P3_RESOURCE_GRAPH.md`: install order, verify, delete,
  teardown order, stop conditions, undo.
- Evidence under `docs/evidence/p3/`: L2 kind lab, L3 window, readiness and
  deletion tests, inventory and cost. Raw logs stay outside Git.

## Negative boundaries

1. Do not install KEDA, Karpenter, Kyverno, OpenCost, Prometheus, ExternalDNS or
   any controller outside Argo CD, Crossplane, the selected provider packages and kro.
2. Do not install the whole AWS provider family; only `provider-family-aws`
   (dependency) and `provider-aws-s3`. EC2/SQS/RDS/IAM/EKS packages are out of P3.
3. Do not create RDS, SQS, Security Groups through Crossplane, GPU or extra node pools.
4. Do not let Crossplane and Terraform manage the same resource (ADR-0003). The
   provider IAM role is Terraform's; the bucket is Crossplane's.
5. Do not give the provider role AWS admin, IAM, or bucket access outside the
   approved prefix. Do not use long-lived access keys; use IRSA.
6. Do not put secrets, account IDs, kubeconfig, Argo admin password or tokens into
   Git, Linear or evidence. The Argo CD repo is public and needs no credential.
7. Do not report `Synced` or `Healthy` from Argo CD as end-to-end readiness;
   readiness comes from the kro instance status backed by child conditions.
8. Do not delete Crossplane or its provider while managed resources still exist;
   that orphans AWS resources.
9. Do not run an AWS window without a separate execution approval, fresh cost and
   identity check, stop time and teardown owner (same rule as P2).
10. Do not use deletion/management-policy values from old examples; use only what
    the pinned Crossplane/provider CRDs accept (verified in Task 1–2).

# 2. Constraints carried forward from P2

- EKS 1.35, AL2023, `us-east-1`, public worker subnets, no NAT, S3 gateway endpoint
  (ADR-0006). The P2 Terraform root and runbooks create, verify and destroy the
  cluster; P3 reuses them unchanged except the IRSA role in Task 4.
- Identity: `zdr-bootstrap` MFA AssumeRole, 1-hour sessions; refresh by clearing the
  CLI cache (P2_L3_WINDOW). Terraform role is still AdministratorAccess: R1 least
  privilege is deferred by the owner (04/11) and must be redone before DRF-27 (19/11)
  or at DRF-29. P3 does not depend on R1 but the window note must state it.
- Cluster admin for the bootstrap role exists only inside a window and is removed
  before destroy (DRF-5 AC-04).
- kubectl `v1.35.10` at `/r/_Dev_tools/kubectl` (per-terminal PATH export).
- Gross project envelope 100 USD; credits do not raise it. P2 actual ≈ 0.07 USD.
- Learning state: Terraform PRACTICED + EXPLAINED; Argo CD, Crossplane and kro are
  `Conceptual only` (`.agent/learning/CURRENT_STATUS.md`).

# 3. Learning objectives

By the end of P3 the owner should be able to:

1. Trace a merged PR to an AWS bucket: Git → Argo CD → kro → Crossplane → AWS API.
2. Explain why Argo `Synced/Healthy`, Crossplane `Synced`, and Crossplane `Ready`
   are different signals, and which one proves the bucket exists.
3. Predict what deleting the instance, the managed resource, or Crossplane itself
   does to the AWS bucket under the pinned policies.
4. Explain how the provider Pod gets AWS credentials through IRSA and why its role
   is limited to one bucket prefix.
5. Locate a failure in Git/Argo, kro graph, Crossplane/provider, IAM or AWS.

# 4. Acceptance scenarios

```gherkin
Scenario: Controllers are pinned and limited
  Given approved chart versions and image digests
  When Argo CD, Crossplane, provider-family-aws, provider-aws-s3 and kro are installed
  Then each controller and ProviderRevision is healthy
  And no other provider package or controller is present

Scenario: One request builds the graph end to end
  Given a merged StorageAppSpike instance in gitops/requests
  When Argo CD syncs it
  Then kro creates the Deployment and the Crossplane bucket
  And the bucket exists in AWS with the expected name and tags
  And the instance reports Ready only after the bucket is Ready and the Deployment is available

Scenario: Readiness is not faked
  Given an instance whose bucket name is outside the IAM-allowed prefix
  When Argo CD syncs it
  Then Argo CD can show Synced while the instance never becomes Ready
  And the managed resource shows the AWS authorization error

Scenario: Ownership and deletion are predictable
  Given the pinned deletion/management semantics
  When the instance is removed from Git
  Then the Deployment and the managed resource are removed
  And the AWS bucket is deleted or retained exactly as the policy predicts
  And an orphaned bucket, if any, is recorded and removed under approval

Scenario: Teardown is complete
  When instances, then kro, Crossplane and Argo CD, then the EKS bootstrap are removed in order
  Then inventory shows no project resource outside the retain allowlist
```

# 5. Work checkpoint matrix

## Task 1 — Contract, pins and decisions (2–3 h) — DRF-14

- [ ] Recheck releases/security notes for Argo CD `v3.5.3`, Crossplane `v2.4.0`,
      provider family `v2.7.0`, kro `0.9.4` (VERSION_MATRIX, checked 2026-09-25).
      Pick exact chart versions and resolve image digests; record sources and dates.
- [ ] Read the pinned CRD schemas: S3 bucket API group/version and scope
      (namespaced vs cluster), `ProviderConfig` kind, IRSA credential source,
      `managementPolicies` and any deletion field; kro RGD/instance status fields
      and the RBAC kro needs for Crossplane kinds.
- [ ] Estimate controller CPU/memory against one `m6i.large` (2 vCPU, 8 GiB,
      29 Pods with VPC CNI) and decide D7.
- [ ] Owner decides D1–D8 and approves the P3 gross cap.

Gate: no installation of kind or any controller before Task 1 decisions.

## Task 2 — L2 kind micro-lab, no AWS (3–4 h) — DRF-14

Owner predicts before each step; Claude records prediction vs observed.

- [ ] (needs install approval) kind `v0.33.0` with the pinned
      `kindest/node:v1.35.8@sha256:07b2536e…` image (ADR-0005).
- [ ] Install Argo CD; sync a plain `Deployment` from this repository; observe
      `Synced/Healthy`; change replicas in Git; observe drift correction.
- [ ] Install Crossplane + selected providers without AWS credentials; verify
      Provider/ProviderRevision health and that only the expected CRDs exist.
- [ ] Apply a bucket MR with no working credentials: observe `Synced=False` or
      `Ready=False` and the error. This is the local proof that Synced ≠ Ready.
- [ ] Install kro; create the RGD; create an instance with in-cluster resources
      only; observe graph order and instance status. Then add the bucket node and
      observe the instance stay not Ready.
- [ ] Delete in order and destroy the kind cluster; record leftovers (none expected).

Evidence: `docs/evidence/p3/DRF14_L2_KIND_<date>.md`. Promote ADR-0005 to
ACCEPTED only if this lab passes. kind evidence never proves IRSA or AWS behavior.

## Task 3 — GitOps layout and manifests (3 h) — DRF-15

- [ ] `gitops/platform/`: Argo CD `Application`s for Crossplane, providers,
      ProviderConfig, kro and the RGD, with explicit sync order (sync waves).
- [ ] `gitops/requests/`: one valid instance and one negative instance (disabled
      by default, enabled only for the negative test).
- [ ] Static checks: no `latest` tags, every image/chart pinned, only allowlisted
      provider packages, no Secret objects, bucket names inside the prefix.
- [ ] Server-side dry run of the manifests in the Task 2 kind cluster when possible.

## Task 4 — Provider IRSA role in Terraform (2 h) — DRF-15

- [ ] Role trust: the cluster OIDC issuer, the provider ServiceAccount subject
      (exact name from the pinned provider), audience `sts.amazonaws.com`.
- [ ] Permissions: S3 bucket-level actions the provider needs, only on
      `arn:aws:s3:::zero-drift-p3-*`; no `s3:*` on `*`, no IAM.
- [ ] `plan_assert.sh` checks: role name prefix, trust subject, no wildcard
      resource, policy size. New plan fingerprint for the P3 window.
- [ ] `iam_check.sh`-style simulation: allowed on the prefix, denied elsewhere.

## Task 5 — Approved L3 window (4–5 h) — DRF-15

- [ ] Window request (P2_L3_WINDOW template): run ID, plan, cap, stop time,
      teardown owner, fresh identity/cost/quota check, pre-inventory.
- [ ] Recreate the P2 bootstrap plus the IRSA role; smoke as in P2.
- [ ] Install Argo CD (pinned), then let it sync `gitops/platform/`; verify
      every controller and ProviderRevision healthy; capture versions/digests.
- [ ] Sync the valid instance: verify the bucket in AWS (head-bucket, tags), the
      Deployment available, and the instance Ready; record timestamps.
- [ ] Negative test: enable the out-of-prefix instance; verify AccessDenied in
      the MR conditions and instance not Ready while Argo shows Synced.
- [ ] Deletion test: remove the instance from Git; verify the predicted effect on
      the Deployment, MR and AWS bucket.
- [ ] Teardown in order (§7.2 of the runbook): instances → MRs gone → kro →
      Crossplane providers/core → Argo CD → admin removal → Terraform destroy →
      immediate inventory (plus S3 buckets with the P3 prefix = 0).

Stop conditions: any controller unhealthy after one fix attempt; any bucket
created outside the prefix; any MR stuck deleting for 15 minutes; session
under 40 minutes before a destroy; freeze time reached.

## Task 6 — Evidence, review, teach-back (2 h) — DRF-15

- [ ] Evidence file with run ID, revision, versions/digests, conditions,
      timestamps, inventories and cost estimate.
- [ ] Delayed inventory and billing follow-up (as DRF-12).
- [ ] Independent review (Codex) of the candidate revision.
- [ ] Owner teach-back (§7); update learning status from demonstration only.

# 6. Verification tiers

| Tier | P3 use | Evidence |
|---|---|---|
| L0 | YAML/static checks, Terraform fmt/validate/plan assertions | commands, exit status |
| L1 | Not used (no local Terraform lab needed beyond P2) | — |
| L2 | kind: controller health, CRDs, Argo sync, kro graph, Synced ≠ Ready without AWS | run ID, predictions, observed conditions |
| L3 | EKS: IRSA, real bucket, readiness, negative IAM, deletion, teardown | approval, manifest, AWS/K8s output, inventory |

# 7. Teach-back questions

1. Walk a merged instance from Git to the AWS bucket: which component acts at each step?
2. Argo shows `Synced/Healthy` but the instance is not Ready. Where do you look, in order?
3. What happens to the AWS bucket when you delete the instance? The MR? Crossplane itself?
4. How does the provider Pod get AWS credentials, and what stops it from touching other buckets?
5. Why must Crossplane be removed only after its managed resources are gone?
6. Why does Terraform own the provider role but not the bucket?

# 8. P3 completion rule

P3 is complete only when the scenarios in §4 have L3 evidence on EKS, teardown and
delayed inventory are clean, an independent review has recorded findings and limits,
and the owner reaches `PRACTICED` + `EXPLAINED` for the Git → Argo CD → kro →
Crossplane → AWS flow and its deletion semantics. If the S3 slice is not stable,
stop and fix it; do not add technology (ver3 §12.1).

# 9. Decisions for the owner (D1–D8)

| ID | Decision | Proposal | Why |
|---|---|---|---|
| D1 | Local-first lab | kind `v0.33.0` per ADR-0005 (install needs approval). k3d `v5.8.3` and Helm `v4.2.2` are already present but k3d runs K3s, which ADR-0005 rejected | Upstream Kubernetes 1.35 image pinned by digest |
| D2 | How Argo CD is installed | Pinned upstream manifest/Helm from the workstation once per window; Argo CD then manages everything else | Terraform stays out of in-cluster objects (ADR-0003) |
| D3 | Argo CD source | This public repository, branch `main`, no repo credential | No secret to manage; PR = audit trail |
| D4 | Provider identity | IRSA role created by Terraform, enabled only for the P3 window | Bootstrap IAM is Terraform's; no access keys |
| D5 | Managed resource API | The S3 bucket kind exposed by the pinned provider (namespaced v2 API if available), confirmed in Task 1 | Must match pinned CRDs, not old examples |
| D6 | Deletion semantics | Default: deleting the instance deletes the bucket. One extra check with an orphaning management policy only if the pinned CRD supports it, then manual cleanup under approval | Ver3 asks for a tested retain/delete path; keep it to one bucket |
| D7 | Node capacity | Decide after Task 1 sizing: 1 × m6i.large if controllers fit with headroom, otherwise desired 2 for the window (+0.096 USD/h) | One node may not fit Argo + Crossplane + providers + kro |
| D8 | P3 gross cap | 3 USD (≈ 4–6 h of EKS + 1–2 nodes ≈ 0.2–0.3 USD/h, plus S3 and logs), inside the 100 USD envelope | Same discipline as P2's 5 USD cap |

# 10. Open risks

- Crossplane `v2.4.0` with provider `v2.7.0` pairing is `UNVERIFIED`; kro `0.9.4`
  on Kubernetes 1.35 is `UNVERIFIED` (VERSION_MATRIX §2). Task 2 must prove both.
- Provider packages add many CRDs; if API server memory or Pod count is a problem
  on one node, D7 changes cost.
- Docker Desktop must be running for kind; the daemon state was not checked.
- Schedule: P3 already slips past 05/11; P4 (RAG, target 08/11) moves unless the
  owner rebaselines. This SPEC does not change ver3 §12 by itself.
