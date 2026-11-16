---
id: SPEC-P6
title: BatchTrainingJob — KEDA ScaledJob, Karpenter GPU NodePool, checkpoint and node reclamation
status: DRAFT_FABLE_20261116
phase: P6
start: TBD (owner rebaseline)
deadline: TBD (owner rebaseline)
schedule_baseline: ver3 §12 window 11–14/11 and the P6 gate of 14/11 already missed; owner rebaseline open
estimated_effort: 36-42 hours (ROADMAP allocates 32 h)
mode: Coach for SQS/KEDA/Karpenter (KEDA first, Karpenter CPU second, GPU last), then Pair
canonical_scope: docs/de_cuong_tot_nghiep_ver3.md
linear: DRF-19 (contract), DRF-20 (outcome); outline issues, split into P6-T tasks at the phase gate
authority: DRAFT_ONLY_NO_INSTALL_NO_AWS_NO_QUOTA_REQUEST_NO_LINEAR_CHANGE
drafted_from: main at df275e4 (2026-11-16); P4 and P5 runtime on EKS are UNVERIFIED
---

# 0. Draft status

Early draft written on 16/11/2026 at the owner's request. It is **not** the
active contract (AGENTS §7, `.agent/docs/FEATURES.md`). Before P6 starts: recheck
§2, refresh every dated fact in §12, let the second agent review the candidate
revision and get the owner's decisions on §9.1. Nothing in ver3 is reduced.

One item cannot wait for the phase gate and is listed first on purpose:
**the account's GPU quota is 0** for both On-Demand and Spot (§2 A1, §10.1).
Until both are raised, no GPU node can start and P6 cannot reach its exit
criterion. The request is free, changes no resource, and its lead time is not
under the project's control. It still needs the owner's explicit approval.

Per ver3 §12.1, until `RAGSandbox` runs end to end on EKS, Batch work stays a
skeleton. In this SPEC "skeleton" means: P6-T0, P6-T1, the worker code with unit
tests and the kind lab. No batch AWS window before P4 is accepted.

# 1. Goal and boundaries

## Goal

Deliver the second golden path on EKS. One `BatchTrainingJob` request, merged in
Git and synced by Argo CD, gives a tenant:

- a training run started by an event in a shared SQS queue through a KEDA
  `ScaledJob`;
- a GPU node provisioned on demand by Karpenter (Spot first, bounded On-Demand
  fallback) and used only by that run;
- checkpoints and a final artifact in the tenant's own S3 bucket, written by the
  application, so that an interrupted run resumes;
- an observable outcome, and a GPU node that is terminated after the run.

This is the ver3 §12 exit criterion for P6: "Batch end-to-end, checkpoint và thu
hồi Pod/GPU node có evidence". Runs in P6 are smoke runs (`official=false`); H2,
H3, H5 and scale-down time are measured in P9.

## MUST deliverables

- `SPEC-P6` approved by the owner with decisions D1–D15 (§9.1) resolved, and an
  ADR recording ownership of the batch platform resources (SQS, Karpenter IAM,
  KEDA identity) and the GPU capacity guard. It closes the `UNVERIFIED` rows
  "Karpenter controller/node-role IAM boundary" (THREAT_MODEL §11) and
  `provider-aws-sqs` "Conditional" (VERSION_MATRIX §3).
- GPU quota evidence: applied values for both G/VT quotas at or above the
  requirement, read on the day of the window.
- Terraform: module `batch-platform` (queue, dead-letter queue, roles) and module
  `karpenter` (controller role, node role, instance profile, access entry,
  interruption queue, discovery tags), both off by default, with tests and plan
  assertions.
- Reference workload under `workloads/batch-training/`: one image, entry points
  `submit`, `train`, `cleanup`, pinned by digest.
- GitOps: KEDA, Karpenter and the NVIDIA device plugin as pinned Argo CD
  applications; `NodePool`s and `EC2NodeClass`; the `BatchTrainingJob`
  ResourceGraphDefinition; one valid request per tenant; disabled negative
  requests; static checks in CI.
- Verification scripts: outcome check (markers, checkpoint, artifact), GPU node
  lifecycle check on both Kubernetes and AWS, and the capacity-bound negatives.
- Runbook `docs/runbooks/P6_BATCH_TRAINING.md`: prepare, verify, retry, delete,
  teardown order, stop conditions, undo, "Tự thử".
- Evidence under `docs/evidence/p6/`: kind lab, CPU window, GPU window(s),
  positive and negative checks, inventory and cost.

## Negative boundaries

1. Do not launch a GPU instance before the quota evidence, a priced estimate at
   the On-Demand price and the owner's window approval exist.
2. Do not allow more than one GPU node at a time. No wildcard GPU family, no
   instance larger than the approved allowlist, no NodePool without `limits`
   and a node expiry (COST_PLAN §9).
3. Do not let Karpenter manage the system node group, and do not run the
   Karpenter controller on a node it provisions.
4. Do not give Karpenter rights to create or change IAM roles, policies or
   instance profiles. `iam:PassRole` is limited to the one node role.
5. Do not install a controller beyond KEDA, Karpenter and the NVIDIA device
   plugin: no GPU operator, no DRA driver, no DCGM exporter, no
   `provider-aws-sqs`, no cluster autoscaler, no AWS FIS.
6. Do not make Karpenter responsible for training state. Checkpoints are the
   application's job (ver3 §6.5).
7. Do not report a run on On-Demand as Spot, and do not count a CPU-profile run
   as a GPU run. Capacity type and device come from the node and the workload,
   not from the request.
8. Do not report `Synced`, a `Running` Pod or the instance's `Ready` as a
   training outcome. `Ready` means "submitted" (D4).
