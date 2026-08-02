#!/usr/bin/env bash
set -euo pipefail

image_ref="${1:?usage: test-railway-owner-lock-container.sh IMAGE_REF}"
run_suffix="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}-$$"
owner_container="ego-profile-owner-${run_suffix}"
contender_container="ego-profile-contender-${run_suffix}"
owner_volume="ego-profile-owner-${run_suffix}"
invalid_volume="ego-profile-invalid-${run_suffix}"

cleanup() {
  docker rm -f "$owner_container" "$contender_container" >/dev/null 2>&1 || true
  docker volume rm "$owner_volume" "$invalid_volume" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker pull "$image_ref" >/dev/null
docker volume create "$owner_volume" >/dev/null
docker volume create "$invalid_volume" >/dev/null

docker run --detach \
  --name "$owner_container" \
  --volume "$owner_volume:/data" \
  --env EGO_VISUAL_MODE=headless \
  "$image_ref" \
  sh -c 'touch /tmp/profile-owner-ready && sleep 60' >/dev/null

for _ in {1..50}; do
  if docker exec "$owner_container" test -f /tmp/profile-owner-ready 2>/dev/null; then
    break
  fi
  sleep 0.1
done
docker exec "$owner_container" test -f /tmp/profile-owner-ready

set +e
docker run --rm \
  --name "$contender_container" \
  --volume "$owner_volume:/data" \
  --env EGO_VISUAL_MODE=headless \
  "$image_ref" \
  sh -c 'exit 0' >/dev/null 2>&1
contender_status=$?
set -e
[[ "$contender_status" -eq 75 ]]
[[ "$(docker inspect --format '{{.State.Running}}' "$owner_container")" == "true" ]]

docker stop --time 10 "$owner_container" >/dev/null
docker rm "$owner_container" >/dev/null
docker run --rm \
  --volume "$owner_volume:/data" \
  --env EGO_VISUAL_MODE=headless \
  "$image_ref" \
  sh -c 'exit 0' >/dev/null

docker run --rm \
  --entrypoint sh \
  --volume "$invalid_volume:/data" \
  "$image_ref" \
  -c 'mkdir -p /data/ego-lite/profile-owner.lock'

set +e
docker run --rm \
  --volume "$invalid_volume:/data" \
  --env EGO_VISUAL_MODE=headless \
  "$image_ref" \
  sh -c 'exit 0' >/dev/null 2>&1
invalid_status=$?
set -e
[[ "$invalid_status" -eq 73 ]]

echo "Railway profile owner lock container checks passed"
