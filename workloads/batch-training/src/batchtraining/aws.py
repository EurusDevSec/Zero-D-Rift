"""boto3 clients. Path-style S3 addressing whenever an endpoint is set (D12).

``S3_ENDPOINT_URL`` and ``SQS_ENDPOINT_URL`` point at S3Mock and ElasticMQ in
the kind lab; on EKS they are unset and IRSA supplies the credentials.
"""

from __future__ import annotations

from collections.abc import Mapping

import boto3
from botocore.config import Config


def _config(read_timeout: int, path_style: bool) -> Config:
    kwargs: dict = {
        "connect_timeout": 5,
        "read_timeout": read_timeout,
        "retries": {"max_attempts": 3, "mode": "standard"},
    }
    if path_style:
        kwargs["s3"] = {"addressing_style": "path"}
    return Config(**kwargs)


def s3_client(env: Mapping[str, str]):
    endpoint = env.get("S3_ENDPOINT_URL") or None
    return boto3.client(
        "s3",
        region_name=env.get("AWS_REGION") or None,
        endpoint_url=endpoint,
        config=_config(20, path_style=endpoint is not None),
    )


def sqs_client(env: Mapping[str, str]):
    endpoint = env.get("SQS_ENDPOINT_URL") or None
    # Long polling waits up to 20 s, so the read timeout must exceed it.
    return boto3.client(
        "sqs",
        region_name=env.get("AWS_REGION") or None,
        endpoint_url=endpoint,
        config=_config(30, path_style=False),
    )


def sts_client(env: Mapping[str, str]):
    region = env.get("AWS_REGION") or None
    endpoint = f"https://sts.{region}.amazonaws.com" if region else None
    return boto3.client("sts", region_name=region, endpoint_url=endpoint, config=_config(10, False))
