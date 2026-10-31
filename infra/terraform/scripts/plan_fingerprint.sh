#!/usr/bin/env bash
# Fingerprint of a saved plan (SPEC-P2 Task 6). Prints two hashes:
#   file   sha256 of this exact plan file; valid only until state or inputs change.
#   shape  sha256 of the sorted "action address" list; no values, so no account ID,
#          IP or tags. A fresh plan in the L3 window must give the same shape hash
#          as the approved candidate, or the window stops.
# Usage: infra/terraform/scripts/plan_fingerprint.sh tfplan
set -euo pipefail

plan="${1:?usage: plan_fingerprint.sh <saved plan file>}"
[[ -f "$plan" ]] || { echo "no such plan file: $plan" >&2; exit 2; }

shape="$(terraform show -json "$plan" | jq -r '
    .resource_changes[]
    | select(.mode == "managed")
    | "\(.change.actions | join("+")) \(.address)"' | sort)"

echo "resources: $(printf '%s\n' "$shape" | grep -c .)"
echo "actions:   $(printf '%s\n' "$shape" | cut -d' ' -f1 | sort | uniq -c | awk '{printf "%s=%s ", $2, $1}')"
echo "file  sha256: $(sha256sum "$plan" | cut -d' ' -f1)"
echo "shape sha256: $(printf '%s\n' "$shape" | sha256sum | cut -d' ' -f1)"
