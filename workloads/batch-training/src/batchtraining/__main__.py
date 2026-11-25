"""``python -m batchtraining <command>``.

Commands (one image, SPEC-P6 P6-T2.1):

``submit``   env TENANT, REQUEST_ID, RUN_ATTEMPT, STEPS, BUCKET, QUEUE_URL
``train``    env TENANT, REQUEST_ID, BUCKET, QUEUE_URL; optional RUN_ATTEMPT,
             FAIL_PROFILE (normal|fail-always), CHECKPOINT_EVERY (25),
             STEP_SECONDS (1.0), HEARTBEAT_SECONDS (40), VISIBILITY_TIMEOUT (120),
             POD_NAME and NODE_NAME (downward API)
``cleanup``  env TENANT, REQUEST_ID, QUEUE_URL
``probe``    ``s3-head|s3-get|s3-put --bucket B --key K --expect-role R``,
             ``s3-conditional --bucket B --prefix P [--expect-role R]``, ``imds``

Common env: AWS_REGION; S3_ENDPOINT_URL / SQS_ENDPOINT_URL for the kind lab only
(path-style S3 when set). The queue URL holds the account ID and is never printed.

Exit codes: 0 success, 1 failure, 2 invalid input or a failed read
(``READ_FAILED``), 3 foreign or malformed message released, 4 probe caller
mismatch, 5 fail profile, 6 message delete failed, 143 SIGTERM after checkpoint.
"""

from __future__ import annotations

import argparse
import os
import signal
import sys
import threading
from collections.abc import Mapping

from . import aws, cleanup, probe, submit, train
from .log import emit, error_code
from .runkey import InvalidRunKey, RunKey, parse_steps
from .store import Store


class ConfigError(ValueError):
    pass


def _req(env: Mapping[str, str], name: str) -> str:
    value = env.get(name, "").strip()
    if not value:
        raise ConfigError(f"{name} is required")
    return value


def _num(env: Mapping[str, str], name: str, default: str, cast=float, minimum: float = 0):
    try:
        value = cast(env.get(name, default) or default)
    except ValueError:
        raise ConfigError(f"{name} must be a number") from None
    if value < minimum:
        raise ConfigError(f"{name} must be >= {minimum}")
    return value


def train_config(env: Mapping[str, str]) -> train.TrainConfig:
    tenant, request_id = _req(env, "TENANT"), _req(env, "REQUEST_ID")
    attempt = env.get("RUN_ATTEMPT", "").strip()
    key = RunKey.of(tenant, request_id, attempt or 1)
    profile = env.get("FAIL_PROFILE", "normal").strip() or "normal"
    if profile not in train.PROFILES:
        raise ConfigError(f"FAIL_PROFILE must be one of {', '.join(train.PROFILES)}")
    heartbeat = _num(env, "HEARTBEAT_SECONDS", "40", float, 1)
    visibility = _num(env, "VISIBILITY_TIMEOUT", "120", int, 1)
    if heartbeat >= visibility:
        raise ConfigError("HEARTBEAT_SECONDS must be shorter than VISIBILITY_TIMEOUT")
    return train.TrainConfig(
        tenant=key.tenant,
        request_id=key.request_id,
        queue_url=_req(env, "QUEUE_URL"),
        run_attempt=key.run_attempt if attempt else None,
        profile=profile,
        checkpoint_every=_num(env, "CHECKPOINT_EVERY", "25", int, 1),
        step_seconds=_num(env, "STEP_SECONDS", "1.0", float, 0),
        heartbeat_seconds=heartbeat,
        visibility_timeout=visibility,
        pod_name=env.get("POD_NAME", ""),
        node_name=env.get("NODE_NAME", ""),
    )


def main(argv: list[str] | None = None, env: Mapping[str, str] | None = None) -> int:
    env = os.environ if env is None else env
    parser = argparse.ArgumentParser(prog="batchtraining")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("submit", help="send one message for a run attempt")
    sub.add_parser("train", help="receive one message and train")
    sub.add_parser("cleanup", help="delete leftover messages of one request")
    p = sub.add_parser("probe", help="one S3 or IMDS call, outcome only")
    p.add_argument("action", choices=[*probe.S3_ACTIONS, "s3-conditional", "imds"])
    p.add_argument("--bucket")
    p.add_argument("--key")
    p.add_argument("--prefix", default="probe")
    p.add_argument("--expect-role", default="")
    args = parser.parse_args(argv)

    try:
        if args.command == "submit":
            key = RunKey.of(_req(env, "TENANT"), _req(env, "REQUEST_ID"), _req(env, "RUN_ATTEMPT"))
            steps = parse_steps(env.get("STEPS", "300"))
            store = Store(aws.s3_client(env), _req(env, "BUCKET"))
            return submit.run(key, steps, store, aws.sqs_client(env), _req(env, "QUEUE_URL"))

        if args.command == "train":
            cfg = train_config(env)
            store = Store(aws.s3_client(env), _req(env, "BUCKET"))
            stop = threading.Event()
            signal.signal(signal.SIGTERM, lambda *_: stop.set())
            return train.run(cfg, store, aws.sqs_client(env), stop)

        if args.command == "cleanup":
            key = RunKey.of(_req(env, "TENANT"), _req(env, "REQUEST_ID"), 1)
            return cleanup.run(key.tenant, key.request_id, aws.sqs_client(env), _req(env, "QUEUE_URL"))

        if args.action == "imds":
            return probe.imds()
        if not args.bucket:
            raise ConfigError("--bucket is required")
        lab = bool(env.get("S3_ENDPOINT_URL"))
        if args.action == "s3-conditional":
            if args.expect_role:
                try:
                    match = probe.caller_matches(aws.sts_client(env), args.expect_role)
                except Exception as exc:
                    print(f"caller_role_match=READ_FAILED\ncode={error_code(exc)}")
                    return probe.EXIT_CALLER_UNKNOWN
                print(f"caller_role_match={str(match).lower()}")
                if not match:
                    return probe.EXIT_CALLER_MISMATCH
            elif not lab:
                raise ConfigError("--expect-role is required outside the kind lab")
            return probe.s3_conditional(aws.s3_client(env), args.bucket, args.prefix)
        if not args.key or not args.expect_role:
            raise ConfigError("--key and --expect-role are required")
        return probe.s3(args.action, aws.sts_client(env), aws.s3_client(env),
                        args.expect_role, args.bucket, args.key)
    except (ConfigError, InvalidRunKey) as exc:
        print(f"batchtraining {args.command}: invalid input: {exc}", file=sys.stderr)
        return 2
    except Exception as exc:  # class and AWS code only, never a message or traceback
        emit("FAILED", command=args.command, code=error_code(exc))
        return 1


if __name__ == "__main__":
    sys.exit(main())
