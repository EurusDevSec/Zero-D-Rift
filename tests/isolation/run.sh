#!/usr/bin/env bash
# P5 isolation suite (DRF-70, SPEC-P5 P5-T4.1). Runs every case, writes
# acceptance.json (case, threat, expected layer and result, observed result,
# UTC time, sanitized evidence) and exits 0 only when every case that ran matched.
#
#   MODE=kind CTX=kind-zdr-p5-iso tests/isolation/run.sh                    # dry run, no AWS
#   MODE=eks  CTX=<eks context> NET_PHASE=control  RUN_ID=... OUT=control.json tests/isolation/run.sh
#   MODE=eks  CTX=<eks context> NET_PHASE=enforced RUN_ID=... CONTROL=control.json tests/isolation/run.sh
#
# kind: cases that need EKS (VPC CNI NetworkPolicy, IMDS, IRSA, RDS, S3) are
# written as SKIPPED_NEEDS_EKS, never PASS. eks: nothing may be skipped.
# eks NET_PHASE=control runs only the network paths, with no NetworkPolicy in
# the tenant namespaces: every path must be open, so a later deny is the policy's
# doing (a failed or non-empty NetworkPolicy list stops it). NET_PHASE=enforced
# runs everything; it needs the control file of RUN_ID-control for the same
# sandbox with every case PASS, the Git NetworkPolicies present and programmed
# (PolicyEndpoints), and Kyverno in Deny. A probe result counts only when its
# Job is Complete.
# The P4 negatives run through infra/p4-window/window.sh probe, which uses the
# current kubectl context, so CTX must be the current context.
# Admission cases are server dry runs. Network and IAM cases run as Jobs: the
# VPC CNI does not enforce NetworkPolicy on a Pod without an owner. Everything
# the suite creates carries app.kubernetes.io/name=zdr-isolation; it is removed
# and the removal verified (case "cleanup") before RESULT, and again from an
# exit trap on an abnormal exit. The context name, account IDs and ARNs are
# scrubbed from every line written.
set -euo pipefail
# "pod ... | case_admit" must record in this shell, not in a pipeline subshell,
# or its result (and a FAIL) would be lost.
shopt -s lastpipe
cd "$(dirname "$0")/../.."

MODE="${MODE:?MODE=kind|eks}"; CTX="${CTX:?CTX=<kubectl context>}"
OUT="${OUT:-acceptance.json}"; RUN_ID="${RUN_ID:-dry-run}"; SANDBOX="${SANDBOX:-docs-qa}"
NET_PHASE="${NET_PHASE:-}"; CONTROL="${CONTROL:-}"
K="kubectl --context $CTX"
LBL=app.kubernetes.io/name=zdr-isolation
IMG="$(grep -m1 -o 'ghcr.io/eurusdevsec/zero-d-rift/rag-sandbox@sha256:[0-9a-f]\{64\}' gitops/platform/rgd/rag-sandbox.yaml)"
cases='[]'; bad=0
if [[ "$MODE" == eks ]]; then
    # window.sh probe uses the current context: refuse to mix two clusters (no name printed).
    [[ "$(kubectl config current-context)" == "$CTX" ]] || { echo "FAIL  CTX is not the current kubectl context"; exit 1; }
    [[ "$NET_PHASE" == control || "$NET_PHASE" == enforced ]] || { echo "FAIL  eks needs NET_PHASE=control|enforced"; exit 1; }
    [[ "$NET_PHASE" == control || -s "$CONTROL" ]] || { echo "FAIL  NET_PHASE=enforced needs CONTROL=<control run json>"; exit 1; }
fi

# Remove the context name, AWS account IDs, ARNs and EKS endpoints from a line.
scrub() {
    local s="${1//"$CTX"/<ctx>}"
    # The account-ID rule loops (one match per pass) so IDs that share a
    # separator (two 12-digit IDs joined by a comma) are all replaced.
    sed -E -e 's/arn:aws[a-z-]*:[^ "]*/<arn>/g' -e ':a' -e 's/(^|[^0-9])[0-9]{12}([^0-9]|$)/\1<acct>\2/' -e 'ta' \
           -e 's/[A-Za-z0-9.-]+\.eks\.amazonaws\.com/<eks-endpoint>/g' <<< "$s" | tr '\n' ' ' | sed 's/ $//'
}

