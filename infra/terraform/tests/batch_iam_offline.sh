#!/usr/bin/env bash
# Offline IAM matrix for the P6 roles (DRF-77): evaluates every case of
# tests/batch_iam_matrix.json on tests/p6_approved_policies.json. No AWS.
# Rules: IAM globs (* and ? match any character, "/" included; actions ignore
# case); a statement applies only when every condition holds for the case
# context; a missing key fails a condition except IfExists and ForAllValues.
# Operators supported: StringEquals, StringLike, StringEqualsIfExists,
# ForAllValues:StringEquals, Bool. Any other operator fails the run.
# It is an approximation: scripts/batch_iam_check.sh runs the same matrix
# through AWS IAM simulation in the window.
# Usage, from infra/terraform: bash tests/batch_iam_offline.sh
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# jq on Windows cannot read /proc/fd, so no process substitution: plain files.
sed 's/ACCT/000000000000/g' tests/p6_approved_policies.json > "$tmp/policies.json"
sed 's/ACCT/000000000000/g' tests/batch_iam_matrix.json > "$tmp/matrix.json"

declare -A policy=([keda]=batch-keda [submit]=batch-submit [tenant-a]=batch-tenant-a [tenant-b]=batch-tenant-b [karpenter]=karpenter-controller)
roles="$(for k in "${!policy[@]}"; do printf '%s=%s\n' "$k" "${policy[$k]}"; done | jq -Rn '[inputs | split("=") | {(.[0]): .[1]}] | add')"

jq -r --argjson roles "$roles" --slurpfile m "$tmp/matrix.json" '
  def rx: gsub("(?<c>[.+^$(){}\\[\\]|\\\\])"; "\\\(.c)") | gsub("\\*"; ".*") | gsub("\\?"; ".");
  def glob($v): . as $g | $v | test("^" + ($g | rx) + "$");
  def iglob($v): . as $g | $v | ascii_downcase | test("^" + ($g | ascii_downcase | rx) + "$");
  def list: if type == "array" then . else [.] end;
  def cond_ok($ctx):
    to_entries | all(.key as $op | .value | to_entries | all(
      .key as $k | (.value | list) as $want | ($ctx[$k]) as $have |
      if $op == "StringEquals" then $have != null and ([$have | list[] | . as $h | $want | index($h)] | all(. != null))
      elif $op == "StringLike" then $have != null and ([$have | list[] | . as $h | any($want[]; glob($h))] | all)
      elif $op == "StringEqualsIfExists" then $have == null or ([$have | list[] | . as $h | $want | index($h)] | all(. != null))
      elif $op == "ForAllValues:StringEquals" then $have == null or ([$have | list[] | . as $h | $want | index($h)] | all(. != null))
      elif $op == "Bool" then $have != null and (($have | tostring) == ($want[0] | tostring))
      else error("unsupported operator " + $op) end));
  ($m[0].cases) as $cases
  | . as $p
  | $cases[]
  | . as $c
  | ($p.policies[$roles[$c.role]] // error("no policy for role " + $c.role)) as $st
  | (if any($st[]; .Effect == "Allow"
        and any((.Action | list)[]; iglob($c.action))
        and any((.Resource | list)[]; glob($c.resource))
        and ((.Condition // {}) | cond_ok($c.context // {}))) then "allowed" else "implicitDeny" end) as $got
  | "\(if $got == $c.expect then "ok   " else "WRONG" end)\t\($c.role)\t\($c.expect)\t\($c.action)\t\($c.resource)\t\($c.context // {} | tostring)"
' "$tmp/policies.json" > "$tmp/out" || { echo "RESULT: FAIL (evaluator error)"; exit 1; }
out="$(tr -d '\r' < "$tmp/out")"
grep -v '^ok' <<< "$out" || true
n="$(grep -c . <<< "$out")"; bad="$(grep -c '^WRONG' <<< "$out" || true)"
roles_seen="$(jq -r '[.cases[].role] | unique | length' tests/batch_iam_matrix.json)"
echo "cases=$n wrong=$bad roles=$roles_seen"
(( bad == 0 && n >= 80 && roles_seen == 5 )) || { echo "RESULT: FAIL"; exit 1; }
echo "RESULT: PASS (offline approximation; batch_iam_check.sh simulates in AWS)"
