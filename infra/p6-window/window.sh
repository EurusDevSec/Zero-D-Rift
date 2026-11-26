#!/usr/bin/env bash
# P6 window helper (DRF-79, SPEC-P6 P6-T4.1; runbook docs/runbooks/P6_L3_WINDOW.md
# B3-B5, F1). The window-only values (queue URL, role ARNs) hold the account ID:
# they are read from `terraform output -json batch_platform_config` into
# variables and go straight into kubectl or aws; they are never printed.
# Run from the repository root with the EKS kubeconfig and AWS_PROFILE /
# AWS_REGION exported (the bootstrap session, MFA refreshed).
#
#   window.sh status                    # yes/no for every window object, key names only
#   window.sh annotate                  # IRSA on keda-operator, karpenter, batch-submit, batch-train x2; restarts KEDA and Karpenter
#   window.sh batch-config              # ConfigMap zdr-platform/batch-config; needs RUN_ID, EXPIRES_AT; refuses if the queue is missing
#   window.sh purge                     # purge queue and DLQ, then wait 60 s after the last successful purge
#   window.sh cleanup TENANT REQUEST    # only for a disabled request: delete its leftover messages, then its Jobs
#
# A failed read prints READ_FAILED and fails; it is never taken as "absent" or 0.
# stderr of aws and kubectl can hold ARNs, queue URLs or account IDs, so calls that
# touch window values discard it and report a fixed code instead.
set -euo pipefail
export MSYS_NO_PATHCONV=1
# Windows jq writes CRLF; a CR inside multi-line output would stick to ids,
# Pod names and S3 keys (P5 DRF-71). pipefail keeps the exit status of jq.
jq() { command jq "$@" | tr -d '\r'; }

cd "$(dirname "$0")/../.."
TF=infra/terraform
PLATFORM_NS=zdr-platform
TENANTS=(tenant-a tenant-b)
RGD=gitops/platform/rgd/batch-training-job.yaml
IMG="$(grep -m1 -o 'ghcr.io/eurusdevsec/zero-d-rift/batch-training@sha256:[0-9a-f]\{64\}' "$RGD")"
[[ -n "$IMG" ]] || { echo "FAIL  worker image digest not found in $RGD"; exit 1; }