# record ID THREAT LAYER EXPECTED OBSERVED EVIDENCE. Observed and evidence are
# scrubbed before they are printed or written.
record() {
    local res ev ob; ev="$(scrub "$6")"; ob="$(scrub "$5")"
    if [[ "$5" == SKIPPED_* ]]; then res="$5"
    elif [[ "$4" == "$5" ]]; then res=PASS
    else res=FAIL; bad=1; fi
    printf '%-18s %-6s %-26s expected=%-30s observed=%-30s %s\n' "$res" "$2" "$1" "$4" "$ob" "${ev:0:110}"
    cases="$(jq -c --arg id "$1" --arg t "$2" --arg l "$3" --arg e "$4" --arg o "$ob" --arg r "$res" \
        --arg ev "${ev:0:300}" --arg at "$(date -u +%FT%TZ)" \
        '. + [{id:$id, threat:$t, layer:$l, expected:$e, observed:$o, result:$r, utc:$at, evidence:$ev}]' <<< "$cases")"
}

# count_list NS RESOURCES: number of suite objects, or "error" when the list
# itself fails (a Forbidden or unreachable API is not "none left").
count_list() { # NS RESOURCES [SELECTOR]
    local out; out="$($K -n "$1" get "$2" -l "${3:-$LBL}" -o name 2>/dev/null)" || { echo error; return; }
    grep -c . <<< "$out" || true
}
# window.sh probe Pods (the P4 wrapper) carry their own label and are deleted
# with --wait=false: wait for them to be gone and count them too. Only this
# run's probes: window.sh adds rag.zero-drift.io/probe-run=$PROBE_RUN, so a
# probe that another run or a person started is never deleted here.
export PROBE_RUN="iso-$(date -u +%Y%m%d%H%M%S)-$$-$RANDOM"
PROBE_LBL="app.kubernetes.io/name=zdr-probe,rag.zero-drift.io/probe-run=$PROBE_RUN"
# Delete what the suite created, then prove it is gone. Sets CLEANUP_STATE to
# verified-empty, left:<n> or unverified; returns 0 only for verified-empty.
CLEANUP_STATE=unverified; CLEANED=""
cleanup() {
    local argo n c left=0 unread=0
    for ns in tenant-a tenant-b; do
        $K -n "$ns" delete jobs,pods,serviceaccounts -l "$LBL" --wait=true --timeout=120s >/dev/null 2>&1 || true
    done
    argo="$($K get ns argocd --ignore-not-found -o name 2>/dev/null)" || argo=error
    [[ "$argo" == namespace/argocd ]] && { $K -n argocd delete applications.argoproj.io -l "$LBL" --wait=true --timeout=60s >/dev/null 2>&1 || true; }
    for n in tenant-a:jobs,pods,serviceaccounts tenant-b:jobs,pods,serviceaccounts ${argo:+argocd:applications.argoproj.io}; do
        [[ "$n" == argocd:* && "$argo" != namespace/argocd ]] && { [[ "$argo" == error ]] && unread=1; continue; }
        c="$(count_list "${n%%:*}" "${n#*:}")"
        if [[ "$c" == error ]]; then unread=1; else left=$((left + c)); fi
    done
    for ns in tenant-a tenant-b zdr-platform; do
        $K -n "$ns" delete pod -l "$PROBE_LBL" --wait=false >/dev/null 2>&1 || true
        $K -n "$ns" wait --for=delete pod -l "$PROBE_LBL" --timeout=120s >/dev/null 2>&1 || true
        c="$(count_list "$ns" pods "$PROBE_LBL")"
        if [[ "$c" == error ]]; then unread=1; else left=$((left + c)); fi
    done
    if (( unread )); then CLEANUP_STATE=unverified
    elif (( left )); then CLEANUP_STATE="left:$left"
    else CLEANUP_STATE=verified-empty; fi
    [[ "$CLEANUP_STATE" == verified-empty ]]
}
# Abnormal exit (set -e, a refusal): still clean up, and never exit 0 unverified.
on_exit() {
    local rc=$?
    [[ -n "$CLEANED" ]] && exit "$rc"
    cleanup || { echo "FAIL  cleanup: $CLEANUP_STATE (label $LBL)"; rc=1; }
    exit "$rc"
}
trap on_exit EXIT

# A restricted-compliant Pod that passes every guardrail; patches change one thing.
pod() { # NAME NS [CONTAINER_PATCH] [SPEC_PATCH] [LABEL_PATCH]
    local c="${3:-}" s="${4:-}" l="${5:-}"
    jq -n --arg n "$1" --arg ns "$2" --arg img "$IMG" --argjson c "${c:-null}" --argjson s "${s:-null}" \
          --argjson l "${l:-null}" '($c // {}) as $c | ($s // {}) as $s | ($l // {}) as $l | {apiVersion:"v1",kind:"Pod",
      metadata:{name:$n,namespace:$ns,labels:({"rag.zero-drift.io/tenant":$ns,"app.kubernetes.io/name":"zdr-isolation"} + $l)},
      spec:({restartPolicy:"Never",automountServiceAccountToken:false,
             securityContext:{runAsNonRoot:true,runAsUser:10001,seccompProfile:{type:"RuntimeDefault"}},
             containers:[({name:"c",image:$img,command:["sleep","60"],
               securityContext:{allowPrivilegeEscalation:false,capabilities:{drop:["ALL"]}},
               resources:{requests:{cpu:"50m",memory:"96Mi"},limits:{memory:"192Mi"}}} * $c)]} * $s)}'
}

