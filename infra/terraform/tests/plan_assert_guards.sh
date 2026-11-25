#!/usr/bin/env bash
# Negative tests for plan_assert.sh guards on synthetic plans:
#   check 13: P3 role policy accepts only the approved bucket-level S3 actions;
#   check 7:  endpoint statement 2 must name exactly the 4 layer buckets
#             (both Codex review 14/11/2026, DRF-38);
#   checks 14-17: P4 RDS, ingress, inline policies and trust (DRF-46);
#   check 18: P5 vpc-cni network policy (DRF-68);
#   checks 19-21: P6 queues, batch and Karpenter policies, trust, node role,
#             interruption rules and discovery tags (DRF-77).
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

# --- P5 (DRF-68) --------------------------------------------------------------
# cni <configuration_values string or null> -> plan with only the vpc-cni add-on
cni() { jq -n --arg c "$1" '{resource_changes: [{mode: "managed", type: "aws_eks_addon", change: {actions: ["create"],
    after: ({addon_name: "vpc-cni"} + (if $c == "" then {} else {configuration_values: $c} end))}}]}'; }
expect5() { run_case "$1" "P5 vpc-cni" "p5-$2" "$3" ADMIN_WINDOW=1 P4_WINDOW=1 P5_WINDOW=1; }
expect5 PASS network-policy-standard "$(cni '{"enableNetworkPolicy":"true","env":{"NETWORK_POLICY_ENFORCING_MODE":"standard"}}')"
expect5 FAIL no-configuration        "$(cni '')"
expect5 FAIL network-policy-off      "$(cni '{"enableNetworkPolicy":"false","env":{"NETWORK_POLICY_ENFORCING_MODE":"standard"}}')"
expect5 FAIL strict-mode             "$(cni '{"enableNetworkPolicy":"true","env":{"NETWORK_POLICY_ENFORCING_MODE":"strict"}}')"

# --- P6 (DRF-77) --------------------------------------------------------------
# The good P6 plan (tests/p6_good_plan.jq) carries the approved policies from
# tests/p6_approved_policies.json with a fake account; each case below changes
# exactly one thing and must turn its guard line to FAIL.
ok6="$(sed 's/ACCT/000000000000/g' tests/p6_approved_policies.json | tr -d '\r' | jq -c .policies)"
p6good="$(jq -n --argjson ok "$ok6" -f tests/p6_good_plan.jq)"
p6() { jq -c "$1" <<< "$p6good"; }
# pol6 <policy-name> <filter>; tru6 <role-name> <filter>; qp6 <queue-policy-name> <filter>
pol6() { p6 "(.resource_changes[] | select(.type == \"aws_iam_role_policy\" and .change.after.name == \"$1\") | .change.after.policy) |= (fromjson | $2 | tojson)"; }
tru6() { p6 "(.resource_changes[] | select(.type == \"aws_iam_role\" and .change.after.name == \"$1\") | .change.after.assume_role_policy) |= (fromjson | $2 | tojson)"; }
qp6()  { p6 "(.resource_changes[] | select(.type == \"aws_sqs_queue_policy\" and .name == \"$1\") | .change.after.policy) |= (fromjson | $2 | tojson)"; }
q6()   { p6 "(.resource_changes[] | select(.type == \"aws_sqs_queue\" and .change.after.name == \"$1\") | .change.after) |= ($2)"; }
expect6() { run_case "$1" "$2" "p6-$3" "$4" ADMIN_WINDOW=1 P4_WINDOW=1 P6_WINDOW=1; }
passrole='select([.Action] | flatten | index("iam:PassRole"))'
a6='arn:aws:s3:::zero-drift-batch-'

for g in "P6 queue settings" "P6 redrive target" "P6 queues not public" "P6 policies known" "P6 policies approved" \
         "P6 karpenter no-iam-write" "P6 no-iam-star" "P6 PassRole" "P6 tenant separation" "P6 submit list" \
         "P6 trust zero-drift-batch-keda" "P6 trust zero-drift-batch-submit" "P6 trust zero-drift-batch-tenant-a" \
         "P6 trust zero-drift-batch-tenant-b" "P6 trust zero-drift-karpenter-controller" \
         "P6 node role" "P6 interruption" "P6 discovery tag"; do
    expect6 PASS "$g" "good-${g//[ :]/-}" "$p6good"
