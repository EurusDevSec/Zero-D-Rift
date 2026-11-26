#!/usr/bin/env bash
# P6 batch suite (DRF-79, SPEC-P6 P6-T4.1, §4). Cases B01-B14, run in phases
# that follow the window (docs/runbooks/P6_L3_WINDOW.md C-E). Each phase adds its
# cases to $OUT (JSON: id, expected, observed, result, utc, evidence); `report`
# exits 0 only when every case is present and matched.
#
#   MODE=eks|kind CTX=<context> RUN_ID=<window run id> [OUT=batch-acceptance.json] batch-suite.sh <phase>
#     stats                          visible=N inflight=N dlq=N (guarded)
#     run TENANT REQUEST CAPACITY    B02 B03 B04 B14 B05 on the current attempt (CAPACITY spot|on-demand)
#     b01 TENANT REQUEST             empty queue after a run: no new Job, no node
#     resume TENANT REQUEST          B09 (extra message) B06 (Pod delete) B07 (NodeClaim delete), new attempt
#     dlq TENANT REQUEST             B08 on a fail-always attempt (purge first: window.sh purge)
#     negatives                      B10 B11 B12 B13 (no batch run active)
#     report                         summary; exit 0 only if B01-B14 all matched
#
# Read-mostly. Every Kubernetes, SQS and S3 read is guarded: a failed read is
# READ_FAILED, never 0 or "absent". Output holds counts, codes and verdicts only:
# no ARN, account ID, queue URL, IP, node or instance name. What the suite creates
# carries app.kubernetes.io/name=zdr-batch-suite and is deleted on exit.
# kind (labs/p6-kind): cases that need EKS (NodeClaims, EC2, IRSA, IMDS) are
# SKIPPED_NEEDS_EKS, never PASS; SQS/S3 are read through the lab toolbox.
set -euo pipefail
shopt -s lastpipe
export MSYS_NO_PATHCONV=1
# Windows jq writes CRLF; a CR inside multi-line output would stick to ids,
# Pod names and S3 keys (P5 DRF-71). pipefail keeps the exit status of jq.
jq() { command jq "$@" | tr -d '\r'; }
SELF="bash $(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")/../.."

MODE="${MODE:?MODE=eks|kind}"; CTX="${CTX:?CTX=<kubectl context>}"
# Every record carries mode and run id; `report` refuses rows of another run.
if [[ "$MODE" == eks ]]; then
  [[ "${RUN_ID:-}" =~ ^P6-L3-[0-9]{8}-[0-9]{2}$ ]] || { echo "FAIL  export RUN_ID=P6-L3-YYYYMMDD-NN"; exit 2; }
else RUN_ID="${RUN_ID:-kind-local}"; fi
export RUN_ID
OUT="${OUT:-batch-acceptance.json}"
# Native jq on Windows cannot open /c/... paths (MSYS_NO_PATHCONV is set above).
command -v cygpath >/dev/null 2>&1 && OUT="$(cygpath -m "$OUT")"
K="kubectl --context $CTX"
LBL=app.kubernetes.io/name=zdr-batch-suite
RGD=gitops/platform/rgd/batch-training-job.yaml
IMG="$(grep -m1 -o 'ghcr.io/eurusdevsec/zero-d-rift/batch-training@sha256:[0-9a-f]\{64\}' "$RGD")"
[[ "$MODE" == kind ]] && IMG=zdr-batch:lab
[[ -n "$IMG" ]] || { echo "FAIL  worker image digest not found"; exit 1; }
POOLS='karpenter.sh/nodepool in (batch-spot,batch-ondemand)'
POLL=10       # ScaledJob pollingInterval
VIS=120; [[ "$MODE" == kind ]] && VIS=20

# --- recording -----------------------------------------------------------------
scrub() {
  sed -E -e "s/${CTX//\//\\/}/<ctx>/g" -e 's/arn:aws[a-z-]*:[^ "]*/<arn>/g' \
         -e ':a' -e 's/(^|[^0-9])[0-9]{12}([^0-9]|$)/\1<acct>\2/' -e 'ta' \
         -e 's#https://sqs\.[^ "]*#<queue-url>#g' -e 's/i-[0-9a-f]{8,17}/<instance>/g' \
         -e 's/ip-[0-9-]+\.[a-z0-9.-]*internal/<node>/g' \
         -e 's/(^|[^0-9.])[0-9]{1,3}(\.[0-9]{1,3}){3}(:[0-9]+)?([^0-9.]|$)/\1<ip>\4/g' <<<"$1" | tr '\n' ' ' | sed 's/ $//'
}
record() { # ID EXPECTED OBSERVED EVIDENCE
  local ob ev res
  ob="$(scrub "$3")"; ev="$(scrub "${4:-}")"
  if [[ "$3" == SKIPPED_* ]]; then res="$3"
  elif [[ "$2" == "$3" ]]; then res=PASS
  else res=FAIL; fi
  printf '%-18s %-4s expected=%-40s observed=%-40s %s\n' "$res" "$1" "$2" "$ob" "${ev:0:120}"
  [[ -s "$OUT" ]] || echo '[]' > "$OUT"
  jq --arg id "$1" --arg e "$2" --arg o "$ob" --arg r "$res" --arg ev "${ev:0:400}" --arg at "$(date -u +%FT%TZ)" \
     --arg m "$MODE" --arg run "$RUN_ID" '[.[] | select(.id != $id)] + [{id:$id, mode:$m, run:$run, expected:$e, observed:$o, result:$r, utc:$at, evidence:$ev}]' \
     "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT" || { echo "FAIL  cannot write $OUT"; exit 1; }
}
skip_eks() { record "$1" "$2" SKIPPED_NEEDS_EKS "${3:-kind has no $1 path}"; }
num_of() { # FIELD STATS -> the number after FIELD= in a qstats line, or READ_FAILED
  local v; v="$(grep -oE "(^| )$1=[0-9]+" <<<"$2" | head -1 | cut -d= -f2)"; echo "${v:-READ_FAILED}"; }