die() { echo "FAIL  $*"; exit 1; }
need_run_vars() {
  [[ "${RUN_ID:-}" =~ ^P6-L3-[0-9]{8}-[0-9]{2}$ ]] || die "export RUN_ID=P6-L3-YYYYMMDD-NN (window request)"
  [[ "${EXPIRES_AT:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || die "export EXPIRES_AT=YYYY-MM-DDTHH:MM:SSZ"
}

# Sensitive Terraform output, read once per call. Never echo $CFG.
CFG=""
cfg() {
  if [[ -z "$CFG" ]]; then
    CFG="$(terraform -chdir="$TF" output -json batch_platform_config 2>/dev/null)" || die "terraform output batch_platform_config: READ_FAILED"
    [[ "$CFG" != null && -n "$CFG" ]] || die "batch_platform_config is null: was the plan applied with enable_batch_platform=true?"
  fi
}
cfg_get() { jq -er "$1" <<<"$CFG"; }
names() { terraform -chdir="$TF" output -json batch_platform; }
region() { terraform -chdir="$TF" output -raw region; }

annotation_set() { # namespace sa -> yes/no/READ_FAILED
  local v
  v="$(kubectl -n "$1" get sa "$2" -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null)" || { echo READ_FAILED; return; }
  [[ -n "$v" ]] && echo yes || echo no
}

# Pod of a Deployment has the IRSA env (the webhook injects it only at Pod creation).
pod_has_irsa() { # namespace deployment-label
  local j
  j="$(kubectl -n "$1" get pods -l "$2" -o json 2>/dev/null)" || { echo READ_FAILED; return; }
  jq -r 'if (.items | length) == 0 then "no-pod"
         elif all(.items[]; [.spec.containers[0].env[]?.name] | index("AWS_ROLE_ARN") != null) then "yes" else "no" end' <<<"$j"
}

cmd_status() {
  local t keys
  echo "image                               $IMG"
  echo "sa keda/keda-operator role          $(annotation_set keda keda-operator)"
  echo "keda-operator pods have IRSA        $(pod_has_irsa keda app.kubernetes.io/name=keda-operator)"
  echo "sa karpenter/karpenter role         $(annotation_set karpenter karpenter)"
  echo "karpenter pods have IRSA            $(pod_has_irsa karpenter app.kubernetes.io/name=karpenter)"
  echo "sa $PLATFORM_NS/batch-submit role   $(annotation_set "$PLATFORM_NS" batch-submit)"
  for t in "${TENANTS[@]}"; do
    echo "sa $t/batch-train role         $(annotation_set "$t" batch-train)"
  done
  if keys="$(kubectl -n "$PLATFORM_NS" get cm batch-config --ignore-not-found -o go-template='{{range $k, $v := .data}}{{$k}} {{end}}' 2>/dev/null)"; then
    echo "configmap batch-config keys         ${keys:-absent}"
  else
    echo "configmap batch-config keys         READ_FAILED"
  fi
}

annotate_sa() { # namespace sa arn expected-role
  [[ "$3" == *":role/$4" ]] || die "the ARN for $1/$2 is not role $4"
  kubectl -n "$1" annotate sa "$2" "eks.amazonaws.com/role-arn=$3" --overwrite >/dev/null 2>&1 || die "annotate sa $1/$2: WRITE_FAILED"
  echo "OK    sa $1/$2 -> role $4"
}

restart() { # namespace deployment
  kubectl -n "$1" rollout restart "deploy/$2" >/dev/null 2>&1 || die "restart deploy $1/$2: WRITE_FAILED"
  kubectl -n "$1" rollout status "deploy/$2" --timeout=240s >/dev/null 2>&1 || die "deploy $1/$2 did not become ready after the restart: NOT_READY"
  echo "OK    deploy $1/$2 restarted (new Pods get the IRSA token)"
}

cmd_annotate() {
  cfg
  local t
  annotate_sa keda keda-operator "$(cfg_get '.role_arns.keda')" zero-drift-batch-keda
  annotate_sa karpenter karpenter "$(cfg_get '.karpenter_controller_role')" zero-drift-karpenter-controller
  annotate_sa "$PLATFORM_NS" batch-submit "$(cfg_get '.role_arns.submit')" zero-drift-batch-submit
  for t in "${TENANTS[@]}"; do
    annotate_sa "$t" batch-train "$(cfg_get ".role_arns[\"$t\"]")" "zero-drift-batch-$t"
  done
  restart keda keda-operator
  restart karpenter karpenter
  cmd_status
}

queue_url() { cfg; cfg_get '.queue_url'; }
dlq_url() { # from the DLQ name in the non-sensitive output
  local n; n="$(names | jq -er '.queues.dlq')" || die "batch_platform.queues.dlq: READ_FAILED"
  timeout 30 aws sqs get-queue-url --queue-name "$n" --query QueueUrl --output text </dev/null 2>/dev/null
}

cmd_batch_config() {
  need_run_vars; cfg
  local url name reg
  url="$(cfg_get '.queue_url')"
  name="$(names | jq -er '.queues.main')" || die "batch_platform.queues.main: READ_FAILED"
  reg="$(region)"
  # The gate: no queue, no ConfigMap (the RGD waits at platformConfig without it).
  timeout 30 aws sqs get-queue-attributes --queue-url "$url" --attribute-names QueueArn </dev/null >/dev/null 2>&1 \
    || die "queue $name is not readable (READ_FAILED): batch-config not written"
  kubectl -n "$PLATFORM_NS" create configmap batch-config \
    --from-literal=queueUrl="$url" --from-literal=queueName="$name" --from-literal=region="$reg" \
    --from-literal=runId="$RUN_ID" --from-literal=expiresAt="$EXPIRES_AT" \
    --dry-run=client -o yaml 2>/dev/null | kubectl apply -f - >/dev/null 2>&1 || die "configmap batch-config: WRITE_FAILED"
  unset url
  echo "OK    configmap $PLATFORM_NS/batch-config written (queue $name)"
  cmd_status
}

purge_one() { # url label
  local i out
  for i in 1 2 3; do
    if out="$(timeout 30 aws sqs purge-queue --queue-url "$1" </dev/null 2>&1)"; then
      echo "OK    purged $2 $(date -u +%T)Z"; return 0
    fi
    # One purge per 60 s per queue: wait and retry; any other error stops.
    [[ "$out" == *PurgeQueueInProgress* ]] || die "purge $2: $(grep -o 'An error occurred ([A-Za-z.]*)' <<<"$out" || echo error)"
    echo "INFO  purge $2 in progress; retry in 61 s"; sleep 61
  done
  die "purge $2 still in progress after 3 tries"
}

cmd_purge() {
  local m d
  m="$(queue_url)"; d="$(dlq_url)" || die "DLQ URL: READ_FAILED"
  purge_one "$m" queue
  purge_one "$d" dlq
  unset m d
  # SQS deletes for up to 60 s after a successful purge.
  echo "INFO  waiting 60 s after the last successful purge"; sleep 60
  echo "OK    purge done $(date -u +%T)Z; requests may be enabled now"
}

cmd_cleanup() {
  local t="${1:?usage: window.sh cleanup TENANT REQUEST}" r="${2:?usage: window.sh cleanup TENANT REQUEST}" st n
  [[ " ${TENANTS[*]} " == *" $t "* ]] || die "unknown tenant $t"
  [[ "$r" =~ ^[a-z0-9]([-a-z0-9]{0,30}[a-z0-9])?$ ]] || die "invalid request name"
  # A live request would receive and release other messages during cleanup (D3).
  st="$(kubectl -n "$t" get batchtrainingjob "$r" --ignore-not-found -o name 2>/dev/null)" || die "read request: READ_FAILED"
  [[ -z "$st" ]] || die "request $t/$r still exists: disable it in Git first"
  st="$(kubectl -n "$t" get scaledjob "batch-$r" --ignore-not-found -o name 2>/dev/null)" || die "read scaledjob: READ_FAILED"
  [[ -z "$st" ]] || die "scaledjob $t/batch-$r still exists: wait for kro to remove it"
  [[ "$(annotation_set "$t" batch-train)" == yes ]] || die "sa $t/batch-train has no role: run 'window.sh annotate'"
  n="zdr-cleanup-$r-$(date +%s)"
  cfg
  jq -n --arg n "$n" --arg ns "$t" --arg img "$IMG" --arg t "$t" --arg r "$r" \
        --arg q "$(cfg_get '.queue_url')" --arg reg "$(region)" \
    '{apiVersion:"batch/v1",kind:"Job",
      metadata:{name:$n,namespace:$ns,labels:{"app.kubernetes.io/name":"zdr-batch-cleanup","rag.zero-drift.io/tenant":$t}},
      spec:{backoffLimit:0,activeDeadlineSeconds:300,ttlSecondsAfterFinished:600,
        template:{metadata:{labels:{"app.kubernetes.io/name":"zdr-batch-cleanup","rag.zero-drift.io/tenant":$t}},
          spec:{restartPolicy:"Never",serviceAccountName:"batch-train",automountServiceAccountToken:false,
            securityContext:{runAsNonRoot:true,seccompProfile:{type:"RuntimeDefault"}},
            containers:[{name:"cleanup",image:$img,args:["cleanup"],
              env:[{name:"TENANT",value:$t},{name:"REQUEST_ID",value:$r},{name:"QUEUE_URL",value:$q},
                   {name:"AWS_REGION",value:$reg},{name:"AWS_DEFAULT_REGION",value:$reg}],
              securityContext:{allowPrivilegeEscalation:false,readOnlyRootFilesystem:true,capabilities:{drop:["ALL"]}},
              resources:{requests:{cpu:"50m",memory:"96Mi"},limits:{memory:"192Mi"}}}]}}}}' \
    | kubectl apply -f - >/dev/null 2>&1 || die "cleanup Job: WRITE_FAILED"
  if ! kubectl -n "$t" wait --for=condition=complete "job/$n" --timeout=300s >/dev/null 2>&1; then
    kubectl -n "$t" logs "job/$n" 2>/dev/null | grep -E '"event"' || true
    die "cleanup Job did not complete: NOT_COMPLETE"
  fi
  kubectl -n "$t" logs "job/$n" 2>/dev/null | grep -E '"event": "CLEANUP"' || echo "INFO  cleanup Job log: READ_FAILED"
  kubectl -n "$t" delete jobs -l "scaledjob.keda.sh/name=batch-$r" --wait=true --timeout=120s >/dev/null 2>&1 || die "delete Jobs of $t/$r: WRITE_FAILED"
  # Success only after a successful final read with no Job and no Pod left.
  local j p
  j="$(kubectl -n "$t" get jobs -l "scaledjob.keda.sh/name=batch-$r" -o name 2>/dev/null)" || die "count Jobs: READ_FAILED"
  p="$(kubectl -n "$t" get pods -l "app.kubernetes.io/name=batch-train,batch.zero-drift.io/request=$r" -o name 2>/dev/null)" || die "count Pods: READ_FAILED"
  j="$(grep -c . <<<"$j" || true)"; p="$(grep -c . <<<"$p" || true)"
  [[ "$j" == 0 && "$p" == 0 ]] || die "after cleanup $t/$r still has jobs=$j pods=$p"
  echo "OK    leftover messages of $t/$r cleaned; jobs=0 pods=0"
}

case "${1:-}" in
  status) cmd_status ;;
  annotate) cmd_annotate ;;
  batch-config) cmd_batch_config ;;
  purge) cmd_purge ;;
  cleanup) shift; cmd_cleanup "$@" ;;
  *) sed -n '2,14p' "$0"; exit 2 ;;
esac
