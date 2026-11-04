#!/usr/bin/env bash
# L3 smoke test for the P2 bootstrap (SPEC-P2 Task 7, DRF-11 AC-03).
# Read-only on AWS. In Kubernetes it starts two short-lived probe Pods (DNS,
# IMDS) and deletes them; set SKIP_POD_TESTS=1 to skip those.
# Prints booleans and counts only: no account ID, IP, CIDR, endpoint URL or IDs.
# Usage, from infra/terraform inside an approved window, after apply:
#   ./scripts/smoke.sh
set -euo pipefail

: "${AWS_PROFILE:?export AWS_PROFILE first}"
: "${AWS_REGION:?export AWS_REGION first}"
export MSYS_NO_PATHCONV=1
name="${CLUSTER_NAME:-zero-drift}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

failed=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; failed=1; }
check() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (got '$2', want '$3')"; fi; }

# Pins come from the root variables, so the test follows the reviewed code.
pin() { sed -nE "s/^ *\"?$1\"? *= *\"([^\"]+)\".*/\1/p" "$here/variables.tf" | head -1; }
ami_pin="$(sed -nE 's/^ *default *= *"(1[.]35[.][0-9]+-[0-9]{8})".*/\1/p' "$here/variables.tf" | head -1)"

echo "smoke $(date -u +%Y-%m-%dT%H:%M:%SZ) cluster=$name region=$AWS_REGION"

# 1. Control plane: version, support, auth mode, endpoints, logs.
c="$(aws eks describe-cluster --name "$name" --output json)"
j() { jq -r "$1" <<< "$c"; }
check "cluster ACTIVE"                  "$(j .cluster.status)" ACTIVE
check "Kubernetes 1.35"                 "$(j .cluster.version)" 1.35
check "standard support"                "$(j .cluster.upgradePolicy.supportType)" STANDARD
check "authentication mode API"         "$(j .cluster.accessConfig.authenticationMode)" API
check "private endpoint on"             "$(j .cluster.resourcesVpcConfig.endpointPrivateAccess)" true
check "public endpoint on"              "$(j .cluster.resourcesVpcConfig.endpointPublicAccess)" true
check "public CIDRs all /24 or narrower" "$(j '[.cluster.resourcesVpcConfig.publicAccessCidrs[] | (split("/")[1] | tonumber) >= 24] | all')" true
check "control plane logs"              "$(j '[.cluster.logging.clusterLogging[] | select(.enabled) | .types[]] | sort | join(",")')" audit,authenticator

# 2. OIDC: the cluster issuer is registered as an IAM provider (for IRSA in P3).
issuer="$(j '.cluster.identity.oidc.issuer' | sed 's#^https://##')"
oidc="$(aws iam list-open-id-connect-providers --output json | jq --arg i "$issuer" '[.OpenIDConnectProviderList[].Arn | select(endswith("oidc-provider/" + $i))] | length')"
check "OIDC provider registered for the issuer" "$oidc" 1

# 3. Add-ons: ACTIVE and exactly the pinned versions.
for a in vpc-cni kube-proxy coredns; do
    got="$(aws eks describe-addon --cluster-name "$name" --addon-name "$a" --query '[addon.status, addon.addonVersion]' --output text | tr '\t' ' ')"
    check "add-on $a" "$got" "ACTIVE $(pin "$a")"
done

# 4. Node group: AL2023, pinned AMI release, type, On-Demand, size.
ng="$(aws eks list-nodegroups --cluster-name "$name" --query 'nodegroups[0]' --output text)"
n="$(aws eks describe-nodegroup --cluster-name "$name" --nodegroup-name "$ng" --output json)"
check "node group ACTIVE"   "$(jq -r .nodegroup.status <<< "$n")" ACTIVE
check "node group AMI"      "$(jq -r '"\(.nodegroup.amiType) \(.nodegroup.releaseVersion)"' <<< "$n")" "AL2023_x86_64_STANDARD $ami_pin"
check "node group capacity" "$(jq -r '"\(.nodegroup.instanceTypes | join(",")) \(.nodegroup.capacityType) desired=\(.nodegroup.scalingConfig.desiredSize) max=\(.nodegroup.scalingConfig.maxSize)"' <<< "$n")" "m6i.large ON_DEMAND desired=1 max=2"

# 5. Instances: one running node, IMDSv2 only with hop limit 1, public IPv4 present.
i="$(aws ec2 describe-instances --filters "Name=tag:eks:cluster-name,Values=$name" Name=instance-state-name,Values=pending,running --output json | jq '[.Reservations[].Instances[]]')"
check "running node instances" "$(jq length <<< "$i")" 1
check "IMDSv2 required, hop limit 1" "$(jq -r '[.[] | "\(.MetadataOptions.HttpTokens)/\(.MetadataOptions.HttpPutResponseHopLimit)"] | unique | join(",")' <<< "$i")" required/1
check "node has a public IPv4 (public subnet, no NAT)" "$(jq -r '[.[] | has("PublicIpAddress")] | all' <<< "$i")" true

