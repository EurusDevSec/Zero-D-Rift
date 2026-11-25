#!/usr/bin/env bash
# Build the image and run it the way the cluster will (non-root, read-only root
# filesystem, no capabilities) against the kind-lab substitutes: Adobe S3Mock for
# S3 and ElasticMQ for SQS (D12, pinned by digest). No AWS, lab keys only.
#   bash workloads/batch-training/smoke.sh [image]   (default: build batchtraining:smoke)
# Checks:
#   1. §9.3 L2 on S3Mock: a second If-None-Match:* write returns 412, first value kept
#   2. submit twice → one message; train end to end → markers, checkpoints, artifact
#   3. SIGTERM mid-run → checkpoint, message kept; next train resumes from it
# Everything it starts is removed on exit.
set -euo pipefail
export MSYS_NO_PATHCONV=1
S3MOCK=adobe/s3mock:5.2.3@sha256:ab01a6946750f451ca215a47e91030695b260e4003b8a5a6201d25029b8fca92
ELASTICMQ=softwaremill/elasticmq-native:1.7.1@sha256:e4580ab9ad1bd5cd37b4ba04911bc5ccc8cd2d9ab4de56ece65acee71c24e05c
here="$(cd "$(dirname "$0")" && pwd)"
ctx="$(cygpath -w "$here" 2>/dev/null || echo "$here")"
img="${1:-}"
if [[ -z "$img" ]]; then
  img=batchtraining:smoke
  docker build --load -q -t "$img" "$ctx" >/dev/null
