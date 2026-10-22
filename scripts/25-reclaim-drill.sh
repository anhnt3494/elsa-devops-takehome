#!/usr/bin/env bash
# Part 2: simulate a spot reclaim. Drain a spot node that runs a quote-api
# replica while a curl loop hits the Ingress, show the rescheduling, then
# uncordon. Fails if any request failed or the on-demand replica is lost.
source "$(dirname "$0")/lib.sh"

URL=http://server/api/quote
RESULTS=$(mktemp)

# Leftover from an interrupted previous run.
for n in $(kubectl get nodes -l acme.io/capacity=spot -o jsonpath='{range .items[?(@.spec.unschedulable==true)]}{.metadata.name}{" "}{end}'); do
  kubectl uncordon "$n"
done
kubectl -n "$APP_NS" rollout status deployment/quote-api --timeout=120s >/dev/null

od_replicas() {
  local od n count=0
  od=" $(kubectl get nodes -l acme.io/capacity=on-demand -o jsonpath='{.items[*].metadata.name}') "
  for n in $(kubectl -n "$APP_NS" get pods -l app.kubernetes.io/name=quote-api \
               --field-selector status.phase=Running -o jsonpath='{.items[*].spec.nodeName}'); do
    case "$od" in *" $n "*) count=$((count + 1)) ;; esac
  done
  echo "$count"
}

# Topology spread is only enforced at scheduling time: if an earlier drain
# moved the on-demand replica away, nothing moves it back (production would
# run the descheduler). Rebalance before the drill.
if [ "$(od_replicas)" -eq 0 ]; then
  log "No replica on on-demand (left over from an earlier drain); rebalancing"
  kubectl -n "$APP_NS" rollout restart deployment/quote-api
  kubectl -n "$APP_NS" rollout status deployment/quote-api --timeout=180s
fi

SPOT_NODES=" $(kubectl get nodes -l acme.io/capacity=spot -o jsonpath='{.items[*].metadata.name}') "
NODE=
for n in $(kubectl -n "$APP_NS" get pods -l app.kubernetes.io/name=quote-api -o jsonpath='{.items[*].spec.nodeName}'); do
  case "$SPOT_NODES" in *" $n "*) NODE=$n; break ;; esac
done
[ -n "$NODE" ] || die "no quote-api replica on a spot node; nothing to reclaim"

cleanup() {
  [ -n "${LOOP_PID:-}" ] && kill "$LOOP_PID" 2>/dev/null || true
  kubectl uncordon "$NODE" >/dev/null 2>&1 || true
  rm -f "$RESULTS"
}
trap cleanup EXIT

log "Before: placement"
"$REPO/scripts/show-placement.sh"

log "Starting traffic: GET $URL every 100ms"
(
  while true; do
    curl -s -o /dev/null -m 2 -w '%{http_code}\n' "$URL" >> "$RESULTS" || echo 000 >> "$RESULTS"
    sleep 0.1
  done
) &
LOOP_PID=$!
sleep 3

log "Reclaiming spot node $NODE (cordon + drain, PDB respected)"
kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data --timeout=180s

log "Waiting for replicas to reschedule"
kubectl -n "$APP_NS" rollout status deployment/quote-api --timeout=180s
sleep 5
kill "$LOOP_PID"; LOOP_PID=

log "After: placement ($NODE is cordoned)"
"$REPO/scripts/show-placement.sh"

log "Scheduling events"
kubectl -n "$APP_NS" get events --sort-by=.metadata.creationTimestamp \
  --field-selector reason=Scheduled -o custom-columns='TIME:.metadata.creationTimestamp,MESSAGE:.message' | tail -5

TOTAL=$(wc -l < "$RESULTS")
FAILED=$(grep -cv '^200$' "$RESULTS" || true)
log "Traffic during drill: $TOTAL requests, $FAILED failed"

OD_REPLICAS=$(od_replicas)

log "Uncordoning $NODE"
kubectl uncordon "$NODE"

[ "$FAILED" -eq 0 ] || die "$FAILED requests failed during the drill"
[ "$OD_REPLICAS" -ge 1 ] || die "no replica left on on-demand"
ok "Service stayed up through the reclaim; $OD_REPLICAS replica(s) still on on-demand"
