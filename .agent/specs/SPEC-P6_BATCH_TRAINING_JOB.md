---
id: SPEC-P6
title: BatchTrainingJob — SQS, KEDA ScaledJob, Karpenter CPU NodePool, checkpoint and node reclamation
status: OWNER_APPROVED_20261125 (owner approved D1–D14 on 25/11 after Codex APPROVE in round 4 at fdedcac)
phase: P6
start: 2026-11-25 (owner rebaseline, D13)
deadline: 2026-11-26 target (owner, D13); a step that does not fit moves to 27/11, it is never cut
schedule_baseline: ver3 §12 window 11–14/11 missed; owner rebaselined P6–P11 on 25/11 (D13, ROADMAP "Rebaseline 25/11")
estimated_effort: 24-28 hours (ROADMAP allocates 32 h); GPU windows removed by ADR-0009
mode: Pair (Claude implements, owner predicts, runs the labs and explains); Coach for the Karpenter micro-lab
canonical_scope: docs/de_cuong_tot_nghiep_ver3.md
governing_adr: ADR-0009 (P6 on CPU nodes under the G/VT quota denial)
linear: DRF-73..DRF-81 (§9.4); DRF-19, DRF-20 cancelled as superseded 25/11
authority: CONTRACT_APPROVED_NO_INSTALL_NO_AWS_UNTIL_TASK_GATES
drafted_from: Fable 5.2 draft of 16/11 (branch claude/specs-p5-p9-draft-ecc762, status DRAFT_FABLE_20261116)
rechecked_at: main at d527307 (2026-11-25), after the P5 technical gate
---

# 0. Status and what changed from the draft

This SPEC starts from the Fable 5.2 draft of 16/11 and is rechecked against
`main` at `d527307` (P4 and P5 done on EKS). Three facts changed the draft:

1. **ADR-0009 (accepted 17/11).** AWS denied the G/VT quota twice. Batch runs on
   CPU nodes created by Karpenter. Every GPU item of the draft is removed: the
   NVIDIA device plugin, GPU NodePools, the GPU quota task (old P6-T0), the two
   GPU windows, the CUDA device check and the GPU cost envelope. The mechanism
   (KEDA → pending Pod → Karpenter node → checkpoint in S3 → node reclaimed) and
   the thresholds of H2, H3, H5 and scale-down time are unchanged. Every batch
   result carries the label `CPU_SUBSTITUTE_FOR_GPU`.
2. **Quota.** The Standard On-Demand quota read in the P5 window on 25/11 is
   8 vCPU, not 5 (P5-T4.2 evidence, preflight row). Two `m6i.large` system nodes
   use 4, so a 2 vCPU On-Demand batch node fits beside them. The open point of
   ADR-0009 §3 is closed by this reading; it is read again before the window.
3. **P5 guardrails are live.** The training Pod runs in a tenant namespace, so
   Pod Security `restricted`, the Kyverno policies (image from
   `ghcr.io/eurusdevsec/zero-d-rift/` by digest, requests and memory limit,
   tenant label), the ResourceQuota, the LimitRange and default-deny egress all
   apply to it. P5 moved the object-count quota test into the P6 suite (P5 audit
   §3.1).

The draft's three AWS windows become **one** L3 window. Nothing in ver3 is
reduced (ver3 §12.1): P6 is a smoke phase; H2, H3, H5 and scale-down time are
still measured in P9 with their full trial counts.

# 1. Goal and boundaries

## Goal

Deliver the second golden path on EKS. One `BatchTrainingJob` request, merged in
Git and synced by Argo CD, gives a tenant:

- a training run started by a message in a shared SQS queue through a KEDA
  `ScaledJob`;
- a CPU node provisioned on demand by Karpenter (Spot first, On-Demand fallback
  with its own label) and used only by batch Pods;
- checkpoints and a final artifact in the tenant's own S3 bucket, written by the
  application, so an interrupted run resumes;
- an observable outcome, and a node that is terminated after the run.

