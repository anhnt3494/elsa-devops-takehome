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

log "Running troubleshoot/verify.sh"
sh "$REPO/troubleshoot/verify.sh"
