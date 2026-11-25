#!/usr/bin/env bash
# P6 role check (DRF-77, SPEC-P6 P6-T3 C). Read-only: Access Analyzer
# validation and an IAM simulation of the allow/deny matrix in
# tests/batch_iam_matrix.json for the four batch roles and the Karpenter
# controller. Creates nothing. The same matrix runs offline in
# tests/batch_iam_offline.sh on tests/p6_approved_policies.json.
# Usage, from infra/terraform with AWS_PROFILE/AWS_REGION exported:
#   ./scripts/batch_iam_check.sh tfplan        # policies from a saved P6 plan (before apply)
#   ./scripts/batch_iam_check.sh --principal   # the live roles (inside the window, after apply)
# Matrix rows with a "context" pass it as --context-entries (s3:prefix,
# iam:PassedToService, resource tags). The account ID is read at runtime and
# never printed.
set -euo pipefail

: "${AWS_PROFILE:?export AWS_PROFILE first}"
export MSYS_NO_PATHCONV=1
src="${1:?usage: batch_iam_check.sh <saved P6 plan> | --principal}"
cd "$(dirname "$0")/.."
matrix="tests/batch_iam_matrix.json"

failed=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; failed=1; }

declare -A role_name=(
    [keda]=zero-drift-batch-keda [submit]=zero-drift-batch-submit
    [tenant-a]=zero-drift-batch-tenant-a [tenant-b]=zero-drift-batch-tenant-b
    [karpenter]=zero-drift-karpenter-controller
)
declare -A policy_name=(
    [keda]=batch-keda [submit]=batch-submit [tenant-a]=batch-tenant-a [tenant-b]=batch-tenant-b
    [karpenter]=karpenter-controller
)
declare -A subject=(
    [keda]=system:serviceaccount:keda:keda-operator
    [submit]=system:serviceaccount:zdr-platform:batch-submit
    [tenant-a]=system:serviceaccount:tenant-a:batch-train
    [tenant-b]=system:serviceaccount:tenant-b:batch-train
    [karpenter]=system:serviceaccount:karpenter:karpenter
)

acct="$(timeout 60 aws sts get-caller-identity --query Account --output text </dev/null)"
acct="${acct%$'\r'}"
declare -A policy=()  # role key -> policy JSON (plan mode)

if [[ "$src" != "--principal" ]]; then
    plan_json="$(terraform show -json "$src")"
    for key in "${!role_name[@]}"; do
        doc="$(jq -c --arg n "${policy_name[$key]}" '
            [.resource_changes[] | select(.type == "aws_iam_role_policy" and .change.after.name == $n) | .change.after.policy // empty]
            | first // empty' <<< "$plan_json")"
        [[ -z "$doc" ]] && { fail "no known policy for $key: was the plan made with enable_batch_platform=true?"; continue; }
        policy[$key]="$doc"
        findings="$(timeout 60 aws accessanalyzer validate-policy --policy-type IDENTITY_POLICY --policy-document "$doc" \
            --query 'findings[].findingType' --output json </dev/null)"
        bad="$(jq '[.[] | select(. == "ERROR" or . == "SECURITY_WARNING")] | length' <<< "$findings")"
        [[ "$bad" == 0 ]] && pass "Access Analyzer $key: 0 ERROR/SECURITY_WARNING" || fail "Access Analyzer $key: $(jq -c . <<< "$findings")"
    done
    unset plan_json
else
    issuer="$(timeout 60 aws eks describe-cluster --name "${CLUSTER_NAME:-zero-drift}" --query 'cluster.identity.oidc.issuer' --output text </dev/null | tr -d '\r' | sed 's#^https://##')"
    for key in "${!role_name[@]}"; do
        trust="$(timeout 60 aws iam get-role --role-name "${role_name[$key]}" --query 'Role.AssumeRolePolicyDocument' --output json </dev/null)"
        ok="$(jq -r --arg i "$issuer" --arg sub "${subject[$key]}" '
            .Statement as $s | $s[0].Condition as $c
            | [($s | length == 1), $s[0].Effect == "Allow", $s[0].Action == "sts:AssumeRoleWithWebIdentity",
               ($s[0].Principal.Federated | endswith(":oidc-provider/" + $i)),
               ($c.StringEquals[$i + ":aud"] == "sts.amazonaws.com"),
               ($c.StringEquals[$i + ":sub"] == $sub),
               (($c | keys) == ["StringEquals"])] | all' <<< "$trust" 2>/dev/null || echo false)"
        [[ "$ok" == true ]] && pass "live trust ${role_name[$key]}: this cluster's OIDC, StringEquals ${subject[$key]}" \
            || fail "live trust ${role_name[$key]} is not the approved shape"
    done
    unset issuer trust
fi

# One simulation call per matrix row, so every decision is printed.
while IFS=$'\t' read -r key expect action resource ctx; do
    ctx="${ctx%$'\r'}"
    resource="${resource//ACCT/$acct}"; shown="${resource//$acct/<ACCOUNT>}"
    entries=()
    if [[ "$ctx" != "{}" ]]; then
        while IFS=$'\t' read -r k v; do
            entries+=("ContextKeyName=$k,ContextKeyValues=${v%$'\r'},ContextKeyType=string")
        done < <(jq -r 'to_entries[] | [.key, .value] | @tsv' <<< "$ctx")
    fi
    ctx_args=()
    (( ${#entries[@]} )) && ctx_args=(--context-entries "${entries[@]}")
    if [[ "$src" == "--principal" ]]; then
        got="$(timeout 60 aws iam simulate-principal-policy --policy-source-arn "arn:aws:iam::$acct:role/${role_name[$key]}" \
            --action-names "$action" --resource-arns "$resource" "${ctx_args[@]}" \
            --query 'EvaluationResults[0].EvalDecision' --output text </dev/null)"
    else
        [[ -n "${policy[$key]:-}" ]] || { fail "$key: no policy to simulate"; continue; }
        got="$(timeout 60 aws iam simulate-custom-policy --policy-input-list "${policy[$key]}" \
            --action-names "$action" --resource-arns "$resource" "${ctx_args[@]}" \
            --query 'EvaluationResults[0].EvalDecision' --output text </dev/null)"
    fi
    got="${got%$'\r'}"
    [[ "$got" == "$expect" ]] && pass "$key  $expect  $action  $shown $ctx" || fail "$key  $action  $shown $ctx: got $got, expected $expect"
done < <(jq -r '.cases[] | [.role, .expect, .action, .resource, (.context // {} | tojson)] | @tsv' "$matrix")

unset acct
echo
if (( failed )); then echo "RESULT: FAIL"; exit 1; fi
echo "RESULT: PASS (simulation only; the real proof is the L3 suite, B12 and B13)"