# job NS NAME PYTHON_CODE [SPEC_PATCH] [ARGS...] -> prints the last "RESULT ..."
# line, read only when the Job has condition Complete=True. A Job that failed,
# hit its deadline or was never created prints "RESULT ERROR job-<state>", even
# if its Pod logged a RESULT line first. The Job owns its Pod.
job() {
    local ns=$1 n=$2 code=$3 spec="${4:-}" state=timeout i cond line
    shift 4 || shift $#
    if ! pod "$n" "$ns" "$(jq -nc --arg c "$code" '{command:(["python","-c",$c] + $ARGS.positional)}' --args "$@")" "$spec" \
        | jq '{apiVersion:"batch/v1",kind:"Job",metadata:{name:.metadata.name,namespace:.metadata.namespace,labels:.metadata.labels},
               spec:{backoffLimit:0,activeDeadlineSeconds:150,template:{metadata:{labels:.metadata.labels},spec:.spec}}}' \
        | $K apply -f - >/dev/null 2>&1; then
        echo "RESULT ERROR job-apply"; return
    fi
    for i in $(seq 1 85); do
        cond=" $($K -n "$ns" get job "$n" -o jsonpath='{range .status.conditions[?(@.status=="True")]}{.type}{" "}{end}' 2>/dev/null || true) "
        [[ "$cond" == *" Complete "* ]] && { state=complete; break; }
        [[ "$cond" == *" Failed "* ]] && { state=failed; break; }
        sleep 2
    done
    # The log read itself must succeed: a partial read that failed is no result.
    line=""; local logs
    if [[ "$state" == complete ]]; then
        if logs="$($K -n "$ns" logs "job/$n" 2>/dev/null)"; then
            line="$(grep '^RESULT ' <<< "$logs" | tail -1 || true)"
        else state=log-error; fi
    fi
    $K -n "$ns" delete job "$n" --cascade=foreground --wait=true --timeout=60s >/dev/null 2>&1 || true
    if [[ "$state" != complete ]]; then echo "RESULT ERROR job-$state"
    elif [[ -n "$line" ]]; then echo "$line"
    else echo "RESULT ERROR no-output"; fi
}