# 6. Security groups in the VPC: no Internet ingress, no SSH.
vpc="$(j .cluster.resourcesVpcConfig.vpcId)"
sg="$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc" --output json)"
check "no ingress from 0.0.0.0/0 or ::/0" "$(jq '[.SecurityGroups[].IpPermissions[] | select(any(.IpRanges[]?; .CidrIp == "0.0.0.0/0") or any(.Ipv6Ranges[]?; .CidrIpv6 == "::/0"))] | length' <<< "$sg")" 0
check "no port 22 ingress" "$(jq '[.SecurityGroups[].IpPermissions[] | select(.FromPort != null and .FromPort <= 22 and .ToPort >= 22)] | length' <<< "$sg")" 0

# 7. S3 gateway endpoint: available, and the public route tables send S3 to it; no NAT route.
ep="$(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$vpc" --output json | jq '.VpcEndpoints')"
check "S3 gateway endpoint available" "$(jq -r '[.[] | "\(.VpcEndpointType) \(.ServiceName) \(.State)"] | join(",")' <<< "$ep")" "Gateway com.amazonaws.$AWS_REGION.s3 available"
epid="$(jq -r '.[0].VpcEndpointId' <<< "$ep")"
rt="$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc" --output json)"
check "route tables with an S3 prefix-list route via the endpoint" "$(jq --arg e "$epid" '[.RouteTables[] | select(any(.Routes[]; .GatewayId == $e and (.DestinationPrefixListId // "" | startswith("pl-"))))] | length' <<< "$rt")" "$(jq '.[0].RouteTableIds | length' <<< "$ep")"
check "no NAT route anywhere" "$(jq '[.RouteTables[].Routes[] | select(.NatGatewayId != null)] | length' <<< "$rt")" 0

# 8. Kubernetes API from this workstation: version, Ready nodes, system Pods.
aws eks update-kubeconfig --name "$name" --region "$AWS_REGION" > /dev/null
check "API server minor" "$(kubectl version -o json | jq -r '.serverVersion.minor' | tr -d '+')" 35
check "Ready nodes" "$(kubectl get nodes -o json | jq '[.items[] | select(any(.status.conditions[]; .type == "Ready" and .status == "True"))] | length')" 1
check "node OS is Amazon Linux 2023" "$(kubectl get nodes -o json | jq -r '[.items[].status.nodeInfo.osImage | startswith("Amazon Linux 2023")] | all')" true
for app in coredns kube-proxy aws-node; do
    sel="k8s-app=$app"
    total="$(kubectl -n kube-system get pods -l "$sel" -o json | jq '.items | length')"
    running="$(kubectl -n kube-system get pods -l "$sel" -o json | jq '[.items[] | select(.status.phase == "Running")] | length')"
    [[ "$total" -ge 1 && "$total" == "$running" ]] && pass "kube-system $app: $running/$total Running" || fail "kube-system $app: $running/$total Running"
done

# 9. Access: the bootstrap role entry exists; report whether the window admin is on.
entries="$(aws eks list-access-entries --cluster-name "$name" --output json | jq '[.accessEntries[] | select(endswith(":role/zero-drift-bootstrap"))] | length')"
check "access entry for the bootstrap role" "$entries" 1
boot_arn="$(aws eks list-access-entries --cluster-name "$name" --output json | jq -r '.accessEntries[] | select(endswith(":role/zero-drift-bootstrap"))')"
admin="$(aws eks list-associated-access-policies --cluster-name "$name" --principal-arn "$boot_arn" --query 'length(associatedAccessPolicies)' --output text)"
echo "INFO  bootstrap admin associations: $admin (1 inside the window, 0 after removal)"
unset boot_arn

# 10-11. Probe Pods: cluster DNS and AWS DNS resolve; IMDSv2 token is unreachable.
if [[ "${SKIP_POD_TESTS:-0}" != 1 ]]; then
    if kubectl run zdr-smoke-dns --image=public.ecr.aws/docker/library/busybox:1.36.1 --restart=Never --rm -i --quiet \
        --pod-running-timeout=3m --command -- sh -c 'nslookup kubernetes.default.svc.cluster.local && nslookup s3.us-east-1.amazonaws.com' > /dev/null 2>&1; then
        pass "Pod DNS: cluster and AWS names resolve"
    else
        fail "Pod DNS (run the kubectl run line by hand to see why)"
    fi
    # PROBE_OK proves the Pod really ran, so an image-pull failure cannot pass
    # as "no token". The token PUT must time out: hop limit 1 drops the reply.
    out="$(kubectl run zdr-smoke-imds --image=public.ecr.aws/docker/library/amazonlinux:2023 --restart=Never --rm -i --quiet \
        --pod-running-timeout=3m --command -- sh -c 'echo PROBE_OK; curl -s -m 3 -X PUT -H "X-aws-ec2-metadata-token-ttl-seconds: 60" http://169.254.169.254/latest/api/token || true' 2>/dev/null || true)"
    rest="$(grep -v '^PROBE_OK$' <<< "$out" | tr -d '[:space:]' || true)"
    if ! grep -q '^PROBE_OK$' <<< "$out"; then fail "IMDS probe Pod did not run"
    elif [[ -z "$rest" ]]; then pass "Pod cannot get an IMDSv2 token (hop limit 1)"
    else fail "Pod got an IMDS token"; fi
    unset out rest
fi

echo
if (( failed )); then echo "RESULT: FAIL"; exit 1; fi
echo "RESULT: PASS (observed runtime; teardown still required)"
