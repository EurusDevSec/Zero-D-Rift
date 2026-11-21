#!/usr/bin/env bash
# P4 window helper (DRF-56, SPEC-P4 P4-T4.1 B-E). Applies the window-only
# objects and runs the platform Jobs and the probes. Values that hold the account
# ID, a role ARN, the master secret ARN or the RDS host are read from
# `terraform output -json rag_platform_config` into variables and go straight
# into kubectl; they are never printed. Run from the repository root, with the
# EKS kubeconfig and, except in LAB mode, AWS_PROFILE/AWS_REGION exported.
#
#   window.sh status                          # yes/no for every window object
#   window.sh annotate                        # role ARNs on rag-db-admin, rag-bootstrap, provider-aws-s3
#   window.sh db-init                         # once per window; needs RUN_ID, EXPIRES_AT
#   window.sh platform-config                 # only after db-init Complete; needs RUN_ID, EXPIRES_AT
#   window.sh bootstrap-identity off|on       # retry case: drop / restore the bootstrap role annotation
#   window.sh probe platform                  # TLS, pgvector, rag_bootstrap attributes, master secret denied
#   window.sh probe sandbox TENANT NAME       # independent check of one sandbox
#   window.sh probe cross TENANT NAME OTHER   # negatives for TENANT's identity against OTHER
#   window.sh cleanup TENANT NAME             # D9 cleanup Job, then the Job Pods kro left without owner
#
# LAB=1: probes only, against labs/p4-kind (file secret store, no TLS, no bucket).
set -euo pipefail
export MSYS_NO_PATHCONV=1

cd "$(dirname "$0")/../.."
HERE=infra/p4-window
TF=infra/terraform
PLATFORM_NS=zdr-platform
IMG="$(grep -m1 -o 'ghcr.io/eurusdevsec/zero-d-rift/rag-sandbox@sha256:[0-9a-f]\{64\}' gitops/platform/rgd/rag-sandbox.yaml)"
LAB="${LAB:-0}"
[[ -n "$IMG" ]] || { echo "FAIL  image digest not found in the RGD"; exit 1; }

die() { echo "FAIL  $*"; exit 1; }
need_run_vars() {
  [[ "${RUN_ID:-}" =~ ^P4-L3-[0-9]{8}-[0-9]{2}$ ]] || die "export RUN_ID=P4-L3-YYYYMMDD-NN (window request)"
  [[ "${EXPIRES_AT:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || die "export EXPIRES_AT=YYYY-MM-DDTHH:MM:SSZ"
}
tags() { echo "Project=Zero-D-Rift,Owner=HoangLV,Environment=PoC,ManagedBy=RAGSandbox,RunId=$RUN_ID,ExpiresAt=$EXPIRES_AT"; }

# The sensitive Terraform output, read once per call. Never echo $CFG.
CFG=""
cfg() {
  [[ "$LAB" == 1 ]] && die "not available with LAB=1"
  if [[ -z "$CFG" ]]; then
    CFG="$(terraform -chdir="$TF" output -json rag_platform_config)"
    [[ "$CFG" != null && -n "$CFG" ]] || die "rag_platform_config is null: was the plan applied with enable_rag_platform=true?"
  fi
}
cfg_get() { jq -er "$1" <<<"$CFG"; }
# Join two JSON arrays (no process substitution: the Windows jq cannot read /dev/fd).
concat() { jq -n --argjson a "$1" --argjson b "$2" '$a + $b'; }
region() { terraform -chdir="$TF" output -raw region; }

# Restricted Pod Security (namespace labels in Git) for every Pod this script starts.
POD_SC='{"runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}}'
CTR_SC='{"allowPrivilegeEscalation":false,"readOnlyRootFilesystem":true,"capabilities":{"drop":["ALL"]}}'

# Common env for the platform commands and the probes, as a JSON array.
db_env() {
  if [[ "$LAB" == 1 ]]; then
    jq -n '[{name:"SECRET_BACKEND",value:"file"},{name:"SECRET_DIR",value:"/secrets"},
            {name:"DB_HOST",value:"lab-db.zdr-platform.svc"},{name:"DB_PORT",value:"5432"},
            {name:"DB_SSLMODE",value:"disable"},{name:"PROBE_BUCKETS",value:"off"}]'
  else
    cfg
    jq -n --arg host "$(cfg_get .db_host)" --arg port "$(cfg_get .db_port)" --arg region "$(region)" \
      '[{name:"SECRET_BACKEND",value:"aws"},{name:"AWS_REGION",value:$region},{name:"AWS_DEFAULT_REGION",value:$region},
        {name:"DB_HOST",value:$host},{name:"DB_PORT",value:$port},{name:"DB_SSLMODE",value:"verify-full"}]'
  fi
}

