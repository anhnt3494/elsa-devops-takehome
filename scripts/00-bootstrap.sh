#!/usr/bin/env bash
# Wait for the 4 k3s agents to register, then run the provided
# troubleshoot/prepare.sh to simulate the spot / on-demand / GPU nodepools.
# Runs automatically as the `bootstrap` compose service; safe to re-run.
source "$(dirname "$0")/lib.sh"

log "Waiting for the Kubernetes API"
wait_for 300 "API server reachable" kubectl get --raw /readyz

log "Waiting for 4 Ready worker nodes"
wait_for 300 "4 worker nodes Ready" worker_nodes_ready

log "Preparing nodepools (troubleshoot/prepare.sh, unmodified)"
sh "$REPO/troubleshoot/prepare.sh"

nodepools_prepared || die "nodepool labels missing after prepare.sh"
ok "Cluster bootstrap complete"
