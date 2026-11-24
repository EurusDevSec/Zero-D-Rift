#!/usr/bin/env bash
# P5 isolation suite (DRF-70, SPEC-P5 P5-T4.1). Runs every case, writes
# acceptance.json (case, threat, expected layer and result, observed result,
# UTC time, evidence line) and exits 0 only when every case that ran matched.
#
#   MODE=kind CTX=kind-zdr-p5-kyv tests/isolation/run.sh   # dry run, no AWS
#   MODE=eks  CTX=<eks context> RUN_ID=P5-L3-... tests/isolation/run.sh
#
# kind: cases that need EKS (VPC CNI NetworkPolicy, IMDS, IRSA, RDS, S3) are
# written as SKIPPED_NEEDS_EKS, never PASS. eks: nothing may be skipped; the
# P4 negatives run unchanged through infra/p4-window/window.sh probe, which
# uses the current kubectl context, so CTX must be the current context.
# Each Pod case is a server dry run, except the network cases (real Pods,
# deleted afterwards). The context name is never written to the output.
set -euo pipefail
# "pod ... | case_admit" must record in this shell, not in a pipeline subshell,
# or its result (and a FAIL) would be lost.
shopt -s lastpipe
cd "$(dirname "$0")/../.."

MODE="${MODE:?MODE=kind|eks}"; CTX="${CTX:?CTX=<kubectl context>}"
OUT="${OUT:-acceptance.json}"; RUN_ID="${RUN_ID:-dry-run}"; SANDBOX="${SANDBOX:-docs-qa}"
K="kubectl --context $CTX"
IMG="$(grep -m1 -o 'ghcr.io/eurusdevsec/zero-d-rift/rag-sandbox@sha256:[0-9a-f]\{64\}' gitops/platform/rgd/rag-sandbox.yaml)"
cases='[]'; bad=0
# window.sh probe uses the current context: refuse to mix two clusters (no name printed).
if [[ "$MODE" == eks && "$(kubectl config current-context)" != "$CTX" ]]; then
    echo "FAIL  CTX is not the current kubectl context"; exit 1
fi

# record ID THREAT LAYER EXPECTED OBSERVED EVIDENCE
record() {
    local res
    if [[ "$5" == SKIPPED_* ]]; then res="$5"
    elif [[ "$4" == "$5" ]]; then res=PASS
    else res=FAIL; bad=1; fi
    printf '%-18s %-6s %-12s expected=%-22s observed=%-22s %s\n' "$res" "$2" "$1" "$4" "$5" "${6:0:110}"
    cases="$(jq -c --arg id "$1" --arg t "$2" --arg l "$3" --arg e "$4" --arg o "$5" --arg r "$res" \
        --arg ev "${6:0:300}" --arg at "$(date -u +%FT%TZ)" \
        '. + [{id:$id, threat:$t, layer:$l, expected:$e, observed:$o, result:$r, utc:$at, evidence:$ev}]' <<< "$cases")"
}

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

