#!/usr/bin/env bash
# LAB ONLY (DRF-76): short commands for docs/runbooks/P6_L2_KIND_KEDA.md.
# Reads ElasticMQ and S3Mock through the toolbox Pod in zdr-lab (the worker
# image, so the same boto3 code path). Prints counts and object keys only.
#   batch.sh setup            lab Secret lab-aws in tenant-a and zdr-platform
#   batch.sh stats            visible=N inflight=N dlq=N
#   batch.sh marks <request>  keys under runs/<request>/ in its tenant-a bucket
#   batch.sh jobs <request>   jobs=N (Jobs of ScaledJob batch-<request>, KEDA label)
#   batch.sh purge            empty the queue and the DLQ
# Every read is guarded: a failed read prints READ_FAILED and exits 2, never 0.
set -euo pipefail
export MSYS_NO_PATHCONV=1
K="${K:-kubectl --context kind-zdr-p6}"

py() {  # run Python in the toolbox; output on stdout
    $K -n zdr-lab exec deploy/toolbox -- python -c "$1" 2>/dev/null || { echo "READ_FAILED"; exit 2; }
}

case "${1:-}" in
setup)
    for ns in tenant-a zdr-platform; do
        $K -n "$ns" create secret generic lab-aws --from-literal=AWS_ACCESS_KEY_ID=lab \
            --from-literal=AWS_SECRET_ACCESS_KEY=lab --dry-run=client -o yaml | $K apply -f - >/dev/null
    done
    echo "lab-aws ready in tenant-a and zdr-platform" ;;
stats)
    py '
import boto3, os
c = boto3.client("sqs", endpoint_url=os.environ["SQS_ENDPOINT_URL"])
base = os.environ["SQS_ENDPOINT_URL"] + "/queue/"
def attrs(q):
    return c.get_queue_attributes(QueueUrl=base + q, AttributeNames=["ApproximateNumberOfMessages", "ApproximateNumberOfMessagesNotVisible"])["Attributes"]
m, d = attrs("zero-drift-batch"), attrs("zero-drift-batch-dlq")
vis, inf = m["ApproximateNumberOfMessages"], m["ApproximateNumberOfMessagesNotVisible"]
dlq = int(d["ApproximateNumberOfMessages"]) + int(d["ApproximateNumberOfMessagesNotVisible"])
print(f"visible={vis} inflight={inf} dlq={dlq}")' ;;
marks)
    r="${2:?usage: batch.sh marks <request>}"
    py '
import os
from batchtraining.aws import s3_client
c = s3_client(os.environ)
keys = [o["Key"] for p in c.get_paginator("list_objects_v2").paginate(Bucket="zero-drift-batch-tenant-a-'"$r"'", Prefix="runs/'"$r"'/") for o in p.get("Contents", [])]
print("\n".join(sorted(keys)) if keys else "(no objects)")' ;;
jobs)
    r="${2:?usage: batch.sh jobs <request>}"
    n="$($K -n tenant-a get jobs -l "scaledjob.keda.sh/name=batch-$r" -o name 2>/dev/null)" || { echo "READ_FAILED"; exit 2; }
    echo "jobs=$(grep -c . <<< "$n" || true)" ;;
purge)
    py '
import boto3, os
c = boto3.client("sqs", endpoint_url=os.environ["SQS_ENDPOINT_URL"])
for q in ("zero-drift-batch", "zero-drift-batch-dlq"):
    c.purge_queue(QueueUrl=os.environ["SQS_ENDPOINT_URL"] + "/queue/" + q)
print("purged zero-drift-batch and zero-drift-batch-dlq")' ;;
*)
    sed -n '2,10p' "$0"; exit 2 ;;
esac
