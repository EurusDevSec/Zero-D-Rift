#!/usr/bin/env python3
"""Normalize raw EC2 and Kubernetes reads into a run timeline and a cost_calc
input, with aliases instead of instance ids (SPEC-P7 T3, D4).

Called by collect_timeline.sh. Raw inputs in --raw:
  instances.json      aws ec2 describe-instances (Project tag), any state
  spot_history.json   {"<type>|<zone>": describe-spot-price-history output}
  on_demand.json      {"<type>": aws pricing get-products output}
  k8s_events.json     kubectl get events -A (NodeClaim and Node objects)
Outputs in --out:
  timeline/events.jsonl   EXPERIMENT_PLAN §9.2 event shape
  timeline/instances.json aliases, roles, type, capacity, zone, launch, end
  cost/cost_input.json    cost_calc.py "run" input for the selected roles
Nothing is written if an instance id, IP, ARN or account id survives.
"""
import argparse
import datetime as dt
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from export_redact import leaks  # noqa: E402

SCHEMA = "1.0"
REASON_TS = re.compile(r"\((\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) GMT\)")


def _load(path, default=None):
    if not os.path.exists(path):
        return default
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def utc(s):
    """AWS and Kubernetes timestamps -> 'YYYY-MM-DDTHH:MM:SS[.ffffff]Z'."""
    if not s:
        return None
    t = dt.datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(dt.timezone.utc)
    return t.strftime("%Y-%m-%dT%H:%M:%S.%fZ" if t.microsecond else "%Y-%m-%dT%H:%M:%SZ")


def tags(inst):
    return {t["Key"]: t["Value"] for t in inst.get("Tags", [])}


def role_of(tg):
    if tg.get("zero-drift.io/role") == "baseline":
        return "baseline"
    if "karpenter.sh/nodepool" in tg:
        return "batch"
    if "eks:nodegroup-name" in tg:
        return "system"
    return "other"


def termination(inst):
    state = inst.get("State", {}).get("Name")
    if state not in ("shutting-down", "terminated"):
        return None, f"state {state}: not terminated at collection"
    m = REASON_TS.search(inst.get("StateTransitionReason", "") or "")
    if not m:
        return None, "terminated, but StateTransitionReason has no time (e.g. Spot interruption); fill from CloudTrail"
    return m.group(1).replace(" ", "T") + "Z", "StateTransitionReason"


def on_demand_price(products):
    """First OnDemand USD price per hour in an `aws pricing get-products` reply."""
    for raw in (products or {}).get("PriceList", []):
        item = json.loads(raw) if isinstance(raw, str) else raw
        for term in item.get("terms", {}).get("OnDemand", {}).values():
            for dim in term.get("priceDimensions", {}).values():
                usd = dim.get("pricePerUnit", {}).get("USD")
                if usd and dim.get("unit") in ("Hrs", "Hours"):
                    return usd
    return None


