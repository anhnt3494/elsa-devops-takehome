#!/usr/bin/env bash
# k3s writes its kubeconfig with server https://127.0.0.1:6443; inside the
# compose network the API server is reachable as https://server:6443.
set -euo pipefail

SRC=/kube/kubeconfig.yaml
for _ in $(seq 1 120); do
  [ -s "$SRC" ] && break
  sleep 2
done
[ -s "$SRC" ] || { echo "kubeconfig not found at $SRC after 240s" >&2; exit 1; }

mkdir -p "$(dirname "$KUBECONFIG")"
sed 's#https://127.0.0.1:6443#https://server:6443#' "$SRC" > "$KUBECONFIG"
chmod 600 "$KUBECONFIG"

exec "$@"
