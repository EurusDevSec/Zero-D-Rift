#!/usr/bin/env bash
# LAB ONLY (DRF-66, SPEC-P5 P5-T2.1 B). Prints one test Pod as JSON on stdout.
# The base Pod passes Pod Security "restricted"; the two JSON arguments add one
# change, so each lab step breaks exactly one rule.
# Usage: labs/p5-kind/pod.sh NAME NAMESPACE [CONTAINER_PATCH_JSON] [SPEC_PATCH_JSON]
#   labs/p5-kind/pod.sh p1 tenant-a '{"securityContext":{"privileged":true}}' | kubectl create -f -
# Image: the pinned pause image of kind node v1.35.8 (already on the node, no pull).
set -euo pipefail
name=$1 ns=$2 cpatch=${3:-'{}'} spatch=${4:-'{}'}
jq -n --arg name "$name" --arg ns "$ns" --argjson c "$cpatch" --argjson s "$spatch" '{
  apiVersion: "v1", kind: "Pod",
  metadata: {name: $name, namespace: $ns, labels: {"rag.zero-drift.io/tenant": $ns, "app.kubernetes.io/name": "zdr-lab"}},
  spec: ({
    automountServiceAccountToken: false,
    securityContext: {runAsNonRoot: true, runAsUser: 10001, seccompProfile: {type: "RuntimeDefault"}},
    containers: [({
      name: "c", image: "registry.k8s.io/pause:3.10",
      securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}
    } * $c)]
  } * $s)
}'
