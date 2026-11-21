#!/usr/bin/env bash
# Registry layer probe (DRF-37, L3 window 05/11). Read-only. Runs INSIDE a short-lived
# Pod and shows, for each image, where a layer blob is downloaded from and whether
# that download works from the node network (through the S3 gateway endpoint).
# Usage, from the repo root, inside a window with cluster admin:
#   kubectl run zdr-registry-probe --image=public.ecr.aws/docker/library/amazonlinux:2023 \
#     --restart=Never --rm -i --quiet -- bash -s < infra/terraform/scripts/registry_probe.sh
# Expect final=200/206 for every line. final=403 with an s3...amazonaws.com host means
# the endpoint policy does not list that registry's layer bucket (modules/network).
ACC='Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.docker.distribution.manifest.list.v2+json'
digests() { grep -o '"digest": *"sha256:[a-f0-9]*"' | sed -E 's/.*"(sha256:[a-f0-9]+)"/\1/'; }
probe() {
  local host=$1 repo=$2 ref=$3 auth=() hdr realm service tok m d layer loc code
  hdr=$(curl -sI "https://$host/v2/$repo/manifests/$ref" | tr -d '\r' | grep -i '^www-authenticate:')
  if [[ -n "$hdr" ]]; then
    realm=$(sed -n 's/.*realm="\([^"]*\)".*/\1/p' <<< "$hdr")
    service=$(sed -n 's/.*service="\([^"]*\)".*/\1/p' <<< "$hdr")
    tok=$(curl -s "$realm?service=$service&scope=repository:$repo:pull" | grep -o '"token": *"[^"]*"' | sed -E 's/.*"([^"]*)"$/\1/')
    auth=(-H "Authorization: Bearer $tok")
  fi
  # -L: registry.k8s.io redirects manifest requests too.
  m=$(curl -sL "${auth[@]}" -H "$ACC" "https://$host/v2/$repo/manifests/$ref")
  if grep -q '"manifests"' <<< "$m"; then
    d=$(digests <<< "$m" | head -1)
    m=$(curl -sL "${auth[@]}" -H "$ACC" "https://$host/v2/$repo/manifests/$d")
  fi
  layer=$(digests <<< "$m" | tail -1)
  loc=$(curl -s -o /dev/null -w '%{redirect_url}' "${auth[@]}" "https://$host/v2/$repo/blobs/$layer")
  code=$(curl -s -o /dev/null -w '%{http_code}' -r 0-0 -L "${auth[@]}" "https://$host/v2/$repo/blobs/$layer")
  echo "$host/$repo -> $(sed -E 's#^https?://([^/?]*)(/[^/?]*)?.*#\1\2#' <<< "$loc") final=$code"
}
# The images the P3 platform pulls (pins: gitops/platform, Argo CD v3.5.7 manifest).
probe quay.io argoproj/argocd v3.5.7
probe registry.k8s.io kro/kro v0.9.4
probe registry.k8s.io pause 3.10
probe xpkg.crossplane.io crossplane/crossplane sha256:1c66261d805a73cade46e2ac94b665c73aebd4a00844de5fcae4bcadaa2be638
probe xpkg.crossplane.io crossplane-contrib/provider-family-aws sha256:ea0d1ff932c78d5a6ef34d6ca1c83a5e6a304173b0735a05fee389f82db25f92
probe xpkg.crossplane.io crossplane-contrib/provider-aws-s3 sha256:4e6277277e91672d4a8b444f98b22723b4ca984d2e5845042188f429807919bd
# P4 (DRF-56): the RAGSandbox image (VERSION_MATRIX §8) and the aws-cli image of the owner micro-lab.
probe ghcr.io eurusdevsec/zero-d-rift/rag-sandbox sha256:512e982a4f530a20d8918f02fcb865c7c3212d6a1894278251658685f2987a57
probe public.ecr.aws aws-cli/aws-cli sha256:b0102d2269f87d8531d931c1a59e248101ace586886e6c077058d94c1c37b846
echo PROBE_DONE
