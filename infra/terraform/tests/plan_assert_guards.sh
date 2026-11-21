#!/usr/bin/env bash
# Negative tests for plan_assert.sh guards on synthetic plans:
#   check 13: P3 role policy accepts only the approved bucket-level S3 actions;
#   check 7:  endpoint statement 2 must name exactly the 4 layer buckets
#             (both Codex review 14/11/2026, DRF-38);
#   checks 14-17: P4 RDS, ingress, inline policies and trust (DRF-46).
# Builds small synthetic plan JSON in memory (no AWS, no Terraform), runs
# plan_assert.sh on it and reads only the line of the guard under test; other
# checks fail on the synthetic plan and are ignored.
# Usage, from infra/terraform: bash tests/plan_assert_guards.sh
# Mutation check: PLAN_ASSERT=<older copy of plan_assert.sh> bash tests/plan_assert_guards.sh
set -euo pipefail
cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
bad=0
pa="${PLAN_ASSERT:-scripts/plan_assert.sh}"

base_actions='["s3:CreateBucket","s3:DeleteBucket","s3:ListBucket","s3:PutBucketTagging","s3:GetBucket*","s3:GetAccelerateConfiguration","s3:GetEncryptionConfiguration","s3:GetLifecycleConfiguration","s3:GetReplicationConfiguration"]'
layers='["arn:aws:s3:::prod-us-east-1-starport-layer-bucket/*","arn:aws:s3:::al2023-repos-us-east-1-de612dc2/*","arn:aws:s3:::quayio-production-s3/*","arn:aws:s3:::prod-registry-k8s-io-us-east-1/*"]'

# plan <actions-json> <resource-json> <layer-buckets-json> -> plan JSON on stdout
plan() {
    jq -n --argjson act "$1" --argjson res "$2" --argjson lay "$3" '{resource_changes: [
        {mode: "managed", type: "aws_iam_role_policy", change: {actions: ["create"], after: {name: "p3-buckets", policy:
            ({Version: "2012-10-17", Statement: [{Effect: "Allow", Action: $act, Resource: $res}]} | tojson)}}},
        {mode: "managed", type: "aws_vpc_endpoint", change: {actions: ["create"], after: {
            service_name: "com.amazonaws.us-east-1.s3", vpc_endpoint_type: "Gateway", policy:
            ({Statement: [{Condition: {StringEquals: {"aws:ResourceAccount": "000000000000"}}},
                          {Action: "s3:GetObject", Resource: $lay}]} | tojson)}}}]}'
}

# run_case <PASS|FAIL|INFO> <grep-pattern> <case-name> <plan-json> <env...>
run_case() {
    local want="$1" pattern="$2" name="$3" json="$4" f line; shift 4
    f="$tmp/$name.json"
    printf '%s' "$json" > "$f"
    line="$(env "$@" bash "$pa" "$f" 2>/dev/null | grep -E "$pattern" | head -1 || true)"
    if [[ "$line" == "$want"* ]]; then echo "ok    $name: $line"
    else echo "WRONG $name: expected $want, got '${line:-no line}'"; bad=1; fi
}
expect()  { run_case "$1" "$2" "$3" "$4" ADMIN_WINDOW=1 P3_WINDOW=1; }
expect4() { run_case "$1" "$2" "p4-$3" "$4" ADMIN_WINDOW=1 P4_WINDOW=1; }

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

# --- P4 (DRF-46) --------------------------------------------------------------
# The good P4 plan uses the approved policies from plan_assert.sh --approved
# (fake account), so every case below changes exactly one thing.
approved="$(bash "$pa" --approved)"
p4good="$(jq -n --argjson ok "$approved" -f tests/p4_good_plan.jq)"

p4()  { jq -c "$1" <<< "$p4good"; }
# pol <policy-name> <filter on the policy document>; tru <role-name> <filter on the trust document>
pol() { p4 "(.resource_changes[] | select(.type == \"aws_iam_role_policy\" and .change.after.name == \"$1\") | .change.after.policy) |= (fromjson | $2 | tojson)"; }
tru() { p4 "(.resource_changes[] | select(.type == \"aws_iam_role\" and .change.after.name == \"$1\") | .change.after.assume_role_policy) |= (fromjson | $2 | tojson)"; }
db()  { p4 "(.resource_changes[] | select(.type == \"aws_db_instance\") | .change.after) |= ($1)"; }
master_unknown='(.resource_changes[] | select(.type == "aws_iam_role_policy" and .change.after.name == "rag-db-admin-master") | .change) |= (.after.policy = null | .after_unknown = {policy: true})'

for g in "P4 RDS private" "P4 RDS shape" "P4 RDS ingress" "P4 policies no-star" "P4 policies no-iam" \
         "P4 policies approved" "P4 tenant separation" "P4 policies size" \
         "P4 trust zero-drift-rag-db-admin" "P4 trust zero-drift-rag-bootstrap" "P4 trust zero-drift-rag-crossplane-s3" \
         "P4 trust zero-drift-rag-tenant-a" "P4 trust zero-drift-rag-tenant-b"; do
    expect4 PASS "$g" "good-${g//[ :]/-}" "$p4good"