# Which layer answered an admission attempt. A webhook that could not be called
# is an error, not a policy decision.
admit() { # manifest on stdin -> prints "OBSERVED|evidence"
    local out p
    if out="$($K create --dry-run=server -f - 2>&1)"; then echo "allow|$out"; return; fi
    case "$out" in
        *"failed calling webhook"*)    echo "error:webhook|$out" ;;
        *"violates PodSecurity"*)      echo "deny:pod-security|$out" ;;
        *'vpol.validate.kyverno.svc-fail" denied the request'*)
            p="$(grep -o 'Policy zdr-[a-z-]* failed' <<< "$out" | head -1 | cut -d' ' -f2)"
            echo "deny:kyverno:${p:-unknown}|$out" ;;
        *"maximum memory usage per Container"*) echo "deny:limitrange|$out" ;;
        *"exceeded quota"*)            echo "deny:quota|$out" ;;
        *)                             echo "error:other|$out" ;;
    esac
}
case_admit() { # ID THREAT EXPECTED  (manifest on stdin)
    local r; r="$(admit)"; record "$1" "$2" admission "$3" "${r%%|*}" "${r#*|}"
}
# A SubjectAccessReview, not "can-i": can-i prints "no" also when the
# authorizer reports an evaluation error. Here allowed=true is allow,
# allowed=false without evaluationError is deny:rbac, anything else (an error,
# no answer) is error:rbac. Groups mirror what impersonation (--as) would send.
case_rbac() { # ID THREAT EXPECTED VERB RESOURCE[.GROUP] NS-or-- USER [GROUP]
    local res="${5%%.*}" grp="" ans
    [[ "$5" == *.* ]] && grp="${5#*.}"
    ans="$(jq -n --arg v "$4" --arg r "$res" --arg g "$grp" --arg ns "$6" --arg u "$7" --arg gr "${8:-}" '
        ($u | startswith("system:serviceaccount:")) as $sa |
        {apiVersion:"authorization.k8s.io/v1", kind:"SubjectAccessReview",
         spec:{user:$u,
               groups:((if $gr != "" then [$gr] else [] end)
                       + (if $sa then ["system:serviceaccounts", "system:serviceaccounts:" + ($u | split(":")[2])] else [] end)
                       + ["system:authenticated"]),
               resourceAttributes:({verb:$v, resource:$r, group:$g} + (if $ns != "-" then {namespace:$ns} else {} end))}}' \
        | $K create -f - -o json 2>/dev/null \
        | jq -r '.status | (if (.evaluationError // "") != "" then "error:rbac" elif .allowed == true then "allow"
                 elif .allowed == false then "deny:rbac" else "error:rbac" end) + "|" + (.reason // "")' 2>/dev/null || true)"
    [[ -n "$ans" ]] || ans="error:rbac|no SubjectAccessReview answer"
    record "$1" "$2" rbac "$3" "${ans%%|*}" "SubjectAccessReview $4 $5 ${6} as $7: ${ans#*|}"
}

# finish PHASE: clean up and record the verified result as a case, then write
# the JSON, then print RESULT. PASS is printed only after cleanup is verified.
finish() {
    cleanup || true; CLEANED=1
    record cleanup T15 harness verified-empty "$CLEANUP_STATE" "suite objects (label $LBL) after the run"
    jq -n --arg run "$RUN_ID" --arg mode "$MODE" --arg ph "$1" --arg sb "$SANDBOX" --arg img "$IMG" --argjson c "$cases" \
        '{run_id:$run, mode:$mode, net_phase:$ph, sandbox:$sb, image:$img, cases:$c,
          summary:{total:($c|length), pass:([$c[]|select(.result=="PASS")]|length),
                   fail:([$c[]|select(.result=="FAIL")]|length),
                   skipped:([$c[]|select(.result|startswith("SKIPPED"))]|length)}}' > "$OUT"
    echo
    jq -r '.summary | "total \(.total), pass \(.pass), fail \(.fail), skipped \(.skipped)"' "$OUT"
    if (( bad )); then echo "RESULT: FAIL ($1, $OUT)"; exit 1; fi
    if [[ "$MODE" == eks && "$(jq '.summary.skipped' "$OUT")" != 0 ]]; then echo "RESULT: FAIL (skipped cases in eks mode)"; exit 1; fi
    echo "RESULT: PASS ($1, $OUT)"; exit 0
}

echo "isolation suite mode=$MODE phase=${NET_PHASE:-n/a} run=$RUN_ID $(date -u +%FT%TZ)"

# --- T10, T06: network paths (D5), needs VPC CNI NetworkPolicy ------------------
# connect: a Job in TENANT opens TCP to HOST:PORT. Only a timeout counts as a
# NetworkPolicy deny (the node agent drops); refused, DNS and other errors fail.
NETCODE='import socket, sys, time
host, port = sys.argv[1], int(sys.argv[2])
time.sleep(20)  # standard mode: a new Pod is default-allow until its policies are programmed
try:
    addr = socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_STREAM)[0][4]
except Exception as e:
    print("RESULT ERROR dns", type(e).__name__); sys.exit(0)
s = socket.socket(); s.settimeout(5)
try:
    s.connect(addr); print("RESULT OPEN")
except socket.timeout:
    print("RESULT TIMEOUT")
except ConnectionRefusedError:
    print("RESULT ERROR refused")
except Exception as e:
    print("RESULT ERROR", type(e).__name__)'
