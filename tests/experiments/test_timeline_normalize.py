"""SYNTHETIC tests for experiments/lib/timeline_normalize.py and its hand-off to
cost_calc.py (SPEC-P7 T3). Instance ids, zones and prices are invented.
Run: python -I -m unittest discover -s tests/experiments -v
"""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "experiments", "lib"))
import cost_calc as cc  # noqa: E402
import timeline_normalize as tn  # noqa: E402

ID_BATCH, ID_SYS, ID_OLD, ID_INT = "i-0aaaaaaaaaaaaaaa1", "i-0bbbbbbbbbbbbbbb2", "i-0ccccccccccccccc3", "i-0ddddddddddddddd4"


def instance(iid, itype, launch, state, reason, tags, spot=False, zone="zone-a"):
    i = {"InstanceId": iid, "InstanceType": itype, "LaunchTime": launch, "State": {"Name": state},
         "StateTransitionReason": reason, "Placement": {"AvailabilityZone": zone},
         "Tags": [{"Key": k, "Value": v} for k, v in tags.items()],
         "PrivateIpAddress": "10.9.9.9"}
    if spot:
        i["InstanceLifecycle"] = "spot"
    return i


def write_raw(d, instances):
    with open(os.path.join(d, "instances.json"), "w") as f:
        json.dump({"Reservations": [{"Instances": instances}]}, f)
    with open(os.path.join(d, "spot_history.json"), "w") as f:
        json.dump({"m5.large|zone-a": {"SpotPriceHistory": [
            {"InstanceType": "m5.large", "AvailabilityZone": "zone-a", "Timestamp": "2026-11-28T20:00:00+00:00", "SpotPrice": "0.039700"}]}}, f)
    with open(os.path.join(d, "on_demand.json"), "w") as f:
        json.dump({"m6i.large": {"PriceList": [json.dumps({"terms": {"OnDemand": {"T": {"priceDimensions": {
            "D": {"unit": "Hrs", "pricePerUnit": {"USD": "0.0960000000"}}}}}}})]}}, f)
    with open(os.path.join(d, "k8s_events.json"), "w") as f:
        json.dump({"items": [
            {"involvedObject": {"kind": "NodeClaim", "name": "batch-spot-x"}, "reason": "Launched", "type": "Normal",
             "lastTimestamp": "2026-11-29T02:00:20Z", "message": f"launched {ID_BATCH} at 10.9.9.9"},
            {"involvedObject": {"kind": "Pod", "name": "p"}, "reason": "Scheduled", "lastTimestamp": "2026-11-29T02:01:00Z"}]}, f)


BASE = [
    instance(ID_BATCH, "m5.large", "2026-11-29T02:00:00+00:00", "terminated",
             "User initiated (2026-11-29 02:07:00 GMT)", {"Project": "Zero-D-Rift", "karpenter.sh/nodepool": "batch-spot"}, spot=True),
    instance(ID_SYS, "m6i.large", "2026-11-29T00:30:00.000Z", "running", "",
             {"Project": "Zero-D-Rift", "eks:nodegroup-name": "system"}),
    instance(ID_OLD, "m5.large", "2026-11-28T10:00:00+00:00", "terminated",
             "User initiated (2026-11-28 11:00:00 GMT)", {"Project": "Zero-D-Rift", "karpenter.sh/nodepool": "batch-spot"}, spot=True),
]


class Normalize(unittest.TestCase):
    def run_main(self, instances, extra=()):
        raw, out = tempfile.mkdtemp(), tempfile.mkdtemp()
        write_raw(raw, instances)
        rc = tn.main(["--raw", raw, "--out", out, "--start", "2026-11-29T01:00:00Z", "--end", "2026-11-29T03:00:00Z",
                      "--run-id", "SYN-1", "--arm", "optimized", "--pair-id", "P1", "--synthetic", *extra])
        return rc, out

    def test_aliases_roles_and_window(self):
        rc, out = self.run_main(BASE)
        self.assertEqual(rc, 0)
        with open(os.path.join(out, "timeline", "instances.json")) as f:
            inst = json.load(f)["instances"]
        self.assertEqual(sorted(x["alias"] for x in inst), ["batch-1", "system-1"])  # ID_OLD is outside the window
        b = next(x for x in inst if x["alias"] == "batch-1")
        self.assertEqual((b["capacity_type"], b["launch_utc"], b["termination_utc"]),
                         ("spot", "2026-11-29T02:00:00Z", "2026-11-29T02:07:00Z"))
        s = next(x for x in inst if x["alias"] == "system-1")
        self.assertIsNone(s["termination_utc"])

    def test_no_identifier_in_any_output(self):
        rc, out = self.run_main(BASE)
        blob = ""
        for d, _, fs in os.walk(out):
            for f in fs:
                with open(os.path.join(d, f), encoding="utf-8") as h:
                    blob += h.read()
        for bad in (ID_BATCH, ID_SYS, "10.9.9.9", "batch-spot-x launched"):
            self.assertNotIn(bad, blob)

    def test_events_follow_the_event_shape(self):
        rc, out = self.run_main(BASE)
        with open(os.path.join(out, "timeline", "events.jsonl")) as f:
            evs = [json.loads(x) for x in f]
        keys = {"schema_version", "run_id", "event_at_utc", "event_type", "source", "status", "evidence_ref", "synthetic"}
        self.assertTrue(all(set(e) == keys for e in evs))
        self.assertEqual([e["event_type"] for e in evs][:3], ["ec2_launch", "ec2_launch", "k8s_nodeclaim_launched"])
        self.assertTrue(all(e["synthetic"] for e in evs))

    def test_pipeline_into_cost_calc(self):
        rc, out = self.run_main(BASE)
        with open(os.path.join(out, "cost", "cost_input.json")) as f:
            doc = json.load(f)
        self.assertEqual([i["alias"] for i in doc["instances"]], ["batch-1"])  # roles=batch only
        r = cc.run_cost(doc)
        self.assertEqual(r["variable_compute_usd"], "0.004891")  # same as the micro-lab optimized arm

    def test_spot_interruption_without_time_is_refused_downstream(self):
        inst = [instance(ID_INT, "m5.large", "2026-11-29T02:00:00Z", "terminated",
                         "Service initiated", {"Project": "Zero-D-Rift", "karpenter.sh/nodepool": "batch-spot"}, spot=True)]
        rc, out = self.run_main(inst)
        self.assertEqual(rc, 0)
        with open(os.path.join(out, "cost", "cost_input.json")) as f:
            doc = json.load(f)
        self.assertIsNone(doc["instances"][0]["termination_utc"])
        with self.assertRaises(cc.Refused):
            cc.run_cost(doc)

    def test_on_demand_price_parsed_from_price_list(self):
        rc, out = self.run_main(BASE, extra=("--roles", "system"))
        with open(os.path.join(out, "cost", "cost_input.json")) as f:
            doc = json.load(f)
        self.assertEqual(doc["prices"]["on_demand"]["m6i.large"]["usd_per_hour"], "0.0960000000")
        with self.assertRaises(cc.Refused):  # the system node is still running
            cc.run_cost(doc)


if __name__ == "__main__":
    unittest.main()
