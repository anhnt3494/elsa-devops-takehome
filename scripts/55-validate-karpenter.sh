#!/usr/bin/env bash
# Part 5a: validate the Karpenter manifests against the real v1.15 CRDs.
# The CRDs are installed into the local cluster (no controller, no AWS) and
# the manifests go through a server-side dry run, so both the OpenAPI schema
# and the CRDs' CEL rules are enforced, not just YAML syntax.
source "$(dirname "$0")/lib.sh"

KARPENTER_VERSION=1.15.0

log "Installing Karpenter $KARPENTER_VERSION CRDs (schema only)"
helm template karpenter-crd oci://public.ecr.aws/karpenter/karpenter-crd \
  --version "$KARPENTER_VERSION" | kubectl apply --server-side -f -
kubectl wait --for=condition=Established --timeout=60s \
  crd/nodepools.karpenter.sh crd/ec2nodeclasses.karpenter.k8s.aws

log "Server-side dry run of karpenter/*.yaml"
kubectl create namespace inference --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl apply --dry-run=server -f "$REPO/karpenter/"
ok "Karpenter manifests are valid for v$KARPENTER_VERSION"