# LAB only: the kind lab reaches secrets through PVC lab-secrets (labs/p4-kind/lab.yaml).
lab_volume() { # namespace -> {volumes, mounts}
  if [[ "$LAB" != 1 ]]; then echo '{"volumes":[],"mounts":[]}'; return; fi
  local mount=/secrets
  [[ "$1" == "$PLATFORM_NS" ]] || mount="/secrets/zero-drift/rag/$1"
  jq -n --arg m "$mount" '{volumes:[{name:"secrets",persistentVolumeClaim:{claimName:"lab-secrets"}}],
                          mounts:[{name:"secrets",mountPath:$m,readOnly:true}]}'
}

# Wait for a Pod to finish; print its log; return 0 only if it Succeeded.
finish_pod() {
  local ns=$1 pod=$2 phase="" i
  for i in $(seq 1 90); do
    phase="$(kubectl -n "$ns" get pod "$pod" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    [[ "$phase" == Succeeded || "$phase" == Failed ]] && break
    sleep 2
  done
  kubectl -n "$ns" logs "$pod" || true
  [[ "$phase" == Succeeded ]]
}

run_probe() { # namespace serviceaccount extra-env-json args...
  local ns=$1 sa=$2 extra=$3; shift 3
  local pod="zdr-probe-$(date +%s)-$RANDOM" env vol rc=0
  env="$(concat "$(db_env)" "$extra")"
  vol="$(lab_volume "$ns")"
  jq -n --arg ns "$ns" --arg pod "$pod" --arg sa "$sa" --arg img "$IMG" --arg code "$(cat "$HERE/probe.py")" \
        --argjson env "$env" --argjson vol "$vol" --argjson podsc "$POD_SC" --argjson ctrsc "$CTR_SC" \
        --args '{apiVersion:"v1",kind:"Pod",
          metadata:{name:$pod,namespace:$ns,labels:{"app.kubernetes.io/name":"zdr-probe"}},
          spec:{restartPolicy:"Never",activeDeadlineSeconds:150,serviceAccountName:$sa,
                automountServiceAccountToken:false,securityContext:$podsc,volumes:$vol.volumes,
                containers:[{name:"probe",image:$img,command:["python","-c",$code],args:$ARGS.positional,
                             env:$env,securityContext:$ctrsc,volumeMounts:$vol.mounts}]}}' "$@" \
    | kubectl apply -f - >/dev/null
  finish_pod "$ns" "$pod" || rc=1
  kubectl -n "$ns" delete pod "$pod" --wait=false >/dev/null
  return $rc
}

job_manifest() { # name serviceaccount env-json args-json labels-json
  jq -n --arg name "$1" --arg ns "$PLATFORM_NS" --arg sa "$2" --arg img "$IMG" \
        --argjson env "$3" --argjson args "$4" --argjson labels "$5" \
        --argjson podsc "$POD_SC" --argjson ctrsc "$CTR_SC" \
    '{apiVersion:"batch/v1",kind:"Job",metadata:{name:$name,namespace:$ns,labels:$labels},
      spec:{backoffLimit:0,activeDeadlineSeconds:300,
            template:{metadata:{labels:$labels},
                      spec:{restartPolicy:"Never",serviceAccountName:$sa,automountServiceAccountToken:false,
                            securityContext:$podsc,
                            containers:[{name:$args[0],image:$img,args:$args,env:$env,securityContext:$ctrsc}]}}}}'
}

wait_job() { # name -> 0 if Complete
  local name=$1 s i
  for i in $(seq 1 160); do
    s="$(kubectl -n "$PLATFORM_NS" get job "$name" -o jsonpath='{range .status.conditions[?(@.status=="True")]}{.type}{" "}{end}' 2>/dev/null || true)"
    [[ "$s" == *Complete* ]] && { kubectl -n "$PLATFORM_NS" logs "job/$name" || true; return 0; }
    [[ "$s" == *Failed* ]] && { kubectl -n "$PLATFORM_NS" logs "job/$name" || true; return 1; }
    sleep 2
  done
  return 1
}

annotation_set() { # namespace sa -> yes/no
  [[ -n "$(kubectl -n "$1" get sa "$2" -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null)" ]] && echo yes || echo no
}

