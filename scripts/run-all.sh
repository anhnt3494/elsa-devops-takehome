#!/usr/bin/env bash
# Run every task script in order. Each one is idempotent.
source "$(dirname "$0")/lib.sh"

log "Waiting for compose bootstrap (nodepool labels)"
wait_for 600 "nodepools prepared" nodepools_prepared

for script in "$REPO"/scripts/[0-9][0-9]-*.sh; do
  case "$(basename "$script")" in
    00-*) continue ;;
  esac
  log "Running $(basename "$script")"
  "$script"
done

ok "All tasks completed"
