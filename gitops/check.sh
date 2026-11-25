#!/usr/bin/env bash
# Static gate for gitops/ (SPEC-P3 Task 3, DRF-35; SPEC-P4 P4-T3.2 B, DRF-51; SPEC-P5 P5-T2.1 A, DRF-66; P5-T2.2 A, DRF-67; P5-T3, DRF-68; SPEC-P6 P6-T2.2 A, DRF-76). Touches no cluster and no AWS.
# Usage: gitops/check.sh   (from anywhere in the repo)
# Exit 0 only when every check passes. Needs python with PyYAML (YAML parsing only).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here"
# Terraform's vpc_cidr (rule 18 cross-check). The guard tests copy only gitops/,
# so they pass the real file in TF_VARIABLES.
export TF_VARIABLES="${TF_VARIABLES:-$here/../infra/terraform/variables.tf}"

failed=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; failed=1; }

# Every manifest Argo CD can sync, plus the bootstrap app and the disabled request.
# Argo's directory source reads .yaml, .yml and .json, so CI reads the same set (Codex C5).
files="$(find bootstrap platform requests \( -name '*.yaml' -o -name '*.yml' -o -name '*.json' \) | sort)"

# 1a. Argo CD v3.5.7 also renders .jsonnet/.libsonnet in a directory source; CI cannot
#     check rendered output, and P4 uses none, so refuse them (Codex re-review 22/11).
jsonnet="$(find bootstrap platform requests \( -name '*.jsonnet' -o -name '*.libsonnet' \) | sort)"
[[ -z "$jsonnet" ]] && pass "no jsonnet in synced sources" || fail "jsonnet (not checkable): $jsonnet"

# 1. Every file is valid YAML.
bad="$(for f in $files; do python -I -c 'import sys,yaml; list(yaml.safe_load_all(open(sys.argv[1])))' "$f" 2>/dev/null || echo "$f"; done)"
[[ -z "$bad" ]] && pass "YAML parses ($(wc -w <<< "$files") files)" || fail "invalid YAML: $bad"

# 2. No Secret objects and no account ID / ARN with an account / AWS key in gitops/.
secrets="$(grep -l -E '^kind: *Secret *$' $files || true)"
[[ -z "$secrets" ]] && pass "no Secret objects" || fail "Secret in: $secrets"
ids="$(grep -n -E '(^|[^0-9])[0-9]{12}([^0-9]|$)|arn:aws:[a-z0-9-]*:[a-z0-9-]*:[0-9]{12}|(AKIA|ASIA)[A-Z0-9]{16}' $files || true)"
[[ -z "$ids" ]] && pass "no account ID, account ARN or access key" || fail "sensitive: $ids"
# P6 (DRF-76): a queue URL holds the account ID; it lives only in the window-only batch-config.
qurl="$(grep -n -i -E 'https?://(sqs\.[a-z0-9-]+\.amazonaws\.com|([a-z0-9-]+\.)?queue\.amazonaws\.com)|arn:aws:sqs:' $files || true)"
[[ -z "$qurl" ]] && pass "no SQS queue URL or queue ARN" || fail "queue URL or ARN: $qurl"