# --- guarded reads ---------------------------------------------------------------
cnt() { local o; o="$("$@" 2>/dev/null)" || { echo READ_FAILED; return; }; grep -c . <<<"$o" || true; }
qurl() { $K -n zdr-platform get cm batch-config -o jsonpath='{.data.queueUrl}' 2>/dev/null; }

toolbox() { $K -n zdr-lab exec deploy/toolbox -- python -c "$1" 2>/dev/null; }

qstats() { # -> visible=N inflight=N dlq=N | READ_FAILED
  if [[ "$MODE" == kind ]]; then
    toolbox '
import boto3, os
c = boto3.client("sqs", endpoint_url=os.environ["SQS_ENDPOINT_URL"]); b = os.environ["SQS_ENDPOINT_URL"] + "/queue/"
a = lambda q: c.get_queue_attributes(QueueUrl=b + q, AttributeNames=["All"])["Attributes"]
m, d = a("zero-drift-batch"), a("zero-drift-batch-dlq")
print("visible=%s inflight=%s dlq=%d" % (m["ApproximateNumberOfMessages"], m["ApproximateNumberOfMessagesNotVisible"],
      int(d["ApproximateNumberOfMessages"]) + int(d["ApproximateNumberOfMessagesNotVisible"])))' || echo READ_FAILED
    return
  fi
  local u du m d
  u="$(qurl)" && [[ -n "$u" ]] || { echo READ_FAILED; return; }
  du="$(timeout 30 aws sqs get-queue-url --queue-name "$(basename "$u")-dlq" --query QueueUrl --output text </dev/null 2>/dev/null)" || { echo READ_FAILED; return; }
  m="$(timeout 30 aws sqs get-queue-attributes --queue-url "$u" --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible --output json </dev/null 2>/dev/null)" || { echo READ_FAILED; return; }
  d="$(timeout 30 aws sqs get-queue-attributes --queue-url "$du" --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible --output json </dev/null 2>/dev/null)" || { echo READ_FAILED; return; }
  jq -rn --argjson m "$m" --argjson d "$d" '"visible=\($m.Attributes.ApproximateNumberOfMessages) inflight=\($m.Attributes.ApproximateNumberOfMessagesNotVisible) dlq=\(($d.Attributes.ApproximateNumberOfMessages|tonumber) + ($d.Attributes.ApproximateNumberOfMessagesNotVisible|tonumber))"'
}

# dlq_own TENANT REQUEST ATTEMPT -> own=N total=M from message bodies in the DLQ | READ_FAILED
# Three receives (VisibilityTimeout 30 s) collect distinct message ids; the DLQ has
# no redrive, so a receive there changes nothing but the visibility.
DLQ_PY='
import json, sys
seen, own = {}, 0
for page in sys.stdin.read().split("\x1e"):
    if not page.strip():
        continue
    for m in json.loads(page).get("Messages", []):
        seen[m["MessageId"]] = m["Body"]
for body in seen.values():
    try:
        d = json.loads(body)
    except ValueError:
        continue
    if [d.get("tenant"), d.get("requestId"), str(d.get("runAttempt"))] == sys.argv[1:4]:
        own += 1
print("own=%d total=%d" % (own, len(seen)))'
dlq_own() {
  local pages="" o i
  if [[ "$MODE" == kind ]]; then
    pages="$(toolbox '
import boto3, json, os
c = boto3.client("sqs", endpoint_url=os.environ["SQS_ENDPOINT_URL"]); u = os.environ["SQS_ENDPOINT_URL"] + "/queue/zero-drift-batch-dlq"
for _ in range(3):
    print(json.dumps(c.receive_message(QueueUrl=u, MaxNumberOfMessages=10, VisibilityTimeout=30, WaitTimeSeconds=1)), end="\x1e")')" \
      || { echo READ_FAILED; return; }
  else
    local u du; u="$(qurl)" && [[ -n "$u" ]] || { echo READ_FAILED; return; }
    du="$(timeout 30 aws sqs get-queue-url --queue-name "$(basename "$u")-dlq" --query QueueUrl --output text </dev/null 2>/dev/null)" || { echo READ_FAILED; return; }
    for i in 1 2 3; do
      o="$(timeout 30 aws sqs receive-message --queue-url "$du" --max-number-of-messages 10 --visibility-timeout 30 --wait-time-seconds 1 --output json </dev/null 2>/dev/null)" || { echo READ_FAILED; return; }
      [[ -n "$o" ]] || o='{}'; pages+="$o"$'\x1e'
    done
  fi
  python -I -c "$DLQ_PY" "$1" "$2" "$3" <<<"$pages" 2>/dev/null || echo READ_FAILED
}

bucket() { echo "zero-drift-batch-$1-$2"; }
attempt() { $K -n "$1" get batchtrainingjob "$2" -o jsonpath='{.spec.runAttempt}' 2>/dev/null; }

# keys TENANT REQUEST ATTEMPT -> "key<TAB>lastModified" lines (key relative to the attempt prefix) | READ_FAILED
keys() {
  local b p; b="$(bucket "$1" "$2")"; p="runs/$2/$3/"
  if [[ "$MODE" == kind ]]; then
    toolbox '
import os
from batchtraining.aws import s3_client
c = s3_client(os.environ)
for pg in c.get_paginator("list_objects_v2").paginate(Bucket="'"$b"'", Prefix="'"$p"'"):
    for o in pg.get("Contents", []):
        print(o["Key"][len("'"$p"'"):] + "\t" + o["LastModified"].strftime("%Y-%m-%dT%H:%M:%S.%f"))' || echo READ_FAILED
    return
  fi
  local o
  o="$(timeout 60 aws s3api list-objects-v2 --bucket "$b" --prefix "$p" --output json </dev/null 2>/dev/null)" || { echo READ_FAILED; return; }
  jq -r --arg p "$p" '(.Contents // [])[] | "\(.Key | ltrimstr($p))\t\(.LastModified)"' <<<"$o"
}
has_key() { grep -q -E "^$1	" <<<"$2"; }