9. Do not train a real model, use a real dataset or call Bedrock. The workload
   is synthetic and short.
10. Do not put tenant data, account IDs, ARNs or queue URLs into Git, Linear,
    evidence or SQS message bodies.
11. Do not delete Karpenter, its NodePools or the cluster while a NodeClaim or a
    Karpenter-launched instance exists.
12. Do not run an AWS window without a separate execution approval, a fresh cost,
    identity and quota check, a stop time and a teardown owner.
13. Do not count a P6 run as an official H2, H3 or H5 trial.

# 2. Giả định từ phase trước (kiểm lại khi vào phase)

| # | Assumption | Source today | Recheck |
|---|---|---|---|
| A1 | Applied quota "Running On-Demand G and VT instances" = **0** and "All G and VT Spot Instance Requests" = **0** in `us-east-1` | COST_PLAN §7.3, `ACCOUNT_VERIFIED` 2026-09-28 | `aws service-quotas list-service-quotas` in the owner's session; quota codes in §12 S2 |
| A2 | Standard On-Demand vCPU quota 5 and Standard Spot vCPU quota 5 | COST_PLAN §7.3, 2026-09-28 | same command |
| A3 | P4 is accepted: `RAGSandbox` runs end to end on EKS (ver3 §12.1 gate for Batch) | not built | P4 acceptance audit |
| A4 | P5 is accepted: tenant namespaces enforce `restricted`, quota (GPU 0), default-deny NetworkPolicy and the Kyverno image/requests policies | SPEC-P5 draft | P5 acceptance audit; each of these constrains the batch Pod |
| A5 | kro v0.9.4 can hold a KEDA `ScaledJob` and a cross-namespace Job in one graph, and removes a renamed child as in the P4 spike | spike covered Job and ConfigMap only | P6-T1 part C on kind |
| A6 | Tenant identity pattern from ADR-0008 (Terraform pre-creates one role per tenant and workload type; Crossplane has no IAM right) carries over | ADR-0008, written for P4 | ADR for P6 |
| A7 | The Crossplane S3 provider role can be extended to a second bucket prefix without a second role | `rag-identity` module not written yet | module as merged in P4 |
| A8 | Node network baseline unchanged: public subnets, public IPv4, no NAT, S3 gateway endpoint with a bounded policy, IMDSv2 with hop limit 1 | ADR-0006, P2 cluster module | read the modules; the endpoint policy must admit every registry host used here |
| A9 | The cluster uses `authentication_mode = "API"`, so a Karpenter node role needs an access entry of type `EC2_LINUX` | `modules/cluster/main.tf` at `df275e4` | module as it is then |
| A10 | Two `m6i.large` system nodes have room for KEDA (three Pods), Karpenter (one) and the existing platform | SPEC-P5 §10 estimate | pod count and memory in the P5 window |
| A11 | The service-linked role for EC2 Spot exists in the account, or the owner approves creating it | never checked | `aws iam get-role --role-name AWSServiceRoleForEC2Spot` (read-only) |
| A12 | The P4 reference image pattern (public GHCR, built by GitHub Actions, pinned by digest) is accepted for a second image | SPEC-P4 D8 | owner decision D11 |
| A13 | GPU envelope 15 USD and one GPU node at a time | ver3 §11, COST_PLAN §4 and §9 | unchanged unless the owner says otherwise |

# 3. Learning objectives

By the end of P6 the owner should be able to:

1. Separate three scalers: KEDA creates Jobs from queue length, the scheduler
   places Pods, Karpenter creates nodes for Pods that cannot be placed.
2. Trace one message: SQS → KEDA → Job → pending Pod → NodeClaim → EC2 instance →
   kubelet → device plugin → container → S3, and say where each can stall.
3. Explain visibility timeout, at-least-once delivery and the dead-letter queue,
   and why the worker deletes the message only after success.
4. Explain why checkpointing belongs to the application and what Karpenter does
   and does not do when a Spot instance is reclaimed.
5. List every guard that keeps GPU spend bounded and say which one is
   authoritative.
6. Explain what the idle window of the baseline does to H5 before measuring it.

# 4. Acceptance scenarios

```gherkin
Scenario: Capacity is approved and bounded before any launch
  Given applied G/VT quotas read on the day, a priced estimate at the On-Demand price
        and an approved window
  Then the NodePools allow only the approved instance types, zones and one GPU node
  And every node carries an expiry and the project tags

Scenario: Events drive Jobs
  Given the shared queue is empty
  Then no training Job and no GPU node exists
  When exactly one message is sent
  Then exactly one training Job is created
  And no further Job is created while that message is in flight

Scenario: One request gives an observable outcome
  Given a merged BatchTrainingJob request in a tenant namespace
  When Argo CD syncs it
  Then kro creates the checkpoint bucket, the ServiceAccount, the ScaledJob and the submit Job
  And the instance reports Ready only after the bucket is Ready and the message is sent
  And Karpenter starts one GPU node of an approved type
  And the training process writes a TRAINING_STARTED marker that names a CUDA device
  And at least one checkpoint and the final artifact exist in the tenant's bucket
  And the Job completes and its message is gone from the queue

Scenario: The GPU node is reclaimed
  Given the training Job has completed
  Then within the scale-down stop no training Pod is running
  And the GPU Node is gone from Kubernetes
  And the EC2 instance is terminated and its volume is gone

Scenario: An interrupted run resumes
  Given a run that has written at least one checkpoint
  When its Pod or node is removed before completion
  Then the message becomes visible again and a new Job starts
  And training continues from the last checkpoint
  And one final artifact exists

Scenario: Failure is visible and bounded
  Given no GPU capacity, or a request whose training always fails
  Then the request never shows a successful outcome
  And the failing layer is visible in the Job, Pod, NodeClaim or queue
  And after the configured number of receives the message is in the dead-letter queue
  And no GPU node keeps running

Scenario: Capacity and placement are bounded
  When a second message arrives while a run is active
  Then no second GPU node is created
  And a Pod without the GPU toleration never lands on the GPU node
  And a GPU request above the tenant quota is rejected

Scenario: Identities are bounded
  Then the training Pod can use only its tenant's checkpoint buckets and the shared queue
  And tenant-a cannot read or write tenant-b's checkpoint bucket
  And the KEDA identity can only read queue attributes
  And the Karpenter identity cannot change IAM or touch the system node group
  And a Pod on the GPU node cannot obtain node credentials from the metadata service

Scenario: Delete and teardown are complete
  When a request is removed from Git and the cleanup is run
  Then its ScaledJob, Jobs, Pods, bucket and leftover messages are gone
  When NodePools, controllers, the batch platform and the bootstrap are removed in order
  Then inventory shows no instance, volume, launch template, queue, role or
       network interface outside the retain allowlist
```