# 3. Every container image and provider package is pinned by digest; no latest.
latest="$(grep -n -E '(:|")latest("|$| )' $files || true)"
[[ -z "$latest" ]] && pass "no latest tag" || fail "latest: $latest"
unpinned="$(grep -h -E '^\s*-?\s*(image|package):\s*\S' $files | grep -v '@sha256:[0-9a-f]\{64\}' || true)"
[[ -z "$unpinned" ]] && pass "every image/package line pinned by @sha256" || fail "not pinned by digest: $unpinned"

# 4-7 need structure: read every document once.
python -I - $files <<'EOF' || failed=1
import sys, yaml, re, os, ipaddress, json
docs = []
for f in sys.argv[1:]:
    for d in yaml.safe_load_all(open(f)):
        if d:
            docs.append((f, d))
ok = True
def res(good, msg):
    global ok
    print(("PASS  " if good else "FAIL  ") + msg)
    ok = ok and good

# 0. No Kubernetes List: Argo syncs each object in "items", but every rule below
#    reads only the outer kind. P4 uses none, so refuse them (Codex re-review 22/11).
lists = [f"{f}: {d.get('kind')}" for f, d in docs
         if isinstance(d, dict) and (isinstance(d.get("items"), list) or str(d.get("kind", "")).endswith("List"))]
res(not lists, "no Kubernetes List objects" + (f": {lists}" if lists else ""))

# 4. Provider packages: exactly the allowlist (family + S3), by approved digest.
allow = {
    "xpkg.crossplane.io/crossplane-contrib/provider-family-aws@sha256:ea0d1ff932c78d5a6ef34d6ca1c83a5e6a304173b0735a05fee389f82db25f92",
    "xpkg.crossplane.io/crossplane-contrib/provider-aws-s3@sha256:4e6277277e91672d4a8b444f98b22723b4ca984d2e5845042188f429807919bd",
}
pkgs = {d["spec"]["package"] for f, d in docs if d.get("kind") == "Provider"}
res(pkgs == allow, f"provider packages = allowlist (family-aws + aws-s3 v2.8.1): {len(pkgs)} found")

# 5. Argo CD Applications: Git sources on main, Helm charts on exact versions,
#    platform apps never prune, the requests app prunes with allowEmpty, all selfHeal.
apps = [(f, d) for f, d in docs if d.get("kind") == "Application"]
charts = {}
for f, d in apps:
    s = d["spec"]["source"]
    if "chart" in s:
        charts[s["chart"]] = s["targetRevision"]
    else:
        res(s["targetRevision"] == "main", f"{d['metadata']['name']}: Git source on main")
res(charts == {"crossplane": "2.4.3", "kro": "0.9.4", "kyverno": "3.10.0", "keda": "2.21.1", "karpenter": "1.15.3"},
    f"Helm charts pinned exactly: {charts}")
# Chart images: the values must carry a digest (Crossplane: repository@sha256 +
# ignoreTag; kro and Kyverno: tag v...@sha256), otherwise the chart default tag
# is used. Every "image" block in the values counts; Kyverno has eight.
# The digest must sit in the key the chart template reads (Codex PR #71
# review): a digest moved to an unused key would leave the real image on a tag.
def image_blocks(node, path=()):
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "image" and isinstance(v, dict):
                yield path, v
            yield from image_blocks(v, path + (k,))
    elif isinstance(node, list):
        for x in node:
            yield from image_blocks(x, path)
IMAGE_KEYS = {  # chart -> {path of the image block: fields the template reads (dotted = nested)}
    "crossplane": {(): ["repository"]},
    "kro": {(): ["tag"]},
    "kyverno": {p: ["tag"] for p in [("admissionController", "initContainer"), ("admissionController", "container"),
                                     ("backgroundController",), ("reportsController",), ("upgrade", "legacyPolicyCheck"),
                                     ("crds", "migration"), ("webhooksCleanup",), ("test",)]},
    # P6: KEDA builds registry/repository:tag for three images in one block;
    # Karpenter appends @<controller.image.digest> to repository:tag.
    "keda": {(): ["keda.tag", "metricsApiServer.tag", "webhooks.tag"]},
    "karpenter": {("controller",): ["digest"]},
}
def field(block, dotted):
    for k in dotted.split("."):
        block = block.get(k, "") if isinstance(block, dict) else ""
    return str(block)
def pinned(dotted, v):
    if dotted.endswith("digest"):
        return re.fullmatch(r"sha256:[0-9a-f]{64}", v)
    return re.search(r"@sha256:[0-9a-f]{64}$", v)
for f, d in apps:
    s = d["spec"]["source"]
    if "chart" in s:
        blocks = dict(image_blocks(s.get("helm", {}).get("valuesObject", {})))
        want = IMAGE_KEYS.get(s["chart"], {})
        res(want and set(blocks) == set(want)
            and all(pinned(k, field(blocks[p], k)) for p, ks in want.items() for k in ks),
            f"{d['metadata']['name']}: chart image pinned by digest at the chart's keys ({len(blocks)} image blocks)")
for f, d in apps:
    a = d["spec"].get("syncPolicy", {}).get("automated", {})
    name = d["metadata"]["name"]
    if name == "zdr-requests":
        res(a.get("prune") is True and a.get("selfHeal") is True and a.get("allowEmpty") is True,
            "zdr-requests: prune + selfHeal + allowEmpty")
        res(d["spec"]["source"].get("directory", {}).get("recurse") is not True,
            "zdr-requests: does not recurse (requests/disabled is ignored)")
    else:
        res(a.get("prune") is False and a.get("selfHeal") is True, f"{name}: selfHeal, no prune")

# 6. Requests: enabled instances use the IAM prefix; the disabled negative does not.
for f, d in docs:
    if d.get("kind") != "StorageAppSpike":
        continue
    b = d["spec"]["bucketName"]
    if "/disabled/" in f.replace("\\", "/"):
        res(not b.startswith("zero-drift-p3-"), f"negative {d['metadata']['name']}: bucket outside prefix")
    else:
        res(b.startswith("zero-drift-p3-") and re.fullmatch(r"[a-z0-9-]{3,63}", b) is not None,
            f"{d['metadata']['name']}: bucket inside prefix zero-drift-p3-")

# 7. Every RGD gates readiness on its bucket's Ready condition (DRF-39 E4).
#    externalRef nodes have no template.
rgd = {d["metadata"]["name"]: d for f, d in docs if d.get("kind") == "ResourceGraphDefinition"}
for name, g in sorted(rgd.items()):
    for r in g["spec"]["resources"]:
        if r.get("template", {}).get("kind") == "Bucket":
            res(any('c.type == "Ready"' in w for w in r.get("readyWhen", [])),
                f"RGD {name}: bucket node has readyWhen on Ready")

# --- P4 (DRF-51, SPEC-P4 P4-T3.2 B) ---------------------------------------
TENANTS = {"tenant-a", "tenant-b"}
PLATFORM_NS = "zdr-platform"
PLATFORM_SA = {"rag-db-admin", "rag-bootstrap", "batch-submit"}  # batch-submit: P6 (DRF-76)
NAME_RE = re.compile(r"[a-z](?:[a-z0-9-]{0,30}[a-z0-9])?")  # ragsandbox/names.py

def walk(node):
    """Yield (key, value) for every mapping entry, depth first."""
    if isinstance(node, dict):
        for k, v in node.items():
            yield k, v
            yield from walk(v)
    elif isinstance(node, list):
        for v in node:
            yield from walk(v)

def request_problems(d):
    meta, spec = d.get("metadata", {}), d.get("spec") or {}
    out = []
    if meta.get("namespace") not in TENANTS:
        out.append(f"namespace {meta.get('namespace')!r} has no tenant role")
    n = meta.get("name", "")
    if not (NAME_RE.fullmatch(n) and "--" not in n):
        out.append(f"name {n!r} breaks the sandbox name contract")
    extra = sorted(set(spec) - {"bootstrapAttempt"})
    if extra:
        out.append(f"unknown spec fields {extra}")
    a = spec.get("bootstrapAttempt", 0)
    if not (isinstance(a, int) and not isinstance(a, bool) and a >= 0):
        out.append(f"bootstrapAttempt {a!r} is not a non-negative integer")
    return out

# 8. RAGSandbox requests: enabled ones pass every rule and are unique; each
#    disabled negative breaks at least one rule (it must stay a negative).
seen = set()
for f, d in docs:
    if d.get("kind") != "RAGSandbox":
        continue
    m = d["metadata"]
    who = f"request {m.get('namespace')}/{m.get('name')}"
    probs = request_problems(d)
    if "/disabled/" in f.replace("\\", "/"):
        res(len(probs) >= 1, f"negative {who}: rejected ({'; '.join(probs) or 'NOTHING WRONG'})")
    else:
        res(not probs, f"{who}: known tenant, name contract, bootstrapAttempt >= 0"
            + (f" ({'; '.join(probs)})" if probs else ""))
        key = (m.get("namespace"), m.get("name"))
        res(key not in seen, f"{who}: unique")
        seen.add(key)

# 8b. The requests app syncs only RAGSandbox and BatchTrainingJob objects (P6).
#     Anything else there (a ConfigMap, a Job...) would bypass the request
#     rules; platform-config and batch-config are window-only (window.sh) and
#     must not exist in any source.
others = [f"{f}: {d.get('kind')} {d.get('metadata', {}).get('name')}" for f, d in docs
          if f.replace("\\", "/").startswith("requests/") and "/disabled/" not in f.replace("\\", "/")
          and d.get("kind") not in ("RAGSandbox", "BatchTrainingJob")]
res(not others, "requests/ holds only RAGSandbox and BatchTrainingJob objects" + (f": {others}" if others else ""))
pc = [f for f, d in docs if d.get("kind") == "ConfigMap"
      and d.get("metadata", {}).get("name") in ("platform-config", "batch-config")]
res(not pc, "no platform-config or batch-config ConfigMap in Git (window-only)" + (f": {pc}" if pc else ""))

# 9. No secret value anywhere: no password/token-like key, and no env var whose
#    name says password/token/key with a literal value.
SECRET_KEY = re.compile(r"(?i)^(password|passwd|secretstring|token|apikey|accesskey|secretaccesskey|privatekey|connectionstring)$")
SECRET_ENV = re.compile(r"(?i)(PASSWORD|PASSWD|TOKEN|SECRET_ACCESS_KEY|PRIVATE_KEY|DATABASE_URL|_URI$)")
leaks = []
for f, d in docs:
    for k, v in walk(d):
        if isinstance(k, str) and SECRET_KEY.match(k):
            leaks.append(f"{f}: key {k}")
        if k == "env" and isinstance(v, list):
            for e in v:
                if isinstance(e, dict) and SECRET_ENV.search(str(e.get("name", ""))) and "value" in e:
                    leaks.append(f"{f}: env {e['name']}")
res(not leaks, "no secret value (password/token keys or env)" + (f": {leaks}" if leaks else ""))

# 10. Platform identities and Jobs stay in zdr-platform (negative boundary 3):
#     ServiceAccounts rag-db-admin/rag-bootstrap, every Job (manifest or RGD
#     template), every Pod spec using a platform ServiceAccount. Tenant and
#     platform namespaces enforce Pod Security "restricted".
objs = [(f, d) for f, d in docs if d.get("kind") != "ResourceGraphDefinition"] + [
    (f + "#" + r["id"], r["template"]) for f, d in docs if d.get("kind") == "ResourceGraphDefinition"
    for r in d["spec"]["resources"] if "template" in r]
bad = []
for f, o in objs:
    md = o.get("metadata", {})
    ns = md.get("namespace")
    if o.get("kind") == "ServiceAccount" and md.get("name") in PLATFORM_SA and ns != PLATFORM_NS:
        bad.append(f"{f}: ServiceAccount {md['name']} in {ns}")
    if o.get("kind") == "Job" and ns != PLATFORM_NS:
        bad.append(f"{f}: Job in {ns}")
    for k, v in walk(o):
        if k == "serviceAccountName" and v in PLATFORM_SA and ns != PLATFORM_NS:
            bad.append(f"{f}: Pod with {v} in {ns}")
    if o.get("kind") == "Namespace" and md.get("name") in TENANTS | {PLATFORM_NS}:
        if md.get("labels", {}).get("pod-security.kubernetes.io/enforce") != "restricted":
            bad.append(f"{f}: namespace {md['name']} not Pod Security restricted")
res(not bad, "platform ServiceAccounts and Jobs only in zdr-platform; namespaces restricted"
    + (f": {bad}" if bad else ""))
nss = {d["metadata"]["name"] for f, d in docs if d.get("kind") == "Namespace"}
sas = {(d["metadata"].get("namespace"), d["metadata"]["name"]) for f, d in docs if d.get("kind") == "ServiceAccount"}
res(TENANTS | {PLATFORM_NS} <= nss
    and sas == {(PLATFORM_NS, s) for s in PLATFORM_SA} | {(t, n) for t in TENANTS for n in ("default", "batch-train")},
    "Git has tenant-a, tenant-b, zdr-platform, the three platform ServiceAccounts, tenant default and batch-train")

# 11. RAGSandbox RGD contract (part A): graph, readiness, retry, status.
g = rgd.get("rag-sandbox")
res(g is not None, "RGD rag-sandbox exists")
if g is not None:
    nodes = {r["id"]: r for r in g["spec"]["resources"]}
    res(set(nodes) == {"platformConfig", "bootstrap", "bucket", "serviceAccount", "app", "service"},
        f"rag-sandbox: nodes {sorted(nodes)}")
    pc = nodes.get("platformConfig", {}).get("externalRef", {})
    res(pc.get("kind") == "ConfigMap" and pc.get("metadata", {}).get("namespace") == PLATFORM_NS,
        "rag-sandbox: platformConfig is an externalRef to a ConfigMap in zdr-platform")
    sch = g["spec"]["schema"]
    att = str(sch.get("spec", {}).get("bootstrapAttempt", ""))
    res(set(sch.get("spec", {})) == {"bootstrapAttempt"} and att.startswith("integer")
        and "default=0" in att and "minimum=0" in att,
        "rag-sandbox: spec is only bootstrapAttempt (integer, default 0, minimum 0)")
    need = {"endpoint", "schema", "secretName", "bucket", "bootstrapJob", "bootstrapState", "availableReplicas"}
    res(need <= set(sch.get("status", {})), f"rag-sandbox: status has {sorted(need)}")
    job = nodes.get("bootstrap", {}).get("template", {})
    js = job.get("spec", {})
    res(job.get("kind") == "Job"
        and job.get("metadata", {}).get("name", "").rstrip("}").rstrip(")").endswith("string(schema.spec.bootstrapAttempt")
        and isinstance(js.get("backoffLimit"), int) and isinstance(js.get("activeDeadlineSeconds"), int)
        and "ttlSecondsAfterFinished" not in js,
        "rag-sandbox: Job name ends in bootstrapAttempt; backoffLimit, activeDeadlineSeconds set; no ttlSecondsAfterFinished")
    res({"rag.zero-drift.io/tenant", "rag.zero-drift.io/sandbox"}
        <= set(js.get("template", {}).get("metadata", {}).get("labels", {})),
        "rag-sandbox: Job Pod template carries the instance labels (orphaned Pods, spike 14/11)")
    res(any('c.type == "Complete"' in w for w in nodes.get("bootstrap", {}).get("readyWhen", [])),
        "rag-sandbox: readyWhen on Job Complete")
    app = nodes.get("app", {})
    probes = [c.get("readinessProbe", {}) for c in
              app.get("template", {}).get("spec", {}).get("template", {}).get("spec", {}).get("containers", [])]
    res(len(probes) == 1 and probes[0].get("httpGet", {}).get("path") == "/readyz"
        and probes[0].get("timeoutSeconds", 0) >= 8 and any("availableReplicas" in w for w in app.get("readyWhen", [])),
        "rag-sandbox: app readiness /readyz, timeoutSeconds >= 8, readyWhen available")
    ungated = [i for i in ("bucket", "serviceAccount", "service")
               if "bootstrap." not in yaml.safe_dump(nodes.get(i, {}).get("template", {}))]
    res(not ungated, "rag-sandbox: bucket and tenant objects wait for the bootstrap Job"
        + (f" (not: {ungated})" if ungated else ""))
    b = nodes.get("bucket", {}).get("template", {})
    res(b.get("metadata", {}).get("name", "").startswith('${"zero-drift-rag-" + schema.metadata.namespace')
        and b.get("spec", {}).get("forProvider", {}).get("forceDestroy") is True,
        "rag-sandbox: bucket zero-drift-rag-<tenant>-<name> with forceDestroy (D7)")

# 12. kro aggregated rights: no wildcard, no Secrets, no Pods, ConfigMaps read only.
for f, d in docs:
    if d.get("kind") != "ClusterRole" or \
            d.get("metadata", {}).get("labels", {}).get("rbac.kro.run/aggregate-to-controller") != "true":
        continue
    wide = [r for r in d.get("rules", [])
            if "*" in r.get("verbs", []) + r.get("resources", []) + r.get("apiGroups", [])
            or {"secrets", "pods"} & set(r.get("resources", []))
            or ("configmaps" in r.get("resources", []) and set(r.get("verbs", [])) - {"get", "list", "watch"})]
    res(not wide, f"{d['metadata']['name']}: no wildcard, no secrets/pods, configmaps read only")

# --- P5 (DRF-66, SPEC-P5 P5-T2.1 A) ----------------------------------------
def objs_of(kind, ns=None):
    return [(f, d) for f, d in docs if d.get("kind") == kind
            and (ns is None or d.get("metadata", {}).get("namespace") == ns)]

# 13. Tenant namespaces: the tenant label carries the tenant name, and Pod
#     Security enforces, audits and warns at "restricted", pinned to v1.35.
PSS = {f"pod-security.kubernetes.io/{m}": "restricted" for m in ("enforce", "audit", "warn")}
PSS |= {f"pod-security.kubernetes.io/{m}-version": "v1.35" for m in ("enforce", "audit", "warn")}
for t in sorted(TENANTS):
    lab = next((d["metadata"].get("labels", {}) for f, d in objs_of("Namespace") if d["metadata"]["name"] == t), {})
    res(lab.get("rag.zero-drift.io/tenant") == t and all(lab.get(k) == v for k, v in PSS.items()),
        f"namespace {t}: tenant label = name; Pod Security enforce/audit/warn restricted v1.35")

others = [d["metadata"]["name"] for f, d in objs_of("Namespace")
          if d["metadata"]["name"] not in TENANTS and "rag.zero-drift.io/tenant" in d["metadata"].get("labels", {})]
res(not others, "tenant label only on tenant namespaces (Kyverno and NetworkPolicy select it)"
    + (f": {others}" if others else ""))

# 14. Tenant RBAC (D1): in each tenant namespace one Role tenant-viewer, read
#     verbs only, no Secrets, no wildcard, bound only to zdr:<tenant>:developers;
#     no ClusterRoleBinding names a tenant group, and no RBAC object of a tenant
#     lives outside platform/tenants/.
READ = {"get", "list", "watch"}
for t in sorted(TENANTS):
    roles = [d for f, d in objs_of("Role", t)]
    rules = [r for d in roles for r in d.get("rules", [])]
    wide = [r for r in rules if "*" in r.get("verbs", []) + r.get("resources", []) + r.get("apiGroups", [])
            or set(r.get("verbs", [])) - READ or "secrets" in r.get("resources", [])]
    res([d["metadata"]["name"] for d in roles] == ["tenant-viewer"] and rules and not wide,
        f"{t}: only Role tenant-viewer, read verbs, no secrets, no wildcard")
    binds = [d for f, d in objs_of("RoleBinding", t)]
    good = [d for d in binds if d.get("roleRef", {}).get("name") == "tenant-viewer"
            and d.get("roleRef", {}).get("kind") == "Role"
            and d.get("subjects") == [{"kind": "Group", "apiGroup": "rbac.authorization.k8s.io",
                                        "name": f"zdr:{t}:developers"}]]
    res(len(binds) == 1 and len(good) == 1, f"{t}: one RoleBinding, Group zdr:{t}:developers -> tenant-viewer")
crb = [f"{f}: {d['metadata']['name']}" for f, d in objs_of("ClusterRoleBinding")
       if any(str(s.get("name", "")).startswith("zdr:") for s in d.get("subjects", []) or [])]
res(not crb, "no ClusterRoleBinding for a tenant group" + (f": {crb}" if crb else ""))
foreign = [f"{d['metadata'].get('namespace')}/{d['metadata']['name']}" for f, d in objs_of("RoleBinding")
           for s in d.get("subjects", []) or [] if str(s.get("name", "")).startswith("zdr:")
           and s.get("name") != f"zdr:{d['metadata'].get('namespace')}:developers"]
res(not foreign, "a tenant group is bound only in its own namespace" + (f": {foreign}" if foreign else ""))
stray = [f for f, d in docs if d.get("kind") in ("Role", "RoleBinding")
         and d.get("metadata", {}).get("namespace") in TENANTS
         and not f.replace("\\", "/").startswith("platform/tenants/")]
res(not stray, "tenant RBAC only in platform/tenants/" + (f": {stray}" if stray else ""))

# 15. Default ServiceAccount (D2), quota and LimitRange (D3) per tenant.
for t in sorted(TENANTS):
    sa = [d for f, d in objs_of("ServiceAccount", t) if d["metadata"]["name"] == "default"]
    res(len(sa) == 1 and sa[0].get("automountServiceAccountToken") is False,
        f"{t}: default ServiceAccount mounts no API token")
    q = [d for f, d in objs_of("ResourceQuota", t)]
    hard = q[0].get("spec", {}).get("hard", {}) if len(q) == 1 else {}
    need = {"pods", "requests.cpu", "requests.memory", "limits.memory", "services", "count/jobs.batch"}
    res(need <= set(hard) and str(hard.get("requests.nvidia.com/gpu")) == "0"
        and str(hard.get("services.loadbalancers")) == "0" and str(hard.get("services.nodeports")) == "0",
        f"{t}: one ResourceQuota with pods/cpu/memory/services/jobs, GPU 0, no LoadBalancer or NodePort")
    # P6 (SPEC-P6 D9): raised by exactly one training Pod and its Jobs, no more.
    d9 = {"pods": "10", "requests.cpu": "900m", "requests.memory": "1152Mi", "limits.memory": "2048Mi",
          "count/jobs.batch": "6", "services": "4"}
    res({k: str(hard.get(k)) for k in d9} == d9, f"{t}: quota values are SPEC-P6 D9 exactly")
    lr = [d for f, d in objs_of("LimitRange", t)]
    c = next((l for d in lr for l in d.get("spec", {}).get("limits", []) if l.get("type") == "Container"), {})
    res(len(lr) == 1 and {"cpu", "memory"} <= set(c.get("defaultRequest", {}))
        and "memory" in c.get("default", {}) and "memory" in c.get("max", {}),
        f"{t}: one LimitRange with default requests, default and max memory limit")

# 16. Request path (D4): AppProject zdr-requests allows only this repository,
#     only tenant-a/tenant-b, nothing cluster-scoped, only RAGSandbox; the
#     requests Application uses it, and no other Application does.
REPO = "https://github.com/EurusDevSec/Zero-D-Rift.git"
proj = [d for f, d in objs_of("AppProject") if d["metadata"]["name"] == "zdr-requests"]
ps = proj[0].get("spec", {}) if len(proj) == 1 else {}
dest = sorted((x.get("server"), x.get("namespace")) for x in ps.get("destinations", []))
res(len(proj) == 1 and ps.get("sourceRepos") == [REPO]
    and dest == [("https://kubernetes.default.svc", t) for t in sorted(TENANTS)]
    and ps.get("clusterResourceWhitelist") == []
    and ps.get("namespaceResourceWhitelist") == [{"group": "kro.run", "kind": "RAGSandbox"},
                                                 {"group": "kro.run", "kind": "BatchTrainingJob"}],
    "AppProject zdr-requests: this repo, tenant-a/b, nothing cluster-scoped, only RAGSandbox and BatchTrainingJob")
in_proj = sorted(d["metadata"]["name"] for f, d in apps if d["spec"].get("project") == "zdr-requests")
req = next((d for f, d in apps if d["metadata"]["name"] == "zdr-requests"), {})
res(in_proj == ["zdr-requests"] and req.get("spec", {}).get("destination", {}).get("namespace") in TENANTS
    and "CreateNamespace=true" not in req.get("spec", {}).get("syncPolicy", {}).get("syncOptions", []),
    "zdr-requests app: project zdr-requests, tenant destination, no CreateNamespace")

# 17. Kyverno (D6-D9): exactly the three validate-only policies, each Pods only,
#     only in tenant-labelled namespaces, fail closed, Audit or Deny, autogen off;
#     no legacy kyverno.io policy and no PolicyException; the chart keeps D7's
#     footprint and limits Kyverno's own webhooks to tenant namespaces (D8).
TENANT_SEL = {"matchExpressions": [{"key": "rag.zero-drift.io/tenant", "operator": "Exists"}]}
vps = {d["metadata"]["name"]: d.get("spec", {}) for f, d in objs_of("ValidatingPolicy")}
res(sorted(vps) == ["zdr-image-digest", "zdr-require-resources", "zdr-tenant-label"],
    f"Kyverno: exactly the three D6 policies: {sorted(vps)}")
for n, s in sorted(vps.items()):
    mc = s.get("matchConstraints", {})
    acts = s.get("validationActions", [])
    res(s.get("failurePolicy") == "Fail" and bool(acts) and set(acts) <= {"Audit", "Deny"}
        and mc.get("namespaceSelector") == TENANT_SEL
        and mc.get("resourceRules") == [{"apiGroups": [""], "apiVersions": ["v1"],
                                         "operations": ["CREATE", "UPDATE"], "resources": ["pods"]}]
        and s.get("autogen", {}).get("podControllers", {}).get("controllers") == [],
        f"{n}: Pods in tenant namespaces only, failurePolicy Fail, Audit/Deny, autogen off")
legacy = [f"{f}: {d.get('kind')}" for f, d in docs
          if str(d.get("apiVersion", "")).startswith("kyverno.io/") or d.get("kind") == "PolicyException"]
res(not legacy, "no legacy kyverno.io policy, no PolicyException (D9)" + (f": {legacy}" if legacy else ""))
kv = next((d["spec"]["source"].get("helm", {}).get("valuesObject", {}) for f, d in apps
           if d["spec"]["source"].get("chart") == "kyverno"), {})
res(kv.get("cleanupController", {}).get("enabled") is False
    and all(kv.get(k, {}).get("replicas") == 1 for k in ("admissionController", "backgroundController", "reportsController"))
    and kv.get("config", {}).get("webhooks", {}).get("namespaceSelector") == TENANT_SEL,
    "zdr-kyverno: three controllers x1, cleanup off, webhooks only in tenant namespaces")

# 18. NetworkPolicy (D5): each tenant namespace has a default-deny for ingress
#     and egress; ingress only from Pods of the same namespace; no rule opens
#     0.0.0.0/0 on every port, and a 0.0.0.0/0 block always cuts out the VPC
#     and the link-local range (instance metadata).
for t in sorted(TENANTS):
    nps = [d.get("spec", {}) for f, d in objs_of("NetworkPolicy", t)]
    deny = [s for s in nps if s.get("podSelector") == {} and sorted(s.get("policyTypes", [])) == ["Egress", "Ingress"]
            and not s.get("ingress") and not s.get("egress")]
    res(len(deny) == 1, f"{t}: one default-deny NetworkPolicy for ingress and egress")
    peers_in = [p for s in nps for r in s.get("ingress", []) or [] for p in r.get("from", []) or [{}]]
    res(all(set(p) == {"podSelector"} for p in peers_in),
        f"{t}: ingress only from Pods of the same namespace")
wide = []
for f, d in objs_of("NetworkPolicy"):
    s = d.get("spec", {})
    for r in (s.get("ingress", []) or []) + (s.get("egress", []) or []):
        for p in r.get("from", []) or r.get("to", []) or []:
            b = p.get("ipBlock", {})
            if b.get("cidr") == "0.0.0.0/0" and (not r.get("ports")
                    or not {"10.0.0.0/16", "169.254.0.0/16"} <= set(b.get("except", []))):
                wide.append(f"{d['metadata'].get('namespace')}/{d['metadata']['name']}")
res(not wide, "no NetworkPolicy opens 0.0.0.0/0 on all ports or into the VPC/metadata" + (f": {wide}" if wide else ""))
# Every egress rule names its peers and its ports (an empty rule, a rule without
# "to" or without "ports" allows everything); a namespaceSelector peer is only
# the DNS path to kube-system on port 53.
DNS_NS = {"matchLabels": {"kubernetes.io/metadata.name": "kube-system"}}
loose = []
for f, d in objs_of("NetworkPolicy"):
    for r in d.get("spec", {}).get("egress", []) or []:
        peers, ports = r.get("to") or [], r.get("ports") or []
        if (not peers or not ports or any(p == {} for p in peers)
                or any("namespaceSelector" in p and (p["namespaceSelector"] != DNS_NS
                       or any(str(q.get("port")) != "53" for q in ports)) for p in peers)):
            loose.append(f"{d['metadata'].get('namespace')}/{d['metadata']['name']}")
res(not loose, "every egress rule names peers and ports; other namespaces only for DNS" + (f": {loose}" if loose else ""))
# Each tenant's egress is exactly these four rules, each port with an explicit
# protocol and number (a port entry {} means every port). A rule that goes
# missing (no DB path for one tenant) fails here too, not only a wider one.
# A rule is keyed by the Pods it applies to (the policy podSelector) as well as
# its peers and ports; ports must be an integer with TCP or UDP. A policy whose
# policyTypes leave out Egress has no egress effect, so its rules do not count;
# with policyTypes omitted, Kubernetes adds Egress when the policy has egress rules.
def canon_rule(r, sel):
    ports = r.get("ports") or []
    if any(set(q) != {"protocol", "port"} or type(q["port"]) is not int or q["protocol"] not in ("TCP", "UDP")
           for q in ports):
        return ("bad-port",)
    return (json.dumps(sel, sort_keys=True), json.dumps(sorted(json.dumps(p, sort_keys=True) for p in r.get("to") or [])),
            tuple(sorted((q["protocol"], str(q["port"])) for q in ports)))
def egress_on(spec):
    pt = spec.get("policyTypes")
    return "Egress" in pt if pt else bool(spec.get("egress"))
def want_egress(t, vpc_s, dbs_s):
    sel = {"matchLabels": {"rag.zero-drift.io/tenant": t}}
    return sorted([
        canon_rule({"to": [{"namespaceSelector": DNS_NS, "podSelector": {"matchLabels": {"k8s-app": "kube-dns"}}}],
                    "ports": [{"protocol": "UDP", "port": 53}, {"protocol": "TCP", "port": 53}]}, sel),
        canon_rule({"to": [{"ipBlock": {"cidr": c}} for c in sorted(dbs_s)], "ports": [{"protocol": "TCP", "port": 5432}]}, sel),
        canon_rule({"to": [{"ipBlock": {"cidr": "0.0.0.0/0", "except": [vpc_s, "169.254.0.0/16"]}}],
                    "ports": [{"protocol": "TCP", "port": 443}]}, sel),
        canon_rule({"to": [{"podSelector": {"matchLabels": {"rag.zero-drift.io/tenant": t}}}],
                    "ports": [{"protocol": "TCP", "port": 8080}]}, sel)], key=str)
_tf = open(os.environ["TF_VARIABLES"], encoding="utf-8").read() if os.path.exists(os.environ["TF_VARIABLES"]) else ""
_m = re.search(r'variable "vpc_cidr"[^}]*?default\s*=\s*"([0-9./]+)"', _tf, re.S)
_vpc = ipaddress.ip_network(_m.group(1)) if _m else None
_dbs = [str(n) for n in list(_vpc.subnets(new_prefix=24))[10:12]] if _vpc else []
for t in sorted(TENANTS):
    got = sorted((canon_rule(r, d["spec"].get("podSelector")) for f, d in objs_of("NetworkPolicy", t)
                  if egress_on(d.get("spec", {}))
                  for r in d.get("spec", {}).get("egress", []) or []), key=str)
    res(_vpc is not None and got == want_egress(t, str(_vpc), _dbs),
        f"{t}: egress is exactly DNS 53, DB 5432, HTTPS 443 outside the VPC, app 8080 in-tenant")
# The DB and VPC addresses in the policies follow Terraform's vpc_cidr default
# (locals.tf: cidrsubnet(vpc_cidr, 8, 10 + i)); a VPC override must change both.
tf = open(os.environ["TF_VARIABLES"], encoding="utf-8").read() if os.path.exists(os.environ["TF_VARIABLES"]) else ""
m = re.search(r'variable "vpc_cidr"[^}]*?default\s*=\s*"([0-9./]+)"', tf, re.S)
vpc = ipaddress.ip_network(m.group(1)) if m else None
dbs = {str(n) for n in list(vpc.subnets(new_prefix=24))[10:12]} if vpc else set()
cidrs = {p["ipBlock"]["cidr"] for f, d in objs_of("NetworkPolicy") for r in d.get("spec", {}).get("egress", []) or []
         for p in r.get("to") or [] if "ipBlock" in p and p["ipBlock"]["cidr"] != "0.0.0.0/0"}
vexc = {e for f, d in objs_of("NetworkPolicy") for r in d.get("spec", {}).get("egress", []) or []
        for p in r.get("to") or [] for e in p.get("ipBlock", {}).get("except", []) if e != "169.254.0.0/16"}
res(vpc is not None and cidrs == dbs and vexc == {str(vpc)},
    f"NetworkPolicy DB subnets {sorted(cidrs)} and VPC except {sorted(vexc)} match Terraform vpc_cidr {vpc}")

# --- P6 (DRF-76, SPEC-P6 P6-T2.2 A) ----------------------------------------
# 19. BatchTrainingJob requests: at most one enabled (D5), directly in
#     requests/; otherwise only in requests/disabled/ (zdr-requests does not
#     recurse, so a file in any other subfolder looks enabled but never syncs).
#     Every one, enabled or disabled, follows the request contract, so moving a
#     disabled one up is safe. The worker checks the same limits (runkey.py).
BTJ_FIELDS = {"steps", "runAttempt", "failProfile"}
def int_in(v, lo, hi):
    return isinstance(v, int) and not isinstance(v, bool) and lo <= v <= hi
def batch_problems(d):
    meta, spec = d.get("metadata", {}), d.get("spec") or {}
    out = []
    if meta.get("namespace") not in TENANTS:
        out.append(f"namespace {meta.get('namespace')!r} has no batch role")
    n = meta.get("name", "")
    if not (NAME_RE.fullmatch(n) and "--" not in n):
        out.append(f"name {n!r} breaks the request name contract")
    extra = sorted(set(spec) - BTJ_FIELDS)
    if extra:
        out.append(f"unknown spec fields {extra}")
    if "steps" in spec and not int_in(spec["steps"], 1, 1000):
        out.append(f"steps {spec['steps']!r} is not an integer 1..1000")
    if "runAttempt" in spec and not int_in(spec["runAttempt"], 1, 9999):
        out.append(f"runAttempt {spec['runAttempt']!r} is not an integer 1..9999")
    if spec.get("failProfile", "normal") not in ("normal", "fail-always"):
        out.append(f"failProfile {spec.get('failProfile')!r} is not normal or fail-always")
    return out
enabled, misplaced = [], []
for f, d in docs:
    if d.get("kind") != "BatchTrainingJob":
        continue
    path = f.replace("\\", "/")
    m = d["metadata"]
    who = f"batch request {m.get('namespace')}/{m.get('name')} ({path})"
    probs = batch_problems(d)
    res(not probs, f"{who}: known tenant, name contract, steps/runAttempt/failProfile in range"
        + (f" ({'; '.join(probs)})" if probs else ""))
    if re.fullmatch(r"requests/[^/]+", path):
        enabled.append(who)
    elif not re.fullmatch(r"requests/disabled/[^/]+", path):
        misplaced.append(who)
res(len(enabled) <= 1, f"at most one enabled BatchTrainingJob (D5): {len(enabled)}"
    + (f": {enabled}" if len(enabled) > 1 else ""))
res(not misplaced, "BatchTrainingJob only in requests/ or requests/disabled/" + (f": {misplaced}" if misplaced else ""))

# 20. BatchTrainingJob RGD contract: graph order, gate, ScaledJob (D5, D8),
#     training Pod (identity, placement, D9 size, hardening), submit Job.
g = rgd.get("batch-training-job")
res(g is not None, "RGD batch-training-job exists")
if g is not None:
    nodes = {r["id"]: r for r in g["spec"]["resources"]}
    res(list(nodes) == ["platformConfig", "bucket", "scaledJob", "submit"],
        f"batch-training-job: nodes in order {list(nodes)}")
    pc = nodes.get("platformConfig", {}).get("externalRef", {})
    res(pc.get("kind") == "ConfigMap" and pc.get("metadata") == {"name": "batch-config", "namespace": PLATFORM_NS},
        "batch-training-job: platformConfig is an externalRef to ConfigMap batch-config in zdr-platform")
    sch = g["spec"]["schema"]
    sp = {k: str(v) for k, v in sch.get("spec", {}).items()}
    res(set(sp) == BTJ_FIELDS and "minimum=1" in sp.get("steps", "") and "maximum=1000" in sp.get("steps", "")
        and "minimum=1" in sp.get("runAttempt", "") and "maximum=9999" in sp.get("runAttempt", "")
        and 'enum="normal,fail-always"' in sp.get("failProfile", ""),
        "batch-training-job: spec steps 1..1000, runAttempt 1..9999, failProfile normal|fail-always")
    need = {"queue", "bucket", "runAttempt", "submitJob", "submitState", "outcome"}
    res(need <= set(sch.get("status", {})), f"batch-training-job: status has {sorted(need)}")
    bt = nodes.get("bucket", {}).get("template", {})
    res(bt.get("metadata", {}).get("name", "").startswith('${"zero-drift-batch-" + schema.metadata.namespace')
        and bt.get("spec", {}).get("forProvider", {}).get("forceDestroy") is True,
        "batch-training-job: bucket zero-drift-batch-<tenant>-<name> with forceDestroy")
    sj = nodes.get("scaledJob", {}).get("template", {})
    ss = sj.get("spec", {})
    trig = ss.get("triggers", [])
    t0 = trig[0] if len(trig) == 1 else {}
    md = t0.get("metadata", {})
    res(sj.get("kind") == "ScaledJob" and sj.get("metadata", {}).get("namespace") == "${schema.metadata.namespace}"
        and ss.get("pollingInterval") == 10 and ss.get("maxReplicaCount") == 1 and ss.get("minReplicaCount", 0) == 0
        and ss.get("successfulJobsHistoryLimit") == 1 and ss.get("failedJobsHistoryLimit") == 1
        and t0.get("type") == "aws-sqs-queue" and md.get("queueLength") == "1" and md.get("scaleOnInFlight") == "true"
        and "awsEndpoint" not in md
        and t0.get("authenticationRef") == {"kind": "ClusterTriggerAuthentication", "name": "zdr-sqs"},
        "batch-training-job: ScaledJob in the tenant, one SQS trigger via zdr-sqs, queueLength 1, "
        "scaleOnInFlight, max 1 Job, poll 10 s, history 1/1")
    # Kind lab 25/11: KEDA copies ScaledJob labels onto its Jobs; with kro's
    # applyset label on them, kro pruned every training Job (the graph holds a
    # Job kind too) and KEDA started a new one each poll.
    exl = set(str(sj.get("metadata", {}).get("annotations", {})
                  .get("scaledjob.keda.sh/job-excluded-labels", "")).split(","))
    res({"applyset.kubernetes.io/part-of", "kro.run/owned", "kro.run/node-id", "kro.run/instance-id",
         "kro.run/instance-name", "kro.run/instance-namespace"} <= exl,
        "batch-training-job: KEDA Jobs do not inherit kro's applyset and ownership labels")
    jt = ss.get("jobTargetRef", {})
    ps = jt.get("template", {}).get("spec", {})
    plab = jt.get("template", {}).get("metadata", {}).get("labels", {})
    cs = ps.get("containers", [])
    c0 = cs[0] if len(cs) == 1 else {}
    rs = c0.get("resources", {})
    res(jt.get("backoffLimit") == 0 and jt.get("activeDeadlineSeconds") == 2700
        and ps.get("serviceAccountName") == "batch-train" and ps.get("automountServiceAccountToken") is False
        and ps.get("nodeSelector") == {"zero-drift.io/pool": "batch"}
        and ps.get("tolerations") == [{"key": "zero-drift.io/batch", "operator": "Equal", "value": "true",
                                       "effect": "NoSchedule"}]
        and plab.get("app.kubernetes.io/name") == "batch-train"
        and plab.get("rag.zero-drift.io/tenant") == "${schema.metadata.namespace}"
        and rs.get("requests") == {"cpu": "500m", "memory": "384Mi"} and rs.get("limits") == {"memory": "512Mi"}
        and "initContainers" not in ps,
        "batch-training-job: training Job backoffLimit 0, deadline 2700 s, batch-train SA without API token, "
        "batch pool only, D9 size")
    sec = c0.get("securityContext", {})
    res(ps.get("securityContext", {}).get("runAsNonRoot") is True and sec.get("allowPrivilegeEscalation") is False
        and sec.get("capabilities", {}).get("drop") == ["ALL"] and sec.get("readOnlyRootFilesystem") is True,
        "batch-training-job: training container non-root, read-only, no capabilities")
    env = {e.get("name"): e.get("value") for e in c0.get("env", [])}
    res(env.get("HEARTBEAT_SECONDS") == "40" and env.get("VISIBILITY_TIMEOUT") == "120"
        and not any(str(k).endswith("_ENDPOINT_URL") for k in env) and "AWS_ACCESS_KEY_ID" not in env,
        "batch-training-job: heartbeat 40 s, visibility 120 s (D8); no lab endpoint or static key")
    sb = nodes.get("submit", {})
    st = sb.get("template", {})
    sjs = st.get("spec", {})
    sps = sjs.get("template", {}).get("spec", {})
    res(st.get("kind") == "Job" and st.get("metadata", {}).get("namespace") == PLATFORM_NS
        and st.get("metadata", {}).get("name", "").endswith("string(schema.spec.runAttempt)}")
        and sps.get("serviceAccountName") == "batch-submit" and sps.get("automountServiceAccountToken") is False
        and isinstance(sjs.get("backoffLimit"), int) and isinstance(sjs.get("activeDeadlineSeconds"), int)
        and "ttlSecondsAfterFinished" not in sjs
        and any('c.type == "Complete"' in w for w in sb.get("readyWhen", []))
        and "scaledJob." in yaml.safe_dump(st.get("metadata", {})),
        "batch-training-job: submit Job in zdr-platform named by runAttempt, batch-submit SA, "
        "readyWhen Complete, created after the ScaledJob")

# 21. KEDA reads the queue only through the platform-owned
#     ClusterTriggerAuthentication zdr-sqs with its own IRSA identity; no
#     per-namespace TriggerAuthentication (it could carry keys).
ctas = {d["metadata"]["name"]: d.get("spec", {}) for f, d in objs_of("ClusterTriggerAuthentication")}
tas = [f for f, d in objs_of("TriggerAuthentication")]
res(ctas == {"zdr-sqs": {"podIdentity": {"provider": "aws", "identityOwner": "keda"}}} and not tas,
    "KEDA auth: only ClusterTriggerAuthentication zdr-sqs, the operator's own AWS identity, no keys")

# 22. Karpenter capacity (D1, D6, D7, negative boundaries 1-3): two NodePools,
#     one capacity type each, allowlisted types and zones, one node, expiry,
#     batch taint and label; one EC2NodeClass with the pre-created profile, the
#     system node AMI release, IMDSv2 hop 1, encrypted root, discovery tags.
TYPES = ["c6i.large", "m5.large", "m6i.large"]
pools = {d["metadata"]["name"]: d.get("spec", {}) for f, d in objs_of("NodePool")}
res(sorted(pools) == ["batch-ondemand", "batch-spot"],
    f"Karpenter: exactly NodePools batch-spot and batch-ondemand: {sorted(pools)}")
def pool_req(spec, key):
    return [r for r in spec.get("template", {}).get("spec", {}).get("requirements", []) if r.get("key") == key]
for n, sp in sorted(pools.items()):
    ts = sp.get("template", {}).get("spec", {})
    cap = pool_req(sp, "karpenter.sh/capacity-type")
    it = pool_req(sp, "node.kubernetes.io/instance-type")
    zs = pool_req(sp, "topology.kubernetes.io/zone")
    keys = {str(r.get("key")) for r in ts.get("requirements", [])}
    res(len(cap) == 1 and cap[0].get("operator") == "In"
        and cap[0].get("values") == {"batch-spot": ["spot"], "batch-ondemand": ["on-demand"]}.get(n)
        and len(it) == 1 and it[0].get("operator") == "In" and sorted(it[0].get("values", [])) == TYPES
        and len(zs) == 1 and zs[0].get("operator") == "In" and sorted(zs[0].get("values", [])) == ["us-east-1a", "us-east-1b"]
        and not any("gpu" in k.lower() or "accelerator" in k.lower() for k in keys),
        f"{n}: one capacity type, only the D1 instance types and zones, no GPU requirement")
    res(sp.get("limits") == {"cpu": "2"} and ts.get("expireAfter") == "2h"
        and sp.get("disruption") == {"consolidationPolicy": "WhenEmpty", "consolidateAfter": "60s"},
        f"{n}: limits.cpu 2 (one node), expireAfter 2h, removed 60 s after empty")
    res(ts.get("taints") == [{"key": "zero-drift.io/batch", "value": "true", "effect": "NoSchedule"}]
        and sp.get("template", {}).get("metadata", {}).get("labels") == {"zero-drift.io/pool": "batch"}
        and ts.get("nodeClassRef") == {"group": "karpenter.k8s.aws", "kind": "EC2NodeClass", "name": "batch"},
        f"{n}: batch taint and label, EC2NodeClass batch")
res([pools.get(n, {}).get("weight") for n in ("batch-spot", "batch-ondemand")] == [100, 10],
    "Karpenter: Spot first (weight 100), On-Demand fallback (weight 10)")
ncs = {d["metadata"]["name"]: d.get("spec", {}) for f, d in objs_of("EC2NodeClass")}
nc = ncs.get("batch", {})
tf_ami = re.search(r'variable "system_node_ami_release_version"[^}]*?default\s*=\s*"1\.35\.[0-9]+-([0-9]{8})"', tf, re.S)
want_alias = f"al2023@v{tf_ami.group(1)}" if tf_ami else None
ami = [t.get("alias") for t in nc.get("amiSelectorTerms", [])]
res(list(ncs) == ["batch"] and nc.get("instanceProfile") == "zero-drift-karpenter-node" and "role" not in nc
    and want_alias is not None and ami == [want_alias],
    f"EC2NodeClass batch: pre-created instance profile (D6); AMI {ami} = system node release {want_alias}")
mo = nc.get("metadataOptions", {})
bdm = nc.get("blockDeviceMappings", [])
ebs = bdm[0].get("ebs", {}) if len(bdm) == 1 else {}
res(mo.get("httpTokens") == "required" and mo.get("httpPutResponseHopLimit") == 1
    and ebs.get("encrypted") is True and ebs.get("volumeType") == "gp3" and ebs.get("volumeSize") == "20Gi"
    and ebs.get("deleteOnTermination") is True
    and all(nc.get("tags", {}).get(k) for k in ("Project", "Owner", "Environment")),
    "EC2NodeClass batch: IMDSv2 hop 1, encrypted gp3 20Gi deleted with the node, project tags")
disc = {"tags": {"karpenter.sh/discovery": "zero-drift"}}
res(nc.get("subnetSelectorTerms") == [disc] and nc.get("securityGroupSelectorTerms") == [disc],
    "EC2NodeClass batch: subnets and security groups only by the discovery tag")

# 23. Karpenter controller: one replica, this cluster and its interruption
#     queue; the chart's affinity (never on a node it provisions) is not
#     overridden; no role ARN in Git (window.sh annotate adds it).
kp = next((d["spec"]["source"].get("helm", {}).get("valuesObject", {}) for f, d in apps
           if d["spec"]["source"].get("chart") == "karpenter"), None)
res(kp is not None and kp.get("replicas") == 1 and kp.get("settings", {}).get("clusterName") == "zero-drift"
    and kp.get("settings", {}).get("interruptionQueue") == "zero-drift-karpenter"
    and not {"affinity", "nodeSelector", "tolerations"} & set(kp)
    and not kp.get("serviceAccount", {}).get("annotations"),
    "zdr-karpenter: 1 replica, cluster zero-drift, interruption queue; chart affinity kept; no role ARN in Git")
sys.exit(0 if ok else 1)
EOF

echo
if (( failed )); then echo "RESULT: FAIL"; exit 1; fi
echo "RESULT: PASS (static only; proves nothing about a cluster or AWS)"