# Jobs and live Pods of one request (KEDA labels its Jobs scaledjob.keda.sh/name).
jobs_of() { cnt $K -n "$1" get jobs -l "scaledjob.keda.sh/name=batch-$2" -o name; }
newest_job() { $K -n "$1" get jobs -l "scaledjob.keda.sh/name=batch-$2" --sort-by=.metadata.creationTimestamp -o name 2>/dev/null | tail -1; }
live_pods() { cnt $K -n "$1" get pods -l "app.kubernetes.io/name=batch-train,batch.zero-drift.io/request=$2" --field-selector=status.phase!=Succeeded,status.phase!=Failed -o name; }
running_pod() { $K -n "$1" get pods -l "app.kubernetes.io/name=batch-train,batch.zero-drift.io/request=$2" --field-selector=status.phase=Running -o name 2>/dev/null | tail -1; }
jobs_since() { # TENANT REQUEST EPOCH -> Jobs created after EPOCH | READ_FAILED
  local j; j="$($K -n "$1" get jobs -l "scaledjob.keda.sh/name=batch-$2" -o json 2>/dev/null)" || { echo READ_FAILED; return; }
  jq --argjson t "$3" '[.items[] | select((.metadata.creationTimestamp | fromdateiso8601) > $t)] | length' <<<"$j"
}
nodeclaims() { [[ "$MODE" == kind ]] && { echo n/a; return; }; cnt $K get nodeclaims -l "$POOLS" -o name; }
kinstances() { # Karpenter-tagged instances in every state but terminated
  [[ "$MODE" == kind ]] && { echo n/a; return; }
  timeout 60 aws ec2 describe-instances --filters Name=tag-key,Values=karpenter.sh/nodepool \
    Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down \
    --query 'length(Reservations[].Instances[])' --output text </dev/null 2>/dev/null || echo READ_FAILED
}

# node_gone NAME -> 0 only when the API says NotFound, or a successful list lacks it.
node_gone() {
  local o
  if o="$($K get node "$1" -o name 2>&1)"; then return 1; fi
  [[ "$o" == *NotFound* ]] && return 0
  o="$($K get nodes -o name 2>/dev/null)" || return 1
  ! grep -qx "node/$1" <<<"$o"
}

wait_until() { # SECONDS COMMAND... -> 0 when COMMAND succeeds
  local end=$((SECONDS + $1)); shift
  until "$@"; do (( SECONDS < end )) || return 1; sleep 5; done
}

# --- suite-owned Pods (restricted, tenant label, D9-sized) ------------------------
suite_pod() { # NAME NS SA ARGS-JSON [SPEC-PATCH] [ENV-JSON] [COMMAND-JSON]
  local sp="${5:-}" ev="${6:-}" cm="${7:-}"
  [[ -n "$sp" ]] || sp='{}'; [[ -n "$ev" ]] || ev='[]'; [[ -n "$cm" ]] || cm='null'
  jq -n --arg n "$1" --arg ns "$2" --arg sa "$3" --arg img "$IMG" --argjson a "$4" \
        --argjson s "$sp" --argjson e "$ev" --argjson cmd "$cm" --arg kind "$MODE" '{apiVersion:"v1",kind:"Pod",
    metadata:{name:$n,namespace:$ns,labels:({"app.kubernetes.io/name":"zdr-batch-suite"}
      + (if ($ns|startswith("tenant-")) then {"rag.zero-drift.io/tenant":$ns} else {} end))},
    spec:({restartPolicy:"Never",serviceAccountName:$sa,automountServiceAccountToken:false,activeDeadlineSeconds:300,
      securityContext:{runAsNonRoot:true,runAsUser:10001,seccompProfile:{type:"RuntimeDefault"}},
      containers:[({name:"c",image:$img,args:$a,env:$e,
        imagePullPolicy:(if $kind == "kind" then "Never" else "IfNotPresent" end),
        securityContext:{allowPrivilegeEscalation:false,readOnlyRootFilesystem:true,capabilities:{drop:["ALL"]}},
        resources:{requests:{cpu:"50m",memory:"96Mi"},limits:{memory:"192Mi"}}}
        + (if $cmd == null then {} else {command:$cmd} end))]} * $s)}'
}
# Manifests go to kubectl as a here-string, never through a pipe into a function:
# on Windows, `jq | tr` feeding a shell function under lastpipe sometimes failed
# with "jq: error: Invalid argument" (kind run 26/11), which dropped the object.
kapply() { [[ -n "$1" ]] && $K apply -f - <<<"$1" >/dev/null 2>&1; }
# run_probe NS SA ARGS-JSON [SPEC-PATCH] [ENV-JSON] [COMMAND-JSON] -> Pod log, only once the Pod finished
run_probe() {
  local n="zdr-bs-$(date +%s)-$RANDOM" ph="" m
  m="$(suite_pod "$n" "$1" "$2" "$3" "${4:-}" "${5:-}" "${6:-}")" && kapply "$m" || { echo "PROBE_APPLY_FAILED"; return; }
  wait_until 240 bash -c "p=\$($K -n $1 get pod $n -o jsonpath='{.status.phase}' 2>/dev/null); [[ \$p == Succeeded || \$p == Failed ]]" || true
  ph="$($K -n "$1" get pod "$n" -o jsonpath='{.status.phase}' 2>/dev/null || echo unknown)"
  [[ "$ph" == Succeeded || "$ph" == Failed ]] && $K -n "$1" logs "$n" 2>/dev/null || echo "PROBE_NOT_FINISHED phase=$ph"
  $K -n "$1" delete pod "$n" --wait=false >/dev/null 2>&1 || true
}
aws_env() { local r; r="$($K -n zdr-platform get cm batch-config -o jsonpath='{.data.region}' 2>/dev/null)"
  jq -nc --arg r "$r" '[{name:"AWS_REGION",value:$r},{name:"AWS_DEFAULT_REGION",value:$r}]'; }
