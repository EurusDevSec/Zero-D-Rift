import json
import urllib.error

import pytest

from batchtraining import __main__ as cli
from batchtraining import cleanup, probe
from batchtraining.runkey import RunKey, message_body

from conftest import BUCKET, QUEUE
from fakes import FAKE_ACCOUNT, FakeS3, FakeSTS


def test_cleanup_deletes_only_this_request(sqs, capsys):
    for attempt in (1, 2):
        sqs.send_message(QueueUrl=QUEUE, MessageBody=message_body(RunKey.of("tenant-a", "demo", attempt), 10))
    sqs.send_message(QueueUrl=QUEUE, MessageBody=message_body(RunKey.of("tenant-b", "demo", 1), 10))
    sqs.send_message(QueueUrl=QUEUE, MessageBody="garbage")
    assert cleanup.run("tenant-a", "demo", sqs, QUEUE, wait_seconds=0, max_rounds=3) in (0, 1)
    left = [json.loads(m["body"]) if m["body"].startswith("{") else m["body"] for m in sqs.messages]
    assert len(sqs.deleted) == 2
    assert {"tenant": "tenant-b", "requestId": "demo", "runAttempt": 1, "steps": 10} in left
    assert "garbage" in left


def test_cleanup_empty_queue_is_complete(sqs, capsys):
    assert cleanup.run("tenant-a", "demo", sqs, QUEUE, wait_seconds=0) == 0
    assert json.loads(capsys.readouterr().out)["complete"] is True


def test_cleanup_read_failure(sqs):
    sqs.fail["ReceiveMessage"] = "AccessDenied"
    assert cleanup.run("tenant-a", "demo", sqs, QUEUE, wait_seconds=0) == cleanup.EXIT_READ_FAILED


def test_role_name_from_arn():
    assert probe.role_name_from_arn("arn:aws:sts::1:assumed-role/r-a/sess") == "r-a"
    assert probe.role_name_from_arn("arn:aws:iam::1:user/bob") == ""
    assert probe.role_name_from_arn("garbage") == ""


def test_probe_match_then_get(capsys):
    s3 = FakeS3()
    s3.put_object(Bucket=BUCKET, Key="k", Body=b"x")
    assert probe.s3("s3-get", FakeSTS("zero-drift-batch-tenant-a"), s3, "zero-drift-batch-tenant-a", BUCKET, "k") == 0
    out = capsys.readouterr().out
    assert out == "caller_role_match=true\naction=s3-get\noutcome=ok\n"


def test_probe_denied_prints_code_only(capsys):
    s3 = FakeS3(fail={"GetObject": "AccessDenied", "PutObject": "AccessDenied"})
    for action in ("s3-get", "s3-put"):
        probe.s3(action, FakeSTS("zero-drift-batch-tenant-b"), s3, "zero-drift-batch-tenant-b", BUCKET, "k")
    out = capsys.readouterr().out
    assert out.count("code=AccessDenied") == 2
    assert FAKE_ACCOUNT not in out and "arn:" not in out


def test_probe_mismatch_stops_before_s3(capsys):
    s3 = FakeS3()
    rc = probe.s3("s3-get", FakeSTS("some-node-role"), s3, "zero-drift-batch-tenant-a", BUCKET, "k")
    assert rc == probe.EXIT_CALLER_MISMATCH and s3.calls == []
    assert capsys.readouterr().out == "caller_role_match=false\n"


def test_probe_sts_failure(capsys):
    rc = probe.s3("s3-head", FakeSTS(fail="AccessDenied"), FakeS3(), "r", BUCKET, "k")
    assert rc == probe.EXIT_CALLER_UNKNOWN
    assert "caller_role_match=READ_FAILED" in capsys.readouterr().out


def test_conditional_write_check_passes_on_fake(capsys):
    assert probe.s3_conditional(FakeS3(), BUCKET, "probe") == 0
    out = capsys.readouterr().out
    assert "conditional_second=412:PreconditionFailed" in out and "conditional_write=PASS" in out


def test_conditional_write_check_fails_when_overwritten(capsys):
    class NoConditional(FakeS3):
        def put_object(self, Bucket, Key, Body, IfNoneMatch=None, ContentType=None):
            return super().put_object(Bucket, Key, Body)

    probe.s3_conditional(NoConditional(), BUCKET, "probe")
    assert "conditional_write=FAIL" in capsys.readouterr().out


class _Resp:
    def __init__(self, body):
        self.body = body

    def read(self):
        return self.body

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


@pytest.mark.parametrize("opener,expected", [
    (lambda req, timeout: _Resp(b"SECRET-TOKEN"), "outcome=obtained"),
    (lambda req, timeout: (_ for _ in ()).throw(urllib.error.URLError(TimeoutError())), "outcome=denied"),
    (lambda req, timeout: (_ for _ in ()).throw(
        urllib.error.HTTPError("u", 401, "x", {}, None)), "code=HTTP401"),
])
def test_imds_outcome_without_token(opener, expected, capsys):
    assert probe.imds(opener=opener) == 0
    out = capsys.readouterr().out
    assert expected in out and "SECRET-TOKEN" not in out


@pytest.mark.parametrize("env", [
    {},
    {"TENANT": "tenant-a", "REQUEST_ID": "demo", "QUEUE_URL": "q", "BUCKET": "b", "HEARTBEAT_SECONDS": "120"},
    {"TENANT": "tenant-a", "REQUEST_ID": "demo", "QUEUE_URL": "q", "BUCKET": "b", "FAIL_PROFILE": "sometimes"},
    {"TENANT": "Tenant A", "REQUEST_ID": "demo", "QUEUE_URL": "q", "BUCKET": "b"},
])
def test_train_config_rejects(env):
    assert cli.main(["train"], env=env) == 2


def test_submit_rejects_steps_out_of_range():
    env = {"TENANT": "tenant-a", "REQUEST_ID": "demo", "RUN_ATTEMPT": "1", "STEPS": "5000",
           "BUCKET": "b", "QUEUE_URL": "q"}
    assert cli.main(["submit"], env=env) == 2


def test_train_config_defaults():
    c = cli.train_config({"TENANT": "tenant-a", "REQUEST_ID": "demo", "QUEUE_URL": "q"})
    assert (c.checkpoint_every, c.heartbeat_seconds, c.visibility_timeout, c.run_attempt) == (25, 40.0, 120, None)


def test_probe_s3_needs_expected_role_on_aws():
    assert cli.main(["probe", "s3-get", "--bucket", "b", "--key", "k"], env={}) == 2
    assert cli.main(["probe", "s3-conditional", "--bucket", "b"], env={}) == 2


def test_path_style_only_with_endpoint():
    from batchtraining import aws

    lab = aws.s3_client({"AWS_REGION": "us-east-1", "S3_ENDPOINT_URL": "http://s3mock:9090",
                         "AWS_ACCESS_KEY_ID": "lab", "AWS_SECRET_ACCESS_KEY": "lab"})
    real = aws.s3_client({"AWS_REGION": "us-east-1"})
    assert lab.meta.config.s3["addressing_style"] == "path"
    assert not (real.meta.config.s3 or {}).get("addressing_style")
