import json

from batchtraining import submit
from batchtraining.runkey import parse_body

from conftest import BUCKET, QUEUE


def test_first_submit_sends_one_message_and_marks(store, s3, sqs, key):
    assert submit.run(key, 300, store, sqs, QUEUE) == 0
    assert [parse_body(b) for b in sqs.sent] == [(key, 300)]
    assert s3.keys(BUCKET) == ["runs/demo/1/submit-started", "runs/demo/1/submitted"]


def test_duplicate_submit_sends_nothing(store, sqs, key):
    submit.run(key, 300, store, sqs, QUEUE)
    assert submit.run(key, 300, store, sqs, QUEUE) == 0
    assert len(sqs.sent) == 1


def test_crash_between_send_and_marker_keeps_first_mark(store, s3, sqs, key, capsys):
    submit.run(key, 300, store, sqs, QUEUE)
    first = s3.body(BUCKET, "runs/demo/1/submit-started")
    del s3.objects[(BUCKET, "runs/demo/1/submitted")]  # the crash: sent, never marked
    assert submit.run(key, 300, store, sqs, QUEUE) == 0
    assert len(sqs.sent) == 2  # a duplicate with the same run key; train absorbs it
    assert s3.body(BUCKET, "runs/demo/1/submit-started") == first
    assert '"first_write": false' in capsys.readouterr().out


def test_other_attempt_marker_does_not_count(store, sqs, key):
    from batchtraining.runkey import RunKey

    submit.run(RunKey.of("tenant-a", "demo", 2), 300, store, sqs, QUEUE)
    assert submit.run(key, 300, store, sqs, QUEUE) == 0
    assert len(sqs.sent) == 2


def test_read_failure_is_not_absent(s3, sqs, key, capsys):
    from batchtraining.store import Store

    for code in ("AccessDenied", "TIMEOUT"):
        s3.fail["ListObjectsV2"] = code
        assert submit.run(key, 300, Store(s3, BUCKET), sqs, QUEUE) == submit.EXIT_READ_FAILED
        line = json.loads(capsys.readouterr().out.strip().splitlines()[-1])
        assert line["event"] == "READ_FAILED"
    assert sqs.sent == [] and s3.objects == {}


def test_submit_uses_list_only_never_get(store, s3, sqs, key):
    submit.run(key, 300, store, sqs, QUEUE)
    assert "GetObject" not in s3.calls and "HeadObject" not in s3.calls


def test_send_failure_leaves_no_submitted(store, s3, sqs, key):
    sqs.fail["SendMessage"] = "InternalError"
    assert submit.run(key, 300, store, sqs, QUEUE) == 1
    assert s3.keys(BUCKET) == ["runs/demo/1/submit-started"]