net_case() { # ID THREAT EXPECTED TENANT HOST PORT
    local r obs; r="$(job "$4" "zdr-iso-net-$RANDOM" "$NETCODE" '' "$5" "$6")"
    case "$r" in
        "RESULT OPEN") obs=allow ;; "RESULT TIMEOUT") obs=deny:network ;;
        *) obs="error:$(cut -d' ' -f3 <<< "$r")" ;;
    esac
    record "$1" "$2" networkpolicy "$3" "$obs" "$4 -> $5:$6: ${r#RESULT }"
}
# NetworkPolicies of TENANT in Git, by name.
# Windows Python prints CRLF; the PolicyEndpoint list from kubectl has none (found in window P5-L3-20261125-01).
git_np() { python -I -c 'import sys,yaml; print("\n".join(d["metadata"]["name"] for d in yaml.safe_load_all(open(sys.argv[1])) if d and d["metadata"]["namespace"] == sys.argv[2]))' gitops/platform/tenants/networkpolicy.yaml "$1" | tr -d '\r' | LC_ALL=C sort -u; }
NETS=("T10-own-app T10 tenant-a rag-$SANDBOX.tenant-a.svc 8080"
      "T10-a-to-b T10 tenant-a rag-$SANDBOX.tenant-b.svc 8080"
      "T10-b-to-a T10 tenant-b rag-$SANDBOX.tenant-a.svc 8080"
      "T06-metadata T06 tenant-a 169.254.169.254 80")
if [[ "$MODE" != eks ]]; then
    for c in T10-own-app T10-a-to-b T10-b-to-a T06-metadata; do
        record "$c" "${c%%-*}" networkpolicy see-eks SKIPPED_NEEDS_EKS "kind has no VPC CNI NetworkPolicy"
    done
elif [[ "$NET_PHASE" == control ]]; then
    # The list must succeed and be empty: a Forbidden list is not "no policy".
    for t in tenant-a tenant-b; do
        if nps="$($K -n "$t" get networkpolicies -o name 2>/dev/null)"; then
            c="$(grep -c . <<< "$nps" || true)"; o="$([[ "$c" == 0 ]] && echo none || echo "present:$c")"
        else o=error:list; fi
        record "net-control-$t" T10 networkpolicy none "$o" "$t NetworkPolicies before the control run"
    done
    # A path probed with policies present (or unknown) proves nothing: stop here.
    (( bad )) || for c in "${NETS[@]}"; do set -- $c; net_case "$1" "$2" allow "$3" "$4" "$5"; done
else
    # The receipt: a control run of this window (RUN_ID-control) and this
    # sandbox, with every case PASS. Only fixed codes reach the output.
    o="$(jq -r --arg run "$RUN_ID-control" --arg sb "$SANDBOX" '
        if .mode != "eks" or .net_phase != "control" then "not-a-control-run"
        elif .run_id != $run then "other-run"
        elif .sandbox != $sb then "other-sandbox"
        elif (.summary.fail != 0) or (.summary.pass != .summary.total) or ([.cases[] | select(.result != "PASS")] | length) != 0 then "control-not-passing"
        else "ok" end' "$CONTROL" 2>/dev/null || echo unreadable)"
    case "$o" in ok|not-a-control-run|other-run|other-sandbox|control-not-passing) ;; *) o=unreadable ;; esac
    record net-control-receipt T10 networkpolicy ok "$o" "control run $RUN_ID-control, sandbox $SANDBOX"
    # The control run opened the same paths before the policies existed.
    for c in "${NETS[@]}"; do set -- $c
        o="$(jq -r --arg id "$1" '[.cases[] | select(.id == $id)][0] | if . == null then "missing"
              elif .result == "PASS" and .observed == "allow" then "allow" else "not-allow" end' "$CONTROL" 2>/dev/null || echo unreadable)"
        case "$o" in allow|not-allow|missing) ;; *) o=unreadable ;; esac
        record "$1-control" "$2" networkpolicy allow "$o" "same path in the control run"
    done
    # Every Git NetworkPolicy exists and the node agent has programmed it.
    for t in tenant-a tenant-b; do
        want="$(git_np "$t")"; got=""
        for i in $(seq 1 24); do
            got="$($K -n "$t" get policyendpoints.networking.k8s.aws -o jsonpath='{range .items[*]}{.spec.policyRef.name}{"\n"}{end}' 2>/dev/null | LC_ALL=C sort -u || true)"
            [[ "$got" == "$want" ]] && break; sleep 5
        done
        record "net-programmed-$t" T10 networkpolicy programmed "$([[ "$got" == "$want" ]] && echo programmed || echo missing)" \
            "$t PolicyEndpoints for: $(tr '\n' ' ' <<< "$want")"
    done
    net_case T10-own-app  T10 allow        tenant-a "rag-$SANDBOX.tenant-a.svc" 8080
    net_case T10-a-to-b   T10 deny:network tenant-a "rag-$SANDBOX.tenant-b.svc" 8080
    net_case T10-b-to-a   T10 deny:network tenant-b "rag-$SANDBOX.tenant-a.svc" 8080
    net_case T06-metadata T06 deny:network tenant-a 169.254.169.254 80
