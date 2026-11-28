#!/usr/bin/env python3
"""Cost calculator for one run, one arm and one window (SPEC-P7 D4, D5, T3).

The contract is docs/finops/COST_MEASUREMENT.md. In short:

  variable compute (one instance) =
      sum over price segments of (billed seconds in segment / 3600 x USD per hour)
    + root volume GB x billed seconds x (USD per GB-month / seconds in that month)

  billed seconds = max(60, ceil(termination - launch))   (per second, 60 s minimum)

On-Demand prices come from the Price List; Spot prices are a step function read
from Spot price history for the type and zone of the run, so a price change
inside a run is integrated, never averaged. The calculator REFUSES (exit 4) a
missing termination time, a missing price, or a Spot history that does not
cover the launch. Billing that has not been read is PENDING, never 0.

Money is Decimal end to end; outputs are rounded to 6 decimals only at the
edge (ROUND_HALF_UP). Ratios use the unrounded sums.

CLI:
  cost_calc.py run    INPUT.json            -> per-instance and per-run cost
  cost_calc.py window WINDOW.json           -> fixed categories and reconciliation
  cost_calc.py pairs  RUN1.json RUN2.json.. -> per-arm sums and the saving ratio
"""
import calendar
import datetime as dt
import json
import math
import sys
from decimal import ROUND_HALF_UP, Decimal

SCHEMA = "1.0"
MIN_BILLED_S = 60
Q6 = Decimal("0.000001")
TOLERANCE_REL = Decimal("0.05")
TOLERANCE_ABS = Decimal("0.02")
H5_MIN_PAIRS = 5
H5_TARGET = Decimal("0.40")
CATEGORIES = ("variable_compute", "cluster_fixed", "data_storage", "network", "logging", "other")


class Refused(Exception):
    """An input the contract does not allow; the caller must fix the input."""


def D(x):
    if isinstance(x, float):
        return Decimal(repr(x))
    return Decimal(str(x))


def r6(x):
    return str(D(x).quantize(Q6, rounding=ROUND_HALF_UP))


def ts(s, what):
    if not s:
        raise Refused(f"{what}: missing timestamp")
    try:
        t = dt.datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        try:
            t = dt.datetime.strptime(s, "%Y-%m-%dT%H:%M:%S.%fZ")
        except ValueError:
            raise Refused(f"{what}: not RFC3339 UTC with Z: {s!r}")
    return t.replace(tzinfo=dt.timezone.utc)


def billed_seconds(launch, end):
    raw = (end - launch).total_seconds()
    if raw < 0:
        raise Refused("termination before launch")
    return max(MIN_BILLED_S, math.ceil(raw)), raw


def month_seconds(t):
    return calendar.monthrange(t.year, t.month)[1] * 86400


def price_segments(inst, prices, launch, billed_end):
    """Return [(seconds, usd_per_hour, source)] covering [launch, billed_end)."""
    cap = inst.get("capacity_type")
    itype = inst.get("instance_type")
    if cap == "on-demand":
        p = prices.get("on_demand", {}).get(itype)
        if not p or p.get("usd_per_hour") in (None, ""):
            raise Refused(f"{inst.get('alias')}: no On-Demand price for {itype}")
        return [((billed_end - launch).total_seconds(), D(p["usd_per_hour"]), p.get("source", "price list"))]
    if cap != "spot":
        raise Refused(f"{inst.get('alias')}: capacity_type must be spot or on-demand, got {cap!r}")
    hist = sorted((ts(h["from_utc"], "spot price from_utc"), D(h["usd_per_hour"]))
                  for h in prices.get("spot", [])
                  if h.get("instance_type") == itype and h.get("zone") == inst.get("zone"))
    if not hist or hist[0][0] > launch:
        raise Refused(f"{inst.get('alias')}: Spot history for {itype} in {inst.get('zone')} does not cover the launch")
    segs = []
    for i, (start, price) in enumerate(hist):
        nxt = hist[i + 1][0] if i + 1 < len(hist) else None
        a = max(start, launch)
        b = billed_end if nxt is None else min(nxt, billed_end)
        if b > a:
            segs.append(((b - a).total_seconds(), price, "spot price history"))
    return segs


def instance_cost(inst, prices):
    alias = inst.get("alias") or "?"
    launch = ts(inst.get("launch_utc"), f"{alias} launch_utc")
    if not inst.get("termination_utc"):
        raise Refused(f"{alias}: missing termination time (still running, or not collected)")
    end = ts(inst["termination_utc"], f"{alias} termination_utc")
    billed, raw = billed_seconds(launch, end)
    billed_end = launch + dt.timedelta(seconds=billed)
    segs = price_segments(inst, prices, launch, billed_end)
    compute = sum((D(s) / D(3600) * p for s, p, _ in segs), Decimal(0))
    vol_gb = D(inst.get("volume_gb", 0))
    vol = Decimal(0)
    if vol_gb:
        gbm = prices.get("ebs_gp3_usd_per_gb_month")
        if gbm in (None, ""):
            raise Refused(f"{alias}: volume present but no gp3 price")
        vol = vol_gb * D(billed) * D(gbm) / D(month_seconds(launch))
    return {
        "alias": alias, "instance_type": inst.get("instance_type"), "capacity_type": inst.get("capacity_type"),
        "zone": inst.get("zone"), "observed_seconds": raw, "billed_seconds": billed,
        "minimum_applied": billed == MIN_BILLED_S and raw < MIN_BILLED_S,
        "price_segments": [{"seconds": s, "usd_per_hour": str(p), "source": src} for s, p, src in segs],
        "spot_granularity_assumed": inst.get("capacity_type") == "spot",
        "_compute": compute, "_volume": vol,
        "compute_usd": r6(compute), "volume_usd": r6(vol), "variable_usd": r6(compute + vol),
    }


