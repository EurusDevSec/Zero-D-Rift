"""SYNTHETIC unit tests for experiments/lib/cost_calc.py (SPEC-P7 T3).

All prices, times and runs are invented inputs. Prices are shaped like the
COST_PLAN §5.2 facts but no result here is an observed cost.
Run: python -I -m unittest discover -s tests/experiments -v
"""
import os
import sys
import unittest
from decimal import Decimal

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "experiments", "lib"))
import cost_calc as cc  # noqa: E402

PRICES = {  # SYNTHETIC
    "on_demand": {"m5.large": {"usd_per_hour": "0.096", "source": "SYNTHETIC price list"}},
    "spot": [{"instance_type": "m5.large", "zone": "zone-a", "from_utc": "2026-11-29T00:00:00Z", "usd_per_hour": "0.0397"}],
    "ebs_gp3_usd_per_gb_month": "0.08",
}


def inst(cap, launch, end, zone="zone-a", gb=20, alias="batch-1"):
    return {"alias": alias, "instance_type": "m5.large", "capacity_type": cap, "zone": zone,
            "launch_utc": launch, "termination_utc": end, "volume_gb": gb}


def run(arm, pair, instance, prices=PRICES, run_id=None):
    return {"run_id": run_id or f"{pair}-{arm}", "pair_id": pair, "arm": arm, "synthetic": True,
            "instances": [instance], "prices": prices}


class MicroLabPair(unittest.TestCase):
    """The P7-T1 micro-lab inputs. The expected values were worked by hand by
    Claude on 28/11; the owner's own paper result (T1) must match them before
    this test counts as the owner's hand pair."""

    def test_hand_pair(self):
        # baseline: On-Demand, 300 s work + 1800 s idle hold + 60 s, 20 GB gp3
        b = cc.run_cost(run("baseline", "P1", inst("on-demand", "2026-11-29T01:00:00Z", "2026-11-29T01:36:00Z")))
        # optimized: Spot, 300 s work + boot and 60 s consolidation = 420 s
        o = cc.run_cost(run("optimized", "P1", inst("spot", "2026-11-29T02:00:00Z", "2026-11-29T02:07:00Z")))
        # 2160/3600 x 0.096 = 0.0576 ; 20 x 2160 x 0.08 / (30 x 86400) = 0.001333
        self.assertEqual(b["instances"][0]["compute_usd"], "0.057600")
        self.assertEqual(b["instances"][0]["volume_usd"], "0.001333")
        self.assertEqual(b["variable_compute_usd"], "0.058933")
        # 420/3600 x 0.0397 = 0.004632 ; 20 x 420 x 0.08 / 2592000 = 0.000259
        self.assertEqual(o["instances"][0]["compute_usd"], "0.004632")
        self.assertEqual(o["variable_compute_usd"], "0.004891")
        p = cc.pairs([run("baseline", "P1", inst("on-demand", "2026-11-29T01:00:00Z", "2026-11-29T01:36:00Z")),
                      run("optimized", "P1", inst("spot", "2026-11-29T02:00:00Z", "2026-11-29T02:07:00Z"))])
        self.assertEqual(p["saving_ratio"], "0.9170")
        self.assertEqual(p["h5_decision"], "INCONCLUSIVE")  # one pair < 5


