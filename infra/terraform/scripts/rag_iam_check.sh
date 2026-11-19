#!/usr/bin/env bash
# P4 role check (DRF-46, SPEC-P4 P4-T2.2 B). Read-only: Access Analyzer
# validation and an IAM simulation of the allow/deny matrix in
# tests/rag_iam_matrix.json for the five P4 roles. Creates nothing.
# The same matrix runs offline in terraform test (tests/rag_platform.tftest.hcl).
# Usage, from infra/terraform with AWS_PROFILE/AWS_REGION exported:
#   ./scripts/rag_iam_check.sh tfplan        # policies from a saved P4 plan (before apply)
#   ./scripts/rag_iam_check.sh --principal   # the live roles (inside the window, after apply)
# A first plan cannot know the master secret ARN: rag-db-admin-master and the
# matrix rows that name MASTER are then skipped and must pass with --principal.
# The account ID and the master secret ARN are read at runtime and never printed.
set -euo pipefail

: "${AWS_PROFILE:?export AWS_PROFILE first}"
export MSYS_NO_PATHCONV=1
src="${1:?usage: rag_iam_check.sh <saved P4 plan> | --principal}"
cd "$(dirname "$0")/.."
matrix="tests/rag_iam_matrix.json"

failed=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; failed=1; }
skip() { echo "SKIP  $1"; }

declare -A role_name=(
    [db-admin]=zero-drift-rag-db-admin [bootstrap]=zero-drift-rag-bootstrap
    [crossplane-s3]=zero-drift-rag-crossplane-s3 [tenant-a]=zero-drift-rag-tenant-a [tenant-b]=zero-drift-rag-tenant-b
)
declare -A subject=(
    [db-admin]="StringEquals system:serviceaccount:zdr-platform:rag-db-admin"
    [bootstrap]="StringEquals system:serviceaccount:zdr-platform:rag-bootstrap"
    [crossplane-s3]="StringEquals system:serviceaccount:crossplane-system:provider-aws-s3"
    [tenant-a]="StringLike system:serviceaccount:tenant-a:rag-*"
    [tenant-b]="StringLike system:serviceaccount:tenant-b:rag-*"
)

acct="$(aws sts get-caller-identity --query Account --output text)"
master=""
declare -A policy=()  # role key -> policy JSON with all its statements (plan mode)

if [[ "$src" != "--principal" ]]; then
    plan_json="$(terraform show -json "$src")"
    for key in "${!role_name[@]}"; do
        # All known inline policies of this role, merged into one document.
        doc="$(jq -c --arg r "$key" '
            [.resource_changes[] | select(.type == "aws_iam_role_policy" and (.change.after.policy // null) != null)
             | select(.change.after.name == ("rag-" + $r) or (.change.after.name | startswith("rag-" + $r + "-")))
             | .change.after.policy | fromjson | .Statement[]]
            | {Version: "2012-10-17", Statement: .}' <<< "$plan_json")"
        [[ "$(jq '.Statement | length' <<< "$doc")" == 0 ]] && { fail "no known policy for $key: was the plan made with enable_rag_platform=true?"; continue; }
        policy[$key]="$doc"
        findings="$(aws accessanalyzer validate-policy --policy-type IDENTITY_POLICY --policy-document "$doc" \
            --query 'findings[].findingType' --output json)"
        bad="$(jq '[.[] | select(. == "ERROR" or . == "SECURITY_WARNING")] | length' <<< "$findings")"
        [[ "$bad" == 0 ]] && pass "Access Analyzer $key: 0 ERROR/SECURITY_WARNING" || fail "Access Analyzer $key: $(jq -c . <<< "$findings")"
    done
    unset plan_json
else
    master="$(aws rds describe-db-instances --db-instance-identifier zero-drift-rag \
        --query 'DBInstances[0].MasterUserSecret.SecretArn' --output text)"
    # Live trust documents: one web identity statement from THIS cluster's OIDC
    # issuer, audience sts.amazonaws.com, subject only as approved.
    issuer="$(aws eks describe-cluster --name "${CLUSTER_NAME:-zero-drift}" --query 'cluster.identity.oidc.issuer' --output text | sed 's#^https://##')"
    for key in "${!role_name[@]}"; do
        read -r op sub <<< "${subject[$key]}"
        trust="$(aws iam get-role --role-name "${role_name[$key]}" --query 'Role.AssumeRolePolicyDocument' --output json)"
        ok="$(jq -r --arg i "$issuer" --arg op "$op" --arg sub "$sub" '
            .Statement as $s | $s[0].Condition as $c
            | [($s | length == 1), $s[0].Effect == "Allow", $s[0].Action == "sts:AssumeRoleWithWebIdentity",
               ($s[0].Principal.Federated | endswith(":oidc-provider/" + $i)),
               ($c.StringEquals[$i + ":aud"] == "sts.amazonaws.com"),
               ($c[$op][$i + ":sub"] == $sub),
               (if $op == "StringEquals" then ($c | has("StringLike") | not) else ($c.StringEquals | has($i + ":sub") | not) end),
               (($c | keys) - ["StringEquals", "StringLike"] | length == 0)] | all' <<< "$trust" 2>/dev/null || echo false)"
        [[ "$ok" == true ]] && pass "live trust ${role_name[$key]}: this cluster's OIDC, $op $sub" || fail "live trust ${role_name[$key]} is not the approved shape"
    done
    unset issuer trust
fi

# One simulation call per matrix row, so every decision is printed.
while IFS=$'\t' read -r key expect action resource; do
    resource="${resource%$'\r'}"
    if [[ "$resource" == MASTER ]]; then
        [[ -z "$master" ]] && { skip "$key $action <master secret>: unknown before apply, run --principal"; continue; }
        resource="$master"; shown="<master secret>"
    else
        resource="${resource//ACCT/$acct}"; shown="${resource//$acct/<ACCOUNT>}"
    fi
    if [[ "$src" == "--principal" ]]; then
        got="$(aws iam simulate-principal-policy --policy-source-arn "arn:aws:iam::$acct:role/${role_name[$key]}" \
            --action-names "$action" --resource-arns "$resource" --query 'EvaluationResults[0].EvalDecision' --output text)"
    else
        [[ -n "${policy[$key]:-}" ]] || { fail "$key: no policy to simulate"; continue; }
        got="$(aws iam simulate-custom-policy --policy-input-list "${policy[$key]}" \
            --action-names "$action" --resource-arns "$resource" --query 'EvaluationResults[0].EvalDecision' --output text)"
    fi
    got="${got%$'\r'}"
    [[ "$got" == "$expect" ]] && pass "$key  $expect  $action  $shown" || fail "$key  $action  $shown: got $got, expected $expect"
done < <(jq -r '.cases[] | [.role, .expect, .action, .resource] | @tsv' "$matrix")

unset acct master
echo
if (( failed )); then echo "RESULT: FAIL"; exit 1; fi
echo "RESULT: PASS (simulation only; the real proof is the L3 negative suite, DRF-56 D)"
