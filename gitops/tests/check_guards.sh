#!/usr/bin/env bash
# Guard tests for gitops/check.sh (DRF-51): each case copies gitops/ to a temp
# directory, breaks exactly one rule, and expects check.sh to FAIL with that
# rule's label. A rule that can never fail would otherwise look like a PASS.
# Usage: bash gitops/tests/check_guards.sh   (needs python with PyYAML)
set -euo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
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

# case NAME EXPECTED_FAIL_TEXT FILE PYTHON
case_() {
    local name="$1" want="$2" file="$3" code="$4" out
    n=$((n + 1))
    rm -rf "$tmp/g" && cp -r "$src" "$tmp/g"
    if [[ "$file" == +* ]]; then
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
REQ=requests/tenant-a-docs-qa.yaml

case_ "request outside the tenants" "has no tenant role" "$REQ" 'docs[0]["metadata"]["namespace"] = "zdr-requests"'
case_ "request in zdr-platform" "has no tenant role" "$REQ" 'docs[0]["metadata"]["namespace"] = "zdr-platform"'
case_ "name with --" "breaks the sandbox name contract" "$REQ" 'docs[0]["metadata"]["name"] = "docs--qa"'
case_ "name of 33 characters" "breaks the sandbox name contract" "$REQ" 'docs[0]["metadata"]["name"] = "a" * 33'
case_ "negative bootstrapAttempt" "not a non-negative integer" "$REQ" 'docs[0]["spec"]["bootstrapAttempt"] = -1'
case_ "string bootstrapAttempt" "not a non-negative integer" "$REQ" 'docs[0]["spec"]["bootstrapAttempt"] = "1"'
case_ "extra spec field" "unknown spec fields" "$REQ" 'docs[0]["spec"]["replicas"] = 3'
case_ "duplicate request" "unique" "+requests/dup.yaml" "$(cat "$src/$REQ")"
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
case_ "bad name in a .yml request" "breaks the sandbox name contract" "+requests/bad.yml" "$(sed 's/name: docs-qa/name: docs--qa/' "$src/$REQ")"
case_ "no-tenant request as .json" "has no tenant role" "+requests/bad.json" '{"apiVersion": "kro.run/v1alpha1", "kind": "RAGSandbox", "metadata": {"name": "json-qa", "namespace": "zdr-requests"}, "spec": {"bootstrapAttempt": 0}}'
case_ "ConfigMap in requests" "requests/ holds only RAGSandbox" "+requests/extra.yaml" 'apiVersion: v1
kind: ConfigMap
metadata: {name: extra, namespace: tenant-a}
data: {a: b}'
case_ "platform-config in Git" "no platform-config ConfigMap" "+platform/tenants/platform-config.yaml" 'apiVersion: v1
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

echo
if (( failed )); then echo "RESULT: FAIL"; exit 1; fi
echo "RESULT: PASS ($n guard cases, each made check.sh fail on its rule)"