# Which layer answered an admission attempt: allow, or deny:<layer>.
admit() { # manifest on stdin -> prints "OBSERVED|evidence"
    local out
    if out="$($K create --dry-run=server -f - 2>&1)"; then echo "allow|$out"; return; fi
    case "$out" in
        *PodSecurity*)                 echo "deny:pod-security|$out" ;;
        *vpol.validate.kyverno*)       echo "deny:kyverno|$out" ;;
        *"maximum memory usage"*)      echo "deny:limitrange|$out" ;;
        *"exceeded quota"*)            echo "deny:quota|$out" ;;
        *)                             echo "deny:other|$out" ;;
    esac
}
case_admit() { # ID THREAT EXPECTED  (manifest on stdin)
    local r; r="$(admit)"; record "$1" "$2" admission "$3" "${r%%|*}" "$(tr '\n' ' ' <<< "${r#*|}")"
}
case_rbac() { # ID THREAT EXPECTED VERB RESOURCE NS-or-- AS GROUP
    local ns=() ans; [[ "$6" != - ]] && ns=(-n "$6")
    ans="$($K auth can-i "$4" "$5" "${ns[@]}" --as="$7" ${8:+--as-group="$8"} 2>/dev/null || true)"
    record "$1" "$2" rbac "$3" "$([[ "$ans" == yes* ]] && echo allow || echo deny:rbac)" "can-i $4 $5 ${6} as $7: ${ans:-no}"
}

echo "isolation suite mode=$MODE run=$RUN_ID $(date -u +%FT%TZ)"

# --- T04: Kubernetes RBAC (D1, D2) --------------------------------------------
DEV=dev-a; GRP=zdr:tenant-a:developers; SA=system:serviceaccount:tenant-a:default
case_rbac T04-own-pods     T04 allow     get  pods                tenant-a "$DEV" "$GRP"
case_rbac T04-b-pods       T04 deny:rbac list pods                tenant-b "$DEV" "$GRP"
case_rbac T04-b-sandboxes  T04 deny:rbac get  ragsandboxes.kro.run tenant-b "$DEV" "$GRP"
case_rbac T04-own-services T04 allow     get  services            tenant-a "$DEV" "$GRP"
case_rbac T04-b-services   T04 deny:rbac get  services            tenant-b "$DEV" "$GRP"
case_rbac T04-own-secrets  T04 deny:rbac get  secrets             tenant-a "$DEV" "$GRP"
case_rbac T04-b-secrets    T04 deny:rbac get  secrets             tenant-b "$DEV" "$GRP"
case_rbac T04-cluster      T04 deny:rbac list namespaces          -        "$DEV" "$GRP"
case_rbac T04-create       T04 deny:rbac create pods              tenant-a "$DEV" "$GRP"
case_rbac T04-sa-b-pods    T04 deny:rbac list pods                tenant-b "$SA"
case_rbac T04-sa-secrets   T04 deny:rbac get  secrets             tenant-a "$SA"

# --- T05: Pod Security restricted --------------------------------------------
pod ok tenant-a | case_admit T05-compliant T05 allow
pod priv tenant-a '{"securityContext":{"privileged":true,"allowPrivilegeEscalation":true}}' | case_admit T05-privileged T05 deny:pod-security
pod hostnet tenant-a '{}' '{"hostNetwork":true}' | case_admit T05-hostnetwork T05 deny:pod-security
pod hostpath tenant-a '{"volumeMounts":[{"name":"h","mountPath":"/h"}]}' '{"volumes":[{"name":"h","hostPath":{"path":"/"}}]}' | case_admit T05-hostpath T05 deny:pod-security
pod root tenant-a '{}' '{"securityContext":{"runAsNonRoot":false,"runAsUser":0}}' | case_admit T05-root T05 deny:pod-security

# --- T14, T10 label, T15 health: Kyverno (D6, D8) ----------------------------
pod tag tenant-b '{"image":"ghcr.io/eurusdevsec/zero-d-rift/rag-sandbox:latest"}' | case_admit T14-tag T14 deny:kyverno
pod reg tenant-b "{\"image\":\"docker.io/library/python@sha256:$(printf 'a%.0s' {1..64})\"}" | case_admit T14-registry T14 deny:kyverno
pod spoof tenant-a '{}' '{}' '{"rag.zero-drift.io/tenant":"tenant-b"}' | case_admit T10-label-spoof T10 deny:kyverno
pod plat zdr-platform '{"image":"busybox:1.37"}' '{}' '{"rag.zero-drift.io/tenant":"x"}' | case_admit T15-platform-out-of-scope T15 allow
health="$($K get validatingpolicies.policies.kyverno.io -o json 2>/dev/null \
    | jq -r '[.items[] | select(.metadata.name | startswith("zdr-"))] | if length == 3 and all(.spec.validationActions == ["Deny"] and .spec.failurePolicy == "Fail" and (.status.conditionStatus.ready == true)) then "ready-deny" else "not-ready-or-audit" end' || echo missing)"
record T15-policies-enforced T15 kyverno ready-deny "$health" "3 zdr- ValidatingPolicies: Deny, Fail, Ready"

# --- T11: quota and LimitRange (D3) ------------------------------------------
pod gpu tenant-a '{"resources":{"limits":{"memory":"192Mi","nvidia.com/gpu":"1"}}}' | case_admit T11-gpu T11 deny:quota
pod big tenant-a '{"resources":{"limits":{"memory":"1Gi"}}}' | case_admit T11-big T11 deny:limitrange
pod noreq tenant-a | jq 'del(.spec.containers[0].resources)' | case_admit T11-defaults T11 allow

# --- T03: request path (D4), needs Argo CD -----------------------------------
if $K get ns argocd >/dev/null 2>&1; then
    app="zdr-iso-badns-$RANDOM"
    jq -n --arg n "$app" '{apiVersion:"argoproj.io/v1alpha1",kind:"Application",metadata:{name:$n,namespace:"argocd"},
      spec:{project:"zdr-requests",source:{repoURL:"https://github.com/EurusDevSec/Zero-D-Rift.git",targetRevision:"main",path:"gitops/requests"},
            destination:{server:"https://kubernetes.default.svc",namespace:"zdr-platform"}}}' | $K apply -f - >/dev/null
    sleep 20
    msg="$($K -n argocd get app "$app" -o jsonpath='{range .status.conditions[*]}{.type}: {.message}{end}' 2>&1)"
    $K -n argocd delete app "$app" --wait=false >/dev/null 2>&1 || true
    record T03-foreign-namespace T03 argocd deny:argocd "$([[ "$msg" == *InvalidSpecError* ]] && echo deny:argocd || echo allow)" "$msg"
