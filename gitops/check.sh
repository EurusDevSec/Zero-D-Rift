#!/usr/bin/env bash
# Static gate for gitops/ (SPEC-P3 Task 3, DRF-35). Touches no cluster and no AWS.
# Usage: gitops/check.sh   (from anywhere in the repo)
# Exit 0 only when every check passes. Needs python with PyYAML (YAML parsing only).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here"

failed=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; failed=1; }

# Every manifest Argo CD can sync, plus the bootstrap app and the disabled request.
files="$(find bootstrap platform requests -name '*.yaml' | sort)"

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
        res(d["spec"]["source"].get("directory", {}).get("recurse") is False,
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

# 7. The RGD gates readiness on the bucket's Ready condition (DRF-39 E4).
rgd = [d for f, d in docs if d.get("kind") == "ResourceGraphDefinition"]
bucket = [r for g in rgd for r in g["spec"]["resources"] if r["template"].get("kind") == "Bucket"]
res(len(bucket) == 1 and any('c.type == "Ready"' in w for w in bucket[0].get("readyWhen", [])),
    "RGD bucket node has readyWhen on Ready")
sys.exit(0 if ok else 1)
EOF

echo
if (( failed )); then echo "RESULT: FAIL"; exit 1; fi
echo "RESULT: PASS (static only; proves nothing about a cluster or AWS)"
