import json

import pytest

from batchtraining.runkey import InvalidRunKey, RunKey, message_body, parse_body, parse_steps


def test_prefix_and_keys():
    k = RunKey.of("tenant-a", "demo", "2")
    assert str(k) == "tenant-a/demo/2"
    assert k.prefix == "runs/demo/2/"
    assert k.received(3) == "runs/demo/2/RECEIVED-3"
    assert k.checkpoint(25) == "runs/demo/2/ckpt/step-000025.json"


@pytest.mark.parametrize("tenant,rid,attempt", [
    ("Tenant-A", "demo", 1), ("tenant-a", "../x", 1), ("tenant-a", "demo/1", 1),
    ("tenant-a", "", 1), ("tenant-a", "demo", 0), ("tenant-a", "demo", 10000),
    ("tenant-a", "demo", "1.0"), ("tenant-a", "demo", True), ("tenant-a", "-demo", 1),
])
def test_rejects_out_of_contract(tenant, rid, attempt):
    with pytest.raises(InvalidRunKey):
        RunKey.of(tenant, rid, attempt)


@pytest.mark.parametrize("steps", [0, 1001, "abc", -5, "10.5", None])
def test_steps_range(steps):
    with pytest.raises(InvalidRunKey):
        parse_steps(steps)


def test_body_round_trip_identifiers_only():
    k = RunKey.of("tenant-b", "req-7", 3)
    body = message_body(k, 300)
    assert set(json.loads(body)) == {"requestId", "tenant", "runAttempt", "steps"}
    assert parse_body(body) == (k, 300)


@pytest.mark.parametrize("body", ["not json", "[]", '{"tenant":"a"}',
                                  '{"tenant":"a","requestId":"b","runAttempt":1,"steps":5000}'])
def test_bad_bodies(body):
    with pytest.raises(InvalidRunKey):
        parse_body(body)
