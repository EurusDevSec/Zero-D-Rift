#!/usr/bin/env python3
"""LAB ONLY (DRF-76): print the kind variant of the real BatchTrainingJob RGD.

The lab must test the graph that goes to EKS (assumption A5: kro holds a KEDA
ScaledJob and a Job in another namespace in one graph), so this script starts
from gitops/platform/rgd/batch-training-job.yaml and changes only what kind
cannot have. Every change is listed here and asserted below:

1. the `bucket` node is a ConfigMap of the same name in the tenant namespace,
   without readyWhen (no Crossplane, no AWS); S3Mock already holds a bucket of
   that name (labs/p6-kind/backends.yaml);
2. the ScaledJob trigger reads ElasticMQ (`awsEndpoint`) with the lab keys of
   TriggerAuthentication `lab-sqs` instead of ClusterTriggerAuthentication
   zdr-sqs (no IRSA on kind);
3. both containers run the locally built image `zdr-batch:lab` (never pulled),
   reach S3Mock and ElasticMQ through S3_ENDPOINT_URL / SQS_ENDPOINT_URL and
   get the lab keys from Secret lab-aws; the training container uses the
   lab's short heartbeat 7 s and visibility timeout 20 s (EKS: 40 s / 120 s).

Graph order, readiness of the submit Job, names, labels, D5 and D9 settings,
placement and security settings stay as in Git.
Usage: python labs/p6-kind/lab_rgd.py | kubectl apply -f -
"""
from __future__ import annotations

import copy
import sys
from pathlib import Path

import yaml

SRC = Path(__file__).resolve().parents[2] / "gitops/platform/rgd/batch-training-job.yaml"
LAB_IMAGE = "zdr-batch:lab"


def set_env(container: dict, name: str, value: str | None = None, secret_key: str | None = None) -> None:
    env = [e for e in container["env"] if e["name"] != name]
    if secret_key:
        env.append({"name": name, "valueFrom": {"secretKeyRef": {"name": "lab-aws", "key": secret_key}}})
    elif value is not None:
        env.append({"name": name, "value": value})
    container["env"] = env


def job_spec(node: dict) -> dict:
    t = node["template"]["spec"]
    return (t["jobTargetRef"] if "jobTargetRef" in t else t)["template"]["spec"]


def main() -> int:
    real = yaml.safe_load(SRC.read_text(encoding="utf-8"))
    lab = copy.deepcopy(real)
    nodes = {r["id"]: r for r in lab["spec"]["resources"]}

    # 1. ConfigMap in place of the Crossplane bucket.
    b = nodes["bucket"]
    b.pop("readyWhen", None)
    b["template"] = {
        "apiVersion": "v1",
        "kind": "ConfigMap",
        "metadata": b["template"]["metadata"],
        # Same edge as the real bucket (region and tags): waits for batch-config.
        "data": {"region": "${platformConfig.data.region}"},
    }

    # 2. Trigger on ElasticMQ with lab keys.
    trig = nodes["scaledJob"]["template"]["spec"]["triggers"][0]
    trig["authenticationRef"] = {"kind": "TriggerAuthentication", "name": "lab-sqs"}
    trig["metadata"]["awsEndpoint"] = "http://elasticmq.zdr-lab:9324"

    # 3. Local image, lab endpoints and keys; short lab queue timings.
    for i in ("scaledJob", "submit"):
        c = job_spec(nodes[i])["containers"][0]
        c["image"] = LAB_IMAGE
        c["imagePullPolicy"] = "Never"
        set_env(c, "S3_ENDPOINT_URL", "http://s3mock.zdr-lab:9090")
        set_env(c, "SQS_ENDPOINT_URL", "http://elasticmq.zdr-lab:9324")
        set_env(c, "AWS_ACCESS_KEY_ID", secret_key="AWS_ACCESS_KEY_ID")
        set_env(c, "AWS_SECRET_ACCESS_KEY", secret_key="AWS_SECRET_ACCESS_KEY")
    train = job_spec(nodes["scaledJob"])["containers"][0]
    set_env(train, "HEARTBEAT_SECONDS", "7")
    set_env(train, "VISIBILITY_TIMEOUT", "20")

    # Guard: only the listed fields differ from Git.
    real_nodes = {r["id"]: r for r in real["spec"]["resources"]}
    assert lab["spec"]["schema"] == real["spec"]["schema"], "schema must not change"
    assert [r["id"] for r in lab["spec"]["resources"]] == [r["id"] for r in real["spec"]["resources"]], "graph order"
    assert nodes["platformConfig"] == real_nodes["platformConfig"], "platformConfig must not change"
    assert b["template"]["metadata"] == real_nodes["bucket"]["template"]["metadata"], "bucket name and labels"
    for i in ("scaledJob", "submit"):
        a, r = copy.deepcopy(nodes[i]), copy.deepcopy(real_nodes[i])
        for n in (a, r):
            for c in job_spec(n)["containers"]:
                for k in ("image", "imagePullPolicy", "env"):
                    c.pop(k, None)
            if "triggers" in n["template"]["spec"]:
                t = n["template"]["spec"]["triggers"][0]
                t.pop("authenticationRef")
                t["metadata"].pop("awsEndpoint", None)
        assert a == r, f"{i}: only image, env and the trigger auth/endpoint may change"
        real_env = {e["name"]: e for e in job_spec(real_nodes[i])["containers"][0]["env"]}
        lab_env = {e["name"]: e for e in job_spec(nodes[i])["containers"][0]["env"]}
        changed = {k for k in real_env if real_env[k] != lab_env.get(k)}
        assert changed <= {"HEARTBEAT_SECONDS", "VISIBILITY_TIMEOUT"}, f"{i}: env changed: {changed}"

    print("# GENERATED by labs/p6-kind/lab_rgd.py from gitops/platform/rgd/batch-training-job.yaml.")
    print("# LAB ONLY: ConfigMap for the bucket, ElasticMQ/S3Mock with lab keys, local image. Do not commit or sync.")
    yaml.safe_dump(lab, sys.stdout, sort_keys=False, width=200)
    return 0


if __name__ == "__main__":
    sys.exit(main())