# 5. Work breakdown

## P6-T0 — GPU quota and Spot prerequisites (0.5 h of work, unknown waiting time)

Owner action, needed as early as possible; independent of every other task.

- [ ] Read both G/VT quotas and the Standard quotas (read-only).
- [ ] Owner approves and files the two quota increase requests per D1.
      This is an account mutation; the agent does not file it.
- [ ] Read whether the EC2 Spot service-linked role exists; if not, the owner
      approves creating it.
- [ ] Record request IDs' status only as `PENDING`/`APPROVED`/`DENIED` with dates;
      no case ID or account data in Git.
- [ ] If a request is denied or still pending when P6-T4 is due, follow §10.1.

## P6-T1 — Contract: decisions, pins, prices and spike (5 h)

**A. SPEC, review, approval (1.5 h)** — recheck §2; second-agent review; owner
decides D1–D15 and the P6 gross cap; ADR drafted and accepted.

**B. Pins and prices (2 h)**

- [ ] KEDA, Karpenter, NVIDIA device plugin: release, Kubernetes 1.35 support,
      chart version, every image digest (§12 S3–S5).
- [ ] AL2023 NVIDIA AMI: the exact alias version Karpenter will resolve for
      Kubernetes 1.35; NVIDIA driver version; root volume size it needs.
- [ ] Prices from the Price List API for every instance type in the allowlist;
      Spot price history for the last 7 days per type and zone
      (`aws ec2 describe-spot-price-history`, read-only). §10.2 and COST_PLAN §5
      and §9 are updated if any value differs.
- [ ] Registry probe (`infra/terraform/scripts/registry_probe.sh`) for every
      registry host of the new images against the S3 endpoint policy.
- [ ] Karpenter controller policy for the pinned version, reduced per D6.
- [ ] VERSION_MATRIX gets a "P6 pins" section.

**C. kro spike on kind (1.5 h)** — same method as the P4 spike.

- [ ] A `ScaledJob` as a graph node: RGD becomes Active only when the KEDA CRDs
      exist; `readyWhen` on its Ready condition.
- [ ] Submit Job in `zdr-platform` named with `spec.runAttempt`; behaviour on
      retry as in the P4 spike.
- [ ] Optional (D4): a child whose field is written by another actor and read
      into instance status. If it fails, the documented outcome command is the
      contract and the status carries pointers only.

Gate: no code, image, Terraform or manifest change for P6 before part A is
approved.

## P6-T2 — Workload and request path (10 h)

### P6-T2.1 — Training application and image (4.5 h)

- [ ] `submit`: sends one message `{requestId, tenant, runAttempt, profile}` and
      nothing else; idempotent per attempt.
- [ ] `train`: receive one message; refuse a foreign `requestId` without deleting
      it; extend visibility on a timer; load the newest checkpoint if any; emit
      `TRAINING_STARTED` (one JSON line on stdout and one marker object in S3)
      only after the device check; train a small synthetic model for a fixed
      number of steps; checkpoint every K steps; write the final artifact and a
      success marker; delete the message; exit 0.
- [ ] On SIGTERM: write a checkpoint, leave the message, exit non-zero.
- [ ] Device check per D12: profile `gpu` fails unless a CUDA device is present.
      Profile `cpu-lab` is for kind and the CPU window and marks every marker
      `device=cpu`.
- [ ] `cleanup`: removes leftover messages of a request and old Job Pods.
- [ ] Unit tests with fakes for SQS and S3: resume, foreign message, SIGTERM,
      double delivery.
- [ ] Image: digest-pinned base, non-root, passes `restricted`; size recorded
      because pull time is part of H2.

### P6-T2.2 — RGD, KEDA objects, requests and kind lab (5.5 h)

**A. Manifests (3 h)**

- [ ] `gitops/platform/rgd/batch-training-job.yaml`: nodes `platformConfig`
      (externalRef), `bucket` (Crossplane), `serviceAccount`, `scaledJob`,
      `submit` (Job in `zdr-platform`). Status: queue name, bucket, run attempt,
      submit state, outcome or outcome pointer.
- [ ] `ScaledJob`: SQS trigger with queue length 1; `maxReplicaCount: 1`; polling
      interval fixed in Git; history limits; Job template with
      `activeDeadlineSeconds` 2,700, `backoffLimit: 0`, GPU limit 1, toleration
      and node selector for the GPU pool, `restricted` security context,
      requests and limits.
- [ ] `TriggerAuthentication` using the KEDA operator's own identity.
- [ ] Two valid requests and disabled negatives (unknown namespace, second
      active request, profile not allowed).
- [ ] `gitops/check.sh`: at most one enabled `BatchTrainingJob`; image digests;
      no queue URL or ARN; provider allowlist unchanged.
