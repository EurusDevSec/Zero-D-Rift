import json
import threading

from batchtraining import submit, train
from batchtraining.runkey import RunKey, message_body
from batchtraining.store import Store

from conftest import BUCKET, QUEUE, StopAfter, cfg
from fakes import FAKE_ACCOUNT

P = "runs/demo/1/"


def send(sqs, key, steps=100):
    sqs.send_message(QueueUrl=QUEUE, MessageBody=message_body(key, steps))


def events(out: str) -> list[dict]:
    return [json.loads(line) for line in out.splitlines() if line.startswith("{")]


def artifact(s3):
    return json.loads(s3.body(BUCKET, P + "artifact/model.json"))


def test_happy_path_markers_and_delete(store, s3, sqs, key, capsys):
    send(sqs, key)
    assert train.run(cfg(pod_name="pod-1", node_name="node-x"), store, sqs) == 0
    keys = s3.keys(BUCKET, P)
    assert P + "RECEIVED-1" in keys and P + "TRAINING_STARTED" in keys
    assert P + "SUCCEEDED" in keys and P + "MESSAGE_DELETED" in keys
    assert [k for k in keys if "/ckpt/" in k] == [P + "ckpt/step-000025.json", P + "ckpt/step-000050.json",
                                                    P + "ckpt/step-000075.json"]
    assert sqs.messages == []
    started = json.loads(s3.body(BUCKET, P + "TRAINING_STARTED"))
    assert started["device"] == "cpu" and started["node"] == "node-x" and started["resumed_from"] == 0
    assert "capacity" not in json.dumps(started) and "instance" not in json.dumps(started)
    ev = events(capsys.readouterr().out)
    assert [e["event"] for e in ev if e["event"] == "TRAINING_STARTED"] == ["TRAINING_STARTED"]
    assert artifact(s3)["accuracy"] > 0.8


def test_sigterm_checkpoints_and_leaves_message(store, s3, sqs, key, capsys):
    send(sqs, key)
    rc = train.run(cfg(step_seconds=1e-9), store, sqs, stop=StopAfter(60))
    assert rc == train.EXIT_SIGTERM
    assert P + "ckpt/step-000060.json" in s3.keys(BUCKET, P)
    assert P + "SUCCEEDED" not in s3.keys(BUCKET, P)
    assert len(sqs.messages) == 1 and sqs.deleted == []
    assert any(e["event"] == "SIGTERM_CHECKPOINT" and e["step"] == 60 for e in events(capsys.readouterr().out))


def test_resume_continues_from_checkpoint_and_matches_uninterrupted(s3, sqs, key, capsys):
    store = Store(s3, BUCKET)
    send(sqs, key)
    train.run(cfg(step_seconds=1e-9), store, sqs, stop=StopAfter(60))
    sqs.advance(121)  # visibility timeout passes, the message comes back
    assert train.run(cfg(), store, sqs) == 0
    out = capsys.readouterr().out
    assert "resumed from step 60" in out
    started = json.loads(s3.body(BUCKET, P + "TRAINING_STARTED"))
    assert started["resumed_from"] == 60
    assert len([k for k in s3.keys(BUCKET, P) if k.startswith(P + "artifact/")]) == 1
    assert json.loads(s3.body(BUCKET, P + "RECEIVED-2"))  # second receive recorded

    from fakes import FakeS3, FakeSQS

    s3b, sqsb = FakeS3(), FakeSQS()
    send(sqsb, key)
    train.run(cfg(), Store(s3b, BUCKET), sqsb)
    assert artifact(s3)["weights"] == artifact(s3b)["weights"]


def test_corrupt_newest_checkpoint_falls_back(store, s3, sqs, key, capsys):
    send(sqs, key)
    train.run(cfg(step_seconds=1e-9), store, sqs, stop=StopAfter(60))
    s3.objects[(BUCKET, P + "ckpt/step-000060.json")] = b"{broken"
    sqs.advance(121)
    assert train.run(cfg(), store, sqs) == 0
    assert "resumed from step 50" in capsys.readouterr().out


def test_double_delivery_is_already_done(store, s3, sqs, key, capsys):
    send(sqs, key)
    send(sqs, key)  # a duplicate submit
    assert train.run(cfg(), store, sqs) == 0
    capsys.readouterr()
    assert train.run(cfg(), store, sqs) == 0
    out = capsys.readouterr().out
    assert "ALREADY_DONE" in out and "TRAINING_STARTED" not in out
    assert sqs.messages == [] and len(sqs.deleted) == 2
    assert len([k for k in s3.keys(BUCKET, P) if "artifact/" in k]) == 1