else
    record T03-foreign-namespace T03 argocd deny:argocd SKIPPED_NEEDS_EKS "no argocd namespace in this cluster"
fi

# --- T10, T06: network (D5), needs VPC CNI NetworkPolicy ---------------------
# connect TENANT HOST PORT -> OPEN or CLOSED, from a real Pod of TENANT.
connect() {
    local n="zdr-iso-net-$RANDOM" code
    # Standard mode leaves a new Pod default-allow until its policies are
    # programmed (SPEC-P5 §10): wait first, so a deny is not tested in the gap.
    code="import socket,sys,time
time.sleep(20)
s=socket.socket(); s.settimeout(5)
try: s.connect((sys.argv[1], int(sys.argv[2]))); print('OPEN')
except Exception as e: print('CLOSED', type(e).__name__)"
    pod "$n" "$1" "$(jq -nc --arg c "$code" --arg h "$2" --arg p "$3" '{command:["python","-c",$c,$h,$p]}')" \
        | $K apply -f - >/dev/null
    $K -n "$1" wait --for=jsonpath='{.status.phase}'=Succeeded pod "$n" --timeout=90s >/dev/null 2>&1 || true
    $K -n "$1" logs "$n" 2>/dev/null | tail -1
    $K -n "$1" delete pod "$n" --wait=false >/dev/null 2>&1 || true
}
net_case() { # ID THREAT EXPECTED TENANT HOST PORT
    local r; r="$(connect "$4" "$5" "$6")"
    record "$1" "$2" networkpolicy "$3" "$([[ "$r" == OPEN* ]] && echo allow || echo deny:network)" "$4 -> $5:$6: ${r:-no output}"
}
if [[ "$MODE" == eks ]]; then
    net_case T10-own-app       T10 allow        tenant-a "rag-$SANDBOX.tenant-a.svc" 8080
    net_case T10-a-to-b        T10 deny:network tenant-a "rag-$SANDBOX.tenant-b.svc" 8080
    net_case T10-b-to-a        T10 deny:network tenant-b "rag-$SANDBOX.tenant-a.svc" 8080
    net_case T06-metadata      T06 deny:network tenant-a 169.254.169.254 80
else
    for c in T10-own-app T10-a-to-b T10-b-to-a T06-metadata; do
        record "$c" "${c%%-*}" networkpolicy see-eks SKIPPED_NEEDS_EKS "kind has no VPC CNI NetworkPolicy"
    done
fi

