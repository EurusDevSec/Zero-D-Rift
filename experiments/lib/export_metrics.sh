#!/usr/bin/env bash
# export_metrics.sh — SPEC-P7 T2.2 (DRF-86). Export raw Prometheus series and
# OpenCost allocation for one UTC window, before teardown (Prometheus has no PV).
#
#   export_metrics.sh --context CTX --start 2026-11-29T01:00:00Z --end 2026-11-29T02:00:00Z \
#                     --out experiments/runs/<campaign>/<run>/metrics [--step 30] [--run-id ID]
#                     [--tenant-regex 'tenant-.*'] [--synthetic] [--official]
#
# Reads through the Kubernetes API service proxy (no port-forward, no AWS call).
# Never prints the kube context (on EKS it is an ARN). Output: prometheus/*.jsonl,
# opencost/allocation_{namespace,controller,pod}.json, export_manifest.json,
# hashes.sha256. Node names, IPs and instance ids are pseudonymized or dropped;
# the export refuses to write if any identifier survives (export_redact.py).
set -euo pipefail

die() { echo "export_metrics: $*" >&2; exit 2; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX="" START="" END="" OUT="" STEP=30 RUN_ID="" TENANTS='tenant-.*' SYNTH=false OFFICIAL=false
while (( $# )); do
  case "$1" in
    --context) CTX="$2"; shift 2 ;;
    --start) START="$2"; shift 2 ;;
    --end) END="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --step) STEP="$2"; shift 2 ;;
    --run-id) RUN_ID="$2"; shift 2 ;;
    --tenant-regex) TENANTS="$2"; shift 2 ;;
    --synthetic) SYNTH=true; shift ;;
    --official) OFFICIAL=true; shift ;;
    -h|--help) sed -n 2,13p "$0"; exit 0 ;;
    *) die "unknown argument $1" ;;
  esac
done
[[ -n "$CTX" && -n "$START" && -n "$END" && -n "$OUT" ]] || die "need --context --start --end --out"
rfc='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
[[ "$START" =~ $rfc && "$END" =~ $rfc ]] || die "start/end must be RFC3339 UTC like 2026-11-29T01:00:00Z"
[[ "$STEP" =~ ^[0-9]+$ ]] && (( STEP >= 15 )) || die "step must be an integer >= 15 (seconds)"
s=$(date -u -d "$START" +%s) e=$(date -u -d "$END" +%s)
(( e > s )) || die "end must be after start"
(( (e - s) / STEP <= 11000 )) || die "window/step gives more than 11000 points per series; raise --step"
(( e <= $(date -u +%s) + 60 )) || die "end is in the future"
[[ -z "$RUN_ID" ]] && RUN_ID="export-$(date -u -d "$START" +%Y%m%dT%H%M%SZ)"
[[ "$RUN_ID" =~ ^[A-Za-z0-9._-]+$ ]] || die "run-id: letters, digits, . _ - only"
if [[ -e "$OUT" ]] && [[ -n "$(ls -A "$OUT" 2>/dev/null)" ]]; then die "$OUT is not empty (raw evidence is immutable)"; fi