class Contract(unittest.TestCase):
    def test_spot_price_change_inside_run_is_integrated(self):
        prices = dict(PRICES, spot=[
            {"instance_type": "m5.large", "zone": "zone-a", "from_utc": "2026-11-29T00:00:00Z", "usd_per_hour": "0.0360"},
            {"instance_type": "m5.large", "zone": "zone-a", "from_utc": "2026-11-29T01:30:00Z", "usd_per_hour": "0.0720"},
            {"instance_type": "m5.large", "zone": "zone-b", "from_utc": "2026-11-29T00:00:00Z", "usd_per_hour": "9.9"},
        ])
        r = cc.run_cost(run("optimized", "P2", inst("spot", "2026-11-29T01:00:00Z", "2026-11-29T02:00:00Z", gb=0), prices))
        segs = r["instances"][0]["price_segments"]
        self.assertEqual([(s["seconds"], s["usd_per_hour"]) for s in segs], [(1800.0, "0.0360"), (1800.0, "0.0720")])
        self.assertEqual(r["variable_compute_usd"], "0.054000")  # 0.5 x 0.036 + 0.5 x 0.072, zone-b ignored

    def test_run_under_one_minute_bills_sixty_seconds(self):
        r = cc.run_cost(run("optimized", "P3", inst("on-demand", "2026-11-29T01:00:00Z", "2026-11-29T01:00:40Z", gb=0)))
        i = r["instances"][0]
        self.assertEqual((i["observed_seconds"], i["billed_seconds"], i["minimum_applied"]), (40.0, 60, True))
        self.assertEqual(i["compute_usd"], "0.001600")  # 60/3600 x 0.096

    def test_partial_second_rounds_up(self):
        r = cc.run_cost(run("baseline", "P4", inst("on-demand", "2026-11-29T01:00:00Z", "2026-11-29T01:10:00.400Z", gb=0)))
        self.assertEqual(r["instances"][0]["billed_seconds"], 601)

    def test_missing_termination_is_refused(self):
        with self.assertRaises(cc.Refused):
            cc.run_cost(run("baseline", "P5", inst("on-demand", "2026-11-29T01:00:00Z", None)))

    def test_missing_price_and_uncovered_spot_history_are_refused(self):
        with self.assertRaises(cc.Refused):
            cc.run_cost(run("baseline", "P6", inst("on-demand", "2026-11-29T01:00:00Z", "2026-11-29T02:00:00Z"),
                            dict(PRICES, on_demand={})))
        with self.assertRaises(cc.Refused):  # history starts after the launch
            cc.run_cost(run("optimized", "P6", inst("spot", "2026-11-28T23:00:00Z", "2026-11-29T01:00:00Z")))
        with self.assertRaises(cc.Refused):  # no history for this zone
            cc.run_cost(run("optimized", "P6", inst("spot", "2026-11-29T01:00:00Z", "2026-11-29T02:00:00Z", zone="zone-c")))
        with self.assertRaises(cc.Refused):
            cc.run_cost({"run_id": "empty", "instances": []})

    def test_pending_billing_is_never_zero(self):
        rec = cc.reconcile(Decimal("0.5"), None)
        self.assertEqual(rec["status"], "PENDING")
        self.assertIsNone(rec["billed_usd"])
        self.assertEqual(cc.reconcile(Decimal("0.5"), {"status": "PENDING", "usd": 0})["status"], "PENDING")

    def test_tolerance_is_five_percent_or_two_cents(self):
        self.assertEqual(cc.reconcile(Decimal("0.10"), {"status": "READ", "usd": "0.12"})["status"], "WITHIN_TOLERANCE")
        self.assertEqual(cc.reconcile(Decimal("0.10"), {"status": "READ", "usd": "0.13"})["status"], "NEEDS_REGISTERED_CAUSE")
        self.assertEqual(cc.reconcile(Decimal("1.00"), {"status": "READ", "usd": "1.05"})["status"], "WITHIN_TOLERANCE")
        self.assertEqual(cc.reconcile(Decimal("1.00"), {"status": "READ", "usd": "1.07"})["status"], "NEEDS_REGISTERED_CAUSE")

    def test_window_keeps_fixed_categories_apart(self):
        w = cc.window_cost({"window_id": "W-SYN", "synthetic": True,
                            "fixed": [
                                {"name": "EKS control plane", "category": "cluster_fixed", "quantity": 1, "hours": 2, "usd_per_unit_hour": "0.10"},
                                {"name": "system nodes m6i.large", "category": "cluster_fixed", "quantity": 2, "hours": 2, "usd_per_unit_hour": "0.096"},
                                {"name": "RDS db.t4g.micro", "category": "data_storage", "quantity": 1, "hours": 2, "usd_per_unit_hour": "0.016"},
                                {"name": "public IPv4", "category": "network", "quantity": 2, "hours": 2, "usd_per_unit_hour": "0.005"}],
                            "runs": [run("optimized", "P1", inst("spot", "2026-11-29T02:00:00Z", "2026-11-29T02:07:00Z"))],
                            "billed_total": {"status": "PENDING"}})
        c = w["by_category_usd"]
        self.assertEqual((c["cluster_fixed"], c["data_storage"], c["network"], c["variable_compute"]),
                         ("0.584000", "0.032000", "0.020000", "0.004891"))
        self.assertEqual(w["computed_total_usd"], "0.640891")
        self.assertEqual(w["reconciliation_total"]["status"], "PENDING")
        with self.assertRaises(cc.Refused):
            cc.window_cost({"fixed": [{"name": "x", "category": "variable_compute", "quantity": 1, "hours": 1, "usd_per_unit_hour": 1}]})

    def test_h5_decision_needs_five_pairs(self):
        docs = []
        for k in range(5):
            docs += [run("baseline", f"P{k}", inst("on-demand", "2026-11-29T01:00:00Z", "2026-11-29T01:36:00Z")),
                     run("optimized", f"P{k}", inst("spot", "2026-11-29T02:00:00Z", "2026-11-29T02:07:00Z"))]
        self.assertEqual(cc.pairs(docs)["h5_decision"], "PASS")
        self.assertEqual(cc.pairs(docs[:8] + docs[9:])["pairs_incomplete"], ["P4"])
        with self.assertRaises(cc.Refused):
            cc.pairs(docs + [docs[0]])

    def test_cli_exit_codes(self):
        import json
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            ok, bad = os.path.join(d, "ok.json"), os.path.join(d, "bad.json")
            with open(ok, "w") as f:
                json.dump(run("baseline", "P1", inst("on-demand", "2026-11-29T01:00:00Z", "2026-11-29T01:36:00Z")), f)
            with open(bad, "w") as f:
                json.dump(run("baseline", "P1", inst("on-demand", "2026-11-29T01:00:00Z", None)), f)
            self.assertEqual(cc.main(["run", ok]), 0)
            self.assertEqual(cc.main(["run", bad]), 4)


if __name__ == "__main__":
    unittest.main()
