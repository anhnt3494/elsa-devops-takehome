#!/usr/bin/env bash
# Part 3: apply the fixed troubleshooting manifests and run the provided
# verifier. Pass --broken to first apply the original broken-app.yaml and
# see verify.sh fail, then fix it.
source "$(dirname "$0")/lib.sh"

if [ "${1:-}" = "--broken" ]; then
  log "Applying the original broken manifests"
  kubectl apply -f "$REPO/troubleshoot/broken-app.yaml"
  sleep 20
  sh "$REPO/troubleshoot/verify.sh" || true
fi

log "Applying troubleshoot/fixed-app.yaml"
kubectl apply -f "$REPO/troubleshoot/fixed-app.yaml"

# verify.sh allows 60s per check. On a cold cluster the images (nginx, curl)
# are pulled for the first time, and one failed pull puts the pod in
# ImagePullBackOff for longer than that. Wait for our own rollouts first, and
# retry the (idempotent) verifier rather than editing the provided file.
log "Waiting for the fixed workloads to roll out"
kubectl -n troubleshoot rollout status deployment/web --timeout=300s
kubectl -n troubleshoot rollout status deployment/ai-inference --timeout=300s

for attempt in 1 2 3; do
  log "Running troubleshoot/verify.sh (attempt $attempt/3)"
  if sh "$REPO/troubleshoot/verify.sh"; then
    exit 0
  fi
  [ "$attempt" -lt 3 ] && echo "verify.sh failed; retrying in 20s (first-time image pulls on a fresh cluster)"
  sleep 20
done
die "troubleshoot/verify.sh did not pass after 3 attempts"