K=(kubectl --context "$CTX" --request-timeout=60s)
PROM=/api/v1/namespaces/prometheus-system/services/prometheus-server:80/proxy
OC=/api/v1/namespaces/opencost/services/opencost:9003/proxy
RAW="$(mktemp -d)"; trap 'rm -rf "$RAW"' EXIT
# Git Bash on Windows runs a Windows python: hand it C:/... paths.
pyp() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s
' "$1"; fi; }
enc() { python -I -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"; }

# Named queries (SPEC-P7 T2.2; D6). job!="opencost": OpenCost re-exports some
# kube_* series; kube-state-metrics is the source for those.
T="namespace=~\"$TENANTS\""
NAMES=(); PROMQL=()
q() { NAMES+=("$1"); PROMQL+=("$2"); }
q nodes_by_pool_capacity 'count by (label_zero_drift_io_pool, label_karpenter_sh_capacity_type, label_eks_amazonaws_com_capacity_type, label_node_kubernetes_io_instance_type) (kube_node_labels{job!="opencost"})'
q node_labels 'max by (node, label_zero_drift_io_pool, label_karpenter_sh_capacity_type, label_karpenter_sh_nodepool, label_eks_amazonaws_com_capacity_type, label_node_kubernetes_io_instance_type, label_topology_kubernetes_io_zone) (kube_node_labels{job!="opencost"})'
q cpu_requested_by_node 'sum by (node) (kube_pod_container_resource_requests{resource="cpu",job!="opencost"})'
q cpu_allocatable_by_node 'sum by (node) (kube_node_status_allocatable{resource="cpu",job!="opencost"})'
q memory_requested_by_node 'sum by (node) (kube_pod_container_resource_requests{resource="memory",job!="opencost"})'
q memory_allocatable_by_node 'sum by (node) (kube_node_status_allocatable{resource="memory",job!="opencost"})'
q tenant_pod_phase "max by (namespace, pod, phase) (kube_pod_status_phase{$T,job!=\"opencost\"} == 1)"
q tenant_pod_node "max by (namespace, pod, node) (kube_pod_info{$T,job!=\"opencost\"})"
q tenant_cpu_used "sum by (namespace, pod) (rate(container_cpu_usage_seconds_total{$T,container!=\"\"}[2m]))"
q tenant_memory_used "sum by (namespace, pod) (container_memory_working_set_bytes{$T,container!=\"\"})"
q namespace_cpu_allocation 'sum by (namespace) (container_cpu_allocation)'
q namespace_memory_allocation 'sum by (namespace) (container_memory_allocation_bytes)'
q opencost_node_hourly_cost 'max by (node, instance_type, region, arch) (node_total_hourly_cost)'
q opencost_node_is_spot 'max by (node, instance_type) (kubecost_node_is_spot)'
q scrape_up 'up'

"${K[@]}" get --raw "$PROM/api/v1/status/buildinfo" > "$RAW/buildinfo.json" || die "Prometheus not reachable through the API proxy"
"${K[@]}" get nodes -o json > "$RAW/nodes.json" || die "cannot list nodes (needed to redact their names and addresses)"
QMETA="[]"
for i in "${!NAMES[@]}"; do
  n="${NAMES[$i]}"; pq="${PROMQL[$i]}"
  "${K[@]}" get --raw "$PROM/api/v1/query_range?query=$(enc "$pq")&start=$START&end=$END&step=${STEP}s" > "$RAW/$n.json" \
    || die "query $n failed"
  QMETA=$(python -I -c 'import json,sys; a=json.loads(sys.argv[1]); a.append({"name":sys.argv[2],"promql":sys.argv[3],"raw":sys.argv[2]+".json"}); print(json.dumps(a))' "$QMETA" "$n" "$pq")
done
AMETA="[]"
for agg in namespace controller pod; do
  "${K[@]}" get --raw "$OC/allocation/compute?window=$(enc "$START,$END")&aggregate=$agg&accumulate=true" > "$RAW/alloc_$agg.json" \
    || die "OpenCost allocation $agg failed"
  AMETA=$(python -I -c 'import json,sys; a=json.loads(sys.argv[1]); a.append({"aggregate":sys.argv[2],"raw":"alloc_"+sys.argv[2]+".json"}); print(json.dumps(a))' "$AMETA" "$agg")
done

python -I - "$(pyp "$RAW")" "$RUN_ID" "$START" "$END" "$STEP" "$SYNTH" "$OFFICIAL" "$QMETA" "$AMETA" > "$RAW/meta.json" <<'PY'
import json, sys, datetime
raw, run, start, end, step, synth, official, q, a = sys.argv[1:]
b = json.load(open(f"{raw}/buildinfo.json", encoding="utf-8"))
print(json.dumps({"run_id": run, "window": {"start_utc": start, "end_utc": end, "step_s": int(step)},
                  "synthetic": synth == "true", "official": official == "true",
                  "exported_at_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                  "prometheus_version": b.get("data", {}).get("version", "unknown"),
                  "queries": json.loads(q), "allocations": json.loads(a)}))
PY

mkdir -p "$OUT"
python -I "$(pyp "$HERE/export_redact.py")" --raw "$(pyp "$RAW")" --out "$(pyp "$OUT")" --meta "$(pyp "$RAW/meta.json")"
( cd "$OUT" && find . -type f ! -name hashes.sha256 | sed 's|^\./||' | LC_ALL=C sort | xargs sha256sum > hashes.sha256 )
echo "export_metrics: wrote $(wc -l < "$OUT/hashes.sha256") files and hashes.sha256 to $OUT"