batch_node_patch='{"nodeSelector":{"zero-drift.io/pool":"batch"},"tolerations":[{"key":"zero-drift.io/batch","operator":"Equal","value":"true","effect":"NoSchedule"}]}'

cleanup() {
  local ns
  for ns in tenant-a tenant-b zdr-platform keda karpenter; do
    $K -n "$ns" delete pods,jobs -l "$LBL" --wait=false >/dev/null 2>&1 || true
  done
}

# --- phases ---------------------------------------------------------------------
phase_run() { # TENANT REQUEST CAPACITY
  local t=$1 r=$2 cap=$3 a j pod node labels ks st n0 e tg ok miss=() ckpt
  [[ "$cap" == spot || "$cap" == on-demand ]] || { echo "usage: run TENANT REQUEST spot|on-demand"; exit 2; }
  a="$(attempt "$t" "$r")" || true; [[ -n "$a" ]] || { record B02 "jobs=1" READ_FAILED "request $t/$r not readable"; return; }
  echo "INFO  run key $t/$r/$a; expecting capacity $cap"

  # B02: one message -> one Job.
  wait_until 600 bash -c "[[ \$($K -n $t get jobs -l scaledjob.keda.sh/name=batch-$r -o name 2>/dev/null | grep -c .) -ge 1 ]]" \
    || { record B02 "jobs=1" "jobs=0" "no Job within 600 s"; return; }
  record B02 "jobs=1" "jobs=$(jobs_of "$t" "$r")" "attempt $a"

  # B03: still one Job (and one live Pod) after three polls.
  sleep $((3 * POLL + 5))
  st="$(qstats)"
  record B03 "jobs=1 pods=1 inflight=1" "jobs=$(jobs_of "$t" "$r") pods=$(live_pods "$t" "$r") inflight=$(num_of inflight "$st")" "after 3 polls: $st"

  # Capacity of the node the training Pod runs on (read from Node labels; no name kept).
  wait_until 1200 bash -c "[[ -n \$($K -n $t get pods -l app.kubernetes.io/name=batch-train,batch.zero-drift.io/request=$r --field-selector=status.phase=Running -o name 2>/dev/null) ]]" \
    || { record B04 "complete capacity=$cap" "FAILED_CAPACITY" "training Pod not Running within 20 min (H3)"; return; }
  pod="$(running_pod "$t" "$r")"
  node="$($K -n "$t" get "$pod" -o jsonpath='{.spec.nodeName}' 2>/dev/null)" || node=""
  labels="$($K get node "$node" -o jsonpath='{.metadata.labels.karpenter\.sh/capacity-type} {.metadata.labels.node\.kubernetes\.io/instance-type} {.metadata.labels.zero-drift\.io/pool}' 2>/dev/null)" || labels="READ_FAILED"
  # B05 needs the instance behind this node; read it now, the node may be gone
  # one consolidateAfter (60 s) after the Job ends (Codex R1 H).
  local pid; pid="$($K get node "$node" -o jsonpath='{.spec.providerID}' 2>/dev/null)" || pid=""
  echo "INFO  training Pod node: capacity/type/pool = $labels"

  # B14 while the batch node is up: IMDS token from a Pod on it (hop limit 1).
  if [[ "$MODE" == kind ]]; then skip_eks B14 "imds=denied" "kind has no IMDS"
  else
    e="$(run_probe "$t" batch-train '["probe","imds"]' "$batch_node_patch" "$(aws_env)")"
    record B14 "imds=denied" "imds=$(grep -o 'outcome=[a-z]*' <<<"$e" | head -1 | cut -d= -f2)" "$(grep -o 'code=[A-Za-z0-9]*' <<<"$e" | head -1)"
  fi

  # B04: the attempt's Job Complete, markers written after submit-started, queue empty.
  wait_until 2700 bash -c "j=\$($K -n $t get jobs -l scaledjob.keda.sh/name=batch-$r --sort-by=.metadata.creationTimestamp -o name 2>/dev/null | tail -1); [[ -n \$j ]] && $K -n $t get \$j -o jsonpath='{.status.conditions[?(@.status==\"True\")].type}' 2>/dev/null | grep -qE 'Complete|Failed'" || true
  j="$(newest_job "$t" "$r")"
  st="$($K -n "$t" get "$j" -o jsonpath='{.status.conditions[?(@.status=="True")].type}' 2>/dev/null || echo READ_FAILED)"
  ks="$(keys "$t" "$r" "$a")"
  if [[ "$ks" == READ_FAILED ]]; then miss+=(READ_FAILED)
  else
    n0="$(awk -F'\t' '$1=="submit-started"{print $2}' <<<"$ks")"
    [[ -n "$n0" ]] || miss+=(no-submit-started)
    for tg in TRAINING_STARTED SUCCEEDED MESSAGE_DELETED artifact/model.json; do
      has_key "$tg" "$ks" || miss+=("no-$tg")
    done
    ckpt="$(grep -c '^ckpt/' <<<"$ks" || true)"; (( ckpt >= 1 )) || miss+=(no-checkpoint)
    (( $(grep -c '^artifact/' <<<"$ks" || true) == 1 )) || miss+=(artifacts!=1)
    # Every marker of this attempt is newer than its submit-started (ISO strings compare in order).
    [[ -z "$n0" ]] || awk -F'\t' -v t0="$n0" '$1!="submit-started" && $1!="submitted" && $2 < t0 {bad=1} END{exit bad}' <<<"$ks" || miss+=(older-than-submit)
  fi
  [[ "$st" == *Complete* ]] || miss+=("job=$st")
  sleep "$VIS"
  ok="$(qstats)"; [[ "$ok" == "visible=0 inflight=0"* ]] || miss+=("queue:$ok")
  local capseen expcap=$cap; capseen="$(cut -d' ' -f1 <<<"$labels")"
  [[ "$MODE" == kind ]] && { capseen=n/a; expcap=n/a; }   # kind nodes carry no capacity-type label
  record B04 "complete capacity=$expcap" "$( ((${#miss[@]})) && echo "missing:${miss[*]}" || echo complete) capacity=${capseen:-none}" \
    "type/pool=$(cut -d' ' -f2- <<<"$labels") checkpoints=${ckpt:-?} CPU_SUBSTITUTE_FOR_GPU"

  # B05: the node leaves Kubernetes, then its instance is terminated on AWS.
  if [[ "$MODE" == kind ]]; then skip_eks B05 "node-gone instance-terminated" "kind nodes are not reclaimed"; return; fi
  local t0=$SECONDS kg="" ig="" iid
  iid="${pid##*/}"
  [[ -n "$node" && "$iid" =~ ^i-[0-9a-f]{8,17}$ ]] || { record B05 "node-gone instance-terminated" "providerID-unread" "node or providerID not read while the Pod ran"; return; }
  wait_until 900 node_gone "$node" && kg="node-gone"
  local tk=$((SECONDS - t0))
  wait_until 900 bash -c "[[ \$(timeout 30 aws ec2 describe-instances --instance-ids $iid --query 'Reservations[0].Instances[0].State.Name' --output text </dev/null 2>/dev/null) == terminated ]]" && ig="instance-terminated"
  record B05 "node-gone instance-terminated" "${kg:-node-present} ${ig:-instance-not-terminated}" \
    "scale-down after Job end: node gone ${tk}s, terminated $((SECONDS - t0))s (smoke)"
}