# --- T07: a ServiceAccount outside the trust pattern rag-* (A10) ---------------
# It carries the tenant role annotation (copied, never printed); STS must refuse.
if [[ "$MODE" == eks ]]; then
    role="$($K -n tenant-a get sa "rag-$SANDBOX" -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')"
    $K -n tenant-a create serviceaccount zdr-iso-other --dry-run=client -o json \
        | jq --arg r "$role" '.metadata.annotations["eks.amazonaws.com/role-arn"] = $r | .automountServiceAccountToken = false' \
        | $K apply -f - >/dev/null
    unset role
    n="zdr-iso-t07-$RANDOM"
    code="import boto3
try: boto3.client('sts', region_name='us-east-1').get_caller_identity(); print('ASSUMED')
except Exception as e: print('DENIED', getattr(e, 'response', {}).get('Error', {}).get('Code', type(e).__name__))"
    pod "$n" tenant-a "$(jq -nc --arg c "$code" '{command:["python","-c",$c]}')" '{"serviceAccountName":"zdr-iso-other"}' \
        | $K apply -f - >/dev/null
    $K -n tenant-a wait --for=jsonpath='{.status.phase}'=Succeeded pod "$n" --timeout=120s >/dev/null 2>&1 || true
    r="$($K -n tenant-a logs "$n" 2>/dev/null | tail -1)"
    $K -n tenant-a delete pod "$n" --wait=true >/dev/null 2>&1 || true
    $K -n tenant-a delete serviceaccount zdr-iso-other >/dev/null 2>&1 || true
    record T07-other-sa T07 iam deny:iam "$([[ "$r" == DENIED* ]] && echo deny:iam || echo allow)" "zdr-iso-other assumes tenant-a role: ${r:-no output}"
else
    record T07-other-sa T07 iam deny:iam SKIPPED_NEEDS_EKS "needs IRSA"
fi

# --- T08, T13, T06: P4 probes unchanged (window.sh probe), positives included --
if [[ "$MODE" == eks ]]; then
    for args in "sandbox tenant-a $SANDBOX" "sandbox tenant-b $SANDBOX" \
                "cross tenant-a $SANDBOX tenant-b" "cross tenant-b $SANDBOX tenant-a"; do
        set -- $args; got=0
        while IFS= read -r line; do
            line="${line%$'\r'}"
            [[ "$line" =~ ^(PASS|FAIL|SKIP)\ \ (.*)$ ]] || continue
            st="${BASH_REMATCH[1]}"; what="${BASH_REMATCH[2]}"; got=$((got + 1))
            case "$what" in *IMDS*) t=T06 ;; *schema*|*ROLE*) t=T13 ;; *) t=T08 ;; esac
            record "P4: ${what%%:*}" "$t" iam-or-db pass "$( [[ $st == PASS ]] && echo pass || echo "${st,,}")" "$what"
        done < <(bash infra/p4-window/window.sh probe "$@" 2>&1 || true)
        # A probe that printed no case at all is a failure, never a silent pass.
        (( got )) || record "P4: probe $1 $2" T08 iam-or-db pass no-output "window.sh probe $* printed no PASS/FAIL line"
    done
else
    record P4-probes T08 iam-or-db pass SKIPPED_NEEDS_EKS "needs RDS, Secrets Manager, S3 and IRSA"
fi

jq -n --arg run "$RUN_ID" --arg mode "$MODE" --arg img "$IMG" --argjson c "$cases" \
    '{run_id:$run, mode:$mode, image:$img, cases:$c,
      summary:{total:($c|length), pass:([$c[]|select(.result=="PASS")]|length),
               fail:([$c[]|select(.result=="FAIL")]|length),
               skipped:([$c[]|select(.result|startswith("SKIPPED"))]|length)}}' > "$OUT"
echo
jq -r '.summary | "total \(.total), pass \(.pass), fail \(.fail), skipped \(.skipped)"' "$OUT"
skipped="$(jq '.summary.skipped' "$OUT")"
if (( bad )); then echo "RESULT: FAIL ($OUT)"; exit 1; fi
if [[ "$MODE" == eks && "$skipped" != 0 ]]; then echo "RESULT: FAIL (skipped cases in eks mode)"; exit 1; fi
echo "RESULT: PASS ($OUT)"
