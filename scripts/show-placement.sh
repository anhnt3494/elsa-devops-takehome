#!/usr/bin/env bash
# Print quote-api pods with the nodepool of the node each one runs on.
source "$(dirname "$0")/lib.sh"

declare -A pool
while read -r node cap gpu; do
  pool[$node]=${cap:-${gpu:-system}}
done < <(kubectl get nodes --no-headers \
  -o custom-columns='N:.metadata.name,C:.metadata.labels.acme\.io/capacity,G:.metadata.labels.acme\.io/node-type' \
  | sed 's/<none>//g')

printf '%-36s %-10s %-9s %s\n' POD NODE POOL STATUS
kubectl -n "$APP_NS" get pods -l app.kubernetes.io/name=quote-api --no-headers \
  -o custom-columns='P:.metadata.name,N:.spec.nodeName,S:.status.phase' \
  | while read -r pod node status; do
      printf '%-36s %-10s %-9s %s\n' "$pod" "$node" "${pool[$node]:--}" "$status"
    done