phase_b01() { # TENANT REQUEST
  local t=$1 r=$2 sj ready a jj made s t0 i bad=0 nj nc ni
  local exp="jobs_new=0 nodeclaims=0 instances=0"; [[ "$MODE" == kind ]] && exp="jobs_new=0 nodeclaims=n/a instances=n/a"
  sj="$($K -n "$t" get scaledjob "batch-$r" -o json 2>/dev/null)" || { record B01 "$exp" "scaledjob-missing" "a missing ScaledJob is FAIL"; return; }
  ready="$(jq -r '[.status.conditions[]? | select(.type=="Ready")][0].status // "none"' <<<"$sj")"
  # The scaler proved it reads the queue: a KEDA Job of this attempt reached Complete.
  a="$(attempt "$t" "$r")" || a=""
  jj="$($K -n "$t" get jobs -l "scaledjob.keda.sh/name=batch-$r" -o json 2>/dev/null)" || { record B01 "$exp" READ_FAILED "Jobs not readable"; return; }
  made="$(jq --arg a "$a" '[.items[] | select(.spec.template.metadata.labels["batch.zero-drift.io/attempt"] == $a)
          | select(any(.status.conditions[]?; .type == "Complete" and .status == "True"))] | length' <<<"$jj")"
  [[ "$ready" == True && -n "$a" && "$made" -ge 1 ]] || { record B01 "$exp" "scaler-not-proven ready=$ready jobs_complete=${made:-?}" "needs a Complete KEDA Job of attempt ${a:-?}"; return; }
  t0="$(date -u +%s)"
  for i in 1 2 3 4; do
    s="$(qstats)"; [[ "$s" == "visible=0 inflight=0"* ]] || bad=1
    sleep "$POLL"
  done
  sleep 5
  nj="$(jobs_since "$t" "$r" "$t0")"; nc="$(nodeclaims)"; ni="$(kinstances)"
  (( bad )) && { record B01 "$exp" "queue-not-empty" "$s"; return; }
  record B01 "$exp" "jobs_new=$nj nodeclaims=$nc instances=$ni" "ScaledJob Ready, Complete Job of attempt $a; queue empty over 4 polls"
}

