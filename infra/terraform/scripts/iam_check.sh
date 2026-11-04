#!/usr/bin/env bash
# R1 policy check (DRF-11 prep). Read-only: Access Analyzer validation plus an
# IAM simulation matrix of what Terraform needs (must be allowed) and what the
# guardrails forbid (must be denied). Creates and attaches nothing.
# Usage, from infra/terraform with AWS_PROFILE/AWS_REGION exported:
#   ./scripts/iam_check.sh             # simulate the policy file (before attach)
#   ./scripts/iam_check.sh --principal # simulate the live role (after attach)
# The account ID is read at runtime and never printed.
set -euo pipefail

: "${AWS_PROFILE:?export AWS_PROFILE first}"
# Git Bash would rewrite the /aws/... parts of ARNs into Windows paths.
export MSYS_NO_PATHCONV=1

mode="${1:-}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here/../../iam"   # file:// must be a relative path on Git Bash
policy="zero-drift-terraform-policy.json"
acct="$(aws sts get-caller-identity --query Account --output text)"

failed=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; failed=1; }

if [[ "$mode" != "--principal" ]]; then
    findings="$(aws accessanalyzer validate-policy --policy-type IDENTITY_POLICY \
        --policy-document "file://$policy" --query 'findings[].findingType' --output json)"
    bad="$(jq '[.[] | select(. == "ERROR" or . == "SECURITY_WARNING")] | length' <<< "$findings")"
    [[ "$bad" == 0 ]] && pass "Access Analyzer: 0 ERROR/SECURITY_WARNING ($(jq -r 'group_by(.) | map("\(.[0])=\(length)") | join(" ") | if . == "" then "no findings" else . end' <<< "$findings"))" \
        || fail "Access Analyzer: $(jq -c . <<< "$findings")"
fi

# expect | action | resource (ACCT is replaced) | context "key=value[;key=value]"
matrix='
allowed|ec2:CreateVpc|arn:aws:ec2:us-east-1:ACCT:vpc/*|aws:RequestedRegion=us-east-1
implicitDeny|ec2:CreateVpc|arn:aws:ec2:us-west-2:ACCT:vpc/*|aws:RequestedRegion=us-west-2
allowed|eks:CreateCluster|arn:aws:eks:us-east-1:ACCT:cluster/zero-drift|aws:RequestedRegion=us-east-1
allowed|ec2:RunInstances|arn:aws:ec2:us-east-1:ACCT:instance/*|aws:RequestedRegion=us-east-1;ec2:InstanceType=m6i.large
explicitDeny|ec2:RunInstances|arn:aws:ec2:us-east-1:ACCT:instance/*|aws:RequestedRegion=us-east-1;ec2:InstanceType=g4dn.xlarge
explicitDeny|ec2:CreateNatGateway|arn:aws:ec2:us-east-1:ACCT:natgateway/*|aws:RequestedRegion=us-east-1
explicitDeny|ec2:AllocateAddress|arn:aws:ec2:us-east-1:ACCT:elastic-ip/*|aws:RequestedRegion=us-east-1
allowed|iam:CreateRole|arn:aws:iam::ACCT:role/zero-drift-cluster-20261104|
allowed|iam:CreateRole|arn:aws:iam::ACCT:role/zero-drift-system-node-20261104|
implicitDeny|iam:CreateRole|arn:aws:iam::ACCT:role/zero-drift-admin|
allowed|iam:AttachRolePolicy|arn:aws:iam::ACCT:role/zero-drift-cluster-20261104|iam:PolicyARN=arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
implicitDeny|iam:AttachRolePolicy|arn:aws:iam::ACCT:role/zero-drift-cluster-20261104|iam:PolicyARN=arn:aws:iam::aws:policy/AdministratorAccess
explicitDeny|iam:AttachRolePolicy|arn:aws:iam::ACCT:role/zero-drift-bootstrap|iam:PolicyARN=arn:aws:iam::aws:policy/AdministratorAccess
explicitDeny|iam:CreatePolicyVersion|arn:aws:iam::ACCT:policy/zero-drift-terraform|
explicitDeny|iam:CreateUser|arn:aws:iam::ACCT:user/zdr-probe|
allowed|iam:PassRole|arn:aws:iam::ACCT:role/zero-drift-system-node-20261104|iam:PassedToService=eks.amazonaws.com
implicitDeny|iam:PassRole|arn:aws:iam::ACCT:role/zero-drift-system-node-20261104|iam:PassedToService=lambda.amazonaws.com
allowed|iam:CreateOpenIDConnectProvider|arn:aws:iam::ACCT:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE|
allowed|iam:CreateServiceLinkedRole|*|iam:AWSServiceName=eks-nodegroup.amazonaws.com
implicitDeny|iam:CreateServiceLinkedRole|*|iam:AWSServiceName=rds.amazonaws.com
allowed|logs:CreateLogGroup|arn:aws:logs:us-east-1:ACCT:log-group:/aws/eks/zero-drift/cluster|
implicitDeny|logs:CreateLogGroup|arn:aws:logs:us-east-1:ACCT:log-group:/other/app|
allowed|rds:CreateDBSubnetGroup|arn:aws:rds:us-east-1:ACCT:subgrp:zero-drift|
implicitDeny|rds:CreateDBInstance|arn:aws:rds:us-east-1:ACCT:db:zero-drift|
allowed|s3:PutObject|arn:aws:s3:::zero-d-rift-tfstate-example/p2/terraform.tfstate|
implicitDeny|s3:GetObject|arn:aws:s3:::some-other-bucket/secret|
explicitDeny|s3:DeleteBucket|arn:aws:s3:::zero-d-rift-tfstate-example|
allowed|ssm:GetParameter|arn:aws:ssm:us-east-1::parameter/aws/service/eks/optimized-ami/1.35/amazon-linux-2023/x86_64/standard/recommended/release_version|
allowed|budgets:ViewBudget|arn:aws:budgets::ACCT:budget/zero-d-rift-project|
implicitDeny|organizations:LeaveOrganization|*|
'

while IFS='|' read -r expect action resource ctx; do
    [[ -z "$expect" ]] && continue
    resource="${resource//ACCT/$acct}"
    args=(--action-names "$action" --resource-arns "$resource")
    if [[ -n "$ctx" ]]; then
        entries=()
        IFS=';' read -ra kvs <<< "$ctx"
        for kv in "${kvs[@]}"; do
            entries+=("ContextKeyName=${kv%%=*},ContextKeyValues=${kv#*=},ContextKeyType=string")
        done
        args+=(--context-entries "${entries[@]}")
    fi
    if [[ "$mode" == "--principal" ]]; then
        got="$(aws iam simulate-principal-policy --policy-source-arn "arn:aws:iam::$acct:role/zero-drift-bootstrap" \
            "${args[@]}" --query 'EvaluationResults[0].EvalDecision' --output text)"
    else
        got="$(aws iam simulate-custom-policy --policy-input-list "file://$policy" \
            "${args[@]}" --query 'EvaluationResults[0].EvalDecision' --output text)"
    fi
    shown="${resource//$acct/<ACCOUNT>}"
    [[ "$got" == "$expect" ]] && pass "$expect  $action  $shown" || fail "$action  $shown: got $got, expected $expect"
done <<< "$matrix"

unset acct
echo
if (( failed )); then echo "RESULT: FAIL"; exit 1; fi
echo "RESULT: PASS (simulation only; the real proof is the L3 apply and destroy)"
