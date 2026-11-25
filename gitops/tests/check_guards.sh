#!/usr/bin/env bash
# Guard tests for gitops/check.sh (DRF-51; P6 rules 19-23, DRF-76): each case copies gitops/ to a temp
# directory, breaks exactly one rule, and expects check.sh to FAIL with that
# rule's label. A rule that can never fail would otherwise look like a PASS.
# Usage: bash gitops/tests/check_guards.sh   (needs python with PyYAML)
set -euo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export TF_VARIABLES="$src/../infra/terraform/variables.tf"
failed=0
n=0

# mutate FILE PYTHON: run PYTHON with `docs` = the documents of FILE (a list),
# then write them back. Comments are lost; only the copy is changed.
mutate() {
    python -I - "$1" "$2" <<'EOF'
import sys, yaml
path, code = sys.argv[1], sys.argv[2]
docs = [d for d in yaml.safe_load_all(open(path)) if d]
def node(i):  # RGD node by id
    return next(r for r in docs[0]["spec"]["resources"] if r["id"] == i)
exec(code)
yaml.safe_dump_all(docs, open(path, "w"), sort_keys=False)
EOF
}

# The request cases mutate a fixture, not a live request: a PR that deletes the
# live requests (sandbox recreate, window P5-L3-20261125-01 F3) must not break
# these tests. The fixture is placed in the copy under the live file's name.
FIX="$src/tests/fixtures/request-tenant-a.yaml"
REQ=requests/tenant-a-docs-qa.yaml
# P6 (DRF-76): one enabled BatchTrainingJob from a fixture, the same way.
BFIX="$src/tests/fixtures/batch-request-tenant-a.yaml"
BREQ=requests/tenant-a-batch.yaml
fresh() {
    rm -rf "$tmp/g" && cp -r "$src" "$tmp/g"
    cp "$FIX" "$tmp/g/$REQ"
    cp "$BFIX" "$tmp/g/$BREQ"
}

