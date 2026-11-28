"""SYNTHETIC unit tests for experiments/lib/export_redact.py (SPEC-P7 T2.2).

Every input here is invented; no value comes from a real cluster or account.
Run: python -I -m unittest discover -s tests/experiments -v
"""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "experiments", "lib"))
import export_redact as er  # noqa: E402

SALT = b"synthetic-test-salt"
NODE = "ip-10-1-2-3.us-west-2.compute.internal"  # SYNTHETIC
PROVIDER = "aws:///us-west-2a/i-0abc1234def567890"  # SYNTHETIC
ACCOUNT = "123456789012"  # SYNTHETIC


class RedactTest(unittest.TestCase):
    def setUp(self):
        self.r = er.Redactor(salt=SALT, node_names=[NODE], secrets_=[PROVIDER, "10.1.2.3"])

    def test_node_pseudonym_is_stable_and_joinable(self):
        a = self.r.walk({"node": NODE})["node"]
        b = self.r.walk({"label_kubernetes_io_hostname": NODE})["label_kubernetes_io_hostname"]
        c = self.r.scrub(f"pod on {NODE}")
        self.assertRegex(a, r"^node-[0-9a-f]{8}$")
        self.assertEqual(a, b)
        self.assertEqual(c, f"pod on {a}")

    def test_new_salt_gives_new_pseudonym(self):
        other = er.Redactor(salt=b"another-salt")
        self.assertNotEqual(self.r.pseudo(NODE), other.pseudo(NODE))

    def test_identifier_keys_are_dropped(self):
        out = self.r.walk({"provider_id": PROVIDER, "providerID": PROVIDER, "uid": "u-1",
                           "pod_ip": "10.1.2.3", "namespace": "tenant-a"})
        self.assertEqual(out, {"namespace": "tenant-a"})

    def test_strings_are_scrubbed(self):
        text = f"arn:aws:iam::{ACCOUNT}:role/x i-0abc1234def567890 10.9.8.7 acct {ACCOUNT}"
        out = self.r.scrub(text)
        for bad in ("arn:aws", ACCOUNT, "i-0abc", "10.9.8.7"):
            self.assertNotIn(bad, out)

    def test_sample_values_are_kept_and_not_scanned(self):
        rec = {"metric": {"namespace": "tenant-a"}, "values": [[1795856164, "123456789012"]]}
        self.assertEqual(self.r.walk(rec)["values"], rec["values"])
        self.assertEqual(list(er.leaks(rec)), [])

    def test_leak_scan_finds_leftovers(self):
        kinds = {k for _, k, _ in er.leaks({"a": "10.0.0.1", "b": [ACCOUNT], "c": "x i-0123456789abcdef0"})}
        self.assertEqual(kinds, {"ipv4", "account-id", "ec2-instance"})
        self.assertEqual([k for _, k, _ in er.leaks({"x": "kind-node-a"}, literals=["kind-node-a"])],
                         ["cluster-literal"])

    def test_eks_label_names_are_not_leaks(self):
        self.assertEqual(list(er.leaks({"label_eks_amazonaws_com_capacity_type": "SPOT"})), [])

    def test_versions_are_not_ipv4(self):
        self.assertEqual(list(er.leaks({"helm_sh_chart": "prometheus-30.0.1", "v": "1.121.5"})), [])


class EndToEndTest(unittest.TestCase):
    """main() on a SYNTHETIC raw folder: writes when clean, refuses when not."""

    def build(self, raw, metric):
        json.dump({"items": [{"metadata": {"name": NODE}, "spec": {"providerID": PROVIDER},
                              "status": {"addresses": [{"type": "InternalIP", "address": "10.1.2.3"}]}}]},
                  open(os.path.join(raw, "nodes.json"), "w"))
        json.dump({"status": "success", "data": {"result": [{"metric": metric, "values": [[1, "0.5"]]}]}},
                  open(os.path.join(raw, "q.json"), "w"))
        json.dump({"code": 200, "data": [{"tenant-a": {"properties": {"node": NODE, "providerID": PROVIDER},
                                                       "totalCost": 0.01}}]},
                  open(os.path.join(raw, "a.json"), "w"))
        meta = {"run_id": "SYNTHETIC-1", "synthetic": True, "official": False,
                "window": {"start_utc": "2026-01-01T00:00:00Z", "end_utc": "2026-01-01T00:10:00Z", "step_s": 30},
                "exported_at_utc": "2026-01-01T00:11:00Z",
                "queries": [{"name": "q", "promql": "up", "raw": "q.json"}],
                "allocations": [{"aggregate": "namespace", "raw": "a.json"}]}
        json.dump(meta, open(os.path.join(raw, "meta.json"), "w"))

    def run_main(self, metric):
        with tempfile.TemporaryDirectory() as raw, tempfile.TemporaryDirectory() as out:
            self.build(raw, metric)
            rc = er.main(["--raw", raw, "--out", out, "--meta", os.path.join(raw, "meta.json")])
            written = sorted(os.path.relpath(os.path.join(d, f), out).replace("\\", "/")
                             for d, _, fs in os.walk(out) for f in fs)
            blob = "".join(open(os.path.join(out, w), encoding="utf-8").read() for w in written)
            return rc, written, blob

    def test_clean_export_is_written_without_identifiers(self):
        rc, written, blob = self.run_main({"node": NODE, "instance": "10.1.2.3:9100", "namespace": "tenant-a"})
        self.assertEqual(rc, 0)
        self.assertEqual(written, ["export_manifest.json", "opencost/allocation_namespace.json", "prometheus/q.jsonl"])
        for bad in (NODE, "10.1.2.3", "i-0abc", "us-west-2a/i-"):
            self.assertNotIn(bad, blob)
        self.assertIn('"synthetic":true', blob.replace(" ", ""))

    def test_failed_query_stops_the_export(self):
        with tempfile.TemporaryDirectory() as raw, tempfile.TemporaryDirectory() as out:
            self.build(raw, {})
            json.dump({"status": "error", "error": "bad"}, open(os.path.join(raw, "q.json"), "w"))
            with self.assertRaises(SystemExit):
                er.main(["--raw", raw, "--out", out, "--meta", os.path.join(raw, "meta.json")])
            self.assertEqual(os.listdir(out), [])


if __name__ == "__main__":
    unittest.main()