fi

if [[ "$NET_PHASE" == control ]]; then finish control; fi

# --- T04: Kubernetes RBAC (D1, D2) ----------------------------------------------
DEV=dev-a; GRP=zdr:tenant-a:developers; SA=system:serviceaccount:tenant-a:default
WSA=system:serviceaccount:tenant-a:rag-$SANDBOX   # the sandbox workload identity
case_rbac T04-own-pods       T04 allow     get    pods                 tenant-a "$DEV" "$GRP"
case_rbac T04-b-pods         T04 deny:rbac list   pods                 tenant-b "$DEV" "$GRP"
case_rbac T04-b-sandboxes    T04 deny:rbac get    ragsandboxes.kro.run tenant-b "$DEV" "$GRP"
case_rbac T04-b-sas          T04 deny:rbac list   serviceaccounts      tenant-b "$DEV" "$GRP"
case_rbac T04-own-services   T04 allow     get    services             tenant-a "$DEV" "$GRP"
case_rbac T04-b-services     T04 deny:rbac get    services             tenant-b "$DEV" "$GRP"
case_rbac T04-own-secrets    T04 deny:rbac get    secrets              tenant-a "$DEV" "$GRP"
case_rbac T04-b-secrets      T04 deny:rbac get    secrets              tenant-b "$DEV" "$GRP"
case_rbac T04-cluster        T04 deny:rbac list   namespaces           -        "$DEV" "$GRP"
case_rbac T04-create         T04 deny:rbac create pods                 tenant-a "$DEV" "$GRP"
case_rbac T04-sa-b-pods      T04 deny:rbac list   pods                 tenant-b "$SA"
case_rbac T04-sa-secrets     T04 deny:rbac get    secrets              tenant-a "$SA"
case_rbac T04-wsa-b-pods     T04 deny:rbac list   pods                 tenant-b "$WSA"
case_rbac T04-wsa-secrets    T04 deny:rbac get    secrets              tenant-a "$WSA"
case_rbac T04-wsa-b-secrets  T04 deny:rbac get    secrets              tenant-b "$WSA"
case_rbac T04-wsa-b-sandbox  T04 deny:rbac get    ragsandboxes.kro.run tenant-b "$WSA"
case_rbac T04-wsa-cluster    T04 deny:rbac list   namespaces           -        "$WSA"

# --- T05: Pod Security restricted -----------------------------------------------
pod ok tenant-a | case_admit T05-compliant T05 allow
pod priv tenant-a '{"securityContext":{"privileged":true,"allowPrivilegeEscalation":true}}' | case_admit T05-privileged T05 deny:pod-security
pod hostnet tenant-a '{}' '{"hostNetwork":true}' | case_admit T05-hostnetwork T05 deny:pod-security
pod hostpath tenant-a '{"volumeMounts":[{"name":"h","mountPath":"/h"}]}' '{"volumes":[{"name":"h","hostPath":{"path":"/"}}]}' | case_admit T05-hostpath T05 deny:pod-security
pod root tenant-a '{}' '{"securityContext":{"runAsNonRoot":false,"runAsUser":0}}' | case_admit T05-root T05 deny:pod-security

# --- T14, T10 label, T15 health: Kyverno (D6, D8) -------------------------------
pod tag tenant-b '{"image":"ghcr.io/eurusdevsec/zero-d-rift/rag-sandbox:latest"}' | case_admit T14-tag T14 deny:kyverno:zdr-image-digest
pod reg tenant-b "{\"image\":\"docker.io/library/python@sha256:$(printf 'a%.0s' {1..64})\"}" | case_admit T14-registry T14 deny:kyverno:zdr-image-digest
pod spoof tenant-a '{}' '{}' '{"rag.zero-drift.io/tenant":"tenant-b"}' | case_admit T10-label-spoof T10 deny:kyverno:zdr-tenant-label
pod plat zdr-platform '{"image":"busybox:1.37"}' '{}' '{"rag.zero-drift.io/tenant":"x"}' | case_admit T15-platform-out-of-scope T15 allow
health="$($K get validatingpolicies.policies.kyverno.io -o json 2>/dev/null \
    | jq -r '[.items[] | select(.metadata.name | startswith("zdr-"))] | if length == 3 and all(.spec.validationActions == ["Deny"] and .spec.failurePolicy == "Fail" and (.status.conditionStatus.ready == true)) then "ready-deny" else "not-ready-or-audit" end' || echo missing)"