resumed_step() { # TENANT REQUEST EPOCH ATTEMPT OLD_JOB -> N from "resumed from step N"
  # of a Pod of ATTEMPT, created after EPOCH, in a Job other than OLD_JOB (backoffLimit 0).
  local p j
  j="$($K -n "$1" get pods -l "app.kubernetes.io/name=batch-train,batch.zero-drift.io/request=$2,batch.zero-drift.io/attempt=$4" -o json 2>/dev/null)" || return 1
  for p in $(jq -r --argjson t "$3" --arg old "$5" '.items[] | select((.metadata.creationTimestamp | fromdateiso8601) > $t)
             | select((.metadata.labels["job-name"] // "") != $old and (.metadata.labels["job-name"] // "") != "") | .metadata.name' <<<"$j"); do
    $K -n "$1" logs "$p" 2>/dev/null | grep -o 'resumed from step [0-9]*' | grep -o '[0-9]*$' | head -1 && return 0
  done
  return 1
}

running_wait() { # TENANT REQUEST SECONDS -> 0 when a training Pod is Running
  wait_until "$3" bash -c "[[ -n \$($K -n $1 get pods -l app.kubernetes.io/name=batch-train,batch.zero-drift.io/request=$2 --field-selector=status.phase=Running -o name 2>/dev/null) ]]"
}
resume_verdict() { [[ -n "$1" && "$1" -gt 0 ]] && echo "resumed>0" || echo "resumed=${1:-none}"; }
job_of() { $K -n "$1" get "$2" -o jsonpath='{.metadata.labels.job-name}' 2>/dev/null; }
blocked() { local c; for c in "$@"; do record "$c" "${EXP[$c]}" "blocked:$BLOCK" "an earlier step of this phase failed"; done; }
declare -A EXP=([B06]="resumed>0" [B07]="resumed>0" [B09]="sent=1 active=1 pods=1 nodeclaims=1 msgs>=2")

phase_resume() { # TENANT REQUEST (a new attempt of a normal request, 300 steps)
  local t=$1 r=$2 a pod node nc t0 n e u oj st
  a="$(attempt "$t" "$r")" || a=""; [[ -n "$a" ]] || { echo "FAIL  request $t/$r not readable"; exit 1; }
  echo "INFO  run key $t/$r/$a"
  running_wait "$t" "$r" 1200 || { echo "FAIL  training Pod not Running within 20 min (H3)"; exit 1; }

  # B06: delete the Pod after its first checkpoint; a new Job resumes from N > 0.
  BLOCK=""
  wait_until 600 bash -c "[[ \$(MODE=$MODE CTX=$CTX OUT=/dev/null $SELF _keys $t $r $a | grep -c '^ckpt/') -ge 1 ]]" || BLOCK=no-checkpoint
  [[ -n "$BLOCK" ]] || { pod="$(running_pod "$t" "$r")"; [[ -n "$pod" ]] || BLOCK=no-running-pod; }
  [[ -n "$BLOCK" ]] || { oj="$(job_of "$t" "$pod")"; [[ -n "$oj" ]] || BLOCK=job-unread; }
  t0="$(date -u +%s)"
  [[ -n "$BLOCK" ]] || $K -n "$t" delete "$pod" --wait=false >/dev/null 2>&1 || BLOCK=pod-delete-failed
  if [[ -n "$BLOCK" ]]; then blocked B06 B07 B09; return; fi
  echo "INFO  training Pod deleted after a checkpoint"
  n=""; wait_until $((VIS + 600)) bash -c "MODE=$MODE CTX=$CTX OUT=/dev/null $SELF _resumed $t $r $t0 $a $oj" && n="$(resumed_step "$t" "$r" "$t0" "$a" "$oj")"
  record B06 "resumed>0" "$(resume_verdict "$n")" "Pod deleted after a checkpoint; new Job of attempt $a resumed from step ${n:-?}"

  # B07: delete the NodeClaim under the resumed Pod (simulated disruption, D11).
  if [[ "$MODE" == kind ]]; then skip_eks B07 "resumed>0" "kind has no NodeClaims"
  else
    running_wait "$t" "$r" 600 || BLOCK=no-running-pod
    sleep 40   # past at least one more checkpoint (every 25 steps)
    [[ -n "$BLOCK" ]] || { pod="$(running_pod "$t" "$r")"; [[ -n "$pod" ]] || BLOCK=no-running-pod; }
    [[ -n "$BLOCK" ]] || { oj="$(job_of "$t" "$pod")"; [[ -n "$oj" ]] || BLOCK=job-unread; }
    [[ -n "$BLOCK" ]] || { node="$($K -n "$t" get "$pod" -o jsonpath='{.spec.nodeName}' 2>/dev/null)" || node=""; [[ -n "$node" ]] || BLOCK=node-unread; }
    [[ -n "$BLOCK" ]] || { nc="$($K get nodeclaims -o json 2>/dev/null)" || BLOCK=nodeclaims-unread; }
    [[ -n "$BLOCK" ]] || { nc="$(jq -r --arg n "$node" '[.items[]? | select(.status.nodeName == $n) | .metadata.name][0] // ""' <<<"$nc")"; [[ -n "$nc" ]] || BLOCK=no-nodeclaim; }
    t0="$(date -u +%s)"
    [[ -n "$BLOCK" ]] || $K delete nodeclaim "$nc" --wait=false >/dev/null 2>&1 || BLOCK=nodeclaim-delete-failed
    if [[ -n "$BLOCK" ]]; then blocked B07 B09; return; fi
    echo "INFO  NodeClaim deleted (simulated disruption)"
    n=""; wait_until $((VIS + 1200)) bash -c "MODE=$MODE CTX=$CTX OUT=/dev/null $SELF _resumed $t $r $t0 $a $oj" && n="$(resumed_step "$t" "$r" "$t0" "$a" "$oj")"
    record B07 "resumed>0" "$(resume_verdict "$n")" "simulated disruption (D11): NodeClaim deleted; new Job of attempt $a resumed from step ${n:-?}"
  fi

  # B09: a second message while this attempt trains: still one Pod, one node.
  # The extra message (request b09-extra) is foreign to every worker: it is
  # released three times and ends in the DLQ. Purge before B08 (window.sh purge).
  if [[ "$MODE" == kind ]]; then skip_eks B09 "${EXP[B09]}" "kind has no NodeClaims"; return; fi
  running_wait "$t" "$r" 900 || { BLOCK=no-running-pod; blocked B09; return; }
  # A fresh attempt number, so a rerun is never ALREADY_SUBMITTED (no message sent).
  local xa=$(( $(date +%s) % 9000 + 1000 )) sent act tot
  u="$(qurl)"
  e="$(run_probe zdr-platform batch-submit '["submit"]' '{}' "$(jq -nc --argjson base "$(aws_env)" --arg t "$t" --arg b "$(bucket "$t" "$r")" --arg q "$u" --arg xa "$xa" \
       '$base + [{name:"TENANT",value:$t},{name:"REQUEST_ID",value:"b09-extra"},{name:"RUN_ATTEMPT",value:$xa},{name:"STEPS",value:"10"},{name:"BUCKET",value:$b},{name:"QUEUE_URL",value:$q}]')")"
  unset u
  grep -q '"event": "SUBMITTED"' <<<"$e" && sent=1 || sent=0
  echo "INFO  extra submit: $(grep -o '"event": "[A-Z_]*"' <<<"$e" | tr '\n' ' ')"
  sleep $((3 * POLL + 5))
  # Still active: a Pod of this attempt is Running when B09 is scored.
  act="$(cnt $K -n "$t" get pods -l "app.kubernetes.io/name=batch-train,batch.zero-drift.io/request=$r,batch.zero-drift.io/attempt=$a" --field-selector=status.phase=Running -o name)"
  st="$(qstats)"
  tot="msgs=READ_FAILED"
  if [[ "$st" == visible=* ]]; then
    tot=$(( $(num_of visible "$st") + $(num_of inflight "$st") ))
    if (( tot >= 2 )); then tot="msgs>=2"; else tot="msgs=$tot"; fi
  fi
  record B09 "${EXP[B09]}" "sent=$sent active=$act pods=$(live_pods "$t" "$r") nodeclaims=$(nodeclaims) $tot" \
    "extra message (own run key) sent while attempt $a trained; $st"
}

phase_dlq() { # TENANT REQUEST (fail-always attempt; queue and DLQ purged before)
  local t=$1 r=$2 a ks rc s dl x8="received=3 dlq_own=1 succeeded=0"
  a="$(attempt "$t" "$r")" || a=""; [[ -n "$a" ]] || { record B08 "$x8" READ_FAILED "request not readable"; return; }
  [[ "$($K -n "$t" get batchtrainingjob "$r" -o jsonpath='{.spec.failProfile}' 2>/dev/null)" == fail-always ]] \
    || { echo "FAIL  $t/$r is not failProfile fail-always"; exit 1; }
  wait_until 1800 bash -c "MODE=$MODE CTX=$CTX OUT=/dev/null $SELF _keys $t $r $a | grep -q '^RECEIVED-3'" || true
  sleep $((VIS + 3 * POLL))
  ks="$(keys "$t" "$r" "$a")"; s="$(qstats)"
  dl="$(dlq_own "$t" "$r" "$a")"
  if [[ "$ks" == READ_FAILED || "$s" == READ_FAILED || "$dl" == READ_FAILED ]]; then record B08 "$x8" READ_FAILED "keys/stats/dlq read failed"; return; fi
  rc="$(grep -c '^RECEIVED-' <<<"$ks" || true)"
  record B08 "$x8" "received=$rc dlq_own=$(num_of own "$dl") succeeded=$(grep -c '^SUCCEEDED' <<<"$ks" || true)" \
    "attempt $a; $s; DLQ $dl (bodies matched on tenant/request/attempt); Failed Jobs not counted (history limit 1)"
}

quota_deny() { # MANIFEST -> the quota resource named in the denial, or allow/error
  local out
  [[ -n "$1" ]] || { echo "error:no-manifest"; return; }
  if out="$($K create --dry-run=server -f - <<<"$1" 2>&1)"; then echo allow; return; fi
  case "$out" in
    *"exceeded quota"*) grep -oE 'requested: [a-z./]+=' <<<"$out" | head -1 | sed -E 's/requested: (.*)=/\1/' ;;
    *Forbidden*) echo "error:forbidden" ;;
    *) echo "error:create-failed" ;;
  esac
}
quota_room() { # TENANT RESOURCE -> hard - used | READ_FAILED
  local q; q="$($K -n "$1" get resourcequota tenant-quota -o json 2>/dev/null)" || { echo READ_FAILED; return; }
  jq -r --arg r "$2" '((.spec.hard[$r] // "0") | tonumber) - ((.status.used[$r] // "0") | tonumber)' <<<"$q"
}
# A small Pod that stays Running (a Succeeded Pod no longer counts against "pods").
SLEEPER='["python","-c","import time; time.sleep(240)"]'
small() { jq -c '.spec.containers[0].resources={requests:{cpu:"10m",memory:"32Mi"},limits:{memory:"64Mi"}}' <<<"$1"; }
as_job() { jq -c '{apiVersion:"batch/v1",kind:"Job",metadata:{name:.metadata.name,namespace:.metadata.namespace,labels:.metadata.labels},
  spec:{suspend:true,backoffLimit:0,template:{metadata:{labels:.metadata.labels},spec:(.spec|del(.activeDeadlineSeconds))}}}' <<<"$1"; }