def build(raw, start, end, run_id, arm, pair_id, roles, volume_gb, gp3_price, synthetic):
    w0, w1 = dt.datetime.fromisoformat(start.replace("Z", "+00:00")), dt.datetime.fromisoformat(end.replace("Z", "+00:00"))
    found = []
    for res in (_load(os.path.join(raw, "instances.json"), {}) or {}).get("Reservations", []):
        for i in res.get("Instances", []):
            launch = utc(i.get("LaunchTime"))
            term, term_src = termination(i)
            lt = dt.datetime.fromisoformat(launch.replace("Z", "+00:00"))
            et = dt.datetime.fromisoformat(term.replace("Z", "+00:00")) if term else None
            if lt > w1 or (et is not None and et < w0):
                continue  # does not overlap the window
            tg = tags(i)
            found.append({"_id": i["InstanceId"], "role": role_of(tg), "pool": tg.get("karpenter.sh/nodepool"),
                          "instance_type": i.get("InstanceType"), "zone": i.get("Placement", {}).get("AvailabilityZone"),
                          "capacity_type": "spot" if i.get("InstanceLifecycle") == "spot" else "on-demand",
                          "launch_utc": launch, "termination_utc": term, "termination_source": term_src,
                          "volume_gb": volume_gb.get(role_of(tg), 0)})
    found.sort(key=lambda x: (x["role"], x["launch_utc"]))
    count, alias_of = {}, {}
    for x in found:
        count[x["role"]] = count.get(x["role"], 0) + 1
        x["alias"] = f"{x['role']}-{count[x['role']]}"
        alias_of[x.pop("_id")] = x["alias"]

    events = []
    def ev(at, etype, source, status, ref):
        events.append({"schema_version": SCHEMA, "run_id": run_id, "event_at_utc": at, "event_type": etype,
                       "source": source, "status": status, "evidence_ref": ref, "synthetic": synthetic})
    for x in found:
        ev(x["launch_utc"], "ec2_launch", "aws", x["alias"], "timeline/instances.json")
        if x["termination_utc"]:
            ev(x["termination_utc"], "ec2_terminated", "aws", x["alias"], "timeline/instances.json")
    for e in (_load(os.path.join(raw, "k8s_events.json"), {}) or {}).get("items", []):
        obj = e.get("involvedObject", {})
        if obj.get("kind") not in ("NodeClaim", "Node"):
            continue
        at = utc(e.get("eventTime") or e.get("lastTimestamp") or e.get("firstTimestamp"))
        if at:
            ev(at, f"k8s_{obj['kind'].lower()}_{(e.get('reason') or 'event').lower()}", "kubernetes",
               e.get("type", ""), "timeline/events.jsonl")
    events.sort(key=lambda x: (x["event_at_utc"], x["event_type"]))

    spot_raw = _load(os.path.join(raw, "spot_history.json"), {}) or {}
    od_raw = _load(os.path.join(raw, "on_demand.json"), {}) or {}
    prices = {"on_demand": {}, "spot": [], "ebs_gp3_usd_per_gb_month": gp3_price}
    for itype, products in od_raw.items():
        usd = on_demand_price(products)
        if usd:
            prices["on_demand"][itype] = {"usd_per_hour": usd, "source": "AWS Price List (get-products)"}
    for key, reply in spot_raw.items():
        for h in (reply or {}).get("SpotPriceHistory", []):
            prices["spot"].append({"instance_type": h["InstanceType"], "zone": h["AvailabilityZone"],
                                   "from_utc": utc(h["Timestamp"]), "usd_per_hour": h["SpotPrice"]})
    prices["spot"].sort(key=lambda h: (h["instance_type"], h["zone"], h["from_utc"]))
    selected = [{k: x[k] for k in ("alias", "instance_type", "capacity_type", "zone", "launch_utc",
                                    "termination_utc", "volume_gb")} for x in found if x["role"] in roles]
    cost_input = {"schema_version": SCHEMA, "run_id": run_id, "pair_id": pair_id, "arm": arm,
                  "synthetic": synthetic, "window": {"start_utc": start, "end_utc": end},
                  "instances": selected, "prices": prices}
    files = {
        "timeline/events.jsonl": "".join(json.dumps(e, sort_keys=True, separators=(",", ":")) + "\n" for e in events),
        "timeline/instances.json": json.dumps({"schema_version": SCHEMA, "run_id": run_id, "synthetic": synthetic,
                                               "window": {"start_utc": start, "end_utc": end},
                                               "instances": found}, indent=1, sort_keys=True) + "\n",
        "cost/cost_input.json": json.dumps(cost_input, indent=1, sort_keys=True) + "\n",
    }
    return files, list(alias_of), found


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--start", required=True)
    ap.add_argument("--end", required=True)
    ap.add_argument("--run-id", required=True)
    ap.add_argument("--arm", default="")
    ap.add_argument("--pair-id", default="")
    ap.add_argument("--roles", default="batch", help="comma list of roles in the cost input")
    ap.add_argument("--batch-volume-gb", default="20", help="EC2NodeClass batch root volume (Git)")
    ap.add_argument("--baseline-volume-gb", default="20")
    ap.add_argument("--gp3-usd-per-gb-month", default="0.08")
    ap.add_argument("--synthetic", action="store_true")
    a = ap.parse_args(argv)
    files, ids, found = build(a.raw, a.start, a.end, a.run_id, a.arm, a.pair_id, set(a.roles.split(",")),
                              {"batch": a.batch_volume_gb, "baseline": a.baseline_volume_gb},
                              a.gp3_usd_per_gb_month, a.synthetic)
    bad = []
    for rel, text in files.items():
        for i in ids:
            if i in text:
                bad.append((rel, "instance-id"))
        docs = [json.loads(x) for x in text.splitlines() if x] if rel.endswith(".jsonl") else [json.loads(text)]
        for d in docs:
            bad += [(rel, k) for _, k, _ in leaks(d)]
    if bad:
        for rel, k in bad[:20]:
            print(f"LEAK {k} in {rel}", file=sys.stderr)
        print("refusing to write: identifiers left", file=sys.stderr)
        return 3
    for rel, text in files.items():
        p = os.path.join(a.out, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
    for x in found:
        print(f"{x['alias']:12s} {x['instance_type']:10s} {x['capacity_type']:9s} {x['launch_utc']} -> "
              f"{x['termination_utc'] or 'MISSING (' + x['termination_source'] + ')'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
