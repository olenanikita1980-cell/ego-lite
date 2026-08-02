#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
entrypoint="$repo_root/scripts/railway-entrypoint.sh"
supervisor="$repo_root/scripts/railway-selkies-supervisor.sh"
bootstrap="$repo_root/scripts/selkies-token-bootstrap.mjs"
selkies_upstream="$repo_root/third_party/selkies/UPSTREAM.md"
selkies_stream_server="$repo_root/third_party/selkies/src/selkies/stream_server.py"

bash -n "$entrypoint"
bash -n "$supervisor"
node --test "$repo_root/scripts/selkies-token-bootstrap.test.mjs"

EGO_RAILWAY_ENTRYPOINT_SOURCE_ONLY=1 source "$entrypoint"
lock_test_root="$(mktemp -d "${TMPDIR:-/tmp}/ego-profile-locks.XXXXXX")"
trap 'rm -rf -- "$lock_test_root"' EXIT
touch "$lock_test_root/Preferences"
ln -s "old-host-123" "$lock_test_root/SingletonLock"
ln -s "/tmp/old-cookie" "$lock_test_root/SingletonCookie"
ln -s "/tmp/old-socket" "$lock_test_root/SingletonSocket"
cleanup_chromium_singleton_links "$lock_test_root" >/dev/null 2>&1
[[ -f "$lock_test_root/Preferences" ]]
[[ ! -e "$lock_test_root/SingletonLock" && ! -L "$lock_test_root/SingletonLock" ]]
[[ ! -e "$lock_test_root/SingletonCookie" && ! -L "$lock_test_root/SingletonCookie" ]]
[[ ! -e "$lock_test_root/SingletonSocket" && ! -L "$lock_test_root/SingletonSocket" ]]

for singleton_name in SingletonCookie SingletonLock SingletonSocket; do
  touch "$lock_test_root/$singleton_name"
  for sibling_name in SingletonCookie SingletonLock SingletonSocket; do
    if [[ "$sibling_name" != "$singleton_name" ]]; then
      ln -s "/tmp/must-remain-${sibling_name}" "$lock_test_root/$sibling_name"
    fi
  done
  set +e
  cleanup_chromium_singleton_links "$lock_test_root" >/dev/null 2>&1
  cleanup_status=$?
  set -e
  [[ "$cleanup_status" -eq 73 ]]
  [[ -f "$lock_test_root/$singleton_name" ]]
  for sibling_name in SingletonCookie SingletonLock SingletonSocket; do
    if [[ "$sibling_name" != "$singleton_name" ]]; then
      [[ -L "$lock_test_root/$sibling_name" ]]
    fi
  done
  rm "$lock_test_root/SingletonCookie" "$lock_test_root/SingletonLock" "$lock_test_root/SingletonSocket"
done

grep -q '877cf202b4955d8477041c7831d4b34ebdb92d16' "$selkies_upstream"
grep -q '/api/health' "$selkies_stream_server"
grep -q '/api/tokens' "$selkies_stream_server"
grep -q 'chromium-sandbox' "$repo_root/Dockerfile.railway"
grep -q 'EGO_CHROME_NO_SANDBOX=0' "$repo_root/Dockerfile.railway"

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