# case NAME EXPECTED_FAIL_TEXT FILE PYTHON
case_() {
    local name="$1" want="$2" file="$3" code="$4" out
    n=$((n + 1))
    fresh
    if [[ "$file" == +* ]]; then
        mkdir -p "$(dirname "$tmp/g/${file#+}")"
        printf '%s\n' "$code" > "$tmp/g/${file#+}"   # new file
    else
        mutate "$tmp/g/$file" "$code"
    fi
    if out="$(bash "$tmp/g/check.sh" 2>&1)"; then
        echo "FAIL  $name: check.sh passed"; failed=1
    elif grep -q "^FAIL  .*$want" <<< "$out"; then
        echo "PASS  $name"
    else
        echo "FAIL  $name: no FAIL line with '$want'"; grep '^FAIL' <<< "$out" | sed 's/^/        /'; failed=1
    fi
}

RGD=platform/rgd/rag-sandbox.yaml

# The unchanged copy with the fixture must pass, or a case could fail for a
# reason other than the rule it breaks.
fresh
if ! out="$(bash "$tmp/g/check.sh" 2>&1)"; then
    echo "FAIL  baseline: check.sh fails on the unchanged copy with the fixture"; grep '^FAIL' <<< "$out" | sed 's/^/        /'
    echo; echo "RESULT: FAIL"; exit 1
fi
echo "PASS  baseline: unchanged copy with the fixture passes check.sh"

case_ "request outside the tenants" "has no tenant role" "$REQ" 'docs[0]["metadata"]["namespace"] = "zdr-requests"'
case_ "request in zdr-platform" "has no tenant role" "$REQ" 'docs[0]["metadata"]["namespace"] = "zdr-platform"'
case_ "name with --" "breaks the sandbox name contract" "$REQ" 'docs[0]["metadata"]["name"] = "docs--qa"'
case_ "name of 33 characters" "breaks the sandbox name contract" "$REQ" 'docs[0]["metadata"]["name"] = "a" * 33'
case_ "negative bootstrapAttempt" "not a non-negative integer" "$REQ" 'docs[0]["spec"]["bootstrapAttempt"] = -1'
case_ "string bootstrapAttempt" "not a non-negative integer" "$REQ" 'docs[0]["spec"]["bootstrapAttempt"] = "1"'
case_ "extra spec field" "unknown spec fields" "$REQ" 'docs[0]["spec"]["replicas"] = 3'
case_ "duplicate request" "unique" "+requests/dup.yaml" "$(cat "$FIX")"
case_ "negative turned valid" "NOTHING WRONG" requests/disabled/rag-sandbox-no-tenant-role.yaml 'docs[0]["metadata"]["namespace"] = "tenant-b"; docs[0]["metadata"]["name"] = "other"'
case_ "password in a request" "no secret value" "$REQ" 'docs[0]["spec"]["password"] = "x"'
case_ "password env in the RGD" "no secret value" "$RGD" 'node("app")["template"]["spec"]["template"]["spec"]["containers"][0]["env"].append({"name": "PGPASSWORD", "value": "x"})'
case_ "bootstrap Job in the tenant namespace" "only in zdr-platform" "$RGD" 'node("bootstrap")["template"]["metadata"]["namespace"] = "${schema.metadata.namespace}"'
case_ "platform SA used by the app" "only in zdr-platform" "$RGD" 'node("app")["template"]["spec"]["template"]["spec"]["serviceAccountName"] = "rag-bootstrap"'
case_ "platform SA in a tenant" "only in zdr-platform" platform/tenants/serviceaccounts.yaml 'docs[1]["metadata"]["namespace"] = "tenant-a"'
case_ "tenant namespace not restricted" "only in zdr-platform" platform/tenants/namespaces.yaml 'docs[1]["metadata"]["labels"]["pod-security.kubernetes.io/enforce"] = "baseline"'
case_ "ttlSecondsAfterFinished" "no ttlSecondsAfterFinished" "$RGD" 'node("bootstrap")["template"]["spec"]["ttlSecondsAfterFinished"] = 60'
case_ "no backoffLimit" "no ttlSecondsAfterFinished" "$RGD" 'del node("bootstrap")["template"]["spec"]["backoffLimit"]'
case_ "Job name without attempt" "Job name ends in bootstrapAttempt" "$RGD" 'node("bootstrap")["template"]["metadata"]["name"] = "${schema.metadata.name}-boot"'
case_ "no readyWhen on the Job" "readyWhen on Job Complete" "$RGD" 'del node("bootstrap")["readyWhen"]'
case_ "Pod template without labels" "instance labels" "$RGD" 'del node("bootstrap")["template"]["spec"]["template"]["metadata"]'
case_ "readiness timeout 5 s" "timeoutSeconds >= 8" "$RGD" 'node("app")["template"]["spec"]["template"]["spec"]["containers"][0]["readinessProbe"]["timeoutSeconds"] = 5'
case_ "bucket before bootstrap" "wait for the bootstrap Job" "$RGD" 'del node("bucket")["template"]["metadata"]["labels"]'
case_ "bucket without forceDestroy" "forceDestroy" "$RGD" 'del node("bucket")["template"]["spec"]["forProvider"]["forceDestroy"]'
case_ "attempt without minimum" "minimum 0" "$RGD" 'docs[0]["spec"]["schema"]["spec"]["bootstrapAttempt"] = "integer | default=0"'
case_ "status without bootstrapState" "status has" "$RGD" 'del docs[0]["spec"]["schema"]["status"]["bootstrapState"]'
case_ "image by tag" "not pinned by digest" "$RGD" 'node("app")["template"]["spec"]["template"]["spec"]["containers"][0]["image"] = "ghcr.io/eurusdevsec/zero-d-rift/rag-sandbox:main"'
case_ "kro may read Secrets" "no wildcard, no secrets/pods" platform/kro-rbac/clusterrole-p4.yaml 'docs[0]["rules"].append({"apiGroups": [""], "resources": ["secrets"], "verbs": ["get"]})'
case_ "kro may write ConfigMaps" "configmaps read only" platform/kro-rbac/clusterrole-p4.yaml 'docs[0]["rules"][0]["verbs"].append("patch")'
case_ "extra provider package" "provider packages = allowlist" platform/providers/providers.yaml 'docs.append({"apiVersion": "pkg.crossplane.io/v1", "kind": "Provider", "metadata": {"name": "provider-aws-iam"}, "spec": {"package": "xpkg.crossplane.io/crossplane-contrib/provider-aws-iam@sha256:" + "0" * 64}})'
# Codex C5: Argo also syncs .yml and .json; requests/ must hold only RAGSandbox.
case_ "bad name in a .yml request" "breaks the sandbox name contract" "+requests/bad.yml" "$(sed 's/name: docs-qa/name: docs--qa/' "$FIX")"
case_ "no-tenant request as .json" "has no tenant role" "+requests/bad.json" '{"apiVersion": "kro.run/v1alpha1", "kind": "RAGSandbox", "metadata": {"name": "json-qa", "namespace": "zdr-requests"}, "spec": {"bootstrapAttempt": 0}}'
case_ "ConfigMap in requests" "requests/ holds only RAGSandbox" "+requests/extra.yaml" 'apiVersion: v1
kind: ConfigMap
metadata: {name: extra, namespace: tenant-a}
data: {a: b}'
case_ "platform-config in Git" "no platform-config or batch-config ConfigMap" "+platform/tenants/platform-config.yaml" 'apiVersion: v1
kind: ConfigMap
metadata: {name: platform-config, namespace: zdr-platform}
data: {dbPort: "5432"}'
# Codex re-review 22/11: Argo also renders .jsonnet and expands List items.
case_ "jsonnet in platform" "jsonnet (not checkable)" "+platform/tenants/extra.jsonnet" '{ apiVersion: "v1", kind: "ConfigMap", metadata: { name: "platform-config", namespace: "zdr-platform" } }'
case_ "platform-config inside a List" "no Kubernetes List objects" "+platform/tenants/list.yaml" 'apiVersion: v1
kind: List
items:
- apiVersion: v1
  kind: ConfigMap
  metadata: {name: platform-config, namespace: zdr-platform}
  data: {dbPort: "5432"}'

# P5 (DRF-66): baseline rules 13-16.
NS=platform/tenants/namespaces.yaml
RB=platform/tenants/rbac.yaml
QT=platform/tenants/quota.yaml
PRJ=platform/apps/85-project-requests.yaml
case_ "tenant label still true" "tenant label = name" "$NS" 'docs[1]["metadata"]["labels"]["rag.zero-drift.io/tenant"] = "true"'
case_ "no Pod Security warn" "enforce/audit/warn restricted" "$NS" 'del docs[2]["metadata"]["labels"]["pod-security.kubernetes.io/warn"]'
case_ "tenant may read Secrets" "no secrets, no wildcard" "$RB" 'docs[0]["rules"][0]["resources"].append("secrets")'
case_ "tenant may create" "read verbs" "$RB" 'docs[2]["rules"][1]["verbs"].append("create")'
case_ "wildcard resource" "no wildcard" "$RB" 'docs[0]["rules"][2]["resources"] = ["*"]'
case_ "binding to the other tenant group" "Group zdr:tenant-a:developers" "$RB" 'docs[1]["subjects"][0]["name"] = "zdr:tenant-b:developers"'
case_ "ClusterRoleBinding for a tenant" "no ClusterRoleBinding for a tenant group" "+platform/tenants/crb.yaml" 'apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: {name: tenant-a-view}
subjects: [{kind: Group, apiGroup: rbac.authorization.k8s.io, name: "zdr:tenant-a:developers"}]
roleRef: {kind: ClusterRole, apiGroup: rbac.authorization.k8s.io, name: view}'
case_ "tenant Role from another path" "tenant RBAC only in platform/tenants/" "+platform/kro-rbac/extra-role.yaml" 'apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: {name: extra, namespace: tenant-a}
rules: [{apiGroups: [""], resources: [pods], verbs: [get]}]'
case_ "default SA mounts a token" "default ServiceAccount mounts no API token" platform/tenants/serviceaccounts.yaml 'docs[2]["automountServiceAccountToken"] = True'
case_ "GPU quota above 0" "GPU 0" "$QT" 'docs[0]["spec"]["hard"]["requests.nvidia.com/gpu"] = "1"'
case_ "NodePort allowed" "no LoadBalancer or NodePort" "$QT" 'del docs[2]["spec"]["hard"]["services.nodeports"]'
case_ "LimitRange without max" "default and max memory limit" "$QT" 'del docs[1]["spec"]["limits"][0]["max"]'
case_ "project allows Namespace" "nothing cluster-scoped" "$PRJ" 'docs[0]["spec"]["clusterResourceWhitelist"] = [{"group": "", "kind": "Namespace"}]'
case_ "project allows ConfigMap" "only RAGSandbox" "$PRJ" 'docs[0]["spec"]["namespaceResourceWhitelist"].append({"group": "", "kind": "ConfigMap"})'
case_ "project allows zdr-platform" "tenant-a/b" "$PRJ" 'docs[0]["spec"]["destinations"].append({"server": "https://kubernetes.default.svc", "namespace": "zdr-platform"})'
case_ "requests app back on default" "project zdr-requests, tenant destination" platform/apps/90-requests.yaml 'docs[0]["spec"]["project"] = "default"'
case_ "requests app creates namespaces" "no CreateNamespace" platform/apps/90-requests.yaml 'docs[0]["spec"]["syncPolicy"]["syncOptions"].append("CreateNamespace=true")'

# P5 (DRF-67): Kyverno rule 17 and chart pins.
KY=platform/apps/45-kyverno.yaml
KV='docs[0]["spec"]["source"]["helm"]["valuesObject"]'
case_ "Kyverno image by tag" "zdr-kyverno: chart image pinned by digest" "$KY" "$KV"'["backgroundController"]["image"]["tag"] = "v1.20.0"'
case_ "Kyverno cleanup controller on" "cleanup off" "$KY" "$KV"'["cleanupController"]["enabled"] = True'
case_ "Kyverno webhooks see all namespaces" "webhooks only in tenant namespaces" "$KY" "del $KV"'["config"]'
case_ "policy fails open" "failurePolicy Fail" platform/policies/zdr-image-digest.yaml 'docs[0]["spec"]["failurePolicy"] = "Ignore"'
case_ "policy matches every namespace" "tenant namespaces only" platform/policies/zdr-tenant-label.yaml 'del docs[0]["spec"]["matchConstraints"]["namespaceSelector"]'
case_ "policy only warns" "Audit/Deny" platform/policies/zdr-require-resources.yaml 'docs[0]["spec"]["validationActions"] = ["Warn"]'
case_ "fourth policy" "exactly the three D6 policies" "+platform/policies/extra.yaml" 'apiVersion: policies.kyverno.io/v1
kind: ValidatingPolicy
metadata: {name: zdr-extra}
spec: {validations: [{expression: "true"}]}'
case_ "PolicyException" "no PolicyException" "+platform/policies/exc.yaml" 'apiVersion: policies.kyverno.io/v1
kind: PolicyException
metadata: {name: skip, namespace: tenant-a}
spec: {policyRefs: [{name: zdr-image-digest, kind: ValidatingPolicy}]}'

# P5 (DRF-68): NetworkPolicy rule 18. Documents per tenant: 0 default-deny,
# 1 dns, 2 db, 3 https-outside-vpc, 4 app-same-tenant (tenant-b from 5).
NP=platform/tenants/networkpolicy.yaml
case_ "no default-deny in tenant-b" "tenant-b: one default-deny" "$NP" 'del docs[5]'
case_ "default-deny with an allow rule" "tenant-a: one default-deny" "$NP" 'docs[0]["spec"]["egress"] = [{}]'
case_ "ingress from another namespace" "ingress only from Pods of the same namespace" "$NP" 'docs[4]["spec"]["ingress"][0]["from"].append({"namespaceSelector": {}})'
case_ "443 rule without ports" "0.0.0.0/0 on all ports" "$NP" 'del docs[3]["spec"]["egress"][0]["ports"]'
case_ "443 rule reaches metadata" "into the VPC/metadata" "$NP" 'docs[8]["spec"]["egress"][0]["to"][0]["ipBlock"]["except"] = ["10.0.0.0/16"]'
# Codex review of P5 code (340558c): four mutations that used to pass.
case_ "unrestricted egress rule" "every egress rule names peers and ports" "$NP" 'docs[1]["spec"]["egress"].append({})'
case_ "egress to every namespace" "every egress rule names peers and ports" "$NP" 'docs[4]["spec"]["egress"][0]["to"].append({"namespaceSelector": {}})'
case_ "DB subnet off the VPC" "match Terraform vpc_cidr" "$NP" 'docs[2]["spec"]["egress"][0]["to"][0]["ipBlock"]["cidr"] = "10.1.10.0/24"'
case_ "HTTPS rule with an empty port" "tenant-a: egress is exactly" "$NP" 'docs[3]["spec"]["egress"][0]["ports"] = [{}]'
case_ "tenant-b loses DB egress" "tenant-b: egress is exactly" "$NP" 'del docs[7]'
case_ "app egress to the other tenant" "tenant-a: egress is exactly" "$NP" 'docs[4]["spec"]["egress"][0]["to"] = [{"podSelector": {"matchLabels": {"rag.zero-drift.io/tenant": "tenant-b"}}}]'
case_ "tenant-b DB policy selects no Pod" "tenant-b: egress is exactly" "$NP" 'docs[7]["spec"]["podSelector"] = {"matchLabels": {"rag.zero-drift.io/tenant": "nobody"}}'
case_ "HTTPS port as a string" "tenant-a: egress is exactly" "$NP" 'docs[3]["spec"]["egress"][0]["ports"][0]["port"] = "443"'
case_ "extra egress policy without policyTypes" "tenant-a: egress is exactly" "$NP" 'import copy; x = copy.deepcopy(docs[3]); x["metadata"]["name"] = "extra"; del x["spec"]["policyTypes"]; x["spec"]["egress"][0]["ports"] = [{"protocol": "TCP", "port": 22}]; docs.append(x)'
case_ "tenant label on zdr-platform" "tenant label only on tenant namespaces" platform/tenants/namespaces.yaml 'next(d for d in docs if d["metadata"]["name"] == "zdr-platform")["metadata"].setdefault("labels", {})["rag.zero-drift.io/tenant"] = "zdr-platform"'
case_ "tenant group bound in zdr-platform" "bound only in its own namespace" platform/tenants/rbac.yaml 'docs.append({"apiVersion": "rbac.authorization.k8s.io/v1", "kind": "RoleBinding", "metadata": {"name": "x", "namespace": "zdr-platform"}, "roleRef": {"apiGroup": "rbac.authorization.k8s.io", "kind": "ClusterRole", "name": "view"}, "subjects": [{"kind": "Group", "apiGroup": "rbac.authorization.k8s.io", "name": "zdr:tenant-a:developers"}]})'
case_ "Kyverno digest in an unused key" "pinned by digest at the chart's keys" "$KY" 'v = '"$KV"'; b = v["backgroundController"]; b["unused"] = {"image": b.pop("image")}'

# P6 (DRF-76): rules 19-23 and the P6 additions to rules 2, 5, 10, 15.
BRGD=platform/rgd/batch-training-job.yaml
SJ='node("scaledJob")["template"]["spec"]'
TP='node("scaledJob")["template"]["spec"]["jobTargetRef"]["template"]["spec"]'
NPF=platform/batch/nodepools.yaml
NCF=platform/batch/ec2nodeclass.yaml
KA=platform/apps/55-karpenter.yaml
case_ "second enabled batch request" "at most one enabled BatchTrainingJob" "+requests/tenant-b-batch.yaml" "$(sed 's/tenant-a/tenant-b/' "$BFIX")"
case_ "batch request in a subfolder" "only in requests/ or requests/disabled/" "+requests/tenant-a/smoke.yaml" "$(sed 's/smoke-1/smoke-2/' "$BFIX")"
case_ "batch request in zdr-platform" "has no batch role" "$BREQ" 'docs[0]["metadata"]["namespace"] = "zdr-platform"'
case_ "batch request name with --" "breaks the request name contract" "$BREQ" 'docs[0]["metadata"]["name"] = "smoke--1"'
case_ "steps 0" "not an integer 1..1000" "$BREQ" 'docs[0]["spec"]["steps"] = 0'
case_ "steps 1001" "not an integer 1..1000" "$BREQ" 'docs[0]["spec"]["steps"] = 1001'
case_ "runAttempt 0" "not an integer 1..9999" "$BREQ" 'docs[0]["spec"]["runAttempt"] = 0'
case_ "runAttempt as a string" "not an integer 1..9999" "$BREQ" 'docs[0]["spec"]["runAttempt"] = "2"'
case_ "unknown failProfile" "not normal or fail-always" "$BREQ" 'docs[0]["spec"]["failProfile"] = "crash"'
case_ "extra batch spec field" "unknown spec fields" "$BREQ" 'docs[0]["spec"]["instanceType"] = "p5.48xlarge"'
case_ "two training Jobs at once" "max 1 Job" "$BRGD" "$SJ"'["maxReplicaCount"] = 2'
case_ "in-flight messages ignored" "scaleOnInFlight" "$BRGD" "$SJ"'["triggers"][0]["metadata"]["scaleOnInFlight"] = "false"'
case_ "lab endpoint in the RGD" "scaleOnInFlight" "$BRGD" "$SJ"'["triggers"][0]["metadata"]["awsEndpoint"] = "http://elasticmq.zdr-lab:9324"'
case_ "per-request trigger auth" "via zdr-sqs" "$BRGD" "$SJ"'["triggers"][0]["authenticationRef"] = {"name": "my-keys"}'
case_ "KEDA Jobs join kro's applyset" "do not inherit kro's applyset" "$BRGD" 'node("scaledJob")["template"]["metadata"]["annotations"]["scaledjob.keda.sh/job-excluded-labels"] = "kro.run/owned"'
case_ "Job retries itself" "backoffLimit 0" "$BRGD" "$SJ"'["jobTargetRef"]["backoffLimit"] = 3'
case_ "training Pod off the batch pool" "batch pool only" "$BRGD" "del $TP"'["tolerations"]'
case_ "training Pod with an API token" "without API token" "$BRGD" "$TP"'["automountServiceAccountToken"] = True'
case_ "training Pod bigger than D9" "D9 size" "$BRGD" "$TP"'["containers"][0]["resources"]["requests"]["cpu"] = "1"'
case_ "writable root filesystem" "read-only" "$BRGD" "$TP"'["containers"][0]["securityContext"]["readOnlyRootFilesystem"] = False'
case_ "heartbeat not under visibility" "heartbeat 40 s" "$BRGD" 'next(e for e in '"$TP"'["containers"][0]["env"] if e["name"] == "HEARTBEAT_SECONDS")["value"] = "150"'
case_ "static key in the RGD" "no lab endpoint or static key" "$BRGD" "$TP"'["containers"][0]["env"].append({"name": "AWS_ACCESS_KEY_ID", "valueFrom": {"secretKeyRef": {"name": "k", "key": "id"}}})'
case_ "submit Job in the tenant" "Jobs only in zdr-platform" "$BRGD" 'node("submit")["template"]["metadata"]["namespace"] = "${schema.metadata.namespace}"'
case_ "submit before the ScaledJob" "created after the ScaledJob" "$BRGD" 'del node("submit")["template"]["metadata"]["labels"]["batch.zero-drift.io/scaledjob"]'
case_ "batch-config in Git" "no platform-config or batch-config" "+platform/tenants/batch-config.yaml" 'apiVersion: v1
kind: ConfigMap
metadata: {name: batch-config, namespace: zdr-platform}
data: {region: us-east-1}'
case_ "queue URL in Git" "queue URL or ARN" "+platform/batch/q.yaml" 'apiVersion: v1
kind: ConfigMap
metadata: {name: q, namespace: karpenter}
data: {url: "https://sqs.us-east-1.amazonaws.com/x/zero-drift-batch"}'
case_ "TriggerAuthentication with keys" "KEDA auth" "+platform/batch/ta.yaml" 'apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata: {name: keys, namespace: tenant-a}
spec: {secretTargetRef: [{parameter: awsAccessKeyID, name: k, key: id}]}'
case_ "NodePool without a limit" "limits.cpu 2" "$NPF" 'del docs[0]["spec"]["limits"]'
case_ "NodePool never expires" "expireAfter 2h" "$NPF" 'docs[1]["spec"]["template"]["spec"]["expireAfter"] = "Never"'
case_ "GPU instance type" "only the D1 instance types" "$NPF" 'next(r for r in docs[0]["spec"]["template"]["spec"]["requirements"] if r["key"] == "node.kubernetes.io/instance-type")["values"].append("g4dn.xlarge")'
case_ "Spot pool also On-Demand" "one capacity type" "$NPF" 'next(r for r in docs[0]["spec"]["template"]["spec"]["requirements"] if r["key"] == "karpenter.sh/capacity-type")["values"].append("on-demand")'
case_ "On-Demand preferred" "Spot first" "$NPF" 'docs[0]["spec"]["weight"] = 1'
case_ "batch pool without taint" "batch taint and label" "$NPF" 'del docs[1]["spec"]["template"]["spec"]["taints"]'
case_ "Karpenter manages the profile" "pre-created instance profile" "$NCF" 'd = docs[0]["spec"]; del d["instanceProfile"]; d["role"] = "zero-drift-karpenter-node"'
case_ "AMI alias drifts from system nodes" "= system node release" "$NCF" 'docs[0]["spec"]["amiSelectorTerms"] = [{"alias": "al2023@v20260101"}]'
case_ "IMDS hop limit 2" "IMDSv2 hop 1" "$NCF" 'docs[0]["spec"]["metadataOptions"]["httpPutResponseHopLimit"] = 2'
case_ "unencrypted root volume" "IMDSv2 hop 1, encrypted" "$NCF" 'docs[0]["spec"]["blockDeviceMappings"][0]["ebs"]["encrypted"] = False'
case_ "Karpenter on its own nodes" "chart affinity kept" "$KA" 'docs[0]["spec"]["source"]["helm"]["valuesObject"]["affinity"] = {}'
case_ "two Karpenter replicas" "1 replica" "$KA" 'docs[0]["spec"]["source"]["helm"]["valuesObject"]["replicas"] = 2'
case_ "Karpenter image by tag only" "pinned by digest at the chart's keys" "$KA" 'del docs[0]["spec"]["source"]["helm"]["valuesObject"]["controller"]["image"]["digest"]'
case_ "KEDA webhooks image by tag only" "pinned by digest at the chart's keys" platform/apps/50-keda.yaml 'docs[0]["spec"]["source"]["helm"]["valuesObject"]["image"]["webhooks"]["tag"] = "2.21.1"'
case_ "quota above D9" "quota values are SPEC-P6 D9 exactly" platform/tenants/quota.yaml 'docs[0]["spec"]["hard"]["pods"] = "12"'
case_ "batch-train SA missing in tenant-b" "tenant default and batch-train" platform/tenants/serviceaccounts.yaml 'docs[:] = [d for d in docs if not (d["metadata"]["name"] == "batch-train" and d["metadata"]["namespace"] == "tenant-b")]'

echo
if (( failed )); then echo "RESULT: FAIL"; exit 1; fi
echo "RESULT: PASS ($n guard cases, each made check.sh fail on its rule)"