record T15-policies-enforced T15 kyverno ready-deny "$health" "3 zdr- ValidatingPolicies: Deny, Fail, Ready"

# --- T11: quota and LimitRange (D3) ---------------------------------------------
pod gpu tenant-a '{"resources":{"limits":{"memory":"192Mi","nvidia.com/gpu":"1"}}}' | case_admit T11-gpu T11 deny:quota
pod big tenant-a '{"resources":{"limits":{"memory":"1Gi"}}}' | case_admit T11-big T11 deny:limitrange
pod noreq tenant-a | jq 'del(.spec.containers[0].resources)' | case_admit T11-defaults T11 allow

# --- T03: request path (D4), needs Argo CD --------------------------------------
# app NAME PATH NAMESPACE: an Application in project zdr-requests, auto-synced.
app() {
    jq -n --arg n "$1" --arg p "$2" --arg ns "$3" '{apiVersion:"argoproj.io/v1alpha1",kind:"Application",
      metadata:{name:$n,namespace:"argocd",labels:{"app.kubernetes.io/name":"zdr-isolation"}},
      spec:{project:"zdr-requests",source:{repoURL:"https://github.com/EurusDevSec/Zero-D-Rift.git",targetRevision:"main",path:$p},
            destination:{server:"https://kubernetes.default.svc",namespace:$ns},syncPolicy:{automated:{}}}}' | $K apply -f - >/dev/null
}
# wait_msg APP TEXT: poll conditions and the operation message for TEXT (90 s).
wait_msg() {
    local m="" i
    for i in $(seq 1 18); do
        m="$($K -n argocd get app "$1" -o jsonpath='{range .status.conditions[*]}{.type}: {.message} {end}{.status.operationState.message}' 2>&1 || true)"
        [[ "$m" == *"$2"* ]] && break; sleep 5
    done
    echo "$m"
}
argo="$($K get ns argocd --ignore-not-found -o name 2>/dev/null)" || argo=error
if [[ "$argo" == namespace/argocd ]]; then
    a="zdr-iso-badns-$RANDOM"; app "$a" gitops/requests zdr-platform
    want="do not match any of the allowed destinations in project 'zdr-requests'"
    m="$(wait_msg "$a" "$want")"
    record T03-foreign-namespace T03 argocd deny:argocd "$([[ "$m" == *"$want"* ]] && echo deny:argocd || echo other)" "$m"
    a="zdr-iso-badkind-$RANDOM"; app "$a" gitops/lab tenant-a
    want="resource apps:Deployment is not permitted in project zdr-requests"
    m="$(wait_msg "$a" "$want")"
    # The list must succeed: a failed list is not "no Deployment created".
    if dl="$($K get deploy -A -o name 2>/dev/null)"; then made="$(grep -c zdr-lab-pause <<< "$dl" || true)"; else made=list-error; fi
    record T03-foreign-kind T03 argocd deny:argocd "$([[ "$m" == *"$want"* && "$made" == 0 ]] && echo deny:argocd || echo "other:deployments=$made")" "$m"
elif [[ "$argo" == error ]]; then
    record T03-foreign-namespace T03 argocd deny:argocd error:list "could not read namespace argocd"
    record T03-foreign-kind      T03 argocd deny:argocd error:list "could not read namespace argocd"
else
    record T03-foreign-namespace T03 argocd deny:argocd SKIPPED_NEEDS_EKS "no argocd namespace in this cluster"
    record T03-foreign-kind      T03 argocd deny:argocd SKIPPED_NEEDS_EKS "no argocd namespace in this cluster"
fi

# --- T07: a ServiceAccount outside the trust pattern rag-* (A10) -----------------
# It carries the tenant role annotation (copied, never printed). STS must answer
# AssumeRoleWithWebIdentity with AccessDenied; an empty annotation, a missing
# IRSA environment or an unreachable STS is an error, not a denial.
T07CODE='import os, sys, boto3, botocore
arn, tf = os.environ.get("AWS_ROLE_ARN"), os.environ.get("AWS_WEB_IDENTITY_TOKEN_FILE")
if not arn or not tf:
    print("RESULT ERROR no-irsa-env"); sys.exit(0)
region = os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION") or "us-east-1"
try:
    boto3.client("sts", region_name=region).assume_role_with_web_identity(
        RoleArn=arn, RoleSessionName="zdr-iso-t07", WebIdentityToken=open(tf).read())
    print("RESULT ASSUMED")
