#!/usr/bin/env bash
# P3 provider role check (DRF-36, SPEC-P3 Task 4). Read-only: Access Analyzer
# validation plus an IAM simulation matrix of the Crossplane provider policy:
# P3-prefixed buckets allowed, everything else denied. Creates nothing.
# Usage, from infra/terraform with AWS_PROFILE/AWS_REGION exported:
#   ./scripts/p3_iam_check.sh tfplan        # policy taken from a saved P3 plan (before apply)
#   ./scripts/p3_iam_check.sh --principal   # the live role (inside the window, after apply)
# The account ID is read at runtime and never printed.
set -euo pipefail

: "${AWS_PROFILE:?export AWS_PROFILE first}"
export MSYS_NO_PATHCONV=1
src="${1:?usage: p3_iam_check.sh <saved P3 plan> | --principal}"
role="zero-drift-p3-crossplane-s3"

failed=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; failed=1; }

acct="$(aws sts get-caller-identity --query Account --output text)"
if [[ "$src" != "--principal" ]]; then
    policy_json="$(terraform show -json "$src" | jq -r '.resource_changes[] | select(.type == "aws_iam_role_policy") | .change.after.policy' | jq -c .)"
    [[ -n "$policy_json" ]] || { echo "no aws_iam_role_policy in the plan: was it made with enable_p3_provider_role=true?" >&2; exit 2; }
    findings="$(aws accessanalyzer validate-policy --policy-type IDENTITY_POLICY \
        --policy-document "$policy_json" --query 'findings[].findingType' --output json)"
    bad="$(jq '[.[] | select(. == "ERROR" or . == "SECURITY_WARNING")] | length' <<< "$findings")"
    [[ "$bad" == 0 ]] && pass "Access Analyzer: 0 ERROR/SECURITY_WARNING ($(jq -r 'group_by(.) | map("\(.[0])=\(length)") | join(" ") | if . == "" then "no findings" else . end' <<< "$findings"))" \
        || fail "Access Analyzer: $(jq -c . <<< "$findings")"
fi

# expect | action | resource
matrix='
allowed|s3:CreateBucket|arn:aws:s3:::zero-drift-p3-spike-check
allowed|s3:DeleteBucket|arn:aws:s3:::zero-drift-p3-spike-check
allowed|s3:ListBucket|arn:aws:s3:::zero-drift-p3-spike-check
allowed|s3:GetBucketTagging|arn:aws:s3:::zero-drift-p3-spike-check
allowed|s3:PutBucketTagging|arn:aws:s3:::zero-drift-p3-spike-check
implicitDeny|s3:CreateBucket|arn:aws:s3:::zdr-outside-prefix-check
implicitDeny|s3:DeleteBucket|arn:aws:s3:::zero-d-rift-tfstate-example
implicitDeny|s3:GetObject|arn:aws:s3:::zero-drift-p3-spike-check/any-key
implicitDeny|s3:PutObject|arn:aws:s3:::zero-drift-p3-spike-check/any-key
implicitDeny|s3:PutBucketPolicy|arn:aws:s3:::zero-drift-p3-spike-check
implicitDeny|s3:ListAllMyBuckets|*
implicitDeny|iam:CreateRole|arn:aws:iam::ACCT:role/zero-drift-p3-escalate
implicitDeny|sts:AssumeRole|arn:aws:iam::ACCT:role/zero-drift-bootstrap
'

while IFS='|' read -r expect action resource; do
    [[ -z "$expect" ]] && continue
    resource="${resource//ACCT/$acct}"
    if [[ "$src" == "--principal" ]]; then
        got="$(aws iam simulate-principal-policy --policy-source-arn "arn:aws:iam::$acct:role/$role" \
            --action-names "$action" --resource-arns "$resource" --query 'EvaluationResults[0].EvalDecision' --output text)"
    else
        got="$(aws iam simulate-custom-policy --policy-input-list "$policy_json" \
            --action-names "$action" --resource-arns "$resource" --query 'EvaluationResults[0].EvalDecision' --output text)"
    fi
    shown="${resource//$acct/<ACCOUNT>}"
    [[ "$got" == "$expect" ]] && pass "$expect  $action  $shown" || fail "$action  $shown: got $got, expected $expect"
done <<< "$matrix"

unset acct
echo
if (( failed )); then echo "RESULT: FAIL"; exit 1; fi
echo "RESULT: PASS (simulation only; the real proof is the L3 negative test)"
