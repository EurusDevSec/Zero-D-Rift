#!/usr/bin/env bash
# S2 retry gate (runbook P6_L3_WINDOW §6 H8; Codex 27/11 finding 1). An apply
# that stopped part-way leaves a retry plan with only the missing resources.
# plan_assert.sh checks only a full plan, so this script proves instead that
# the retry plan is a subset of the approved full plan, value for value:
#   1. same configuration (code) and same input variables as the full plan;
#   2. every managed change is "create" (no update, delete, replace or forget);
#   3. every created address is a "create" of the same type and provider in the
#      full plan;
#   4. the created value equals the full plan's, compared as a whole structure:
#      same object keys, same array lengths, same leaves. It may differ or add
#      only under a path that the full plan's after_unknown marks true (Codex
#      27/11 round 2: an added list element or tag must not pass).
# Values the full plan did not know yet (an ARN of a role made in the same
# apply) come from the same expressions (rule 1) over resources that were made
# by the approved plan and are not changed (rule 2).
# Read-only, no AWS call. Prints addresses and attribute paths, never values.
# Usage, from infra/terraform:
#   ./scripts/retry_plan_check.sh tfplan retry.tfplan           # saved plans (*.tfplan is gitignored)
#   ./scripts/retry_plan_check.sh --json full.json retry.json   # terraform show -json output
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

if [[ "${1:-}" == "--json" ]]; then
    cp "${2:?usage: retry_plan_check.sh --json <full.json> <retry.json>}" "$tmp/full.json"
    cp "${3:?usage: retry_plan_check.sh --json <full.json> <retry.json>}" "$tmp/retry.json"
else
    terraform show -json "${1:?usage: retry_plan_check.sh <full plan> <retry plan>}" > "$tmp/full.json"
    terraform show -json "${2:?usage: retry_plan_check.sh <full plan> <retry plan>}" > "$tmp/retry.json"
fi

# jq on Windows cannot read /proc/fd, so plain files; strip CR from its output.
out="$(jq -r --slurpfile f "$tmp/full.json" --slurpfile r "$tmp/retry.json" -n '
  $f[0] as $F | $r[0] as $R |
  def managed($p): [$p.resource_changes[]? | select(.mode == "managed")];
  def creates($p): managed($p) | map(select(.change.actions == ["create"]));
  # Paths where retry value $c differs from full value $o. $u is the full
  # plan after_unknown at the same place: true there means "not known yet",
  # so anything is allowed under it. Elsewhere keys, lengths and leaves must match.
  def diff($o; $c; $u):
    if $u == true then empty
    elif ($o | type) == "object" and ($c | type) == "object" then
      (($o | keys) + ($c | keys) | unique[]) as $k |
      ($u | if type == "object" then .[$k] else null end) as $uk |
      if $uk == true then empty
      elif ($o | has($k)) and ($c | has($k)) then diff($o[$k]; $c[$k]; $uk) | [$k] + .
      else [$k] end
    elif ($o | type) == "array" and ($c | type) == "array" then
      if ($o | length) != ($c | length) then []
      else range(0; $o | length) as $i |
        ($u | if type == "array" then .[$i] else null end) as $ui |
        diff($o[$i]; $c[$i]; $ui) | [$i] + .
      end
    elif $o == $c then empty
    else [] end;
  (managed($F) | map({key: .address, value: .}) | from_entries) as $FI |
  [
    (if ($F.resource_changes // null) == null or ($R.resource_changes // null) == null
     then "FAIL  input is not a plan (no resource_changes)" else empty end),
    (if (creates($F) | length) == 0 then "FAIL  full plan creates nothing" else empty end),
    (if $F.configuration == $R.configuration then "PASS  same configuration as the full plan"
     else "FAIL  configuration differs from the full plan (code changed: make a new full plan)" end),
    (if $F.variables == $R.variables then "PASS  same input variables as the full plan"
     else "FAIL  input variables differ: " + ([($F.variables // {} | keys[]), ($R.variables // {} | keys[])] | unique
          | map(select(. as $k | $F.variables[$k] != $R.variables[$k])) | join(",")) end),
    (managed($R)[] | select(.change.actions != ["no-op"] and .change.actions != ["create"])
     | "FAIL  \(.address): action \(.change.actions | join("+")); only create is allowed"),
    (if (creates($R) | length) == 0 then "FAIL  retry plan creates nothing" else empty end),
    (creates($R)[] | . as $c | $FI[$c.address] as $o |
      if $o == null then "FAIL  \($c.address): not in the full plan"
      elif $o.change.actions != ["create"] then "FAIL  \($c.address): full plan action is \($o.change.actions | join("+")), not create"
      elif $o.type != $c.type or $o.provider_name != $c.provider_name then "FAIL  \($c.address): type or provider differs"
      else
        ([diff($o.change.after; $c.change.after; $o.change.after_unknown)
          | if length == 0 then "(whole value)" else map(tostring) | join(".") end] | unique) as $bad |
        if ($bad | length) == 0 then "PASS  \($c.address): create, value equals the full plan (outside its unknowns)"
        else "FAIL  \($c.address): differs from the full plan at \($bad | join(", "))" end
      end)
  ] | .[]
' 2>/dev/null)" || { echo "FAIL  plans unreadable"; echo "RESULT: FAIL"; exit 1; }
out="${out//$'\r'/}"
printf '%s\n' "$out"
echo
if grep -q '^FAIL' <<< "$out" || [[ -z "$out" ]]; then echo "RESULT: FAIL"; exit 1; fi
echo "RESULT: PASS (retry is a subset of the full plan; confirm the full plan's shape hash with plan_fingerprint.sh)"