This is the ver3 §12 exit criterion for P6 ("Batch end-to-end, checkpoint và thu
hồi Pod/GPU node có evidence"), read through ADR-0009 as "CPU node". Runs in P6
are smoke runs (`official=false`).

## MUST deliverables

- This SPEC approved by the owner with decisions D1–D14 (§9.1).
- Terraform module `batch-platform` (queue, dead-letter queue, IRSA roles) and
  module `karpenter` (controller role, node role, instance profile, access
  entry, interruption queue and rules, discovery tags), both behind
  `enable_batch_platform` (default false), with `terraform test` and plan
  assertions.
- Reference workload `workloads/batch-training/`: one image, entry points
  `submit`, `train`, `cleanup`, unit tests, published to GHCR and pinned by digest.
- GitOps: KEDA and Karpenter as pinned Argo CD applications; `NodePool`s and
  `EC2NodeClass`; the `BatchTrainingJob` ResourceGraphDefinition; one request
  per tenant (only one enabled); static checks in `gitops/check.sh`.
- Verification: outcome check (markers, checkpoint, artifact), node lifecycle
  check on Kubernetes **and** AWS, capacity and identity negatives, the
  object-count quota test carried from P5.
- Runbooks `docs/runbooks/P6_L2_KIND_KEDA.md` and `docs/runbooks/P6_L3_WINDOW.md`.
- Evidence under `docs/evidence/p6/`: kind lab, L3 window, inventory, cost,
  acceptance audit, teach-back.

## Negative boundaries

1. No GPU instance, GPU NodePool, NVIDIA device plugin, GPU AMI or GPU claim
   (ADR-0009 §4). No result is extrapolated from CPU to GPU.
2. No NodePool without an instance-type allowlist, `limits`, `expireAfter` and
   project tags. At most one batch node per capacity type.
3. Karpenter never manages the system node group, and its controller never runs
   on a node it provisions.
4. Karpenter gets no right to create or change IAM roles, policies or instance
   profiles. `iam:PassRole` only for the one node role.
5. No controller beyond KEDA and Karpenter: no cluster autoscaler, no
   `provider-aws-sqs`, no AWS FIS, no Volcano or Kueue.
6. Karpenter is not responsible for training state. Checkpoints are the
   application's job (ver3 §6.5).
7. A run on On-Demand is never reported as Spot. Capacity type comes from the
   label `karpenter.sh/capacity-type` of the Node that actually ran the Pod,
   read by the suite while that Node exists. It never comes from the request
   or from the worker.
8. `Synced`, a `Running` Pod or the instance's `Ready` is not a training outcome.
   `Ready` means "submitted" (D4).
9. No real model, real dataset or Bedrock call. The workload is synthetic.
10. No tenant data, account ID, ARN, queue URL or node name in Git, Linear,
    evidence or a message body.
11. Karpenter, its NodePools or the cluster are never deleted while a NodeClaim
    or a Karpenter-launched instance exists (§9.5).
12. No AWS window without its own execution approval, fresh cost, identity and
    quota check, stop time and teardown owner.
13. No P6 run counts as an official H2, H3 or H5 trial.
14. No PolicyException and no weakening of a P5 guardrail to make the batch Pod
    fit. A Pod that does not comply is changed; a quota is raised only by the
    amount D9 states.

# 2. Assumptions from earlier phases (rechecked 25/11)

| # | Assumption | Result 25/11 | Source |
|---|---|---|---|
| A1 | G/VT quotas are 0 | **True**, and stays out of scope (ADR-0009) | COST_PLAN §7.3.1 |
| A2 | Standard On-Demand 5 vCPU, Spot 5 vCPU | **Changed:** On-Demand read as 8 vCPU on 22/11 and 25/11. Spot not read since 28/09 | P5-T4.2 evidence §preflight; reread at T−30 |
| A3 | P4 accepted (`RAGSandbox` end to end on EKS) | **True** (24/11) | P4 audit |
| A4 | P5 accepted: `restricted`, quota (GPU 0), default-deny, Kyverno | **True technically** (25/11); delayed inventory and Bills on 26/11 | P5 audit §6 |
| A5 | kro v0.9.4 can hold a KEDA `ScaledJob` and a Job in another namespace in one graph | **Unverified.** The P4 spike covered a Job and a ConfigMap; RAG uses a Job in `zdr-platform` | P6-T2.2 kind lab, step 1 |
| A6 | ADR-0008 identity pattern (Terraform pre-creates one role per tenant and workload; Crossplane has no IAM right) carries over | **True**; `rag-identity` creates `zero-drift-rag-<tenant>` the same way. P6 also keeps the batch ServiceAccount platform-owned (P6-T2.2), so the identity does not depend on a request | `infra/terraform/modules/rag-identity/main.tf` |
| A7 | Crossplane S3 role can take a second bucket prefix | **True with a change:** today the role is `zero-drift-rag-crossplane-s3` in `rag-identity`; batch buckets need prefix `zero-drift-batch-` added | P6-T3 A |
| A8 | Network baseline: public subnets with `map_public_ip_on_launch`, no NAT, S3 gateway endpoint, IMDSv2 hop 1 | **True** | `modules/network/main.tf` |
| A9 | `authentication_mode = "API"`; a Karpenter node role needs an `EC2_LINUX` access entry | **True** | `modules/cluster/main.tf:48` |
| A10 | Two `m6i.large` system nodes have room for KEDA (3 Pods) and Karpenter (1) | **Unmeasured.** P5 window ran Kyverno too; Pod count read in the window | L3 preflight |
| A11 | EC2 Spot service-linked role exists | **Unknown**; read-only check at T−30 | `aws iam get-role` |
| A12 | Second image follows the P4 pattern (public GHCR, built by GitHub Actions, pinned by digest) | **True**; also required by Kyverno `zdr-image-digest` | `.github/workflows/rag-sandbox-image.yml` |
| A13 | Tenant egress allows 443 outside the VPC (SQS) and the S3 gateway endpoint | **True** for SQS public endpoint; S3 path read in the kind lab and window | `gitops/platform/tenants/networkpolicy.yaml` |
| A14 | Tenant quota is sized for two sandboxes only (400m CPU, 768Mi, 8 Pods, `count/jobs.batch` 4) | **True**; one training Pod does not fit beside two sandboxes, D9 | `gitops/platform/tenants/quota.yaml` |

# 3. Learning objectives

By the end of P6 the owner can:

1. Separate three scalers: KEDA creates Jobs from queue length, the scheduler
   places Pods, Karpenter creates nodes for Pods that cannot be placed.
2. Trace one message: SQS → KEDA → Job → pending Pod → NodeClaim → EC2 instance →
   kubelet → container → S3, and say where each step can stall.
3. Explain visibility timeout, at-least-once delivery and the dead-letter queue,
   and why the worker deletes the message only after success.
4. Explain why checkpointing belongs to the application and what Karpenter does
   and does not do when a Spot node is reclaimed.
5. List every guard that keeps batch spend bounded and say which one AWS enforces.
6. Explain what the idle window of the baseline does to H5 before measuring it.

# 4. Acceptance scenarios

```gherkin
Scenario: Capacity is bounded before any launch
  Given Standard quotas read on the day and an approved window
  Then the batch NodePools allow only the allowlisted 2 vCPU types and two zones
  And each NodePool has limits of one node and an expiry
  And every Karpenter node carries the project tags and the batch taint

Scenario: Events drive Jobs
  Given a ScaledJob that is Ready and has already started a Job from this queue
  And the shared queue has shown visible=0 and inflight=0 over at least three polls
  Then no new training Job and no batch node exists
  When exactly one message is sent
  Then exactly one training Job is created
  And no second Job is created while that message is in flight

Scenario: One request gives an observable outcome
  Given a merged BatchTrainingJob request in a tenant namespace
  When Argo CD syncs it
  Then kro creates the checkpoint bucket, the ScaledJob and the submit Job
  And the instance reports Ready only after the bucket is Ready and the message is sent
  And Karpenter starts one node of an allowlisted type
  And the training process writes TRAINING_STARTED with device=cpu, the run attempt and its node name
  And the suite reads capacity type and instance type from that Node while it exists
  And at least one checkpoint and the final artifact exist under this attempt's prefix
  And the Job completes and its message is gone from the queue

Scenario: The node is reclaimed
  Given the training Job has completed
  Then within the scale-down stop no training Pod is running
  And the Karpenter Node is gone from Kubernetes
  And the EC2 instance is terminated and its volume is gone

Scenario: An interrupted run resumes
  Given a run that has written at least one checkpoint
  When its Pod or its node is removed before completion
  Then the message becomes visible again and a new Job starts
  And training continues from the last checkpoint, not from step 0
  And exactly one final artifact exists

Scenario: Failure is visible and bounded
  Given a request whose training always fails
  Then the request never shows a successful outcome
  And the failing layer is visible in the Job, Pod, NodeClaim or queue
  And the attempt's RECEIVED markers show receive counts 1 to maxReceiveCount
  And that attempt's message is in the dead-letter queue
  And no batch node keeps running

Scenario: Capacity and placement are bounded
  When a second message arrives while a run is active
  Then no second batch Job and no second batch node is created
  And a Pod without the batch toleration never lands on a batch node
  And a batch Pod above the tenant quota is rejected
  And an object above the pods or count/jobs.batch quota is rejected with that resource named

Scenario: Identities are bounded
  Then the training Pod can use only its tenant's checkpoint buckets and the shared queue
  And the owning tenant can read an existing object in its bucket
  And the other tenant gets AccessDenied reading or writing that same object
  And the KEDA identity can only read queue attributes
  And the Karpenter identity cannot change IAM
  And a Pod on a batch node cannot obtain node credentials from the metadata service

Scenario: Delete and teardown are complete
  When a request is removed from Git and the cleanup is run
  Then its ScaledJob, Jobs, Pods, bucket and leftover messages are gone
  When NodePools, controllers, the batch platform and the bootstrap are removed in order
  Then inventory shows no instance, volume, launch template, queue, role or
       network interface outside the retain allowlist
```

# 5. Work breakdown

## P6-T1 — Contract: decisions, pins, prices (2 h)

- [x] Recheck §2 (done 25/11 in this file), second-agent review (Codex, four
      rounds, APPROVE at `fdedcac`), owner decides D1–D14 (approved 25/11, §9.1).
- [ ] Pins (§11): KEDA chart and app 2.21.1, Karpenter chart and app 1.15.3,
      ElasticMQ 1.7.1 for kind only. Image digests read and recorded in
      `docs/evidence/p6/P6-T1_PINS_<date>.md` and VERSION_MATRIX "P6 pins".
- [ ] KEDA SQS scaler IAM action confirmed from the scaler source (S3); KEDA
      2.21 audience change (S2) checked against the TriggerAuthentication shape.
- [ ] Karpenter controller policy for 1.15.3 taken from the release's
      CloudFormation reference, reduced per D6.
- [ ] Prices: `m6i.large`, `m5.large`, `c6i.large` On-Demand from the Price List
      API; Spot price history 7 days per type and zone (read-only). §10 updated.
- [ ] ADR-0009 consequences applied where a P6 file says GPU: EXPERIMENT_PLAN §7
      wording, COST_PLAN §5.3 batch line, ver3 P6 row note. Thresholds unchanged.

Gate: no Terraform, manifest or image change merges before D1–D14 are approved.

## P6-T2 — Workload and request path (9 h)

### P6-T2.1 — Training application and image (4 h)

- [ ] **One run key.** `tenant/requestId/runAttempt` names the message, and the
      S3 prefix `runs/<requestId>/<runAttempt>/` holds every checkpoint, marker
      and the artifact of that attempt. A new attempt never reads or counts
      another attempt's objects.
- [ ] `submit`, in this order:
      1. `ListObjectsV2` with `Prefix=runs/<requestId>/<runAttempt>/submitted`.
         A successful call that returns exactly that key → exits 0 without
         sending. A successful call without that key → continues. A failed
         call (`403`, timeout) → `READ_FAILED`, exits non-zero, sends nothing.
         The submit role may list only that prefix (P6-T3), so it never sees
         the names of tenant objects.
      2. Writes `submit-started` (time) under the attempt prefix **before**
         sending, with a conditional write (`If-None-Match: *`). If it already
         exists (`412 PreconditionFailed`) the first value is kept and submit
         continues. A retry never moves the mark, so checkpoints a worker wrote
         after the first send still count. This is the freshness mark B04
         compares against; the worker may start before step 4 finishes.
      3. Sends one message `{requestId, tenant, runAttempt, steps}`.
      4. Writes `submitted`.
      A crash between 3 and 4 can send a duplicate with the same key; `train`
      makes that harmless.
- [ ] `train`: receives one message and writes `RECEIVED-<n>` with the SQS
      `ApproximateReceiveCount` n. If the attempt already has `SUCCEEDED`, it
      deletes the message, logs `ALREADY_DONE` and exits 0 without training. It
      refuses a foreign `requestId` without deleting it (visibility set to 0),
      extends visibility on a heartbeat and loads the newest checkpoint of the
      attempt. It emits `TRAINING_STARTED` (one JSON line on stdout and one
      marker in S3) with `device=cpu`, the run key, the Pod name and
      `spec.nodeName` from the downward API. The downward API cannot expose Node
      labels, so the worker records no capacity type or instance type and the
      tenant gets no right to read Nodes. It trains a small synthetic model
      (NumPy logistic regression) for a fixed number of steps, checkpoints every
      K steps, writes the final artifact and `SUCCEEDED`, then deletes the
      message. Only when `DeleteMessage` succeeds does it write
      `MESSAGE_DELETED` and exit 0. If the delete fails it exits non-zero; the
      message comes back and the next receive ends in `ALREADY_DONE`, which
      also writes `MESSAGE_DELETED` after a successful delete.
- [ ] On SIGTERM: writes a checkpoint, leaves the message, exits non-zero.
- [ ] Failure profile `fail-always` for the dead-letter scenario. It fails after
      `RECEIVED-<n>`, so every receive is recorded.
- [ ] `cleanup`: deletes leftover messages of one `requestId` (receive and
      filter) and finished Jobs of the request.
- [ ] `probe`: one S3 or IMDS call (`head`, `get`, `put` on a given bucket and
      key, or the IMDS token call) that prints only the outcome and the AWS
      error code. Before any S3 call it runs STS `GetCallerIdentity` and prints
      only `caller_role_match=true|false` against an expected role name passed
      in; it never prints the ARN or account. B12 and B14 use it, so their probe Pods pass the same Kyverno
      digest policy as training.
- [ ] Conditional write check (§9.3 L2): against MinIO and the real S3 API, a
      second `If-None-Match: *` write of `submit-started` returns `412` and the
      first value stays.
- [ ] Unit tests with in-memory fakes for SQS and S3: resume, foreign message,
      SIGTERM, double delivery, duplicate submit, `ALREADY_DONE`, receive
      markers, heartbeat, fail profile.
- [ ] Image: digest-pinned `python:3.12-slim` base, non-root UID, read-only root
      filesystem, passes `restricted`; size recorded (pull time is part of H2).
      Built by `.github/workflows/batch-training-image.yml`, same pattern as RAG.

### P6-T2.2 — RGD, KEDA objects, requests and kind lab (5 h)

**A. Manifests (3 h)**

- [ ] `gitops/platform/rgd/batch-training-job.yaml`, nodes in order:
      `platformConfig` (externalRef to ConfigMap `batch-config` in
      `zdr-platform`, keys `queueUrl`, `region`),
      `bucket` (Crossplane, `zero-drift-batch-<tenant>-<name>`), `scaledJob`,
      `submit` (Job in `zdr-platform`, named with `spec.runAttempt`). Status:
      queue name, bucket, run attempt, submit state, outcome pointer.
- [ ] ServiceAccount `batch-train` in each tenant namespace, owned by the
      platform (`gitops/platform/tenants/serviceaccounts.yaml`), not by the RGD.
      Its IRSA role `zero-drift-batch-<tenant>` exists for both tenants, so the
      identity outlives a disabled request and B12 has a real second tenant. The
      role ARN annotation holds the account ID, so the window adds it with
      kubectl and the Application ignores that field (same pattern as
      `rag-db-admin`). The ScaledJob Job template and every probe Pod set
      `serviceAccountName: batch-train` and `automountServiceAccountToken: false`
      (P5 D2); IRSA mounts its own projected web identity token.
- [ ] ConfigMap `batch-config` in `zdr-platform` is **not in Git**: the queue URL
      holds the account ID. `infra/p6-window/window.sh batch-config` writes it
      from Terraform outputs, as `window.sh platform-config` does in P4, and the
      `zdr-tenants` Application ignores it. Until it exists the graph waits at
      `platformConfig` and creates no ScaledJob or submit Job; that wait is the
      gate. The same script's `annotate` step adds the IRSA annotations.
- [ ] `ScaledJob`: `aws-sqs-queue` trigger, `queueLength: "1"`,
      `scaleOnInFlight: "true"`, `maxReplicaCount: 1`, `pollingInterval: 10`,
      `successfulJobsHistoryLimit: 1`, `failedJobsHistoryLimit: 1`; Job template
      with `activeDeadlineSeconds: 2700`, `backoffLimit: 0`, toleration and node
      selector for the batch pool, `restricted` security context, requests and
      limits per D9, tenant label, digest-pinned image. The **Pod** template
      carries `app.kubernetes.io/name: batch-train`; Pod selectors use it.
      KEDA sets the **Job** labels itself (`app.kubernetes.io/name` = the
      ScaledJob name, plus `scaledjob.keda.sh/name`), so every Job count in the
      suite, the lab helper and the runbooks selects on `scaledjob.keda.sh/name`.
- [ ] `ClusterTriggerAuthentication` `zdr-sqs` (platform-owned, not per request)
      using the KEDA operator's IRSA identity.
- [ ] kro RBAC: ClusterRole for `ScaledJob` and `Job`; AppProject `zdr-requests`
      admits `BatchTrainingJob` (SPEC-P5 D4).
- [ ] Requests: `gitops/requests/disabled/tenant-a-batch.yaml` and
      `gitops/requests/disabled/tenant-b-batch.yaml`. Both are **disabled when the
      platform is built**. `zdr-requests` syncs only files directly in
      `gitops/requests/` (no `directory.recurse`, P4), so enabling a request means
      moving its file up one level in a PR, after the queue is purged. A file in
      a subfolder such as `requests/tenant-a/` is never synced. Negatives in
      `gitops/tests/` (second enabled request, unknown namespace, steps out of range).
- [ ] `gitops/check.sh`: at most one `BatchTrainingJob` directly in
      `gitops/requests/`; no `BatchTrainingJob` in any other subfolder than
      `disabled/`; image digest; no queue URL or ARN in Git; Karpenter NodePools
      have limits and expiry.
- [ ] Tenant quota and LimitRange per D9.

**B. L2 kind lab (2 h)** — `docs/runbooks/P6_L2_KIND_KEDA.md`, owner predicts first.
L2 covers Pod Security `restricted`, the tenant quota and LimitRange, KEDA and
resume. It runs without Kyverno and without NetworkPolicy, and uses a locally
built image by tag; the image-digest policy and the real network path are
checked only at L3.

- [ ] KEDA 2.21.1 on kind with ElasticMQ as the queue and MinIO as S3 (lab-only
      images, lab namespace, not in Git requests).
- [ ] Zero messages → zero Jobs. One message → one Job. Message in flight → no
      second Job. Message never deleted → redelivery after the visibility timeout.
- [ ] Training end to end against MinIO; kill the Pod mid-run; resume from the
      checkpoint; one artifact.
- [ ] kro graph with a `ScaledJob` node becomes Active (A5).
- [ ] Runbook step 5 reads the replacement Job with a guarded read and stops
      if no Job name came back, before `kubectl wait` (§9.3 L1).

kind proves nothing about SQS, IRSA, Karpenter or EC2. Karpenter has no
published kind provider (S5), so Karpenter is L3 only.

## P6-T3 — Terraform: batch platform and Karpenter (6 h)

**A. Module `batch-platform` (2.5 h)**

- [ ] Queue `zero-drift-batch` and dead-letter queue: retention 1 h, visibility
      timeout and `maxReceiveCount` per D8, SSE-SQS, project tags.
- [ ] IRSA roles (exact `sub` and `aud`): KEDA operator (`sqs:GetQueueAttributes`
      on the one queue); `zero-drift-batch-submit` in `zdr-platform` (send to the
      queue; `s3:PutObject` only on `zero-drift-batch-*/runs/*/submitted` and
      `.../submit-started`; `s3:ListBucket` on `zero-drift-batch-*` only with
      condition `StringLike s3:prefix = runs/*/submitted`, so it can check a
      marker but cannot list tenant object names; no `s3:GetObject`);
      `zero-drift-batch-tenant-a` and `-tenant-b`, trusted only by
      `system:serviceaccount:<tenant>:batch-train` (receive, delete, change
      visibility on the queue; list, get, put, delete on that tenant's
      `zero-drift-batch-<tenant>-*` buckets only).
- [ ] Crossplane S3 role: add prefix `zero-drift-batch-` (A7).
- [ ] Root flag `enable_batch_platform` (default false); requires
      `enable_rag_platform` for the Crossplane role, or the role moves (decided in
      the module).

**B. Module `karpenter` (2 h)**

- [ ] Controller IRSA role (service account `karpenter/karpenter`), node role with
      the three EKS worker policies and `AmazonSSMManagedInstanceCore` left out,
      instance profile created here and named in the `EC2NodeClass`, access entry
      `EC2_LINUX` for the node role, interruption queue with the four EventBridge
      rules, discovery tag `karpenter.sh/discovery` on public subnets and the
      node security group.
- [ ] Controller policy: release policy reduced per D6; no IAM write;
      `iam:PassRole` for the node role only; EC2 actions conditioned on the
      cluster tag where the release policy does so.

**C. Guards and inventory (1.5 h)**

- [ ] `plan_assert.sh` behind `P6_WINDOW=1`, with guard tests on synthetic
      plans: no wildcard resource on IAM, no IAM write for Karpenter, tenant-a
      role cannot name a tenant-b bucket, submit role's `s3:ListBucket` carries
      the `s3:prefix` condition and it has no `s3:GetObject`, queue not public,
      `enable_batch_platform` off by default.
- [ ] `batch_iam_check.sh`: simulation matrix for the new roles (allowed and denied).
- [ ] `inventory.sh` counts Karpenter-tagged instances, launch templates, Spot
      requests, P6 queues, roles and instance profiles. Counts only.

## P6-T4 — L3 window, suite and acceptance (7 h)

### P6-T4.1 — Batch suite (1.5 h)

Also `infra/p6-window/window.sh` with `annotate` (IRSA annotations on the
`batch-train` and submit ServiceAccounts), `batch-config` (ConfigMap from
Terraform outputs, refuses to run if the queue does not exist) and
`purge` (queue and DLQ, then waits 60 s).

`gitops/tests/batch-suite.sh` (L3, read-mostly). Counts and verdicts only. Every
AWS or Kubernetes read is guarded: a failed read gives `READ_FAILED`, never `0`.

| Case | Checks | PASS only if |
|---|---|---|
| B01 | Empty queue → no Job, no node. Runs **after** the first run, so a working scaler is proven | the ScaledJob is `Ready` and has already started a Job from this queue; `visible=0 inflight=0` over at least three polls; then 0 new Jobs, 0 NodeClaims, 0 Karpenter instances. A missing ScaledJob is `FAIL`, not an empty result |
| B02 | One message → one Job | exactly one Job for this run key |
| B03 | In-flight → no second Job | still one Job after three polls |
| B04 | Outcome of the current attempt | the attempt's training Job is `Complete`; under this attempt's prefix there are `TRAINING_STARTED`, at least one checkpoint, `SUCCEEDED`, exactly one artifact and `MESSAGE_DELETED`, all written after this attempt's `submit-started`; after one visibility timeout the queue shows `visible=0 inflight=0`. Files present with a failed delete is `FAIL`. While the Pod runs, the suite reads Pod → `spec.nodeName` → Node labels `karpenter.sh/capacity-type` and `node.kubernetes.io/instance-type` and stores them with the run key. No label read means no capacity claim |
| B05 | Node reclaimed | the Node is gone from Kubernetes and the instance is `terminated` on AWS, counted by tag |
| B06 | Resume after Pod delete | new Job for the same run key; `resumed from step N`, N > 0 |
| B07 | Resume after NodeClaim delete | as B06, labelled "simulated disruption" (D11) |
| B08 | Dead letter after `fail-always` | the attempt has `RECEIVED-1` to `RECEIVED-3`, its message is in the DLQ, no `SUCCEEDED`. The number of Failed Jobs is not counted (`failedJobsHistoryLimit: 1` keeps one) |
| B09 | Second message → no second node | one Job and one NodeClaim |
| B10 | Pod without toleration | not on a batch node |
| B11 | Quotas (P5 audit §3.1) | separate rejections for `pods` and for `count/jobs.batch` at the D9 values, each denial message naming that resource, plus one Pod above `requests.cpu`. A generic error is `FAIL` |
| B12 | Cross-tenant bucket | an object that exists in tenant-a's bucket; **both** probes first report `caller_role_match=true` (tenant-a probe → `zero-drift-batch-tenant-a`, tenant-b probe → `zero-drift-batch-tenant-b`); then the tenant-a probe reads the object (positive control) and the tenant-b probe gets `AccessDenied` for get and put on the same key. A caller mismatch, `NoSuchBucket`, a timeout or any other code is `FAIL` |
| B13 | KEDA and Karpenter identity limits | simulation (`batch_iam_check.sh`) plus one denied real call each |
| B14 | IMDS from a batch Pod | the probe gets no token (hop limit 1) |

### P6-T4.2 — L3 window on EKS (4 h)

`docs/runbooks/P6_L3_WINDOW.md`. One window, approved separately:

- [ ] Bootstrap with `enable_rag_platform` and `enable_batch_platform`; platform
      sync; P5 guardrails on (Kyverno, NetworkPolicy).
- [ ] KEDA and Karpenter sync; NodePools. Both requests are disabled at this
      point. `window.sh annotate` and `window.sh batch-config`; check that
      `batch-config` has keys `queueUrl` and `region` (key names only). Purge
      the queue and the DLQ, wait **60 s after the last successful purge**
      (SQS deletes asynchronously for up to 60 s and allows one purge per
      60 s), then enable `tenant-a-batch` by PR.
- [ ] Suite order: B02–B05 on the first run, then B01, then B06–B14.
- [ ] Both tenants complete one run, one after the other; one run on On-Demand
      by pausing the Spot pool, labelled `on-demand`. The switch takes two PRs.
      PR 1 disables `tenant-a-batch` and sets the Spot pool's limit to 0. Then
      check: no ScaledJob and no Job of tenant-a remain, the queue shows
      `visible=0 inflight=0`, `batch-spot` reads `limits.cpu: "0"` from the
      cluster, and no NodeClaim exists. Only then PR 2 enables
      `tenant-b-batch`, so no tenant-a worker can receive and release a
      tenant-b message (D3) and no Spot node can start for it.
- [ ] Owner micro-lab: follow one NodeClaim from creation to termination.
- [ ] Smoke timings: sync, message, Job, NodeClaim, instance running, node Ready,
      image pulled, `TRAINING_STARTED`; scale-down time. Smoke values only.
- [ ] Teardown per §9.5; immediate inventory.

Stop conditions: those of P5, plus a batch node alive more than 15 minutes with
no batch Pod; a second batch node in one pool; capacity not obtained 20 minutes
after the Pod went pending (record `FAILED_CAPACITY`, never widen the allowlist
in the window); a NodeClaim that does not terminate 15 minutes after deletion;
gross reaching the window cap.

### P6-T4.3 — Acceptance (1.5 h)

- [ ] Audit `docs/evidence/p6/P6_ACCEPTANCE_AUDIT_<date>.md`: revisions,
      versions and digests, capacity and instance type of every run, scenario →
      evidence, limits.
- [ ] Delayed inventory and Bills gross read by the owner the next day.
- [ ] Second-agent review; owner teach-back on §7; learning status from
      demonstration only.

# 6. Verification tiers

| Tier | P6 use | Evidence |
|---|---|---|
| L0 | Unit tests, YAML/static checks, `terraform fmt/validate/test`, plan assertions, CI | commands, exit status |
| L1 | Rendered RGD and ScaledJob checked against the pinned CRDs | render output |
| L2 | kind: KEDA queue behaviour (ElasticMQ), resume (MinIO), kro graph with ScaledJob | run ID, predictions, observed |
| L3 | EKS: SQS, IRSA, Karpenter Spot and On-Demand, reclamation, negatives, teardown | approval, AWS and Kubernetes output, inventory |

# 7. Teach-back questions

1. A message is in the queue and nothing happens. Walk the chain and say what
   you check at each step.
2. Why does the worker delete the message at the end and not at the start? What
   happens to cost if it never deletes it?
3. KEDA created the Job. Why is there still no node, and which controller acts next?
4. A Spot node is reclaimed 3 minutes into a run. What does Karpenter do, what
   does the application do, and where does the run continue from?
5. Which guard actually stops a second batch node: quota, NodePool limit,
   `maxReplicaCount` or the tenant quota? What if one of them is wrong?
6. Pods are at zero and the node is gone. What still costs money?
7. The baseline keeps a node idle for 30 minutes. How does the length of the
   training run change the H5 result?
8. In what order do you remove Karpenter and its nodes, and what is left behind
   if you get it wrong?

# 8. P6 completion rule

P6 is complete when every scenario in §4 has L3 evidence on EKS with a node
created by Karpenter, both tenants have completed one run, reclamation is shown
on Kubernetes and on AWS, teardown and delayed inventory are clean, billing is
read, a second-agent review has recorded findings and limits, and the owner
reaches `PRACTICED` + `EXPLAINED` for SQS semantics, KEDA, Karpenter and
checkpointing. Every batch result is labelled `CPU_SUBSTITUTE_FOR_GPU`
(ADR-0009); no GPU claim is made.

# 9. Decisions, traceability and tracking

## 9.1. Decisions (D1–D14) — approved by the owner 25/11

Owner, 25/11, after Claude explained the decisions grouped by who should decide
(D1, D3, D10, D11, D14 as the owner's own calls; D13 already decided; D2, D4–D9,
D12 as technical choices): "duyệt". Every row below is approved as proposed.
The accepted limits carried into the thesis: soft isolation on the shared queue
(D3) and simulated, not real, Spot disruption (D11).

| ID | Decision | Proposal | Why | Alternative |
|---|---|---|---|---|
| D1 | Capacity | CPU only (ADR-0009). Batch NodePools allow `m6i.large`, `m5.large`, `c6i.large` (2 vCPU) in `us-east-1a`/`b` | Fits Standard quotas; three types raise Spot availability with one size, so trials stay comparable | `m6i.large` only (uniform, lower Spot availability) |
| D2 | Who owns the batch platform | Terraform: queue, DLQ, every role, Karpenter prerequisites, behind `enable_batch_platform`. Crossplane: only the per-request checkpoint bucket | One owner per resource (ADR-0003, ADR-0008); no new provider | `provider-aws-sqs` and a queue per request |
| D3 | Queue topology | One shared queue (ver3 §6.5). Bodies carry identifiers only. Both tenants' workers may receive from it; a foreign `requestId` is released, not deleted. Recorded as soft isolation. A release still counts as a receive toward `maxReceiveCount`, so the enabled request changes only after the queue has drained | Matches ver3; no tenant data in messages; a wrong tenant still cannot write the other's bucket | One queue per tenant |
| D4 | Meaning of `Ready` and the outcome | `Ready` = bucket Ready and submit Job complete. Outcome = `SUCCEEDED` marker and artifact in S3, read by the suite (B04); status carries the bucket and attempt as pointers | kro does not own the Jobs KEDA creates | A status-writer Job (more RBAC) |
| D5 | Concurrency | One enabled `BatchTrainingJob` at a time, enforced by `check.sh`; `maxReplicaCount: 1` | A shared queue cannot route a message to one ScaledJob; keeps one node per window | Queue per request |
| D6 | Karpenter IAM | IRSA (the cluster uses IRSA, no Pod Identity agent). Instance profile pre-created by Terraform and named in `EC2NodeClass.spec.instanceProfile`; release controller policy without the instance-profile statements; `iam:PassRole` for the node role only | Karpenter needs no IAM write; closes THREAT_MODEL §11 row | Let Karpenter manage the instance profile (upstream default) |
| D7 | NodePools | `batch-spot` (weight 100, Spot) and `batch-ondemand` (weight 10, On-Demand). Each: D1 types, taint `zero-drift.io/batch=true:NoSchedule`, label `zero-drift.io/pool=batch`, `limits.cpu: "2"` (one node), `consolidationPolicy: WhenEmpty`, `consolidateAfter: 60s`, `expireAfter: 2h`. `EC2NodeClass`: alias `al2023@<pinned>` matching the system node AMI release, IMDSv2 required with hop limit 1, encrypted gp3 20 Gi root, `associatePublicIPAddress: true`, project tags | Explicit capacity type per pool; the On-Demand run is forced by setting the Spot pool's limit to 0, not by editing labels; expiry needs no human | One pool with both capacity types (Karpenter picks Spot first) |
| D8 | Queue settings | Visibility timeout 120 s, heartbeat every 40 s; `maxReceiveCount` 3 to the DLQ; retention 1 h; purge at preflight, before any request is enabled | Redelivery within two minutes after a lost node; a failing run that has received its message cannot relaunch nodes forever; no stale message in a later window. The DLQ counts receives only: a Job that fails before `ReceiveMessage` (image pull, crash at start) is bounded by stop condition H5 of the window runbook, not by the DLQ | Long visibility timeout without heartbeat |
| D9 | Tenant quota and Pod size | Training container requests `500m` CPU, `384Mi` memory, memory limit `512Mi` (inside LimitRange max). Tenant quota raised by exactly one training Pod and its Jobs: `pods` 8→10, `requests.cpu` 400m→900m, `requests.memory` 768Mi→1152Mi, `limits.memory` 1536Mi→2048Mi, `count/jobs.batch` 4→6. GPU stays 0 | A14; smallest change that fits one run beside two sandboxes; the batch node is dedicated by taint, so the request only sizes the Pod | Separate batch namespace per tenant |
| D10 | Workload | NumPy logistic regression on synthetic data, `steps` from the request (default 300, about 5 min with a fixed per-step pause), checkpoint every 25 steps; image on GHCR by digest | Short, repeatable, small image (H2 pull time); no dataset, no licence | PyTorch CPU (GB image, closer to real training) |
| D11 | Disruption test | Operator deletes the Pod (B06) and the NodeClaim (B07) mid-run; labelled "simulated disruption" | A real Spot interruption cannot be ordered without AWS FIS (boundary 5) | AWS FIS (new service, extra cost) |
| D12 | Kind lab substitutes | ElasticMQ 1.7.1 for SQS, MinIO for S3, static lab keys in a lab Secret; never in `gitops/requests` | Same boto3 code path with `endpoint_url`; no AWS cost | LocalStack (larger, more services than needed) |
| D13 | Schedule | **Owner 25/11: rebaseline, P6 runs 25–26/11.** Overflow moves to 27/11, never cut. P7–P11 per ROADMAP "Rebaseline 25/11" | Owner directive 25/11; ver3 §12.1 forbids cutting trials, acceptance, learning gate or teardown | Keep 02/12 and cut P8 per the ADR-0009 cut order |
| D14 | P6 gross cap and windows | 4 USD for the window and retries; one window planned, a second only on new approval | §10 estimate about 2.5 USD for 5 h | — |

## 9.2. Traceability

| Source requirement | Covered by |
|---|---|
| ver3 §6.5 KEDA `ScaledJob` from a shared SQS queue | scenarios 2, 3; P6-T2.2; D3 |
| ver3 §6.5 Pod runs only on the Karpenter NodePool (CPU per ADR-0009) | scenarios 3, 7; D7 |
| ver3 §6.5 Spot first with On-Demand fallback | D7; P6-T4.2 On-Demand run |
| ver3 §6.5 application checkpoints to S3 | scenarios 3, 5; P6-T2.1 |
| ver3 §9.2 steps 1–5 | scenarios 2–4 |
| ver3 §10.1 checkpoint/artifact in S3 and node reclaimed | scenarios 3, 4; §8 |
| ver3 §11 quota, instance family and vCPU limits | scenario 1; D1, D7 |
| ver3 §12.1 Spot capacity rule | boundary 7; D7 |
| THREAT_MODEL §6.4 KEDA, Karpenter, batch ServiceAccount rows | scenario 8; P6-T3 |
| EXPERIMENT_PLAN §6 H2 end event and scale-down end event | P6-T2.1 marker; P6-T4.2 timings |
| P5 audit §3.1 object-count quota moved to P6 | B11 |
| ADR-0009 §2 label `CPU_SUBSTITUTE_FOR_GPU` | §0, §8 |
| DRF-19, DRF-20 | whole SPEC; split per §9.4 |

## 9.3. Independent review

The 25/11 recheck was done by Claude (Opus 5.5); it is not a second-agent review.

Codex review 25/11 (owner ran it on the uncommitted candidate): **REQUEST
CHANGES**, five HIGH and four MEDIUM findings. Claude applied all nine on 25/11:

| # | Finding | Applied in |
|---|---|---|
| 1 | Requests in a subfolder are never synced by `zdr-requests` | P6-T2.2 requests and `check.sh` |
| 2 | B01 before the ScaledJob exists passes without a scaler; submit could run before purge | §4 scenario 2, B01, P6-T4.2 order, D8 |
| 3 | Downward API cannot expose Node labels | P6-T2.1 marker, B04, boundary 7, §4 scenario 3 |
| 4 | Teardown: root self-heal, unguarded counts, `stopped` instances missed | §9.5, L3 runbook F |
| 5 | Duplicate submit and stale artifacts can make B04 pass | P6-T2.1 run key, `ALREADY_DONE`, B04 |
| 6 | `maxReceiveCount` counts receives; one Failed Job kept | P6-T2.1 `RECEIVED-<n>`, B08, D3, D8, §12 |
| 7 | B11 must name each quota; B12 needs an existing object and a real second tenant | B11, B12; platform-owned `batch-train` ServiceAccount |
| 8 | L2 `kubectl wait` by label; spike reads only one namespace | L2 runbook steps 5 and 8 |
| 9 | SPEC said kind runs every P5 guardrail | P6-T2.2 B, §12 |

Codex re-review 25/11 at `1c24bda`: **REQUEST CHANGES**. Seven of the nine
closed, 5 and 7 partly; five new findings (three HIGH, two MEDIUM). Claude
applied them on 25/11 (R3):

| # | Finding | Applied in |
|---|---|---|
| R1 | Submit role cannot read the marker; B04 passes with a failed delete; worker can start before `submitted` | P6-T2.1 submit order with `submit-started` and `READ_FAILED`, `MESSAGE_DELETED`; submit role in P6-T3; B04 |
| R2 | The RGD waits on a config object no step creates | `batch-config` ConfigMap and `window.sh batch-config` in P6-T2.2; P6-T4.2; L3 runbook B |
| R3 | Tenant switch races the old scaler and the Spot limit | two PRs with checks between them, P6-T4.2; L3 runbook E |
| R4 | `AccessDenied` can come from a wrong role; SA token mount | `serviceAccountName`, `automountServiceAccountToken: false`; `caller_role_match` in `probe` and B12 |
| R5 | Purge is asynchronous | 60 s wait after the last purge, P6-T4.2; L3 runbook B |

Codex round 3 at `2662398`: **REQUEST CHANGES**. R2, R4, R5 and old 7 closed;
R1, R3 and old 5 partly. Applied 25/11 (R4 of this SPEC):

| # | Finding | Applied in |
|---|---|---|
| C1 | E2 counted Jobs by a label KEDA does not set to `batch-train` | Job counts on `scaledjob.keda.sh/name` (P6-T2.2; L3 E2; L2 step 5) |
| C2 | A submit retry overwrote `submit-started` | conditional write, first value kept (P6-T2.1) |
| C3 | Submit role could list every object name | `ListObjectsV2` limited by `s3:prefix`, no `GetObject` (P6-T2.1, P6-T3) |
| C4 | `; echo` hid a failed read | `&& echo` (L3 runbook B) |

Codex round 4 at `fdedcac`: **APPROVE**. All earlier findings closed; no finding
blocks the owner's decision on D1–D14. Two LOW, non-blocking items are carried
into the implementation tasks:

| # | Item | Carried to |
|---|---|---|
| L1 | L2 step 5: `tail -1` can hide a failed Job read before `wait` | P6-T2.2 B: check the read succeeded and a Job name exists before `wait` |
| L2 | MinIO image in the lab not yet shown to honour `If-None-Match: *` | P6-T2.1 / T2.2: write the same key twice, expect `412` and the first value kept |

Review was read-only (Git Bash stubs for E2 and the ConfigMap check); no AWS,
EKS or kind run.

## 9.4. Linear tracking

Created on 25/11 at the owner's request (parents before sub-tasks). DRF-19 and
DRF-20 are cancelled as superseded, like DRF-18 in P5.

| Issue | Code | Title | Est. | Due |
|---|---|---|---|---|
| DRF-73 | P6-T1 | Hợp đồng P6: quyết định D1–D14, pin KEDA/Karpenter, giá | 2 h | 25/11 |
| DRF-74 | P6-T2 | Workload và đường request batch | parent | 26/11 |
| DRF-75 | P6-T2.1 | Ứng dụng training và image | 4 h | 25/11 |
| DRF-76 | P6-T2.2 | RGD BatchTrainingJob, KEDA và lab kind | 5 h | 26/11 |
| DRF-77 | P6-T3 | Terraform: batch platform và Karpenter | 6 h | 25/11 |
| DRF-78 | P6-T4 | Batch suite, window L3 và nghiệm thu P6 | parent | 26/11 |
| DRF-79 | P6-T4.1 | Batch suite | 1.5 h | 26/11 |
| DRF-80 | P6-T4.2 | Window L3 trên EKS | 4 h | 26/11 |
| DRF-81 | P6-T4.3 | Nghiệm thu P6 | 1.5 h | 27/11 (delayed inventory) |

## 9.5. Teardown order for a batch window

1. Remove or disable requests in Git; run `cleanup`; wait until ScaledJobs and Jobs are gone.
2. Pause automated sync of `zdr-root` first (its `selfHeal` would recreate a
   deleted child app), then delete the NodePools app with the cascade
   finalizer. The Karpenter controller stays up through this step. Pass only
   when **both** reads succeed and both are zero: NodeClaims from the
   Kubernetes API, and Karpenter-tagged instances on AWS in every state except
   `terminated` (`pending`, `running`, `stopping`, `stopped`, `shutting-down`;
   a `stopped` instance still bills its volume). A failed read is
   `READ_FAILED`, never `0`.
3. Delete the `EC2NodeClass`; then the Karpenter and KEDA applications.
4. P5, P4 and P3 teardown order as applicable (Kyverno before Argo CD).
5. `terraform destroy` (queues, roles, instance profile and access entry go with it).
6. Immediate inventory; delayed inventory the next day.

Karpenter-launched instances are **not** in Terraform state. If step 2 is
skipped, `terraform destroy` removes the cluster but leaves the instances
running and billing. The inventory counts Karpenter-tagged instances for that
reason.

# 10. Quota, cost and timing

Gross USD in `us-east-1`. Prices from COST_PLAN §5.2 (Price List API, 28/09);
rechecked in P6-T1. Durations are assumptions until the window.

| Quota | Applied | Needed at peak | State |
|---|---:|---:|---|
| Running On-Demand Standard | 8 vCPU (read 25/11) | 4 (system) + 2 (batch-ondemand) = 6 | fits |
| All Standard Spot | 5 vCPU (read 28/09) | 2 (batch-spot) | fits; reread |
| G/VT | 0 | 0 | out of scope (ADR-0009) |

| Item | Price |
|---|---:|
| Cluster + two `m6i.large` + RDS `db.t4g.micro`, P5 stack | about 0.45 USD/h (P5 window estimate, `P5_L3_WINDOW.md` §7) |
| `m6i.large` On-Demand + gp3 20 Gi + public IPv4 | 0.096 + 0.002 + 0.005 ≈ 0.103 USD/h |
| `m6i.large` Spot | unread; 0.04 USD/h is a sizing assumption only |
| SQS, EventBridge | requests in the thousands; below 0.01 USD |

Window estimate (5 h): stack 2.25 + batch nodes about 2 node-hours 0.2 ≈
**2.5 USD**. Cap D14: 4 USD.

H2 budget (target p95 ≤ 900 s, measured in P9): KEDA poll ≤ 10 s; Karpenter
launch to node Ready 1–3 min on CPU (no driver); image pull under 1 min for a
small image; process start seconds. The CPU path is expected well under the
target; that is a property of the substitute and is stated as such.

H5 (target ≥ 40 %): with 5 min of training, 3 min of overhead and the locked
30-minute idle window, On-Demand optimized vs baseline is (35 − 8) / 35 ≈ 77 %;
most of the saving comes from removing the idle window, not from Spot. The
report states this dependence (ver3 §15.2); the profile is locked in P7/P8.

# 11. Sources and dated facts

| # | Fact | Source | Checked | Status |
|---|---|---|---|---|
| S1 | KEDA v2.21.1 latest (15/11); v2.21 supports Kubernetes 1.34–1.36; chart `kedacore/keda` 2.21.1 (16/11) | [KEDA releases](https://github.com/kedacore/keda/releases), [cluster](https://keda.sh/docs/latest/operate/cluster/), [charts](https://github.com/kedacore/charts/releases) | 2026-11-25 | `SOURCE_VERIFIED`; digests at P6-T1 |
| S2 | KEDA 2.21.0 breaking change: service-account token audience enforcement (`boundServiceAccountToken` TriggerAuthentications) | KEDA release notes; [migration](https://keda.sh/docs/2.21/migration/) not read | 2026-11-25 | read migration page at P6-T1 |
| S3 | SQS scaler: `queueURL`, `queueLength` (default 5), `activationQueueLength`, `awsRegion`, `awsEndpoint`, `scaleOnInFlight` (true), `scaleOnDelayed` (false); auth `podIdentity.provider: aws` or static keys via `secretTargetRef`; docs say only "read properties" of the queue | [KEDA SQS scaler](https://keda.sh/docs/latest/scalers/aws-sqs/) | 2026-11-25 | `DOC_VERIFIED`; exact IAM action from the scaler source at P6-T1 |
| S4 | Karpenter v1.15.3 latest (20/11); Kubernetes 1.35 needs `>= 1.9`; chart `oci://public.ecr.aws/karpenter/karpenter` 1.15.3; empty selector terms now ignored | [releases](https://github.com/aws/karpenter-provider-aws/releases), [compatibility](https://karpenter.sh/docs/upgrading/compatibility/) | 2026-11-25 | `SOURCE_VERIFIED` |
| S5 | `EC2NodeClass` v1: `associatePublicIPAddress`, `role` or `instanceProfile`, `amiSelectorTerms` alias `al2023@<version>` exclusive, `metadataOptions`; NodePool `limits` (cpu, memory, nodes), `expireAfter`, `consolidationPolicy` `WhenEmpty`, `consolidateAfter`. No published KWOK image (build from source) | [NodeClasses](https://karpenter.sh/docs/concepts/nodeclasses/), [NodePools](https://karpenter.sh/docs/concepts/nodepools/), [kwok](https://github.com/aws/karpenter-provider-aws/tree/main/kwok) | 2026-11-25 | `DOC_VERIFIED` |
| S6 | ElasticMQ `softwaremill/elasticmq-native` 1.7.1 (= `latest`), SQS-compatible REST on 9324 | [Docker Hub](https://hub.docker.com/r/softwaremill/elasticmq-native/tags), [repo](https://github.com/softwaremill/elasticmq) | 2026-11-25 | `SOURCE_VERIFIED`; digest at P6-T1 |
| S7 | Standard On-Demand quota 8 vCPU | P5-T4.2 evidence, preflight | 2026-11-25 | `ACCOUNT_VERIFIED` then; reread at T−30 |
| S8 | `m6i.large` 0.096 USD/h; gp3 0.08 USD/GB-month; public IPv4 0.005 USD/h; EKS 0.10 USD/h | COST_PLAN §5.2 | 2026-09-28 | `PRICE_API_VERIFIED`; recheck |
| S9 | Spot price of D1 types | — | never read | `UNVERIFIED`; P6-T1 and T−30 |

# 12. Open risks

- **Orphaned instances.** Karpenter nodes are outside Terraform state (§9.5).
- **Stale message.** A message left in the queue launches a node as soon as the
  controllers come up. Retention 1 h, purge at preflight, the queue lives only
  for a window.
- **Message never deleted.** A worker bug makes KEDA start Job after Job; the
  DLQ bounds it to three receives. A Job that fails **before** it receives
  (image pull, crash at start) does not raise the receive count, so KEDA keeps
  creating Jobs; window stop condition H5 bounds that case.
- **Duplicate messages.** A submit that crashes between send and marker sends
  the same run key twice. `ALREADY_DONE` makes the second delivery harmless,
  and B04 reads only the current attempt's prefix.
- **Shared queue.** A tenant's worker can receive the other tenant's message
  (D3); it releases it. Soft isolation, recorded.
- **kro and KEDA Jobs.** The outcome is outside the graph (D4); kro leaves Job
  Pods behind (P4 spike); `cleanup` covers them.
- **P5 guardrails.** `restricted`, image digest, requests, tenant label, quota,
  default-deny all apply to the training Pod. The kind lab covers `restricted`,
  quota and LimitRange only; Kyverno and NetworkPolicy are first exercised in
  the L3 window, so a policy mismatch can still appear there.
- **Kyverno and Karpenter nodes.** Karpenter's own Pods run in `karpenter`, not
  a tenant namespace, so the fail-closed webhook does not block them.
- **Limits are eventually consistent.** Karpenter can briefly overshoot a
  NodePool limit; the account quota is the hard cap.
- **Logs disappear with the node.** Markers go to S3; the suite does not rely
  on `kubectl logs` after completion.
- **Schedule.** P6 in two days needs the kind lab and the window on 26/11; any
  overflow goes to 27/11 and shifts P7–P11 (D13).
