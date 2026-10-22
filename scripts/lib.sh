#!/usr/bin/env bash
# Shared helpers. Every numbered script sources this first.
#
# Scripts are meant to run inside the toolbox container (repo bind-mounted at
# /workspace). When one is started from the host, re-exec it there so the
# reviewer only ever types ./scripts/NN-*.sh.
set -euo pipefail

if [ -z "${IN_TOOLBOX:-}" ]; then
  _repo_root=$(cd "$(dirname "${BASH_SOURCE[1]}")/.." && pwd)
  _tty=-T
  [ -t 0 ] && [ -t 1 ] && _tty=
  # shellcheck disable=SC2086
  exec docker compose --project-directory "$_repo_root" exec $_tty toolbox \
    "/workspace/scripts/$(basename "${BASH_SOURCE[1]}")" "$@"
fi

# Read by the scripts that source this file.
# shellcheck disable=SC2034
{
  REPO=/workspace
  APP_NS=quote-api
  ARGOCD_NS=argocd
}

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✔ %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m✘ %s\033[0m\n' "$*" >&2; exit 1; }

# wait_for <timeout-seconds> <description> <command...>
wait_for() {
  local timeout=$1 desc=$2; shift 2
  local start=$SECONDS
  until "$@" >/dev/null 2>&1; do
    (( SECONDS - start >= timeout )) && die "timed out after ${timeout}s waiting for: $desc"
    sleep 3
  done
  ok "$desc"
}

worker_nodes_ready() {
  local n
  n=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' --no-headers 2>/dev/null \
      | awk '$2 == "Ready"' | wc -l)
  [ "$n" -ge 4 ]
}

nodepools_prepared() {
  [ "$(kubectl get nodes -l acme.io/capacity=spot --no-headers 2>/dev/null | wc -l)" -ge 2 ] &&
  [ "$(kubectl get nodes -l acme.io/capacity=on-demand --no-headers 2>/dev/null | wc -l)" -ge 1 ] &&
  [ "$(kubectl get nodes -l acme.io/node-type=gpu --no-headers 2>/dev/null | wc -l)" -ge 1 ]
}