- [ ] Tenant quota raised for exactly one training Pod and one GPU; tenant
      NetworkPolicy allows the same egress shape as RAG without the database.

**B. L2 kind lab: KEDA behaviour without AWS (2.5 h)** — owner predicts first.

- [ ] KEDA on kind with a lab-only SQS-compatible queue (`labs/p6-kind/`).
- [ ] Zero messages → zero Jobs. One message → one Job. A message in flight →
      no second Job. Message never deleted → what KEDA does after the visibility
      timeout.
- [ ] `cpu-lab` profile end to end against lab object storage or a fake.
- [ ] Kill the Pod mid-run; observe redelivery and resume.

Evidence: `docs/evidence/p6/P6-T2.2_L2_KIND_KEDA_<date>.md`. kind proves nothing
about SQS, IRSA, Karpenter, EC2 or GPUs.

## P6-T3 — Terraform: batch platform and Karpenter prerequisites (7 h)

**A. Module `batch-platform` (3 h)**

- [ ] Queue and dead-letter queue: short retention, visibility timeout and
      `maxReceiveCount` per D8, service-managed encryption, project tags.
- [ ] Roles (IRSA, exact subject and audience unless stated): KEDA operator
      (read attributes of the one queue); `batch-submit` in `zdr-platform`
      (send to the one queue); `zero-drift-batch-tenant-a` and `-tenant-b`
      (receive, delete, change visibility on the queue; list, get, put on that
      tenant's `zero-drift-batch-<tenant>-*` buckets).
- [ ] Crossplane S3 role: second bucket prefix (A7).
- [ ] Root flag `enable_batch_platform` (default false).

**B. Module `karpenter` (2.5 h)**

- [ ] Controller role, node role, instance profile created here and referenced
      by name; access entry for the node role; interruption queue and its event
      rules; discovery tags on the subnets and the node security group.
- [ ] No Karpenter permission on IAM beyond `iam:PassRole` for the node role.

**C. Guards and inventory (1.5 h)**

- [ ] `plan_assert.sh` behind `P6_WINDOW=1`, each with a synthetic-plan guard
      test: no wildcard resource, exact action allowlists, no IAM write for
      Karpenter, tenant-a cannot name a tenant-b bucket, platform roles not
      assumable from a tenant namespace, queue not public.
- [ ] IAM simulation script: allowed and denied matrix for the new roles.
- [ ] `inventory.sh` learns Spot requests, Karpenter-tagged instances and launch
      templates, P6 queues, buckets and roles. Counts only.

## P6-T4 — L3 windows on EKS (11 h)

Prerequisites: P4 accepted; P5 accepted; P6-T2 and P6-T3 merged; kind lab PASSED.
GPU windows also need P6-T0 approved quotas. The RAG platform stays off in these
windows unless the owner wants a regression check.

### P6-T4.1 — Window 1: KEDA and Karpenter on CPU, no GPU (3.5 h)

- [ ] Window request and approval as in P4.
- [ ] Platform plus KEDA and Karpenter; real SQS queue.
- [ ] CPU `NodePool` on Standard Spot quota, one small node, same limits and
      expiry pattern as the GPU pool.
- [ ] `cpu-lab` request end to end: message → Job → pending Pod → NodeClaim →
      node → marker → checkpoint → completion → node gone on Kubernetes and AWS.
- [ ] Interruption drill: remove the node mid-run; resume from checkpoint.
- [ ] Negatives that need no GPU: second message, foreign `requestId`,
      dead-letter queue, cross-tenant bucket, KEDA and Karpenter identity limits.
- [ ] Teardown; inventory.

This window proves the mechanism and is the owner's Karpenter micro-lab. It is
not GPU evidence.

### P6-T4.2 — Window 2: GPU bring-up (3.5 h)

- [ ] Fresh quota read; window request priced at the On-Demand rate.
- [ ] Device plugin; GPU `NodePool`s per D7.
- [ ] One `gpu` request. Record each step time: sync, message, Job, NodeClaim,
      instance running, node Ready, GPU allocatable, image pulled,
      `TRAINING_STARTED`. These are smoke values for the H2 budget in §10.3.
- [ ] Reclamation on both sides: Pod gone, Node gone, instance terminated, volume
      gone. Record the scale-down time as a smoke value.
- [ ] Owner-typed micro-lab: follow one NodeClaim from creation to termination.

### P6-T4.3 — Window 3: full scenarios, negatives, teardown (4 h)

- [ ] Both tenants, one request each, one after the other.
- [ ] Interruption drill on GPU (simulated disruption, labelled as such).
- [ ] Capacity negatives: second message, tenant GPU quota, Pod without
      toleration, non-GPU Pod.
- [ ] On-Demand fallback exercised once if the window approval includes it; the
      run is labelled `on-demand`.
- [ ] Metadata check from a Pod on the GPU node.
- [ ] Delete, cleanup, teardown in the order of §9.4; immediate inventory.

Stop conditions for every window: those of SPEC-P4, plus: a GPU node alive more
than 15 minutes with no training Pod on it; a second GPU instance; capacity not
obtained 20 minutes after the Pod went pending (record `FAILED_CAPACITY`, do not
widen the allowlist in the window); GPU spend in the window reaching its sub-cap;
a NodeClaim that does not terminate 15 minutes after deletion.

## P6-T5 — Acceptance: evidence, review, teach-back (3 h)

- [ ] Acceptance audit in `docs/evidence/p6/`: run IDs, revisions, versions and
      digests, capacity type and instance type of every run, scenario → evidence,
      limits (smoke values, simulated disruption, fallback use).
- [ ] Delayed inventory and billing read by the owner; GPU ledger updated.
- [ ] Independent review by the second agent.
- [ ] Owner teach-back on §7; learning status from demonstration only.

# 6. Verification tiers

| Tier | P6 use | Evidence |
|---|---|---|
| L0 | Unit tests, YAML/static checks, Terraform fmt/validate/test, plan assertions, CI | commands, exit status |
| L1 | Rendered RGD and ScaledJob checked against the pinned CRDs | render output |
| L2 | kind: kro graph with ScaledJob, KEDA queue behaviour, resume | run ID, predictions, observed |
| L3 | EKS: SQS, IRSA, Karpenter CPU then GPU, device plugin, reclamation, negatives, teardown | approval, manifest, AWS and Kubernetes output, inventory |

# 7. Teach-back questions

1. A message is in the queue and nothing happens. Walk the chain and say what
   you check at each step.
2. Why does the worker delete the message at the end and not at the start? What
   happens to cost if it never deletes it?
3. KEDA scaled the Job. Why is there still no node, and which controller acts next?
4. A Spot node is reclaimed 3 minutes into a run. What does Karpenter do, what
   does the application do, and where does the run continue from?
5. Which guard actually stops a second GPU node: quota, NodePool limit,
   `maxReplicaCount` or the tenant quota? What if one of them is wrong?
6. Pods are at zero and the GPU node is gone. What still costs money?
7. The baseline keeps a node idle for 30 minutes. How does the length of the
   training run change the H5 result?
8. In what order do you remove Karpenter and its nodes, and what is left behind
   if you get it wrong?

# 8. P6 completion rule

P6 is complete only when every scenario in §4 has L3 evidence on EKS with a real
GPU node, both tenants have completed one run, the node reclamation is shown on
Kubernetes and on AWS, teardown and delayed inventory are clean, billing is read,
an independent review has recorded findings and limits, and the owner reaches
`PRACTICED` + `EXPLAINED` for SQS semantics, KEDA, Karpenter and checkpointing.
A CPU-only result does not complete P6; it is recorded as the mechanism working
with the GPU part open (§10.1).

# 9. Decisions, traceability and tracking

## 9.1. Decisions for the owner (D1–D15) — proposals, not approved

| ID | Decision | Proposal | Why | Alternative |
|---|---|---|---|---|
| D1 | GPU quota request | 4 vCPUs for On-Demand G/VT and 4 vCPUs for Spot G/VT in `us-east-1`; filed by the owner as soon as approved | One `xlarge` GPU instance is 4 vCPUs; the quota itself becomes the hard cap of one node per capacity type. Both are needed: Spot for the optimized arm, On-Demand for the H5 baseline and the fallback | 8 each (room for a replacement node during disruption, weaker cap) |
| D2 | Who owns the batch platform | Terraform: queue, dead-letter queue, every role, Karpenter prerequisites, behind `enable_batch_platform`. Crossplane: only the per-request checkpoint bucket | One owner per resource (ADR-0003); same reasoning as ADR-0008; no new provider CRDs | `provider-aws-sqs` and a queue per request |
| D3 | Queue topology | One shared queue for the PoC, as ver3 §6.5 says. Message bodies carry identifiers only. Both tenants' workers can receive from it; recorded as a soft-isolation limit | Matches ver3; no tenant data in messages; a wrong tenant cannot write the other's bucket | One queue per tenant (two queues; stronger, small deviation from ver3 wording) |
| D4 | Meaning of `Ready` and the outcome | `Ready` = bucket Ready and message submitted. Outcome = success marker and final artifact in S3, shown in status if the spike of P6-T1 C works, otherwise by a documented command | kro does not see Jobs that KEDA creates | A status-writer Job (more RBAC) |
| D5 | Concurrency | One enabled `BatchTrainingJob` at a time in the PoC, enforced by the static check; `maxReplicaCount: 1` | One GPU node at a time (COST_PLAN §9); a shared queue cannot route messages to a specific ScaledJob | Queue per request |
| D6 | Karpenter IAM | Instance profile pre-created by Terraform and named in the `EC2NodeClass`; controller policy from the pinned release with the instance-profile and role statements removed; `iam:PassRole` for the node role only; identity through IRSA | Closes the THREAT_MODEL row; Karpenter needs no IAM write | Let Karpenter manage the instance profile (upstream default) |
| D7 | NodePools | `gpu-spot` (higher weight, Spot) and `gpu-ondemand` (lower weight, On-Demand, `g4dn.xlarge` only). Each: allowlisted types, two zones, GPU taint, limits of one node and one GPU, consolidation when empty after a fixed delay, node expiry of 2 h. `EC2NodeClass`: pinned AL2023 NVIDIA AMI alias, IMDSv2 hop limit 1, encrypted gp3 root, public IPv4, project tags | Explicit capacity type per pool; the On-Demand pool can be left out of a window; expiry is a cost guard that needs no human | One pool with both capacity types |
| D8 | Queue settings | Visibility timeout 180 s extended by a worker heartbeat; `maxReceiveCount` 3 to the dead-letter queue; retention 1 h; purge at preflight | Redelivery within minutes after a lost node; a failing run cannot relaunch GPUs forever; no stale message in a later window | Long visibility timeout without heartbeat |
| D9 | Spot instance types | Start with `g4dn.xlarge` only. Add `g5.xlarge` and `g6.xlarge` to the Spot pool only if P6-T1 B prices them and the window cap is recomputed | Cheapest priced type; more types raise Spot availability but also the worst-case price and vary the instance across trials | Three types from the start |
| D10 | Fallback | The On-Demand pool exists; every GPU window is priced and approved at the On-Demand rate, so a fallback stays inside the cap. Each run records its real capacity type | ver3 §6.5 and §12.1 | No fallback in P6; add it in P8 |
| D11 | Workload and image | Small PyTorch model on synthetic tensors, about 5 minutes on one T4, checkpoint every K steps; image public on GHCR by digest | Short, repeatable, shows GPU use; no dataset, no licence issue | A minimal CUDA program without a framework (smaller image, less like training) |
| D12 | Proof of GPU use | `TRAINING_STARTED` and the success marker carry the device name; profile `gpu` fails without CUDA | H2 ends at a GPU training process, not at `Running` | Trust the resource limit |
| D13 | GPU device management | NVIDIA device plugin DaemonSet on GPU nodes only | The AL2023 NVIDIA AMI ships drivers and toolkit but not the plugin (§12 S6); the plugin gives `nvidia.com/gpu` | DRA driver (recommended by AWS for new work, needs Karpenter 1.15+ feature gates) |
| D14 | Disruption test | Operator removes the Pod or the NodeClaim mid-run; labelled "simulated disruption" | A real Spot interruption cannot be ordered without AWS FIS | AWS FIS Spot interruption action (new service, extra cost) |
| D15 | P6 gross cap and windows | 8 USD for all P6 windows and retries, of which at most 3 USD GPU; three windows planned, a fourth only on new approval | §10.2 | — |

## 9.2. Traceability

| Source requirement | Covered by |
|---|---|
| ver3 §6.5 KEDA `ScaledJob` from a shared SQS queue | scenario 2 and 3; P6-T2.2 |
| ver3 §6.5 Pod requests GPU and runs only on the Karpenter GPU NodePool | scenario 3 and 7; D7 |
| ver3 §6.5 Spot first with On-Demand fallback | D7, D10; P6-T4.3 |
| ver3 §6.5 application checkpoints to S3 | scenario 3 and 5; P6-T2.1 |
| ver3 §9.2 steps 1–5 | scenarios 2–4 |
| ver3 §10.1 checkpoint/artifact in S3 and GPU node reclaimed | scenarios 3 and 4; §8 |
| ver3 §11 quota, instance family and total GPU vCPU limits | scenario 1; D1, D7; §10.2 |
| ver3 §12.1 Spot capacity rule | negative boundary 7; D10; §10.1 |
| THREAT_MODEL §6.4 KEDA, Karpenter and batch ServiceAccount rows | scenario 8; P6-T3 |
| EXPERIMENT_PLAN §6 H2 end event and scale-down end event | D12; P6-T4.2 |
| DRF-19 (queue, checkpoint, GPU quota, lifecycle) | P6-T0, P6-T1, P6-T3 |
| DRF-20 (outcome, checkpoint, node reclamation) | P6-T2, P6-T4, P6-T5 |

## 9.3. Independent review

Not done. This draft has had no second-agent review and no owner approval.

## 9.4. Teardown order for a batch window

1. Remove requests from Git; run `cleanup`; wait for ScaledJobs and Jobs to go.
2. Confirm zero NodeClaims and zero Karpenter-launched instances **on AWS**.
3. Remove NodePools and the EC2NodeClass; then Karpenter, KEDA and the device
   plugin.
4. P5, P4 and P3 teardown order as applicable.
5. `terraform destroy` (queues and roles go with it).
6. Immediate inventory; delayed inventory the next day.

# 10. Quota, cost and timing analysis

All money figures are gross USD in `us-east-1`. Prices come from COST_PLAN §5.2
(Price List API, 2026-09-28) unless marked; every one is rechecked in P6-T1 B.
Durations are planning assumptions until P6-T4.2 replaces them with observed
values. Nothing here is a result.

## 10.1. Quota: the critical path

| Quota | Applied today | Needed | State |
|---|---:|---:|---|
| Running On-Demand G and VT instances | 0 vCPU | 4 vCPU | `BLOCKED_BY_QUOTA` |
| All G and VT Spot Instance Requests | 0 vCPU | 4 vCPU | `BLOCKED_BY_QUOTA` |
| Running On-Demand Standard instances | 5 vCPU | 4 vCPU (two `m6i.large`) | fits; one vCPU spare |
| All Standard Spot Instance Requests | 5 vCPU | 2 vCPU (CPU lab node) | fits |

Read-only check the owner can type:

```bash
aws service-quotas list-service-quotas --service-code ec2 --region us-east-1 \
  --query "Quotas[?contains(QuotaName, 'G and VT') || contains(QuotaName, 'Standard')].[QuotaName,QuotaCode,Value]" \
  --output table
```

The increase request is `aws service-quotas request-service-quota-increase`
with the quota code and the desired value. It is an account mutation and is run
only by the owner after approving D1.

What is not known: how long AWS takes, and whether an account that runs on
promotional credit with almost no billing history gets a GPU quota at all. The
plan therefore has an explicit ladder. Each rung is the owner's decision; none
may be taken silently, and none changes a label.

| Outcome of the requests | Consequence | What can still be claimed |
|---|---|---|
| Both approved | Plan as written | everything |
| On-Demand approved, Spot denied or pending | Functional runs and the H5 baseline run on On-Demand. Optimized arms run on On-Demand and are labelled so | H2, H3, scale-down time. H5 as a Spot claim is **not** supported; the saving from removing the idle window alone can be reported as its own, differently named observation |
| Spot approved, On-Demand denied | Optimized arms run; no fallback; the H5 baseline arm cannot run | H2/H3 if Spot capacity holds; H5 `INCONCLUSIVE` |
| Both denied or pending past the rebaselined date | Window 1 (CPU) still proves the KEDA and Karpenter mechanism. The GPU part of P6, H2, H5 and the GPU scale-down metric stay open | Mechanism on CPU only. Any substitute for the GPU requirement is a scope change that needs the owner, the supervisor and an ADR (ver3 §15.2); this SPEC does not propose one |

Moving to another Region does not help by itself: quotas are per Region and the
Terraform root accepts only `us-east-1`.

## 10.2. Cost

Unit prices used:

| Item | Price | Source |
|---|---:|---|
| `g4dn.xlarge` On-Demand (4 vCPU, 16 GiB, one T4) | 0.526 USD/h | COST_PLAN §5.2 |
| GPU node root volume, gp3 50 GB | 0.0055 USD/h | 50 × 0.08 / 730 |
| Public IPv4 | 0.005 USD/h | COST_PLAN §5.2 |
| **GPU node, On-Demand, all in** | **0.537 USD/h** | sum |
| GPU node on Spot | unknown | must be read from Spot price history; **0.22 USD/h is a sizing assumption only** (about 40 % of On-Demand) |
| Cluster with two `m6i.large`, no RDS | 0.309 USD/h | 0.10 + 2 × (0.096 + 0.005 + 0.0033) |
| `g5.xlarge`, `g6.xlarge` | not looked up | recalled as roughly 2× and 1.5× the `g4dn.xlarge` price; `UNVERIFIED` |

Time model per run (assumptions): provisioning to training start plus
termination about 10 minutes; training 5 minutes; baseline idle window
30 minutes (EXPERIMENT_PLAN §5.4, locked).

| Run type | Node time | On-Demand | Spot (assumed) |
|---|---:|---:|---:|
| Optimized run (KEDA + Karpenter) | 0.25 h | 0.134 USD | 0.055 USD |
| Baseline arm (On-Demand, always on through the idle window) | 0.75 h | 0.402 USD | — |

P6 windows:

| Window | Cluster | GPU (worst case, On-Demand) | Estimate |
|---|---:|---:|---:|
| 1 — CPU lab, 3 h | 0.93 | 0 (CPU Spot node ≈ 0.10) | 1.0 |
| 2 — GPU bring-up, 4 h | 1.24 | ≤ 2 h → 1.07 | 2.3 |
| 3 — full scenarios, 4 h | 1.24 | ≤ 2 h → 1.07 | 2.3 |
| **Total** | 3.4 | 2.1 | **5.6** |

Proposed cap (D15): 8 USD, GPU part at most 3 USD, which is 5.6 GPU-hours at the
On-Demand rate (COST_PLAN §9 formula: remaining GPU envelope ÷ hourly price).

GPU envelope across the remaining phases (ver3 §11: 15 USD), worst case with
every optimized run on On-Demand:

| Phase | GPU use | Worst case |
|---|---|---:|
| P6 | bring-up and scenarios | 3.0 |
| P7 | one smoke under metrics, one manual-baseline dry run | 1.0 |
| P8 | pilot: two H2 runs and one cost pair | 1.0 |
| P9 | 20 optimized runs (2.68) + 5 baseline arms (2.01) + 25 % for replacement trials | 5.9 |
| **Total** | | **10.9 of 15** |

About 4 USD stays free, which is 7.6 On-Demand GPU-hours. With Spot at the
assumed price the P9 line drops to about 3.9. COST_PLAN §5.3 planned 20 GPU-hours
(10.63 USD); this model is consistent with it. If a larger instance type joins
the allowlist (D9), every line is recomputed before approval.

Guards on GPU spend, from strongest to weakest:

1. Account quota of 4 vCPUs per capacity type (D1) — enforced by AWS.
2. NodePool allowlist of types and zones; `limits` of one node and one GPU —
   enforced by Karpenter, eventually consistent (§12 S4).
3. Node expiry of 2 h — a node dies even if everything else hangs.
4. `maxReplicaCount: 1`, one enabled request, tenant GPU quota of 1.
5. Job deadline of 2,700 s; dead-letter queue after 3 receives.
6. Window stop time, the stop conditions of P6-T4 and the inventory.
7. Budget alerts — late by design; not a guard for a single window.

## 10.3. What the model says about H2 and H5 before any measurement

H2 (`TARGET` p95 ≤ 900 s from Argo observing the request to `TRAINING_STARTED`).
Expected stages, all `ASSUMPTION` until P6-T4.2:

| Stage | Assumed | Depends on |
|---|---:|---|
| kro graph, bucket Ready, message sent | 0.5–1.5 min | Crossplane, S3 API |
| KEDA sees the message, creates the Job | ≤ polling interval | value fixed in Git |
| Karpenter launches; instance running; node Ready | 2–5 min | capacity, AMI boot, driver load |
| Device plugin Pod ready; GPU allocatable | 0.5–1.5 min | plugin image pull |
| Training image pull | 1–4 min | image size; a framework image is several GB |
| Process start and device check | < 0.5 min | — |

The sum is about 5–12 minutes when capacity is available, so the target is
plausible but not safe. The image size and the KEDA polling interval are the two
parts under the project's control; both are fixed before the campaign freeze
and not tuned afterwards. A Spot capacity error costs minutes before the
fallback pool is tried and can push a trial past the target or the 1,800 s
timeout; that is a valid result, not an exclusion.

H5 (`TARGET` ≥ 40 % lower variable compute cost). In the time model above:

| Comparison | Saving ratio |
|---|---:|
| Optimized on Spot (assumed price) vs baseline | (0.402 − 0.055) / 0.402 ≈ 86 % |
| Optimized on On-Demand vs baseline | (0.402 − 0.134) / 0.402 ≈ 67 % |

The second line shows that most of the saving comes from removing the idle
window, not from the Spot discount. It also shows the result depends on the
locked profile: with the same 10-minute overhead and 30-minute idle window, an
On-Demand-only comparison stays above 40 % only while the training run is
shorter than about 35 minutes. The report must state this dependence. The
profile (run length, idle window, instance type) is locked in P7 and frozen in
P8 before any cost is seen, and is not changed afterwards (ver3 §15.2).

# 11. Open risks

- **GPU quota** (§10.1). The largest schedule risk in the project.
- **Spot capacity.** A single type in two zones can be unavailable for long
  stretches. D9 trades availability against price and trial uniformity.
- **Orphaned instances.** If Karpenter is removed before its nodes, the
  instances keep running and billing with nothing left to stop them. §9.4 and
  the AWS-side inventory are the control.
- **Stale message.** A message left in the queue launches a GPU node as soon as
  the controllers come up. Short retention, purge at preflight and queues that
  live only for a window are the controls.
- **Message never deleted.** A bug in the worker makes KEDA start Job after Job.
  The dead-letter queue bounds it to three launches.
- **Image size against H2** (§10.3).
- **Registry reachability.** Device plugin, KEDA and Karpenter images come from
  registries not used in P3/P4; the S3 endpoint policy may block a redirect.
- **kro and Jobs created by KEDA.** The outcome is outside the graph (D4). The
  P4 spike found that kro leaves Job Pods behind; the submit Job has the same
  issue and `cleanup` must cover it.
- **Guardrails from P5.** Pod Security `restricted`, the image policy, the GPU
  quota and default-deny egress all apply to the training Pod. Each is tested
  in `Audit` first.
- **Limits are eventually consistent.** Karpenter can briefly overshoot a
  NodePool limit; the account quota is the real cap.
- **Node clock.** The `TRAINING_STARTED` time comes from the node. The clock
  check of EXPERIMENT_PLAN §11.2 (2 s) must include a freshly booted GPU node.
- **Logs disappear with the node.** Pod logs are gone once the node is
  terminated. Markers are written to S3 for that reason; the harness must not
  depend on `kubectl logs` after completion.
- **Shared queue.** A tenant's worker can receive or delete the other tenant's
  message (D3). Soft isolation; recorded, not hidden.
- **Schedule.** P6 starts after its gate; the rebaseline is the owner's.

# 12. Sources and dated facts (recheck at P6-T1)

| # | Fact | Source | Checked | Status |
|---|---|---|---|---|
| S1 | G/VT On-Demand and Spot quotas are 0; Standard quotas are 5 | COST_PLAN §7.3 | 2026-09-28 | `ACCOUNT_VERIFIED` then; recheck |
| S2 | Quota codes `L-DB2E81BA` (On-Demand G and VT) and `L-3819A6DF` (Spot G and VT) | author's recollection | not looked up | `UNVERIFIED`; read them from `list-service-quotas` |
| S3 | KEDA latest release `v2.21.1`; matrix candidate `v2.21.0` tested on Kubernetes 1.34–1.36 | [KEDA releases](https://github.com/kedacore/keda/releases); VERSION_MATRIX §2 | 2026-11-16; 2026-09-25 | `SOURCE_VERIFIED`; pin at P6-T1 |
| S4 | Karpenter latest release `v1.15.2`; matrix candidate `v1.14.1` LTS. Spot is tried before On-Demand; an unavailable offering is cached for three minutes; `limits` are eventually consistent; `weight` orders NodePools; consolidation policies `WhenEmpty`, `WhenEmptyOrUnderutilized`, `Balanced` | [Karpenter releases](https://github.com/aws/karpenter-provider-aws/releases), [NodePools](https://karpenter.sh/docs/concepts/nodepools/) | 2026-11-16 | `DOC_VERIFIED` for the latest docs; recheck against the pinned version |
| S5 | `EC2NodeClass`: `instanceProfile` means Karpenter does not manage the profile; default metadata options are `httpTokens: required`, hop limit 1; default AL2023 root volume 20 Gi gp3 | [Karpenter NodeClasses](https://karpenter.sh/docs/concepts/nodeclasses/) | 2026-11-16 | `DOC_VERIFIED`; whether the `al2023` alias selects the NVIDIA variant for GPU types is `UNVERIFIED` |
| S6 | AL2023 x86_64 NVIDIA AMI supports `g4dn`, `g5`, `g6`; includes driver and container toolkit; does **not** include the NVIDIA device plugin or DRA driver; kernel 6.12 for Kubernetes 1.33–1.35 | [EKS accelerated AMIs](https://docs.aws.amazon.com/eks/latest/userguide/ml-eks-optimized-ami.html), [NVIDIA GPUs on EKS](https://docs.aws.amazon.com/eks/latest/userguide/device-management-nvidia.html) | 2026-11-16 | `DOC_VERIFIED` |
| S7 | KEDA SQS scaler defaults: `queueLength` 5, `scaleOnInFlight` true, `scaleOnDelayed` false; `identityOwner` deprecated; pod identity provider `aws` | [KEDA AWS SQS scaler 2.21](https://keda.sh/docs/2.21/scalers/aws-sqs/) | 2026-11-16 | `DOC_VERIFIED`; the exact IAM action is not named there — confirm |
| S8 | `g4dn.xlarge` 0.526 USD/h; gp3 0.08 USD/GB-month; public IPv4 0.005 USD/h; `m6i.large` 0.096 USD/h; EKS 0.10 USD/h | COST_PLAN §5.2 | 2026-09-28 | `PRICE_API_VERIFIED`; recheck |
| S9 | Spot price for any GPU type | — | never read | `UNVERIFIED`; `describe-spot-price-history` at P6-T1 and before each window |
| S10 | NVIDIA device plugin version and image | — | not looked up | `UNVERIFIED`; pin at P6-T1 |
| S11 | Size of a CUDA framework image; GPU node boot time | — | not measured | `ASSUMPTION`; measured in P6-T4.2 |