def test_delete_failure_exits_nonzero_then_already_done(store, s3, sqs, key):
    send(sqs, key)
    sqs.fail["DeleteMessage"] = "InternalError"
    assert train.run(cfg(), store, sqs) == train.EXIT_DELETE_FAILED
    assert P + "SUCCEEDED" in s3.keys(BUCKET, P)
    assert P + "MESSAGE_DELETED" not in s3.keys(BUCKET, P)
    del sqs.fail["DeleteMessage"]
    sqs.advance(121)
    assert train.run(cfg(), store, sqs) == 0
    assert P + "MESSAGE_DELETED" in s3.keys(BUCKET, P) and sqs.messages == []


def test_foreign_message_is_released_not_deleted(store, s3, sqs):
    send(sqs, RunKey.of("tenant-b", "other", 1))
    assert train.run(cfg(), store, sqs) == train.EXIT_FOREIGN
    assert len(sqs.messages) == 1 and sqs.deleted == []
    assert sqs.messages[0]["visible_at"] == sqs.now  # visible again at once
    assert s3.objects == {}


def test_other_attempt_is_foreign_when_job_knows_its_attempt(store, sqs):
    send(sqs, RunKey.of("tenant-a", "demo", 1))
    assert train.run(cfg(run_attempt=2), store, sqs) == train.EXIT_FOREIGN


def test_malformed_message_released(store, sqs):
    sqs.send_message(QueueUrl=QUEUE, MessageBody="garbage")
    assert train.run(cfg(), store, sqs) == train.EXIT_FOREIGN
    assert len(sqs.messages) == 1


def test_fail_profile_records_every_receive(store, s3, sqs, key):
    send(sqs, key)
    for _ in range(3):
        assert train.run(cfg(profile="fail-always"), store, sqs) == train.EXIT_FAIL_PROFILE
    keys = s3.keys(BUCKET, P)
    assert [k for k in keys if "RECEIVED-" in k] == [P + "RECEIVED-1", P + "RECEIVED-2", P + "RECEIVED-3"]
    assert P + "SUCCEEDED" not in keys and P + "TRAINING_STARTED" not in keys


def test_heartbeat_extends_visibility(store, sqs, key):
    send(sqs, key)
    rc = train.run(cfg(step_seconds=0.002, heartbeat_seconds=0.01, checkpoint_every=1000),
                   store, sqs, stop=threading.Event())
    assert rc == 0
    assert 120 in sqs.visibility_calls


def test_no_message_exits_zero(store, sqs):
    assert train.run(cfg(), store, sqs) == 0


def test_receive_failure_is_read_failed(store, sqs):
    sqs.fail["ReceiveMessage"] = "AccessDenied"
    assert train.run(cfg(), store, sqs) == train.EXIT_READ_FAILED


def test_checkpoint_listing_failure_is_not_step_zero(store, s3, sqs, key):
    send(sqs, key)
    real = s3.list_objects_v2

    def flaky(**kw):
        if "/ckpt/" in kw["Prefix"]:
            raise __import__("fakes").client_error("AccessDenied", "ListObjectsV2")
        return real(**kw)

    s3.list_objects_v2 = flaky
    assert train.run(cfg(), store, sqs) == train.EXIT_READ_FAILED
    assert P + "TRAINING_STARTED" not in s3.keys(BUCKET, P) and len(sqs.messages) == 1


def test_submit_then_train_end_to_end(store, s3, sqs, key):
    assert submit.run(key, 50, store, sqs, QUEUE) == 0
    assert train.run(cfg(), store, sqs) == 0
    assert P + "SUCCEEDED" in s3.keys(BUCKET, P) and sqs.messages == []


def test_errors_never_print_arn_or_account(store, s3, sqs, key, capsys):
    send(sqs, key)
    s3.fail["PutObject"] = "AccessDenied"
    train.run(cfg(), store, sqs)
    sqs.fail["ReceiveMessage"] = "AccessDenied"
    train.run(cfg(), store, sqs)
    out = capsys.readouterr()
    text = out.out + out.err
    assert "AccessDenied" in text
    assert FAKE_ACCOUNT not in text and "arn:" not in text and QUEUE not in text