fi
net=zdr-bt-smoke s3=zdr-bt-s3mock mq=zdr-bt-elasticmq bucket=zero-drift-batch-tenant-a-smoke
q="http://$mq:9324/queue/zero-drift-batch"
cleanup() { docker rm -f "$s3" "$mq" zdr-bt-train >/dev/null 2>&1 || true; docker network rm "$net" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup
docker network create "$net" >/dev/null
docker run -d --name "$s3" --network "$net" -e COM_ADOBE_TESTING_S3MOCK_STORE_INITIAL_BUCKETS="$bucket" "$S3MOCK" >/dev/null
docker run -d --name "$mq" --network "$net" "$ELASTICMQ" >/dev/null

hardened=(--network "$net" --read-only --cap-drop ALL --security-opt no-new-privileges
  -e AWS_REGION=us-east-1 -e AWS_DEFAULT_REGION=us-east-1 -e AWS_ACCESS_KEY_ID=lab -e AWS_SECRET_ACCESS_KEY=lab
  -e S3_ENDPOINT_URL="http://$s3:9090" -e SQS_ENDPOINT_URL="http://$mq:9324"
  -e TENANT=tenant-a -e REQUEST_ID=smoke -e BUCKET="$bucket" -e QUEUE_URL="$q")
step() { echo "== $*"; }
fail() { echo "FAIL: $*"; exit 1; }
py() { docker run --rm "${hardened[@]}" --entrypoint python "$img" -c "$1"; }

step "wait for S3Mock and ElasticMQ, create the queue (visibility 120 s, D8)"
ready=no
for _ in $(seq 1 60); do
  py 'import boto3,os
from batchtraining.aws import s3_client
s3_client(os.environ).head_bucket(Bucket=os.environ["BUCKET"])
boto3.client("sqs",endpoint_url=os.environ["SQS_ENDPOINT_URL"]).create_queue(QueueName="zero-drift-batch",Attributes={"VisibilityTimeout":"120"})' \
    >/dev/null 2>&1 && { ready=yes; break; }
  sleep 1
done
[[ "$ready" == yes ]] || fail "S3Mock or ElasticMQ not ready after 60 tries"
keys() {  # keys under runs/<request>/<attempt>/, one per line
  py 'import boto3,os
from batchtraining.aws import s3_client
c=s3_client(os.environ)
for o in c.list_objects_v2(Bucket=os.environ["BUCKET"],Prefix="runs/'"$1"'/").get("Contents",[]): print(o["Key"])'
}
depth() {
  py 'import boto3,os
a=boto3.client("sqs",endpoint_url=os.environ["SQS_ENDPOINT_URL"]).get_queue_attributes(QueueUrl=os.environ["QUEUE_URL"],AttributeNames=["ApproximateNumberOfMessages","ApproximateNumberOfMessagesNotVisible"])["Attributes"]
print(a["ApproximateNumberOfMessages"], a["ApproximateNumberOfMessagesNotVisible"])'
}

step "user and root filesystem"
docker run --rm "${hardened[@]}" --entrypoint sh "$img" -c 'id -u; touch /probe 2>&1 | sed "s/^/  /" || true'

step "L2 (§9.3): conditional write on S3Mock"
out="$(docker run --rm "${hardened[@]}" "$img" probe s3-conditional --bucket "$bucket" --prefix probe)"
echo "$out" | sed 's/^/  /'
grep -qx 'conditional_write=PASS' <<<"$out" || fail "conditional write"

step "submit twice → one message"
docker run --rm "${hardened[@]}" -e RUN_ATTEMPT=1 -e STEPS=60 "$img" submit | sed 's/^/  /'
docker run --rm "${hardened[@]}" -e RUN_ATTEMPT=1 -e STEPS=60 "$img" submit | sed 's/^/  /'
d="$(depth)"; echo "  queue visible/inflight: $d"
[[ "$d" == "1 0" ]] || fail "expected exactly one message, got $d"

step "train end to end"
docker run --rm "${hardened[@]}" -e STEP_SECONDS=0 -e POD_NAME=smoke-pod -e NODE_NAME=smoke-node "$img" train \
  | sed 's/^/  /'
k="$(keys smoke/1)"; echo "$k" | sed 's/^/  /'
for want in submit-started submitted RECEIVED-1 TRAINING_STARTED ckpt/step-000025.json ckpt/step-000050.json \
            artifact/model.json SUCCEEDED MESSAGE_DELETED; do
  grep -qx "runs/smoke/1/$want" <<<"$k" || fail "missing $want"
done
d="$(depth)"; [[ "$d" == "0 0" ]] || fail "queue not empty after train: $d"

step "SIGTERM mid-run → checkpoint, message kept; resume"
docker run --rm "${hardened[@]}" -e RUN_ATTEMPT=2 -e STEPS=60 "$img" submit >/dev/null
docker run -d --name zdr-bt-train "${hardened[@]}" -e STEP_SECONDS=0.2 -e CHECKPOINT_EVERY=1000 "$img" train >/dev/null
for _ in $(seq 1 30); do docker logs zdr-bt-train 2>/dev/null | grep -q TRAINING_STARTED && break; sleep 1; done
sleep 3
docker stop -t 10 zdr-bt-train >/dev/null
rc="$(docker inspect -f '{{.State.ExitCode}}' zdr-bt-train)"
docker logs zdr-bt-train | tail -1 | sed 's/^/  /'
docker rm zdr-bt-train >/dev/null
[[ "$rc" == 143 ]] || fail "exit code $rc after SIGTERM, expected 143"
k="$(keys smoke/2)"
grep -q '^runs/smoke/2/ckpt/step-' <<<"$k" || fail "no checkpoint after SIGTERM"
grep -qx 'runs/smoke/2/SUCCEEDED' <<<"$k" && fail "SUCCEEDED after SIGTERM"
d="$(depth)"; echo "  queue visible/inflight: $d"; [[ "$d" == "0 1" ]] || fail "message not kept in flight: $d"
step "release the in-flight message (stands in for the 120 s visibility timeout)"
py 'import boto3,os
c=boto3.client("sqs",endpoint_url=os.environ["SQS_ENDPOINT_URL"])
c.purge_queue(QueueUrl=os.environ["QUEUE_URL"])' # purge drops it; send the same run key again
docker run --rm "${hardened[@]}" --entrypoint python "$img" -c 'import boto3,os
from batchtraining.runkey import RunKey,message_body
boto3.client("sqs",endpoint_url=os.environ["SQS_ENDPOINT_URL"]).send_message(QueueUrl=os.environ["QUEUE_URL"],MessageBody=message_body(RunKey.of("tenant-a","smoke",2),60))'
out="$(docker run --rm "${hardened[@]}" -e STEP_SECONDS=0 "$img" train)"
echo "$out" | sed 's/^/  /'
grep -q '"message": "resumed from step [1-9]' <<<"$out" || fail "did not resume from a checkpoint"
k="$(keys smoke/2)"
[[ "$(grep -c '^runs/smoke/2/artifact/' <<<"$k")" == 1 ]] || fail "artifact count"
grep -qx 'runs/smoke/2/MESSAGE_DELETED' <<<"$k" || fail "missing MESSAGE_DELETED"
echo "SMOKE PASS"
