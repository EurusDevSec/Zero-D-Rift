#!/usr/bin/env python3
"""Turn raw Prometheus and OpenCost exports into committed-safe evidence.

Called by export_metrics.sh (SPEC-P7 T2.2). Reads the raw responses from a
temporary folder, writes JSONL/JSON to the output folder, and refuses to
write anything if an identifier survives redaction.

Redaction rules (SPEC-P7 T2.2: "no account or instance identifier in
committed output"):
- keys that name a node or host (node, instance, ...) get a pseudonym
  "node-<8 hex>" from an HMAC with a random salt that is never stored, so the
  same node keeps one pseudonym inside one export and cannot be reversed;
- keys that only carry identifiers (provider id, uid, IPs, container ids) are
  dropped;
- any other string is scrubbed for IPv4, EC2 instance ids, ARNs, 12-digit
  account ids and AWS endpoint hostnames, then scanned again; a hit stops the
  export (exit 3).
Sample values (Prometheus "values"/"value") are numbers and are not scanned.
"""
import argparse
import hashlib
import hmac
import json
import os
import re
import secrets
import sys

SCHEMA = "1.0"


def _load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)
PSEUDO_KEYS = {"node", "instance", "kubernetes_node", "exported_node", "exported_instance",
               "hostname", "host", "nodename"}
DROP_KEYS = {"provider_id", "providerID", "providerid", "uid", "pod_ip", "host_ip", "internal_ip",
             "external_ip", "ip", "address", "container_id", "image_id", "id", "pod_uid",
             "system_uuid", "machine_id", "boot_id", "kernel_version", "os_image"}
SKIP_SCAN_KEYS = {"values", "value"}
PATTERNS = [
    ("ipv4", re.compile(r"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])")),
    ("ec2-instance", re.compile(r"\bi-[0-9a-f]{8,17}\b")),
    ("arn", re.compile(r"\barn:aws[a-z-]*:[^\s\"]*")),
    ("account-id", re.compile(r"(?<!\d)\d{12}(?!\d)")),
    ("aws-host", re.compile(r"\b[\w.-]+\.(?:compute\.internal|ec2\.internal|amazonaws\.com)\b")),
    ("ip-hostname", re.compile(r"\bip-\d{1,3}-\d{1,3}-\d{1,3}-\d{1,3}\b")),
]
# Any key that ends in one of these names a host (e.g. kubernetes_io_hostname,
# label_kubernetes_io_hostname): its value gets the node pseudonym.
PSEUDO_SUFFIX = re.compile(r"(?:^|_)(?:hostname|node|nodename|instance)$")
# Label names (not values) that legitimately contain an AWS domain.
SAFE_LABEL_NAME = re.compile(r"^label_eks_amazonaws_com_\w+$")


class Redactor:
    def __init__(self, salt=None, node_names=(), secrets_=()):
        """node_names: literal node names seen in the cluster (pseudonymized
        anywhere); secrets_: literal addresses and provider ids (redacted)."""
        self.salt = salt if salt is not None else secrets.token_bytes(32)
        self.node_names = sorted({n for n in node_names if n}, key=len, reverse=True)
        self.literals = sorted({x for x in secrets_ if x}, key=len, reverse=True)

    def pseudo(self, value):
        if value in ("", None):
            return value
        d = hmac.new(self.salt, str(value).encode(), hashlib.sha256).hexdigest()[:8]
        return f"node-{d}"

    def scrub(self, text):
        for lit in self.literals:
            text = text.replace(lit, "<redacted>")
        for name in self.node_names:
            text = text.replace(name, self.pseudo(name))
        for kind, rx in PATTERNS:
            if kind in ("ip-hostname", "aws-host"):  # node names: keep joinable
                text = rx.sub(lambda m: self.pseudo(m.group(0)), text)
            else:
                text = rx.sub("<redacted>", text)
        return text

    def walk(self, node, key=None):
        if isinstance(node, dict):
            out = {}
            for k, v in node.items():
                if k in DROP_KEYS:
                    continue
                if k in SKIP_SCAN_KEYS:
                    out[k] = v
                elif isinstance(v, str) and (k in PSEUDO_KEYS or PSEUDO_SUFFIX.search(str(k))):
                    out[k] = self.pseudo(v)
                else:
                    out[self.scrub(k) if isinstance(k, str) else k] = self.walk(v, k)
            return out
        if isinstance(node, list):
            return [self.walk(x, key) for x in node]
        if isinstance(node, str):
            return self.scrub(node)
        return node


def leaks(node, path="$", literals=()):
    """Yield (path, kind, text) for every identifier left in strings."""
    if isinstance(node, str):
        for lit in literals:
            if lit in node:
                yield (path, "cluster-literal", node)
    if isinstance(node, dict):
        for k, v in node.items():
            if k in SKIP_SCAN_KEYS:
                continue
            if isinstance(k, str) and not SAFE_LABEL_NAME.match(k):
                for kind, rx in PATTERNS:
                    if rx.search(k):
                        yield (f"{path}.<key>", kind, k)
            yield from leaks(v, f"{path}.{k}", literals)
    elif isinstance(node, list):
        for i, x in enumerate(node):
            yield from leaks(x, f"{path}[{i}]", literals)
    elif isinstance(node, str):
        for kind, rx in PATTERNS:
            if rx.search(node):
                yield (path, kind, node)


