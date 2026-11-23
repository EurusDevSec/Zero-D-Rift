#!/usr/bin/env bash
# Static gate for gitops/ (SPEC-P3 Task 3, DRF-35; SPEC-P4 P4-T3.2 B, DRF-51; SPEC-P5 P5-T2.1 A, DRF-66). Touches no cluster and no AWS.
# Usage: gitops/check.sh   (from anywhere in the repo)
# Exit 0 only when every check passes. Needs python with PyYAML (YAML parsing only).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here"

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

# 3. Every container image and provider package is pinned by digest; no latest.
latest="$(grep -n -E '(:|")latest("|$| )' $files || true)"
[[ -z "$latest" ]] && pass "no latest tag" || fail "latest: $latest"
unpinned="$(grep -h -E '^\s*-?\s*(image|package):\s*\S' $files | grep -v '@sha256:[0-9a-f]\{64\}' || true)"
[[ -z "$unpinned" ]] && pass "every image/package line pinned by @sha256" || fail "not pinned by digest: $unpinned"

# 4-7 need structure: read every document once.
python -I - $files <<'EOF' || failed=1
import sys, yaml, re
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
res(charts == {"crossplane": "2.4.3", "kro": "0.9.4"}, f"Helm charts pinned exactly: {charts}")
# Chart images: the values must carry a digest (Crossplane: repository@sha256 +
# ignoreTag; kro: tag v0.9.4@sha256), otherwise the chart default tag is used.
for f, d in apps:
    v = d["spec"]["source"].get("helm", {}).get("valuesObject", {}).get("image", {})
    if "chart" in d["spec"]["source"]:
        ref = v.get("repository", "") + ":" + str(v.get("tag", ""))
        res(re.search(r"@sha256:[0-9a-f]{64}", ref) is not None, f"{d['metadata']['name']}: chart image pinned by digest")
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
PLATFORM_SA = {"rag-db-admin", "rag-bootstrap"}
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

# 8b. The requests app syncs only RAGSandbox objects. Anything else there (a
#     ConfigMap, a Job...) would bypass the request rules; platform-config is
#     window-only (window.sh, after db-init) and must not exist in any source.
others = [f"{f}: {d.get('kind')} {d.get('metadata', {}).get('name')}" for f, d in docs
          if f.replace("\\", "/").startswith("requests/") and "/disabled/" not in f.replace("\\", "/")
          and d.get("kind") != "RAGSandbox"]
res(not others, "requests/ holds only RAGSandbox objects" + (f": {others}" if others else ""))
pc = [f for f, d in docs if d.get("kind") == "ConfigMap" and d.get("metadata", {}).get("name") == "platform-config"]
res(not pc, "no platform-config ConfigMap in Git (window-only)" + (f": {pc}" if pc else ""))

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
    and sas == {(PLATFORM_NS, s) for s in PLATFORM_SA} | {(t, "default") for t in TENANTS},
    "Git has tenant-a, tenant-b, zdr-platform, the two platform ServiceAccounts and the tenant default ones")

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
    and ps.get("namespaceResourceWhitelist") == [{"group": "kro.run", "kind": "RAGSandbox"}],
    "AppProject zdr-requests: this repo, tenant-a/b, nothing cluster-scoped, only RAGSandbox")
in_proj = sorted(d["metadata"]["name"] for f, d in apps if d["spec"].get("project") == "zdr-requests")
req = next((d for f, d in apps if d["metadata"]["name"] == "zdr-requests"), {})
res(in_proj == ["zdr-requests"] and req.get("spec", {}).get("destination", {}).get("namespace") in TENANTS
    and "CreateNamespace=true" not in req.get("spec", {}).get("syncPolicy", {}).get("syncOptions", []),
    "zdr-requests app: project zdr-requests, tenant destination, no CreateNamespace")
sys.exit(0 if ok else 1)
EOF

echo
if (( failed )); then echo "RESULT: FAIL"; exit 1; fi
echo "RESULT: PASS (static only; proves nothing about a cluster or AWS)"
