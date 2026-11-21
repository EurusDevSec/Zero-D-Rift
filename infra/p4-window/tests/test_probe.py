"""Negative tests for probe.py (Codex review C2, DRF-57).

A secret without username/password must not count as read, and only a timeout
counts as "no IMDS token". Run: bash infra/p4-window/tests/run_probe_tests.sh
"""
import socket
import sys
import urllib.error
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path[:0] = [str(ROOT / "workloads/rag-sandbox/src"), str(ROOT / "infra/p4-window")]
import probe  # noqa: E402


class Store:
    def __init__(self, value):
        self.value = value

    def get(self, name):
        return self.value


@pytest.fixture(autouse=True)
def fresh(monkeypatch):
    probe.failed.clear()
    monkeypatch.setattr(probe, "BUCKETS", False)


@pytest.mark.parametrize("value", [{}, {"username": "u"}, {"password": "p"}, {"username": "", "password": "p"}])
@pytest.mark.parametrize("cmd", ["platform", "sandbox"])
def test_incomplete_secret_fails(monkeypatch, capsys, value, cmd):
    monkeypatch.setattr(probe, "store", lambda: Store(value))
    monkeypatch.setattr(probe.db, "connect", lambda *a, **k: pytest.fail("must not connect"))
    rc = probe.main(["platform"] if cmd == "platform" else ["sandbox", "tenant-a", "docs-qa"])
    out = capsys.readouterr().out
    assert rc == 1, out
    assert "RESULT: FAIL" in out and "no username/password" in out


def test_missing_secret_fails(monkeypatch, capsys):
    monkeypatch.setattr(probe, "store", lambda: Store(None))
    assert probe.main(["sandbox", "tenant-a", "docs-qa"]) == 1
    assert "not found" in capsys.readouterr().out


@pytest.mark.parametrize(
    "exc, ok",
    [
        (TimeoutError("timed out"), True),
        (socket.timeout("timed out"), True),
        (urllib.error.URLError(TimeoutError("timed out")), True),
        (urllib.error.URLError(ConnectionRefusedError(111, "refused")), False),
        (urllib.error.URLError(socket.gaierror(-2, "Name or service not known")), False),
        (OSError("network unreachable"), False),
        (ValueError("bug"), False),
    ],
)
def test_imds_counts_only_a_timeout(exc, ok):
    assert probe.imds_timed_out(exc) is ok
