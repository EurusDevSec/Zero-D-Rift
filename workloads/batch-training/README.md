# batch-training — BatchTrainingJob reference workload

SPEC-P6 P6-T2.1 (DRF-75). One image, four entry points:
`python -m batchtraining submit|train|cleanup|probe`. The workload is synthetic
(D10): NumPy logistic regression, 512 samples × 8 features from a seed derived
from the request ID, checkpoint every 25 steps.

## Run key and S3 layout

Run key `tenant/requestId/runAttempt`. Everything of one attempt sits under
`runs/<requestId>/<runAttempt>/` in the tenant's checkpoint bucket:

| Key | Written by | Meaning |
|---|---|---|
| `submit-started` | submit, `If-None-Match: *` | freshness mark; the first value is kept on retry (412) |
| `submitted` | submit, after the send | read back by submit with `ListObjectsV2` only |
| `RECEIVED-<n>` | train | one per receive, n = SQS `ApproximateReceiveCount` |
| `TRAINING_STARTED` | train | `device=cpu`, run key, Pod, `spec.nodeName`, `resumed_from` |
| `ckpt/step-NNNNNN.json` | train | weights at step N (every `CHECKPOINT_EVERY`, and on SIGTERM) |
| `artifact/model.json` | train | final weights, loss, accuracy |
| `SUCCEEDED` | train | written before the message is deleted |
| `MESSAGE_DELETED` | train | only after a successful `DeleteMessage` |

No capacity type or instance type is recorded: the downward API cannot expose
Node labels; the suite reads them from the Node (SPEC-P6 boundary 7).

## Environment

| Variable | Used by | Default |
|---|---|---|
| `TENANT`, `REQUEST_ID` | submit, train, cleanup | required |
| `RUN_ATTEMPT` | submit (required), train (optional: then another attempt's message is released) | — |
| `STEPS` | submit | `300` (1–1000) |
| `BUCKET`, `QUEUE_URL` | submit, train; cleanup needs only `QUEUE_URL` | required |
| `FAIL_PROFILE` | train | `normal`; `fail-always` stops after `RECEIVED-<n>` |
| `CHECKPOINT_EVERY`, `STEP_SECONDS` | train | `25`, `1.0` |
| `HEARTBEAT_SECONDS`, `VISIBILITY_TIMEOUT` | train | `40`, `120` (D8) |
| `POD_NAME`, `NODE_NAME` | train | downward API |
| `AWS_REGION` | all | — |
| `S3_ENDPOINT_URL`, `SQS_ENDPOINT_URL` | kind lab only | unset on EKS; when set, S3 uses path-style |

The queue URL holds the account ID; it is never printed. AWS errors print the
error code only, never the message (an `AccessDenied` message names the ARN).

## Exit codes

`0` success (also `NO_MESSAGE`, `ALREADY_SUBMITTED`, `ALREADY_DONE`) · `1` failure ·
`2` invalid input or `READ_FAILED` · `3` foreign or malformed message released ·
`4` probe caller mismatch · `5` fail profile · `6` delete failed · `143` SIGTERM after checkpoint.

## Probe

```bash
python -m batchtraining probe s3-get --bucket B --key K --expect-role zero-drift-batch-tenant-a
python -m batchtraining probe s3-conditional --bucket B --prefix probe [--expect-role R]
python -m batchtraining probe imds
```

Output is `key=value` lines: `caller_role_match=true|false|READ_FAILED` first,
then `action`, `outcome`, `code`. A mismatch stops before the S3 call.

## Test, smoke, publish

```bash
bash workloads/batch-training/test.sh    # unit tests, in-memory SQS and S3
bash workloads/batch-training/smoke.sh   # hardened image on S3Mock + ElasticMQ
bash workloads/batch-training/lock.sh    # regenerate hashed requirements
```

Published by `.github/workflows/batch-training-image.yml` to
`ghcr.io/eurusdevsec/zero-d-rift/batch-training` on `main`; consumers pin
`@sha256`. Runbook: `docs/runbooks/P6_WORKER_IMAGE.md`.