sp() { suite_pod "$1" tenant-a default '[]' "${2:-}" '' "$SLEEPER"; }

phase_negatives() {
  local t=tenant-a o nc0 nc1 i room cpu_res jobs_res pods_res
  # B10: a Pod that selects the batch pool without the toleration stays Pending, and no node starts for it.
  nc0="$(nodeclaims)"
  kapply "$(sp zdr-bs-b10 '{"nodeSelector":{"zero-drift.io/pool":"batch"}}')" || true
  sleep 90
  o="$($K -n "$t" get pod zdr-bs-b10 -o jsonpath='{.status.phase}' 2>/dev/null || echo READ_FAILED)"
  nc1="$(nodeclaims)"
  $K -n "$t" delete pod zdr-bs-b10 --wait=false >/dev/null 2>&1 || true
  local ncnew="n/a"; [[ "$nc0" =~ ^[0-9]+$ && "$nc1" =~ ^[0-9]+$ ]] && ncnew=$((nc1 - nc0))
  [[ "$nc0" == READ_FAILED || "$nc1" == READ_FAILED ]] && ncnew=READ_FAILED
  local exp10="Pending nodeclaims_new=0"; [[ "$MODE" == kind ]] && exp10="Pending nodeclaims_new=n/a"
  record B10 "$exp10" "${o:-none} nodeclaims_new=$ncnew" "taint zero-drift.io/batch keeps a Pod without the toleration off the batch pool"

  # B11: each quota denial names its resource (D9).
  cpu_res="$(quota_deny "$(jq -c '.spec.containers[0].resources.requests.cpu="1"' <<<"$(sp zdr-bs-cpu)")")"
  room="$(quota_room "$t" count/jobs.batch)"
  if [[ "$room" =~ ^[0-9]+$ ]]; then
    for ((i = 1; i <= room; i++)); do kapply "$(as_job "$(sp "zdr-bs-q$i")")" || echo "INFO  filler Job $i not created"; done
    jobs_res="$(quota_deny "$(as_job "$(sp zdr-bs-qx)")")"
  else jobs_res=READ_FAILED; fi
  $K -n "$t" delete jobs -l "$LBL" --wait=true --timeout=60s >/dev/null 2>&1 || true
  room="$(quota_room "$t" pods)"
  if [[ "$room" =~ ^[0-9]+$ ]]; then
    for ((i = 1; i <= room; i++)); do kapply "$(small "$(sp "zdr-bs-p$i")")" || echo "INFO  filler Pod $i not created"; done
    sleep 5
    pods_res="$(quota_deny "$(small "$(sp zdr-bs-px)")")"
  else pods_res=READ_FAILED; fi
  $K -n "$t" delete pods -l "$LBL" --wait=true --timeout=120s >/dev/null 2>&1 || true
  record B11 "pods count/jobs.batch requests.cpu" "$pods_res $jobs_res $cpu_res" "each denial names its quota resource (D9)"

  # B12: tenant-b's identity cannot read or write tenant-a's bucket; tenant-a can (positive control).
  if [[ "$MODE" == kind ]]; then skip_eks B12 "a:true/ok b:true/error:AccessDenied/true/error:AccessDenied" "no IRSA on kind"
  else
    local req="${B12_REQUEST:?export B12_REQUEST=<tenant-a request whose attempt 1 SUCCEEDED>}" b key ag bg bp
    b="$(bucket tenant-a "$req")"; key="runs/$req/1/artifact/model.json"
    ag="$(run_probe tenant-a batch-train "$(jq -nc --arg b "$b" --arg k "$key" '["probe","s3-get","--bucket",$b,"--key",$k,"--expect-role","zero-drift-batch-tenant-a"]')" '' "$(aws_env)")"
    bg="$(run_probe tenant-b batch-train "$(jq -nc --arg b "$b" --arg k "$key" '["probe","s3-get","--bucket",$b,"--key",$k,"--expect-role","zero-drift-batch-tenant-b"]')" '' "$(aws_env)")"
    bp="$(run_probe tenant-b batch-train "$(jq -nc --arg b "$b" --arg k "$key" '["probe","s3-put","--bucket",$b,"--key",$k,"--expect-role","zero-drift-batch-tenant-b"]')" '' "$(aws_env)")"
    pv() { echo "$(grep -o 'caller_role_match=[a-zA-Z_]*' <<<"$1" | cut -d= -f2)/$(grep -o 'outcome=[a-z]*' <<<"$1" | cut -d= -f2)$(grep -o 'code=[A-Za-z]*' <<<"$1" | sed 's/code=/:/')"; }
    record B12 "a:true/ok b:true/error:AccessDenied/true/error:AccessDenied" "a:$(pv "$ag") b:$(pv "$bg")/$(pv "$bp")" "object = artifact of tenant-a/$req attempt 1"
  fi

  # B13: simulation, plus one real denied call per controller identity.
  if [[ "$MODE" == kind ]]; then skip_eks B13 "sim=PASS keda=AccessDenied karpenter=AccessDenied" "no IRSA on kind"
  else
    local sim kd kp code u
    sim="$(bash infra/terraform/scripts/batch_iam_check.sh --principal 2>&1 </dev/null | grep -E '^RESULT' | grep -q PASS && echo PASS || echo FAIL)"
    code='import boto3, os, sys
from botocore.exceptions import ClientError
try:
    if sys.argv[1] == "keda":
        boto3.client("sqs").send_message(QueueUrl=os.environ["Q"], MessageBody="b13")
    else:
        boto3.client("iam").create_role(RoleName="zdr-b13-denied", AssumeRolePolicyDocument="{}")
    print("code=Allowed")
except ClientError as e:
    print("code=" + e.response["Error"]["Code"])'
    u="$(qurl)"
    kd="$(run_probe keda keda-operator '["keda"]' '' "$(jq -nc --argjson base "$(aws_env)" --arg q "$u" '$base + [{name:"Q",value:$q}]')" \
          "$(jq -nc --arg c "$code" '["python","-c",$c]')")"
    unset u
    kp="$(run_probe karpenter karpenter '["karpenter"]' '' "$(aws_env)" "$(jq -nc --arg c "$code" '["python","-c",$c]')")"
    record B13 "sim=PASS keda=AccessDenied karpenter=AccessDenied" \
      "sim=$sim keda=$(grep -o 'code=[A-Za-z.]*' <<<"$kd" | cut -d= -f2) karpenter=$(grep -o 'code=[A-Za-z.]*' <<<"$kp" | cut -d= -f2)" \
      "keda: SendMessage; karpenter: CreateRole with an invalid document (never created)"
  fi
}