cmd_status() {
  echo "image                          $IMG"
  echo "sa rag-db-admin role           $(annotation_set "$PLATFORM_NS" rag-db-admin)"
  echo "sa rag-bootstrap role          $(annotation_set "$PLATFORM_NS" rag-bootstrap)"
  local drc pod
  drc="$(kubectl get deploymentruntimeconfig provider-aws-s3 -o jsonpath='{.spec.serviceAccountTemplate.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || true)"
  echo "provider-aws-s3 role (DRC)     $([[ "$drc" == *:role/zero-drift-rag-crossplane-s3 ]] && echo "yes, RAG role" || echo no)"
  pod="$(kubectl -n crossplane-system get pods -o name 2>/dev/null | grep provider-aws-s3 | head -1 || true)"
  echo "provider pod has AWS_ROLE_ARN  $([[ -n "$pod" ]] && kubectl -n crossplane-system get "$pod" -o json | jq -e '[.spec.containers[0].env[]?.name] | index("AWS_ROLE_ARN") != null' >/dev/null && echo yes || echo no)"
  echo "job db-init                    $(kubectl -n "$PLATFORM_NS" get job db-init -o jsonpath='{.status.conditions[?(@.status=="True")].type}' 2>/dev/null || echo absent)"
  echo "configmap platform-config      $(kubectl -n "$PLATFORM_NS" get configmap platform-config >/dev/null 2>&1 && echo present || echo absent)"
}

cmd_annotate() {
  cfg
  local k arn
  for k in db-admin bootstrap; do
    arn="$(cfg_get ".role_arns[\"$k\"]")"
    [[ "$arn" == *":role/zero-drift-rag-$k" ]] || die "role_arns[$k] is not the zero-drift-rag-$k role"
    kubectl -n "$PLATFORM_NS" annotate sa "rag-$k" "eks.amazonaws.com/role-arn=$arn" --overwrite >/dev/null
    echo "OK    sa/rag-$k annotated with role zero-drift-rag-$k"
  done
  arn="$(cfg_get '.role_arns["crossplane-s3"]')"
  [[ "$arn" == *":role/zero-drift-rag-crossplane-s3" ]] || die "role_arns[crossplane-s3] is not the RAG Crossplane role"
  kubectl patch deploymentruntimeconfig provider-aws-s3 --type merge \
    -p "$(jq -n --arg a "$arn" '{spec:{serviceAccountTemplate:{metadata:{annotations:{"eks.amazonaws.com/role-arn":$a}}}}}')" >/dev/null
  unset arn
  echo "OK    DeploymentRuntimeConfig provider-aws-s3 -> role zero-drift-rag-crossplane-s3"
  # The EKS webhook injects the IRSA token only into new Pods.
  kubectl -n crossplane-system delete $(kubectl -n crossplane-system get pods -o name | grep provider-aws-s3) --wait=true >/dev/null
  sleep 5
  kubectl -n crossplane-system wait --for=condition=Ready pod -l pkg.crossplane.io/provider=provider-aws-s3 --timeout=180s >/dev/null \
    || kubectl -n crossplane-system get pods | grep provider-aws-s3
  cmd_status
}

cmd_db_init() {
  need_run_vars; cfg
  [[ "$(annotation_set "$PLATFORM_NS" rag-db-admin)" == yes ]] || die "run 'window.sh annotate' first"
  if kubectl -n "$PLATFORM_NS" get job db-init >/dev/null 2>&1; then
    echo "INFO  job db-init exists; showing its result (db-init runs once per window)"
    wait_job db-init; return
  fi
  local env
  env="$(concat "$(db_env)" "$(jq -n --arg m "$(cfg_get .master_secret_arn)" --arg t "$(tags)" \
          '[{name:"MASTER_SECRET_ID",value:$m},{name:"SECRET_TAGS",value:$t}]')")"
  job_manifest db-init rag-db-admin "$env" '["db-init"]' '{"app.kubernetes.io/name":"rag-db-init"}' \
    | kubectl apply -f - >/dev/null
  echo "OK    job/db-init created $(date -u +%T)Z"
  wait_job db-init || die "db-init did not complete (stop condition: fix once, else teardown)"
}

