#!/usr/bin/env bash
# Part 2: install Argo CD, then let it deploy quote-api from charts/quote-api
# in this Git repo. The app itself is never helm-installed by hand.
source "$(dirname "$0")/lib.sh"

ARGOCD_CHART_VERSION=10.10.5

log "Installing Argo CD (chart $ARGOCD_CHART_VERSION)"
helm repo add argo https://argoproj.github.io/argo-helm --force-update >/dev/null
helm upgrade --install argocd argo/argo-cd \
  --namespace "$ARGOCD_NS" --create-namespace \
  --version "$ARGOCD_CHART_VERSION" \
  --values "$REPO/argocd/values.yaml" \
  --wait --timeout 10m
ok "Argo CD ready"

log "Registering the quote-api Application"
kubectl apply -f "$REPO/argocd/quote-api-app.yaml"

app_healthy() {
  [ "$(kubectl -n "$ARGOCD_NS" get application quote-api \
        -o jsonpath='{.status.sync.status}/{.status.health.status}')" = "Synced/Healthy" ]
}
wait_for 600 "Application quote-api Synced/Healthy" app_healthy
kubectl -n "$APP_NS" rollout status deployment/quote-api --timeout=300s

log "Replica placement"
"$REPO/scripts/show-placement.sh"

log "Smoke test through the Ingress"
wait_for 120 "GET /api/quote via Traefik" curl -fsS http://server/api/quote
curl -fsS http://server/api/quote; echo
ok "From your host: curl http://localhost:${HTTP_PORT:-8080}/api/quote"
ok "Argo CD UI: http://argocd.localhost:${HTTP_PORT:-8080} (user admin, password:"
echo "   kubectl -n $ARGOCD_NS get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
