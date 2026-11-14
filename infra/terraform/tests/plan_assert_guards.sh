#!/usr/bin/env bash
# Negative tests for two plan_assert.sh guards (Codex review 14/11/2026, DRF-38):
#   check 13: P3 role policy accepts only the approved bucket-level S3 actions;
#   check 7:  endpoint statement 2 must name exactly the 4 layer buckets.
# Builds small synthetic plan JSON in memory (no AWS, no Terraform), runs
# plan_assert.sh on it and reads only the line of the guard under test; other
# checks fail on the synthetic plan and are ignored.
# Usage, from infra/terraform: bash tests/plan_assert_guards.sh
# Mutation check: PLAN_ASSERT=<older copy of plan_assert.sh> bash tests/plan_assert_guards.sh
set -euo pipefail
cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
bad=0

base_actions='["s3:CreateBucket","s3:DeleteBucket","s3:ListBucket","s3:PutBucketTagging","s3:GetBucket*","s3:GetAccelerateConfiguration","s3:GetEncryptionConfiguration","s3:GetLifecycleConfiguration","s3:GetReplicationConfiguration"]'
layers='["arn:aws:s3:::prod-us-east-1-starport-layer-bucket/*","arn:aws:s3:::al2023-repos-us-east-1-de612dc2/*","arn:aws:s3:::quayio-production-s3/*","arn:aws:s3:::prod-registry-k8s-io-us-east-1/*"]'

# plan <actions-json> <resource-json> <layer-buckets-json> -> plan JSON on stdout
plan() {
    jq -n --argjson act "$1" --argjson res "$2" --argjson lay "$3" '{resource_changes: [
        {mode: "managed", type: "aws_iam_role_policy", change: {actions: ["create"], after: {policy:
            ({Version: "2012-10-17", Statement: [{Effect: "Allow", Action: $act, Resource: $res}]} | tojson)}}},
        {mode: "managed", type: "aws_vpc_endpoint", change: {actions: ["create"], after: {
            service_name: "com.amazonaws.us-east-1.s3", vpc_endpoint_type: "Gateway", policy:
            ({Statement: [{Condition: {StringEquals: {"aws:ResourceAccount": "000000000000"}}},
                          {Action: "s3:GetObject", Resource: $lay}]} | tojson)}}}]}'
}

# expect <PASS|FAIL> <grep-pattern> <case-name> <plan-json>
expect() {
    local f="$tmp/$3.json" line
    printf '%s' "$4" > "$f"
    line="$(ADMIN_WINDOW=1 P3_WINDOW=1 bash "${PLAN_ASSERT:-scripts/plan_assert.sh}" "$f" 2>/dev/null | grep -E "$2" || true)"
    if [[ "$line" == "$1"* ]]; then echo "ok    $3: $line"
    else echo "WRONG $3: expected $1, got '${line:-no line}'"; bad=1; fi
}

add() { jq -c --arg a "$1" '. + [$a]' <<< "$base_actions"; }
p3='["arn:aws:s3:::zero-drift-p3-*"]'
pol='P3 role policy:'
ep='endpoint policy'

expect PASS "$pol" approved-actions          "$(plan "$base_actions" "$p3" "$layers")"
expect FAIL "$pol" plus-DeleteObject         "$(plan "$(add s3:DeleteObject)" "$p3" "$layers")"
expect FAIL "$pol" plus-GetObject            "$(plan "$(add s3:GetObject)" "$p3" "$layers")"
expect FAIL "$pol" plus-PutObject            "$(plan "$(add s3:PutObject)" "$p3" "$layers")"
expect FAIL "$pol" plus-Get-wildcard         "$(plan "$(add 's3:Get*')" "$p3" "$layers")"
expect FAIL "$pol" plus-iam-PassRole         "$(plan "$(add iam:PassRole)" "$p3" "$layers")"
expect FAIL "$pol" resource-star             "$(plan "$base_actions" '["*"]' "$layers")"
expect PASS "$ep"  four-layer-buckets        "$(plan "$base_actions" "$p3" "$layers")"
expect FAIL "$ep"  three-layer-buckets       "$(plan "$base_actions" "$p3" "$(jq -c '.[:3]' <<< "$layers")")"
expect FAIL "$ep"  extra-bucket              "$(plan "$base_actions" "$p3" "$(jq -c '. + ["arn:aws:s3:::other/*"]' <<< "$layers")")"

if (( bad )); then echo "RESULT: FAIL"; exit 1; fi
echo "RESULT: PASS (guards only; plan_assert on a real plan is still required)"