cmd_platform_config() {
  need_run_vars; cfg
  [[ "$(kubectl -n "$PLATFORM_NS" get job db-init -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null)" == True ]] \
    || die "job db-init is not Complete: platform-config opens the request path and must wait for it"
  local a prefix
  a="$(cfg_get '.role_arns["tenant-a"]')"
  [[ "$a" == *":role/zero-drift-rag-tenant-a" ]] || die "role_arns[tenant-a] is not the zero-drift-rag-tenant-a role"
  prefix="${a%tenant-a}"
  [[ "$(cfg_get '.role_arns["tenant-b"]')" == "${prefix}tenant-b" ]] || die "tenant-b role does not share the prefix"
  jq -n --arg ns "$PLATFORM_NS" --arg host "$(cfg_get .db_host)" --arg port "$(cfg_get .db_port)" \
        --arg region "$(region)" --arg prefix "$prefix" --arg run "$RUN_ID" --arg exp "$EXPIRES_AT" \
    '{apiVersion:"v1",kind:"ConfigMap",metadata:{name:"platform-config",namespace:$ns},
      data:{dbHost:$host,dbPort:$port,region:$region,tenantRoleArnPrefix:$prefix,runId:$run,expiresAt:$exp}}' \
    | kubectl apply -f - >/dev/null
  unset a prefix
  echo "OK    configmap/platform-config applied $(date -u +%T)Z (runId $RUN_ID, expiresAt $EXPIRES_AT)"
}

cmd_bootstrap_identity() {
  case "${1:-}" in
    off) kubectl -n "$PLATFORM_NS" annotate sa rag-bootstrap eks.amazonaws.com/role-arn- >/dev/null
         echo "OK    sa/rag-bootstrap has no role: new bootstrap Pods get no AWS credential" ;;
    on)  cfg
         kubectl -n "$PLATFORM_NS" annotate sa rag-bootstrap "eks.amazonaws.com/role-arn=$(cfg_get '.role_arns["bootstrap"]')" --overwrite >/dev/null
         echo "OK    sa/rag-bootstrap annotated with role zero-drift-rag-bootstrap" ;;
    *)   die "usage: window.sh bootstrap-identity off|on" ;;
  esac
}

cmd_probe() {
  case "${1:-}" in
    platform)
      [[ $# -eq 1 ]] || die "usage: window.sh probe platform"
      local extra='[]'
      if [[ "$LAB" != 1 ]]; then
        cfg; extra="$(jq -n --arg m "$(cfg_get .master_secret_arn)" '[{name:"MASTER_SECRET_ID",value:$m}]')"
      fi
      run_probe "$PLATFORM_NS" rag-bootstrap "$extra" platform ;;
    sandbox)
      [[ $# -eq 3 ]] || die "usage: window.sh probe sandbox TENANT NAME"
      run_probe "$2" "rag-$3" '[]' sandbox "$2" "$3" ;;
    cross)
      [[ $# -eq 4 ]] || die "usage: window.sh probe cross TENANT NAME OTHER"
      run_probe "$2" "rag-$3" '[]' cross "$2" "$3" "$4" ;;
    *) die "usage: window.sh probe platform | sandbox TENANT NAME | cross TENANT NAME OTHER" ;;
  esac
}

cmd_cleanup() {
  [[ $# -eq 2 ]] || die "usage: window.sh cleanup TENANT NAME"
  need_run_vars
  local t=$1 n=$2 job="cleanup-$1-$2" env labels
  [[ "$t" =~ ^tenant-(a|b)$ && "$n" =~ ^[a-z]([a-z0-9-]{0,30}[a-z0-9])?$ && "$n" != *--* ]] || die "bad tenant or name"
  kubectl -n "$t" get ragsandbox "$n" >/dev/null 2>&1 && die "request $t/$n still exists: remove it from Git first"
  env="$(concat "$(db_env)" "$(jq -n --arg t "$t" --arg n "$n" '[{name:"SANDBOX_TENANT",value:$t},{name:"SANDBOX_NAME",value:$n}]')")"
  labels="$(jq -n --arg t "$t" --arg n "$n" '{"app.kubernetes.io/name":"rag-cleanup","rag.zero-drift.io/cleanup-of":($t+"."+$n)}')"
  kubectl -n "$PLATFORM_NS" delete job "$job" --ignore-not-found >/dev/null
  job_manifest "$job" rag-bootstrap "$env" '["cleanup"]' "$labels" | kubectl apply -f - >/dev/null
  echo "OK    job/$job created $(date -u +%T)Z"
  wait_job "$job" || die "cleanup failed"
  # kro deletes bootstrap Jobs but leaves their Pods without owner (spike 14/11, D9).
  kubectl -n "$PLATFORM_NS" delete pods -l "rag.zero-drift.io/tenant=$t,rag.zero-drift.io/sandbox=$n" --ignore-not-found
}

case "${1:-}" in
  status) cmd_status ;;
  annotate) cmd_annotate ;;
  db-init) cmd_db_init ;;
  platform-config) cmd_platform_config ;;
  bootstrap-identity) shift; cmd_bootstrap_identity "$@" ;;
  probe) shift; cmd_probe "$@" ;;
  cleanup) shift; cmd_cleanup "$@" ;;
  *) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