phase_report() {
  local ids exp missing bad stale
  [[ -s "$OUT" ]] || { echo "RESULT: FAIL (no results in $OUT)"; exit 1; }
  stale="$(jq --arg m "$MODE" --arg run "$RUN_ID" '[.[] | select(.mode != $m or .run != $run)] | length' "$OUT")"
  [[ "$stale" == 0 ]] || { echo "RESULT: FAIL ($stale rows of another mode or run in $OUT; use a new OUT per run)"; exit 1; }
  ids="$(jq -r '.[].id' "$OUT" | sort -u | tr '\n' ' ')"
  jq -r '.[] | "\(.result)\t\(.id)\t\(.observed)"' "$OUT" | sort -t$'\t' -k2
  missing=""; for exp in B01 B02 B03 B04 B05 B06 B07 B08 B09 B10 B11 B12 B13 B14; do [[ " $ids " == *" $exp "* ]] || missing+="$exp "; done
  if [[ "$MODE" == kind ]]; then bad="$(jq '[.[] | select(.result != "PASS" and .result != "SKIPPED_NEEDS_EKS")] | length' "$OUT")"
  else bad="$(jq '[.[] | select(.result != "PASS")] | length' "$OUT")"; fi
  [[ -z "$missing" && "$bad" == 0 ]] && { echo "RESULT: PASS ($MODE $RUN_ID; $(jq length "$OUT") cases)"; exit 0; }
  echo "RESULT: FAIL (missing: ${missing:-none}; not matched: $bad)"; exit 1
}

case "${1:-}" in
  stats) qstats ;;
  run) shift; trap cleanup EXIT; phase_run "$@" ;;
  b01) shift; phase_b01 "$@" ;;
  resume) shift; trap cleanup EXIT; phase_resume "$@" ;;
  dlq) shift; phase_dlq "$@" ;;
  negatives) trap cleanup EXIT; phase_negatives ;;
  report) phase_report ;;
  _keys) shift; keys "$@" ;;                                   # internal (wait loops)
  _resumed) shift; resumed_step "$@" >/dev/null ;;             # internal (wait loops)
  *) sed -n '2,17p' "${SELF#bash }"; exit 2 ;;
esac