except botocore.exceptions.ClientError as e:
    c = e.response.get("Error", {}).get("Code", "unknown")
    print("RESULT", "DENIED" if c == "AccessDenied" else "ERROR", c)
except Exception as e:
    print("RESULT ERROR", type(e).__name__)'
if [[ "$MODE" == eks ]]; then
    role="$($K -n tenant-a get sa "rag-$SANDBOX" -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || true)"
    if [[ -z "$role" ]]; then
        record T07-other-sa T07 iam deny:iam error:no-annotation "rag-$SANDBOX in tenant-a has no role annotation to copy"
    else
        # An apply error can echo the object (and the ARN): keep it off the output.
        if $K -n tenant-a create serviceaccount zdr-iso-other --dry-run=client -o json 2>/dev/null \
            | jq --arg r "$role" '.metadata.annotations["eks.amazonaws.com/role-arn"] = $r
                 | .metadata.labels["app.kubernetes.io/name"] = "zdr-isolation" | .automountServiceAccountToken = false' \
            | $K apply -f - >/dev/null 2>&1; then
            r="$(job tenant-a "zdr-iso-t07-$RANDOM" "$T07CODE" '{"serviceAccountName":"zdr-iso-other"}')"
        else r="RESULT ERROR sa-apply"; fi
        unset role
        case "$r" in "RESULT DENIED AccessDenied") obs=deny:iam ;; "RESULT ASSUMED") obs=allow ;; *) obs="error:$(cut -d' ' -f3 <<< "$r")" ;; esac
        record T07-other-sa T07 iam deny:iam "$obs" "zdr-iso-other AssumeRoleWithWebIdentity on the tenant-a role: ${r#RESULT }"
    fi
else
    record T07-other-sa T07 iam deny:iam SKIPPED_NEEDS_EKS "needs IRSA"
fi

# --- T08, T13, T06: P4 probes (window.sh probe), positives included -------------
# Each probe must exit 0 and print exactly its expected case set; a missing
# case, a SKIP or an early stop is a FAIL.
p4() { # LABEL "case name"... -- window.sh probe args...
    local label=$1 want=() seen=() out rc=0 line st what t c; shift
    while [[ "$1" != -- ]]; do want+=("$1"); shift; done; shift
    out="$(bash infra/p4-window/window.sh probe "$@" 2>&1)" || rc=$?
    while IFS= read -r line; do
        line="${line%$'\r'}"
        [[ "$line" =~ ^(PASS|FAIL|SKIP)\ \ ([^:]*):(.*)$ ]] || continue
        st="${BASH_REMATCH[1]}"; what="${BASH_REMATCH[2]}"; seen+=("$what")
        case "$what" in *IMDS*) t=T06 ;; *schema*|*ROLE*|*rag_bootstrap*|*pgvector*|*TLS*) t=T13 ;; *) t=T08 ;; esac
        record "P4 $label: $what" "$t" iam-or-db pass "${st,,}" "$what:${BASH_REMATCH[3]}"
    done <<< "$out"
    for c in "${want[@]}"; do
        printf '%s\n' "${seen[@]}" | grep -qxF "$c" || record "P4 $label: $c" T08 iam-or-db pass missing "case not printed by window.sh probe $*"
    done
    record "P4 $label: exit" T08 iam-or-db exit-0 "exit-$rc" "window.sh probe $* exit status"
}
if [[ "$MODE" == eks ]]; then
    p4 platform "bootstrap secret readable" "TLS on the connection" "pgvector installed by db-init" \
        "rag_bootstrap attributes" "rag_bootstrap database grants" "bootstrap identity cannot read the master secret" -- platform
    for t in tenant-a tenant-b; do
        o=$([[ $t == tenant-a ]] && echo tenant-b || echo tenant-a)
        p4 "sandbox $t" "own secret readable" "own schema queried" "vector query in own schema" \
            "own bucket reachable (HeadBucket)" "app /readyz through the Service" "app /query through the Service" -- sandbox "$t" "$SANDBOX"
        p4 "cross $t" "$t reads $o's secret" "$t reads the bootstrap secret" "$t reaches $o's bucket" "$t reads $o's schema" \
            "$t sandbox role runs CREATE ROLE" "$t sandbox role creates a schema" "$t Pod gets an IMDS token" -- cross "$t" "$SANDBOX" "$o"
    done
else
    record P4-probes T08 iam-or-db pass SKIPPED_NEEDS_EKS "needs RDS, Secrets Manager, S3 and IRSA"
fi

finish "${NET_PHASE:-none}"
