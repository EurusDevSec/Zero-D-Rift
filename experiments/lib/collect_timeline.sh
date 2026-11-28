#!/usr/bin/env bash
# collect_timeline.sh — SPEC-P7 T3 (DRF-87). Read-only collection of the
# instance timeline of one run: EC2 launch and termination, type, capacity
# type, zone; Spot price history for the type and zone; the On-Demand price
# from the Price List; NodeClaim and Node events. Aliases replace instance ids.
#
#   AWS_PROFILE=zdr-tf collect_timeline.sh --context CTX --start T0 --end T1 \
#       --run-id ID --out experiments/runs/<campaign>/<run> [--arm baseline|optimized]
#       [--pair-id P] [--roles batch|baseline] [--region us-east-1]
#
# Run it after the instance is terminated (EC2 keeps terminated instances for
# about an hour) and before Kubernetes events expire (one hour by default).
# Only describe/get calls: no create, no delete, no Cost Explorer.
set -euo pipefail

die() { echo "collect_timeline: $*" >&2; exit 2; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX="" START="" END="" RUN_ID="" OUT="" ARM="" PAIR="" ROLES=batch REGION=us-east-1
while (( $# )); do
  case "$1" in
    --context) CTX="$2"; shift 2 ;;
    --start) START="$2"; shift 2 ;;
    --end) END="$2"; shift 2 ;;
    --run-id) RUN_ID="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --arm) ARM="$2"; shift 2 ;;
    --pair-id) PAIR="$2"; shift 2 ;;
    --roles) ROLES="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    -h|--help) sed -n 2,14p "$0"; exit 0 ;;
    *) die "unknown argument $1" ;;
  esac
done
[[ -n "$CTX" && -n "$START" && -n "$END" && -n "$RUN_ID" && -n "$OUT" ]] || die "need --context --start --end --run-id --out"
rfc='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
[[ "$START" =~ $rfc && "$END" =~ $rfc ]] || die "start/end must be RFC3339 UTC with Z"
[[ "$RUN_ID" =~ ^[A-Za-z0-9._-]+$ ]] || die "run-id: letters, digits, . _ - only"
[[ -z "$ARM" || "$ARM" == baseline || "$ARM" == optimized ]] || die "arm: baseline or optimized"
[[ "${AWS_PROFILE:-}" == zdr-tf ]] || die "set AWS_PROFILE=zdr-tf (MFA session)"
for f in timeline/events.jsonl timeline/instances.json cost/cost_input.json; do
  [[ -e "$OUT/$f" ]] && die "$OUT/$f exists (raw evidence is immutable)"
done

RAW="$(mktemp -d)"; trap 'rm -rf "$RAW"' EXIT
pyp() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
aws_ro() { timeout 60 aws --region "$REGION" --output json "$@" </dev/null; }

# Instances of the project that may overlap the window, any state.
aws_ro ec2 describe-instances --filters "Name=tag:Project,Values=Zero-D-Rift" > "$RAW/instances.json" \
  || die "describe-instances failed (MFA session expired? run the owner's refresh)"
# Kubernetes NodeClaim and Node events (expire after about one hour).
timeout 60 kubectl --context "$CTX" get events -A -o json </dev/null > "$RAW/k8s_events.json" \
  || die "kubectl get events failed"

# Prices: for every (type, zone, capacity) seen in the window.
python -I -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
seen = set()
for r in d.get("Reservations", []):
    for i in r.get("Instances", []):
        seen.add((i.get("InstanceType"), i.get("Placement", {}).get("AvailabilityZone"),
                  "spot" if i.get("InstanceLifecycle") == "spot" else "on-demand"))
for t, z, c in sorted(seen):
    print(t, z, c)' "$(pyp "$RAW/instances.json")" > "$RAW/seen.txt"

SPOT_FROM=$(date -u -d "$START - 1 day" +%Y-%m-%dT%H:%M:%SZ)
echo '{}' > "$RAW/spot_history.json"; echo '{}' > "$RAW/on_demand.json"
while read -r itype zone cap; do
  [[ -z "$itype" ]] && continue
  if [[ "$cap" == spot ]]; then
    aws_ro ec2 describe-spot-price-history --instance-types "$itype" --availability-zone "$zone" \
      --product-descriptions "Linux/UNIX" --start-time "$SPOT_FROM" --end-time "$END" > "$RAW/spot.$itype.$zone.json" \
      || die "spot price history failed for $itype $zone"
    python -I -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d[sys.argv[2]]=json.load(open(sys.argv[3])); json.dump(d, open(p,"w"))' \
      "$(pyp "$RAW/spot_history.json")" "$itype|$zone" "$(pyp "$RAW/spot.$itype.$zone.json")"
  fi
  if ! python -I -c 'import json,sys; sys.exit(0 if sys.argv[2] in json.load(open(sys.argv[1])) else 1)' "$(pyp "$RAW/on_demand.json")" "$itype"; then
    timeout 60 aws --region us-east-1 --output json pricing get-products --service-code AmazonEC2 --filters \
      "Type=TERM_MATCH,Field=instanceType,Value=$itype" "Type=TERM_MATCH,Field=regionCode,Value=$REGION" \
      "Type=TERM_MATCH,Field=operatingSystem,Value=Linux" "Type=TERM_MATCH,Field=tenancy,Value=Shared" \
      "Type=TERM_MATCH,Field=preInstalledSw,Value=NA" "Type=TERM_MATCH,Field=capacitystatus,Value=Used" \
      </dev/null > "$RAW/od.$itype.json" || die "pricing get-products failed for $itype"
    python -I -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d[sys.argv[2]]=json.load(open(sys.argv[3])); json.dump(d, open(p,"w"))' \
      "$(pyp "$RAW/on_demand.json")" "$itype" "$(pyp "$RAW/od.$itype.json")"
  fi
done < "$RAW/seen.txt"

mkdir -p "$OUT"
EXTRA=(); [[ -n "$ARM" ]] && EXTRA+=(--arm "$ARM"); [[ -n "$PAIR" ]] && EXTRA+=(--pair-id "$PAIR")
python -I "$(pyp "$HERE/timeline_normalize.py")" --raw "$(pyp "$RAW")" --out "$(pyp "$OUT")" \
  --start "$START" --end "$END" --run-id "$RUN_ID" --roles "$ROLES" "${EXTRA[@]}"
echo "collect_timeline: next: python -I experiments/lib/cost_calc.py run $OUT/cost/cost_input.json"