def run_cost(doc):
    insts = doc.get("instances")
    if not insts:
        raise Refused("run has no instances; a run without capacity is not 0, it is an input error")
    rows = [instance_cost(i, doc.get("prices", {})) for i in insts]
    total = sum((r["_compute"] + r["_volume"] for r in rows), Decimal(0))
    for r in rows:
        r.pop("_compute"), r.pop("_volume")
    return {"schema_version": SCHEMA, "run_id": doc.get("run_id"), "pair_id": doc.get("pair_id"),
            "arm": doc.get("arm"), "synthetic": bool(doc.get("synthetic")), "instances": rows,
            "_total": total, "variable_compute_usd": r6(total),
            "source": "computed (D4); AWS Billing reconciles per window (D5)"}


def reconcile(computed, billed):
    """billed: None or {"status": "PENDING"} or {"status": "READ", "usd": x, "read_on": d}."""
    if not billed or billed.get("status") != "READ" or billed.get("usd") in (None, ""):
        return {"status": "PENDING", "computed_usd": r6(computed), "billed_usd": None,
                "note": "billing not read yet; never treated as 0"}
    b = D(billed["usd"])
    diff = b - computed
    tol = max(TOLERANCE_REL * b, TOLERANCE_ABS)
    return {"status": "WITHIN_TOLERANCE" if abs(diff) <= tol else "NEEDS_REGISTERED_CAUSE",
            "computed_usd": r6(computed), "billed_usd": r6(b), "difference_usd": r6(diff),
            "tolerance_usd": r6(tol), "read_on": billed.get("read_on")}


def window_cost(doc):
    """Fixed categories from inventory hours x unit prices, plus reconciliation."""
    lines, by_cat = [], {c: Decimal(0) for c in CATEGORIES}
    for it in doc.get("fixed", []):
        cat = it.get("category")
        if cat not in CATEGORIES or cat == "variable_compute":
            raise Refused(f"fixed line {it.get('name')!r}: category must be one of {CATEGORIES[1:]}")
        for k in ("quantity", "hours", "usd_per_unit_hour"):
            if it.get(k) in (None, ""):
                raise Refused(f"fixed line {it.get('name')!r}: missing {k}")
        usd = D(it["quantity"]) * D(it["hours"]) * D(it["usd_per_unit_hour"])
        by_cat[cat] += usd
        lines.append({**it, "usd": r6(usd)})
    variable = Decimal(0)
    for r in doc.get("runs", []):
        variable += run_cost(r)["_total"]
    by_cat["variable_compute"] = variable
    total = sum(by_cat.values(), Decimal(0))
    return {"schema_version": SCHEMA, "window_id": doc.get("window_id"), "synthetic": bool(doc.get("synthetic")),
            "fixed_lines": lines, "by_category_usd": {c: r6(v) for c, v in by_cat.items()},
            "computed_total_usd": r6(total),
            "reconciliation_variable_compute": reconcile(variable, doc.get("billed_variable_compute")),
            "reconciliation_total": reconcile(total, doc.get("billed_total")),
            "note": "fixed costs stay visible; Pods at zero is not cost at zero (ver3 8.4)"}


def pairs(docs):
    runs = [run_cost(d) for d in docs]
    by_pair = {}
    for r in runs:
        if r["arm"] not in ("baseline", "optimized") or not r["pair_id"]:
            raise Refused(f"run {r['run_id']}: needs pair_id and arm baseline|optimized")
        if r["arm"] in by_pair.setdefault(r["pair_id"], {}):
            raise Refused(f"pair {r['pair_id']}: two {r['arm']} runs")
        by_pair[r["pair_id"]][r["arm"]] = r["_total"]
    complete = {p: a for p, a in by_pair.items() if len(a) == 2}
    base = sum((a["baseline"] for a in complete.values()), Decimal(0))
    opt = sum((a["optimized"] for a in complete.values()), Decimal(0))
    ratio = (base - opt) / base if base else None
    if len(complete) < H5_MIN_PAIRS or ratio is None:
        decision = "INCONCLUSIVE"
    else:
        decision = "PASS" if ratio >= H5_TARGET else "FAIL"
    return {"schema_version": SCHEMA, "pairs_complete": len(complete),
            "pairs_incomplete": sorted(p for p, a in by_pair.items() if len(a) != 2),
            "baseline_usd": r6(base), "optimized_usd": r6(opt),
            "saving_ratio": None if ratio is None else str(ratio.quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP)),
            "pairwise_ratio": {p: str(((a["baseline"] - a["optimized"]) / a["baseline"]).quantize(Decimal("0.0001")))
                               for p, a in sorted(complete.items()) if a["baseline"]},
            "h5_decision": decision,
            "synthetic": any(r["synthetic"] for r in runs)}


def _public(x):
    if isinstance(x, dict):
        return {k: _public(v) for k, v in x.items() if not k.startswith("_")}
    if isinstance(x, list):
        return [_public(v) for v in x]
    return x


def _load(p):
    with open(p, encoding="utf-8") as f:
        return json.load(f)


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if len(argv) < 2 or argv[0] not in ("run", "window", "pairs"):
        print(__doc__.split("CLI:")[1], file=sys.stderr)
        return 2
    try:
        if argv[0] == "run":
            out = run_cost(_load(argv[1]))
        elif argv[0] == "window":
            out = window_cost(_load(argv[1]))
        else:
            out = pairs([_load(p) for p in argv[1:]])
    except Refused as e:
        print(f"cost_calc: REFUSED: {e}", file=sys.stderr)
        return 4
    print(json.dumps(_public(out), indent=1, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
