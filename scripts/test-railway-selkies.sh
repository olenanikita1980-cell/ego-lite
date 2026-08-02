#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
supervisor="$repo_root/scripts/railway-selkies-supervisor.sh"
bootstrap="$repo_root/scripts/selkies-token-bootstrap.mjs"

bash -n "$repo_root/scripts/railway-entrypoint.sh"
bash -n "$supervisor"
node --test "$repo_root/scripts/selkies-token-bootstrap.test.mjs"

master="master-0123456789abcdefghijklmnopqrstuvwxyz"
controller="controller-0123456789abcdefghijklmnopqrstuv"
viewer="viewer-0123456789abcdefghijklmnopqrstuvwxyz"

check_output="$({
  SELKIES_MASTER_TOKEN="$master" \
  EGO_VIEWER_CONTROLLER_TOKEN="$controller" \
  EGO_VIEWER_VIEWER_TOKEN="$viewer" \
  node "$bootstrap" --check
})"
[[ "$check_output" == '{"ok":true,"tokenCount":2}' ]]
[[ "$check_output" != *"$master"* ]]
[[ "$check_output" != *"$controller"* ]]
[[ "$check_output" != *"$viewer"* ]]

supervisor_check="$({
  XDG_RUNTIME_DIR="/tmp/ego-selkies-check" \
  EGO_TOKEN_BOOTSTRAP_SCRIPT="$bootstrap" \
  SELKIES_MASTER_TOKEN="$master" \
  EGO_VIEWER_CONTROLLER_TOKEN="$controller" \
  EGO_VIEWER_VIEWER_TOKEN="$viewer" \
    "$supervisor" --check
})"
[[ "$supervisor_check" == '{"ok":true,"port":8080,"healthPort":8082,"healthHost":"127.0.0.1","display":":99","resolution":"1920x1080","cpuEncoding":true}' ]]

if SELKIES_MASTER_TOKEN="short" \
  EGO_VIEWER_CONTROLLER_TOKEN="$controller" \
  node "$bootstrap" --check >/dev/null 2>&1; then
  echo "weak master token was accepted" >&2
  exit 1
fi

if XDG_RUNTIME_DIR="/tmp/ego-selkies-check" \
  EGO_TOKEN_BOOTSTRAP_SCRIPT="$bootstrap" \
  PORT=8080 \
  EGO_INTERNAL_HEALTH_PORT=8080 \
  SELKIES_MASTER_TOKEN="$master" \
  EGO_VIEWER_CONTROLLER_TOKEN="$controller" \
    "$supervisor" --check >/dev/null 2>&1; then
  echo "conflicting public and health ports were accepted" >&2
  exit 1
fi

echo "railway Selkies configuration checks passed"