done
expect6 FAIL "P6 queue settings"    visibility-30            "$(q6 zero-drift-batch '.visibility_timeout_seconds = 30')"
expect6 FAIL "P6 queue settings"    retention-4-days         "$(q6 zero-drift-batch '.message_retention_seconds = 345600')"
expect6 FAIL "P6 queue settings"    max-receive-5            "$(q6 zero-drift-batch '.redrive_policy |= (fromjson | .maxReceiveCount = 5 | tojson)')"
expect6 FAIL "P6 queue settings"    dlq-no-sse               "$(q6 zero-drift-batch-dlq '.sqs_managed_sse_enabled = false')"
expect6 FAIL "P6 redrive target"    redrive-to-other-queue   "$(q6 zero-drift-batch '.redrive_policy |= (fromjson | .deadLetterTargetArn = "arn:aws:sqs:us-east-1:000000000000:other" | tojson)')"
expect6 FAIL "P6 queues not public" allow-principal-star     "$(qp6 main '.Statement += [{Effect: "Allow", Principal: "*", Action: "sqs:SendMessage", Resource: "x"}]')"
expect6 FAIL "P6 queues not public" allow-aws-principal      "$(qp6 dlq '.Statement += [{Effect: "Allow", Principal: {AWS: "*"}, Action: "sqs:ReceiveMessage", Resource: "x"}]')"
expect6 FAIL "P6 queues not public" dlq-allows-http          "$(qp6 dlq '.Statement = []')"
expect6 FAIL "P6 policies known"    keda-policy-unknown      "$(p6 '(.resource_changes[] | select(.type == "aws_iam_role_policy" and .change.after.name == "batch-keda") | .change) |= (.after.policy = null | .after_unknown = {policy: true})')"
expect6 FAIL "P6 policies approved" keda-plus-ReceiveMessage "$(pol6 batch-keda '.Statement[0].Action += ["sqs:ReceiveMessage"]')"
expect6 FAIL "P6 policies approved" tenant-b-policy-missing  "$(p6 '.resource_changes |= map(select(.change.after.name != "batch-tenant-b"))')"
expect6 FAIL "P6 policies approved" submit-any-object-key    "$(pol6 batch-submit '(.Statement[] | select(.Sid == "WriteSubmitMarkers") | .Resource) = ["'"$a6"'*/*"]')"
expect6 FAIL "P6 karpenter no-iam-write" plus-CreateInstanceProfile "$(pol6 karpenter-controller '.Statement += [{Sid: "X", Effect: "Allow", Action: ["iam:CreateInstanceProfile"], Resource: ["arn:aws:iam::000000000000:instance-profile/*"]}]')"
expect6 FAIL "P6 karpenter no-iam-write" plus-iam-star          "$(pol6 karpenter-controller '.Statement[0].Action += ["iam:*"]')"
expect6 FAIL "P6 no-iam-star"       passrole-resource-star   "$(pol6 karpenter-controller "(.Statement[] | $passrole | .Resource) = [\"*\"]")"
expect6 FAIL "P6 PassRole"          passrole-any-service     "$(pol6 karpenter-controller "(.Statement[] | $passrole) |= del(.Condition)")"
expect6 FAIL "P6 PassRole"          passrole-other-role      "$(pol6 karpenter-controller "(.Statement[] | $passrole | .Resource) = [\"arn:aws:iam::000000000000:role/zero-drift-bootstrap\"]")"
expect6 FAIL "P6 tenant separation" tenant-a-names-tenant-b  "$(pol6 batch-tenant-a '(.Statement[] | select(.Sid == "OwnObjects") | .Resource) += ["'"$a6"'tenant-b-*/*"]')"
expect6 FAIL "P6 tenant separation" tenant-b-any-batch-bucket "$(pol6 batch-tenant-b '(.Statement[] | select(.Sid == "ListOwnBuckets") | .Resource) = ["'"$a6"'*"]')"
expect6 FAIL "P6 submit list"       submit-list-no-prefix    "$(pol6 batch-submit '(.Statement[] | select(.Sid == "ListSubmittedMarkerOnly")) |= del(.Condition)')"
expect6 FAIL "P6 submit list"       submit-list-any-prefix   "$(pol6 batch-submit '(.Statement[] | select(.Sid == "ListSubmittedMarkerOnly") | .Condition.StringLike["s3:prefix"]) = ["runs/*"]')"
expect6 FAIL "P6 submit list"       submit-plus-GetObject    "$(pol6 batch-submit '.Statement[0].Action += ["s3:GetObject"]')"
expect6 FAIL "P6 trust zero-drift-batch-tenant-a"  tenant-a-pattern  "$(tru6 zero-drift-batch-tenant-a '.Statement[0].Condition |= {StringEquals: (.StringEquals | with_entries(select(.key | endswith(":aud")))), StringLike: (.StringEquals | with_entries(select(.key | endswith(":sub"))) | map_values("system:serviceaccount:tenant-*:batch-train"))}')"
expect6 FAIL "P6 trust zero-drift-batch-submit"    submit-from-tenant "$(tru6 zero-drift-batch-submit '.Statement[0].Condition.StringEquals |= with_entries(if (.key | endswith(":sub")) then .value = "system:serviceaccount:tenant-a:batch-submit" else . end)')"
expect6 FAIL "P6 trust zero-drift-karpenter-controller" no-audience "$(tru6 zero-drift-karpenter-controller '.Statement[0].Condition.StringEquals |= with_entries(select(.key | endswith(":aud") | not))')"
expect6 FAIL "P6 trust zero-drift-batch-keda"      second-statement  "$(tru6 zero-drift-batch-keda '.Statement += [.Statement[0]]')"
expect6 INFO "P6 trust zero-drift-batch-keda"      unknown-first-plan "$(p6 '(.resource_changes[] | select(.type == "aws_iam_role" and .change.after.name == "zero-drift-batch-keda") | .change) |= (.after.assume_role_policy = null | .after_unknown = {assume_role_policy: true})')"
expect6 FAIL "P6 node role"         plus-SSM-attachment      "$(p6 '.resource_changes += [first(.resource_changes[] | select(.type == "aws_iam_role_policy_attachment")) | .change.after.policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]')"
expect6 FAIL "P6 node role"         no-instance-profile      "$(p6 '.resource_changes |= map(select(.type != "aws_iam_instance_profile"))')"
expect6 FAIL "P6 node role"         node-trusts-lambda       "$(tru6 zero-drift-karpenter-node '.Statement[0].Principal.Service = "lambda.amazonaws.com"')"
expect6 FAIL "P6 interruption"      three-rules              "$(p6 '.resource_changes |= (map(select(.type != "aws_cloudwatch_event_rule" or .name != "AWS Health Event")))')"
expect6 FAIL "P6 interruption"      target-other-queue       "$(p6 '(first(.resource_changes[] | select(.type == "aws_cloudwatch_event_target")) | .change.after.arn) = "arn:aws:sqs:us-east-1:000000000000:zero-drift-batch"')"
expect6 FAIL "P6 discovery tag"     sg-untagged              "$(p6 '(.resource_changes[] | select(.type == "aws_security_group") | .change.after.tags) |= del(.["karpenter.sh/discovery"])')"
expect6 FAIL "P6 discovery tag"     database-subnet-tagged   "$(p6 '(.resource_changes[] | select(.type == "aws_subnet" and .name == "database") | .change.after.tags["karpenter.sh/discovery"]) = "zero-drift"')"

if (( bad )); then echo "RESULT: FAIL"; exit 1; fi
echo "RESULT: PASS (guards only; plan_assert on a real plan is still required)"
