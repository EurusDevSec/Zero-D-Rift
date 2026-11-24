#!/usr/bin/env bash
# LAB ONLY (DRF-66, SPEC-P5 P5-T2.1 B "one real API call from a Pod using a
# ServiceAccount token"). Prints one Pod as JSON on stdout. The Pod asks for its
# ServiceAccount token itself (Pod-level automountServiceAccountToken: true wins
# over the ServiceAccount's false), then calls the API server twice with it.
# Expected: both calls 403, because the tenant's ServiceAccount has no RoleBinding.
# Needs IMAGE = the project image by digest (it has Python); the Pod really runs.
# Usage: IMAGE=ghcr.io/...@sha256:... labs/p5-kind/api-call.sh [NAMESPACE] | kubectl create -f -
set -euo pipefail
ns=${1:-tenant-a}
: "${IMAGE:?set IMAGE to the project image by digest}"
code=$(cat <<'PY'
import json, ssl, urllib.request as u, urllib.error as ue
d = "/var/run/secrets/kubernetes.io/serviceaccount/"
tok = open(d + "token").read()
ns = open(d + "namespace").read()
ctx = ssl.create_default_context(cafile=d + "ca.crt")
for path in ("/api/v1/namespaces/%s/pods" % ns, "/api/v1/namespaces/%s/secrets" % ns):
    req = u.Request("https://kubernetes.default.svc" + path, headers={"Authorization": "Bearer " + tok})
    try:
        r = u.urlopen(req, context=ctx, timeout=10)
        print(r.status, path, "ALLOWED")
    except ue.HTTPError as e:
        print(e.code, path, json.loads(e.read()).get("message", ""))
    except Exception as e:
        print("ERR", path, type(e).__name__, e)
PY
)
c=$(jq -nc --arg code "$code" '{command: ["python", "-c", $code]}')
s='{"automountServiceAccountToken": true, "restartPolicy": "Never"}'
exec "$(dirname "$0")/pod.sh" apicall "$ns" "$c" "$s"