done
expect4 FAIL "P4 RDS private"           rds-public                "$(db '.publicly_accessible = true')"
expect4 FAIL "P4 RDS private"           rds-unencrypted           "$(db '.storage_encrypted = false')"
expect4 FAIL "P4 RDS private"           rds-own-password          "$(db '.manage_master_user_password = false')"
expect4 FAIL "P4 RDS shape"             rds-final-snapshot        "$(db '.skip_final_snapshot = false')"
expect4 FAIL "P4 RDS shape"             rds-larger-class          "$(db '.instance_class = "db.t4g.small"')"
expect4 FAIL "P4 RDS ingress"           ingress-from-internet     "$(p4 '(.resource_changes[] | select(.type == "aws_vpc_security_group_ingress_rule") | .change) |= (.after.cidr_ipv4 = "0.0.0.0/0" | .after_unknown = {})')"
expect4 FAIL "P4 RDS ingress"           ingress-two-rules         "$(p4 '.resource_changes += [.resource_changes[] | select(.type == "aws_vpc_security_group_ingress_rule")]')"
expect4 FAIL "P4 policies no-star" tenant-a-resource-star    "$(pol rag-tenant-a '.Statement[0].Resource = ["*"]')"
expect4 FAIL "P4 policies no-iam"      bootstrap-plus-PassRole   "$(pol rag-bootstrap '.Statement[0].Action += ["iam:PassRole"]')"
expect4 FAIL "P4 policies no-iam"      crossplane-s3-star        "$(pol rag-crossplane-s3 '.Statement[0].Action += ["s3:*"]')"
expect4 FAIL "P4 policies no-iam"      crossplane-GetBucket-star "$(pol rag-crossplane-s3 '(.Statement[] | select(.Sid == "RagBuckets") | .Action) |= (map(select(startswith("s3:GetBucket") | not)) + ["s3:GetBucket*"])')"
expect4 FAIL "P4 policies approved" crossplane-plus-PutObject "$(pol rag-crossplane-s3 '.Statement[0].Action += ["s3:PutObject"]')"
expect4 FAIL "P4 policies approved" bootstrap-secret-star     "$(pol rag-db-admin '.Statement[0].Resource |= map(sub("-[?]+$"; "-*"))')"
expect4 FAIL "P4 policies approved" tenant-a-any-rag-bucket   "$(pol rag-tenant-a '(.Statement[] | select(.Sid == "ReadOwnObjects") | .Resource) = ["arn:aws:s3:::zero-drift-rag-*/*"]')"
expect4 FAIL "P4 policies approved" master-other-secret       "$(pol rag-db-admin-master '.Statement[0].Resource = ["arn:aws:secretsmanager:us-east-1:000000000000:secret:zero-drift/rag/tenant-a/*"]')"
expect4 FAIL "P4 tenant separation"     tenant-a-names-tenant-b   "$(pol rag-tenant-a '(.Statement[] | select(.Sid == "OwnSecrets") | .Resource) += ["arn:aws:secretsmanager:us-east-1:000000000000:secret:zero-drift/rag/tenant-b/*"]')"
expect4 FAIL "P4 trust zero-drift-rag-db-admin"      platform-from-tenant-ns  "$(tru zero-drift-rag-db-admin '(.Statement[0].Condition.StringEquals | to_entries | map(if (.key | endswith(":sub")) then .value = "system:serviceaccount:tenant-a:rag-db-admin" else . end) | from_entries) as $c | .Statement[0].Condition.StringEquals = $c')"
expect4 FAIL "P4 trust zero-drift-rag-bootstrap"     platform-pattern         "$(tru zero-drift-rag-bootstrap '.Statement[0].Condition |= {StringEquals: (.StringEquals | with_entries(select(.key | endswith(":aud")))), StringLike: (.StringEquals | with_entries(select(.key | endswith(":sub"))) | map_values("system:serviceaccount:*:rag-bootstrap"))}')"
expect4 FAIL "P4 trust zero-drift-rag-tenant-a"      tenant-a-trusts-tenant-b "$(tru zero-drift-rag-tenant-a '.Statement[0].Condition.StringLike |= map_values("system:serviceaccount:tenant-b:rag-*")')"
expect4 FAIL "P4 trust zero-drift-rag-crossplane-s3" crossplane-no-audience   "$(tru zero-drift-rag-crossplane-s3 '.Statement[0].Condition.StringEquals |= with_entries(select(.key | endswith(":aud") | not))')"
expect4 INFO "P4 policies unknown"      master-unknown-first-plan "$(p4 "$master_unknown")"
expect4 PASS "P4 policies approved" master-unknown-rest-ok    "$(p4 "$master_unknown")"

if (( bad )); then echo "RESULT: FAIL"; exit 1; fi
echo "RESULT: PASS (guards only; plan_assert on a real plan is still required)"