def convert(raw_dir, out_dir, meta, redactor):
    """Return (files, manifest). Nothing is written here."""
    files = {}
    queries = []
    for q in meta["queries"]:
        body = _load(os.path.join(raw_dir, q["raw"]))
        if body.get("status") != "success":
            raise SystemExit(f"query {q['name']} failed: {body.get('error', body.get('status'))}")
        lines = []
        for s in body["data"]["result"]:
            rec = redactor.walk({"metric": s.get("metric", {})})
            lines.append({"schema_version": SCHEMA, "run_id": meta["run_id"], "query_name": q["name"],
                          "metric": rec["metric"], "values": s.get("values", []),
                          "synthetic": meta["synthetic"]})
        rel = f"prometheus/{q['name']}.jsonl"
        files[rel] = "".join(json.dumps(x, sort_keys=True, separators=(",", ":")) + "\n" for x in lines)
        queries.append({"name": q["name"], "promql": q["promql"], "file": rel, "series": len(lines),
                        "samples": sum(len(x["values"]) for x in lines)})
    allocations = []
    for a in meta["allocations"]:
        body = _load(os.path.join(raw_dir, a["raw"]))
        if body.get("code") not in (200, None):
            raise SystemExit(f"OpenCost allocation {a['aggregate']} failed: {body.get('message', body.get('code'))}")
        red = redactor.walk(body.get("data", []))
        rel = f"opencost/allocation_{a['aggregate']}.json"
        files[rel] = json.dumps({"schema_version": SCHEMA, "run_id": meta["run_id"], "aggregate": a["aggregate"],
                                 "window": meta["window"], "source": "opencost (allocation view, not the AWS bill)",
                                 "synthetic": meta["synthetic"], "data": red}, sort_keys=True, indent=1) + "\n"
        rows = sum(len(x) for x in red if isinstance(x, dict))
        allocations.append({"aggregate": a["aggregate"], "file": rel, "rows": rows})
    manifest = {
        "schema_version": SCHEMA, "run_id": meta["run_id"], "official": meta["official"],
        "synthetic": meta["synthetic"], "window": meta["window"], "exported_at_utc": meta["exported_at_utc"],
        "prometheus_version": meta.get("prometheus_version", "unknown"),
        "queries": queries, "opencost_allocations": allocations,
        "redaction": {"pseudonymized_keys": sorted(PSEUDO_KEYS), "dropped_keys": sorted(DROP_KEYS),
                      "salt": "random per export, never stored",
                      "patterns": [k for k, _ in PATTERNS]},
        "note": "OpenCost numbers are an allocation view at public On-Demand prices; AWS Billing is the cost source (SPEC-P7 D4, D5).",
    }
    files["export_manifest.json"] = json.dumps(manifest, sort_keys=True, indent=1) + "\n"
    return files, manifest


def cluster_literals(path):
    """Node names, addresses and provider ids from `kubectl get nodes -o json`."""
    if not os.path.exists(path):
        return [], []
    names, lits = [], []
    for n in _load(path).get("items", []):
        names.append(n["metadata"]["name"])
        lits.append(n.get("spec", {}).get("providerID", ""))
        lits += [a.get("address", "") for a in n.get("status", {}).get("addresses", [])
                 if a.get("type") != "Hostname"]
        names += [a.get("address", "") for a in n.get("status", {}).get("addresses", [])
                  if a.get("type") == "Hostname"]
    return [x for x in names if x], [x for x in lits if x]


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--meta", required=True, help="JSON written by export_metrics.sh")
    a = ap.parse_args(argv)
    meta = _load(a.meta)
    names, lits = cluster_literals(os.path.join(a.raw, "nodes.json"))
    files, manifest = convert(a.raw, a.out, meta, Redactor(node_names=names, secrets_=lits))
    found = []
    for rel, text in files.items():
        docs = [json.loads(x) for x in text.splitlines() if x] if rel.endswith(".jsonl") else [json.loads(text)]
        for d in docs:
            found += [(rel, p, k) for p, k, _ in leaks(d, literals=names + lits)]
    if found:
        for rel, p, k in found[:20]:
            print(f"LEAK {k} in {rel} at {p}", file=sys.stderr)
        print(f"refusing to write: {len(found)} identifier(s) left after redaction", file=sys.stderr)
        return 3
    for rel, text in files.items():
        path = os.path.join(a.out, rel)
        os.makedirs(os.path.dirname(path) or a.out, exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
    for q in manifest["queries"]:
        print(f"{q['name']:32s} series={q['series']:<4d} samples={q['samples']}")
    for x in manifest["opencost_allocations"]:
        print(f"opencost allocation {x['aggregate']:12s} rows={x['rows']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
